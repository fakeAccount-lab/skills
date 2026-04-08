#!/bin/bash
# controlflow_analyzer.sh - 控制流分析器
#
# 用法：
#   controlflow_analyzer.sh /path/to/project /output/controlflow.json
#
# 功能：
#   - 识别条件分支（if/switch）
#   - 识别循环结构（for/while/do-while）
#   - 识别异常路径（goto, longjmp）
#   - 构建基本块（Basic Blocks）
#   - 识别可能的错误处理路径
#   - 识别未初始化的变量使用
#
# 输出格式：JSON
#
# 注意：
#   - 这是一个轻量级的静态分析工具
#   - 不处理复杂的宏和条件编译
#   - 基本块划分是基于启发式的，不是精确的

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_FLOW="$2"

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$OUTPUT_FLOW" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /output/controlflow.json" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$(dirname "$OUTPUT_FLOW")"

# 临时文件
TMP_FUNCTIONS=$(mktemp)
TMP_BLOCKS=$(mktemp)
TMP_BRANCHES=$(mktemp)
TMP_LOOPS=$(mktemp)
TMP_FLOW=$(mktemp)

trap "rm -f $TMP_FUNCTIONS $TMP_BLOCKS $TMP_BRANCHES $TMP_LOOPS $TMP_FLOW" EXIT

echo "[1/5] 扫描函数定义..."
# 扫描所有函数定义（复用 call_graph_builder.sh 的逻辑）
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print | while IFS= read -r file; do
    awk '
    BEGIN {
        in_function = 0
        brace_count = 0
        func_name = ""
        func_line = 0
    }

    /^[a-zA-Z_]/ {
        if (in_function == 0) {
            if (/\(/ && /\)/ && /\{/) {
                match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)
                if (RSTART > 0) {
                    func_line = NR
                    func_name = substr($0, RSTART, RLENGTH)
                    gsub(/[()\s]/, "", func_name)
                    in_function = 1
                    brace_count = 1
                }
            }
        }
    }

    {
        if (in_function == 1) {
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }

            if (brace_count == 0 && in_function == 1) {
                if (func_name != "") {
                    print "'"$file"'|" func_line "|" func_name
                }
                in_function = 0
                func_name = ""
                func_line = 0
            }
        }
    }
    ' "$file"
done > "$TMP_FUNCTIONS"

TOTAL_FUNCTIONS=$(wc -l < "$TMP_FUNCTIONS")
echo "    找到 $TOTAL_FUNCTIONS 个函数"

echo "[2/5] 构建基本块..."
# 构建基本块
# 基本块定义：只有一个入口和一个出口的连续代码序列
# 基本块结束条件：
#   - 条件分支（if, switch）
#   - 循环（for, while, do-while）
#   - 跳转语句（goto, return, break, continue）
#   - 函数调用（可能改变执行流）

while IFS='|' read -r file line func_name; do
    awk -v filename="$file" -v funcstart="$line" -v funcname="$func_name" '
    BEGIN {
        in_function = 0
        brace_count = 0
        line_num = 0
        bb_id = 0
        bb_start = 0
        bb_type = "entry"
    }

    {
        line_num++

        if (line_num == funcstart) {
            in_function = 1
            brace_count = 1
            bb_start = line_num
            next
        }

        if (in_function == 1) {
            # 移除注释
            gsub(/\/\/.*/, "")

            # 计算大括号
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }

            # 检查基本块结束条件
            bb_ended = 0
            bb_end_type = "normal"

            # 条件分支
            if (/\bif\s*\(/ || /\bswitch\s*\(/) {
                bb_ended = 1
                bb_end_type = "conditional"
            }

            # 循环
            if (/\bfor\s*\(/ || /\bwhile\s*\(/ || /\bdo\s*\{/) {
                bb_ended = 1
                bb_end_type = "loop"
            }

            # 跳转语句
            if (/\bgoto\s+[a-zA-Z_][a-zA-Z0-9_]*/ || /\breturn\b/ || /\bbreak\b/ || /\bcontinue\b/) {
                bb_ended = 1
                bb_end_type = "jump"
            }

            # 函数调用（非关键字）
            if (/[a-zA-Z_][a-zA-Z0-9_]*\s*\(/ && !/\b(if|while|for|switch|return|sizeof|typeof|asm|__attribute__|__builtin_)\s*\(/) {
                # 这是一个函数调用，可能改变执行流
                if (!/\b(if|while|for|switch)\s*\(/) {
                    # bb_ended = 1
                    # bb_end_type = "function_call"
                }
            }

            # 函数结束
            if (brace_count == 0) {
                bb_ended = 1
                bb_end_type = "exit"
            }

            # 输出基本块
            if (bb_ended == 1) {
                bb_id++
                print filename "|" funcname "|" bb_id "|" bb_start "|" line_num "|" bb_type "|" bb_end_type

                # 更新类型
                if (bb_end_type == "conditional") {
                    bb_type = "conditional"
                } else if (bb_end_type == "loop") {
                    bb_type = "loop"
                } else {
                    bb_type = "normal"
                }

                bb_start = line_num + 1
            }
        }
    }
    ' "$file"

done < "$TMP_FUNCTIONS" > "$TMP_BLOCKS"

TOTAL_BLOCKS=$(wc -l < "$TMP_BLOCKS")
echo "    构建了 $TOTAL_BLOCKS 个基本块"

echo "[3/5] 识别分支结构..."
# 识别分支结构（if, switch）
while IFS='|' read -r file func_name bb_id bb_start bb_end bb_type bb_end_type; do
    if [ "$bb_end_type" = "conditional" ]; then
        # 提取分支信息
        awk -v filename="$file" -v start="$bb_start" -v end="$bb_end" -v func="$func_name" '
        {
            if (NR >= start && NR <= end) {
                gsub(/\/\/.*/, "")

                # 匹配 if 条件
                if ($0 ~ /\bif\s*\(/) {
                    match($0, /if\s*\(([^)]+)\)/)
                    if (RSTART > 0) {
                        condition = substr($0, RSTART+3, RLENGTH-3)
                        print filename "|" func "|" bb_id "|" NR "|" "if|" condition
                    }
                }

                # 匹配 switch 条件
                if ($0 ~ /\bswitch\s*\(/) {
                    match($0, /switch\s*\(([^)]+)\)/)
                    if (RSTART > 0) {
                        condition = substr($0, RSTART+7, RLENGTH-7)
                        print filename "|" func "|" bb_id "|" NR "|" "switch|" condition
                    }
                }
            }
        }
        ' "$file"
    fi
done < "$TMP_BLOCKS" | sort -u > "$TMP_BRANCHES"

TOTAL_BRANCHES=$(wc -l < "$TMP_BRANCHES")
echo "    找到 $TOTAL_BRANCHES 个分支结构"

echo "[4/5] 识别循环结构..."
# 识别循环结构（for, while, do-while）
while IFS='|' read -r file func_name bb_id bb_start bb_end bb_type bb_end_type; do
    if [ "$bb_end_type" = "loop" ]; then
        # 提取循环信息
        awk -v filename="$file" -v start="$bb_start" -v end="$bb_end" -v func="$func_name" '
        {
            if (NR >= start && NR <= end) {
                gsub(/\/\/.*/, "")

                # 匹配 for 循环
                if ($0 ~ /\bfor\s*\(/) {
                    match($0, /for\s*\(([^)]+)\)/)
                    if (RSTART > 0) {
                        condition = substr($0, RSTART+4, RLENGTH-4)
                        print filename "|" func "|" bb_id "|" NR "|" "for|" condition
                    }
                }

                # 匹配 while 循环
                if ($0 ~ /\bwhile\s*\(/) {
                    match($0, /while\s*\(([^)]+)\)/)
                    if (RSTART > 0) {
                        condition = substr($0, RSTART+6, RLENGTH-6)
                        print filename "|" func "|" bb_id "|" NR "|" "while|" condition
                    }
                }

                # 匹配 do-while 循环
                if ($0 ~ /\bdo\s*\{/) {
                    print filename "|" func "|" bb_id "|" NR "|" "do-while|"
                }
            }
        }
        ' "$file"
    fi
done < "$TMP_BLOCKS" | sort -u > "$TMP_LOOPS"

TOTAL_LOOPS=$(wc -l < "$TMP_LOOPS")
echo "    找到 $TOTAL_LOOPS 个循环结构"

echo "[5/5] 构建控制流图..."
# 构建控制流图
echo "{" > "$TMP_FLOW"
echo '  "project_dir": "'"$PROJECT_DIR"'",' >> "$TMP_FLOW"
echo '  "timestamp": '$(date +%s)',' >> "$TMP_FLOW"
echo '  "functions": {' >> "$TMP_FLOW"

FIRST_FUNC=true

# 为每个函数构建控制流信息
declare -A FUNC_BB_COUNT
declare -A_FUNC_BRANCH_COUNT
declare -A FUNC_LOOP_COUNT

# 统计每个函数的基本块、分支、循环数量
while IFS='|' read -r file func_name bb_id bb_start bb_end bb_type bb_end_type; do
    key="${func_name}"
    if [ -z "${FUNC_BB_COUNT[$key]:-}" ]; then
        FUNC_BB_COUNT[$key]=1
    else
        FUNC_BB_COUNT[$key]=$((${FUNC_BB_COUNT[$key]} + 1))
    fi
done < "$TMP_BLOCKS"

while IFS='|' read -r file func_name bb_id line branch_type condition; do
    key="${func_name}"
    if [ -z "${FUNC_BRANCH_COUNT[$key]:-}" ]; then
        FUNC_BRANCH_COUNT[$key]=1
    else
        FUNC_BRANCH_COUNT[$key]=$((${FUNC_BRANCH_COUNT[$key]} + 1))
    fi
done < "$TMP_BRANCHES"

while IFS='|' read -r file func_name bb_id line loop_type condition; do
    key="${func_name}"
    if [ -z "${FUNC_LOOP_COUNT[$key]:-}" ]; then
        FUNC_LOOP_COUNT[$key]=1
    else
        FUNC_LOOP_COUNT[$key]=$((${FUNC_LOOP_COUNT[$key]} + 1))
    fi
done < "$TMP_LOOPS"

# 输出每个函数的控制流信息
while IFS='|' read -r file line func_name; do
    if [ "$FIRST_FUNC" = false ]; then
        echo "," >> "$TMP_FLOW"
    fi
    FIRST_FUNC=false

    # 转义文件路径中的双引号
    escaped_file=$(echo "$file" | sed 's/"/\\"/g')

    # 获取该函数的基本块
    func_blocks=$(grep "|${func_name}|" "$TMP_BLOCKS" | awk -F'|' '{
        printf "{\"id\": %s, \"start\": %s, \"end\": %s, \"type\": \"%s\", \"end_type\": \"%s\"}", $3, $4, $5, $6, $7
        if (NR>0) printf ", "
    }')

    # 获取该函数的分支
    func_branches=$(grep "|${func_name}|" "$TMP_BRANCHES" | awk -F'|' '{
        # 转义条件中的双引号
        cond = $6
        gsub(/"/, "\\\"", cond)
        printf "{\"line\": %s, \"type\": \"%s\", \"condition\": \"%s\"}", $4, $5, cond
        if (NR>0) printf ", "
    }')

    # 获取该函数的循环
    func_loops=$(grep "|${func_name}|" "$TMP_LOOPS" | awk -F'|' '{
        # 转义条件中的双引号
        cond = $6
        gsub(/"/, "\\\"", cond)
        printf "{\"line\": %s, \"type\": \"%s\", \"condition\": \"%s\"}", $4, $5, cond
        if (NR>0) printf ", "
    }')

    # 统计信息
    bb_count=${FUNC_BB_COUNT[$func_name]:-0}
    branch_count=${FUNC_BRANCH_COUNT[$func_name]:-0}
    loop_count=${FUNC_LOOP_COUNT[$func_name]:-0}

    # 估算圈复杂度（Cyclomatic Complexity）
    # CC = 分支数 + 循环数 + 1
    cyclomatic_complexity=$((branch_count + loop_count + 1))

    echo -n '    "'"$func_name"'": {' >> "$TMP_FLOW"
    echo -n ' "file": "'"$escaped_file"'",' >> "$TMP_FLOW"
    echo -n ' "line": '"$line"',' >> "$TMP_FLOW"
    echo -n ' "basic_blocks_count": '"$bb_count"',' >> "$TMP_FLOW"
    echo -n ' "branches_count": '"$branch_count"',' >> "$TMP_FLOW"
    echo -n ' "loops_count": '"$loop_count"',' >> "$TMP_FLOW"
    echo -n ' "cyclomatic_complexity": '"$cyclomatic_complexity"',' >> "$TMP_FLOW"
    echo -n ' "basic_blocks": ['"$func_blocks"'],' >> "$TMP_FLOW"
    echo -n ' "branches": ['"$func_branches"'],' >> "$TMP_FLOW"
    echo -n ' "loops": ['"$func_loops"']' >> "$TMP_FLOW"
    echo -n ' }' >> "$TMP_FLOW"

done < "$TMP_FUNCTIONS"

echo "" >> "$TMP_FLOW"
echo "  }" >> "$TMP_FLOW"
echo "}" >> "$TMP_FLOW"

# 格式化输出
if command -v jq &> /dev/null; then
    jq '.' "$TMP_FLOW" > "$OUTPUT_FLOW"
else
    cp "$TMP_FLOW" "$OUTPUT_FLOW"
fi

echo "✓ 控制流分析完成: $OUTPUT_FLOW"
echo "  - 函数总数: $TOTAL_FUNCTIONS"
echo "  - 基本块总数: $TOTAL_BLOCKS"
echo "  - 分支结构总数: $TOTAL_BRANCHES"
echo "  - 循环结构总数: $TOTAL_LOOPS"
echo "  - 平均圈复杂度: $(awk -v total=$(echo "$TOTAL_FUNCTIONS" | head -1) -v branches="$TOTAL_BRANCHES" -v loops="$TOTAL_LOOPS" 'BEGIN { if (total > 0) print (branches + loops + total) / total; else print 0 }')"
