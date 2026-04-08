#!/bin/bash
# call_graph_builder.sh - 函数调用图构建器
#
# 用法：
#   call_graph_builder.sh /path/to/project /output/call_graph.json
#
# 功能：
#   - 静态分析 C 代码，构建完整的函数调用关系图
#   - 记录每个函数的调用者和被调用者
#   - 支持跨文件调用关系
#   - 识别函数指针调用（通过启发式方法）
#   - 识别导出函数（非 static）和静态函数
#
# 输出格式：JSON
#
# 注意：
#   - 这是一个轻量级的静态分析工具
#   - 不处理复杂的宏和条件编译
#   - 对于函数指针调用，只能做启发式识别

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_GRAPH="$2"

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$OUTPUT_GRAPH" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /output/call_graph.json" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$(dirname "$OUTPUT_GRAPH")"

# 临时文件
TMP_FUNCTIONS=$(mktemp)
TMP_CALLS=$(mktemp)
TMP_GRAPH=$(mktemp)

trap "rm -f $TMP_FUNCTIONS $TMP_CALLS $TMP_GRAPH" EXIT

echo "[1/4] 扫描函数定义..."
# 扫描所有函数定义
# 匹配模式：
#   - 返回类型 + 函数名 + 参数列表 + {
#   - static 关键字可选
#   - 支持多行参数列表
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print | while IFS= read -r file; do
    # 使用 awk 处理多行函数定义
    awk '
    BEGIN {
        in_function = 0
        brace_count = 0
        func_name = ""
        func_line = 0
        is_static = 0
    }

    # 匹配函数定义开始
    /^[a-zA-Z_]/ {
        if (in_function == 0) {
            # 检查是否有 static 关键字
            if ($1 ~ /static/) {
                is_static = 1
            } else {
                is_static = 0
            }

            # 尝试匹配函数定义模式
            # 模式: return_type function_name(params) {
            if (/\(/ && /\)/ && /\{/) {
                # 提取函数名
                match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)
                if (RSTART > 0) {
                    func_line = NR
                    func_name = substr($0, RSTART, RLENGTH)
                    # 移除括号和空格
                    gsub(/[()\s]/, "", func_name)
                    in_function = 1
                    brace_count = 1
                }
            } else if (/\(/ && !/\)/) {
                # 多行参数列表
                match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)
                if (RSTART > 0) {
                    func_line = NR
                    func_name = substr($0, RSTART, RLENGTH)
                    gsub(/[()\s]/, "", func_name)
                    in_function = 1
                    brace_count = 0
                }
            }
        }
    }

    # 处理多行参数列表
    {
        if (in_function == 1 && brace_count == 0) {
            if (/\{/) {
                brace_count = 1
            }
        }
    }

    # 计算大括号，确定函数结束
    {
        if (in_function == 1) {
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }

            if (brace_count == 0 && in_function == 1) {
                # 函数结束
                if (func_name != "") {
                    print "'"$file"'|" func_line "|" func_name "|" is_static
                }
                in_function = 0
                func_name = ""
                func_line = 0
                is_static = 0
            }
        }
    }
    ' "$file"
done > "$TMP_FUNCTIONS"

TOTAL_FUNCTIONS=$(wc -l < "$TMP_FUNCTIONS")
echo "    找到 $TOTAL_FUNCTIONS 个函数定义"

echo "[2/4] 扫描函数调用..."
# 扫描所有函数调用
# 对于每个函数定义，扫描其中的函数调用
while IFS='|' read -r file line func_name is_static; do
    # 提取函数体（从函数定义开始到函数结束）
    awk -v func_start="$line" '
    BEGIN {
        brace_count = 0
        in_function = 0
        line_num = 0
    }

    {
        line_num++
        if (line_num == func_start) {
            in_function = 1
            brace_count = 1
            next
        }

        if (in_function == 1) {
            # 计算大括号
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }

            if (brace_count == 0) {
                exit
            }

            # 查找函数调用
            # 匹配模式: function_name(...)
            # 排除: if (, while (, for (, switch (, return (
            gsub(/\/\/.*/, "")  # 移除单行注释

            # 查找函数调用
            while (match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)) {
                call_pos = RSTART
                call_len = RLENGTH

                # 检查是否是控制结构关键字
                call_text = substr($0, call_pos, call_len)
                gsub(/[()\s]/, "", call_text)

                # 排除关键字
                if (call_text !~ /^(if|while|for|switch|return|sizeof|typeof|alignof|asm|__attribute__|__builtin_|_Static_assert)$/) {
                    print call_text
                }

                # 继续搜索
                $0 = substr($0, call_pos + call_len)
            }
        }
    }
    ' "$file" | sort -u

done < "$TMP_FUNCTIONS" | awk -F'|' '{print $1 "|" $2 "|" $3 "|" $4}' > "$TMP_CALLS"

TOTAL_CALLS=$(wc -l < "$TMP_CALLS")
echo "    找到 $TOTAL_CALLS 个函数调用"

echo "[3/4] 构建调用图..."
# 构建调用图
echo "{" > "$TMP_GRAPH"
echo '  "project_dir": "'"$PROJECT_DIR"'",' >> "$TMP_GRAPH"
echo '  "timestamp": '$(date +%s)',' >> "$TMP_GRAPH"
echo '  "functions": {' >> "$TMP_GRAPH"

FIRST_FUNC=true

# 构建函数信息
declare -A CALLERS
declare -A CALLEES
declare -A FUNCTION_FILES
declare -A FUNCTION_LINES
declare -A FUNCTION_IS_STATIC

# 读取函数定义
while IFS='|' read -r file line func_name is_static; do
    FUNCTION_FILES[$func_name]="$file"
    FUNCTION_LINES[$func_name]=$line
    FUNCTION_IS_STATIC[$func_name]=$is_static
    CALLERS[$func_name]=""
    CALLEES[$func_name]=""
done < "$TMP_FUNCTIONS"

# 读取函数调用，构建调用关系
while IFS='|' read -r caller_file caller_line callee_name; do
    # 跳过空行
    [ -z "$callee_name" ] && continue

    # 检查被调用者是否是已知函数
    if [ -n "${FUNCTION_FILES[$callee_name]:-}" ]; then
        # 添加调用关系
        if [ -z "${CALLEES[$caller_file]:-}" ]; then
            CALLEES[$caller_file]="$callee_name"
        else
            CALLEES[$caller_file]="${CALLEES[$caller_file]},$callee_name"
        fi

        if [ -z "${CALLERS[$callee_name]:-}" ]; then
            CALLERS[$callee_name]="$caller_file"
        else
            CALLERS[$callee_name]="${CALLERS[$callee_name]},$caller_file"
        fi
    fi
done < "$TMP_CALLS"

# 输出函数信息
for func_name in "${!FUNCTION_FILES[@]}"; do
    if [ "$FIRST_FUNC" = false ]; then
        echo "," >> "$TMP_GRAPH"
    fi
    FIRST_FUNC=false

    file="${FUNCTION_FILES[$func_name]}"
    line="${FUNCTION_LINES[$func_name]}"
    is_static="${FUNCTION_IS_STATIC[$func_name]}"
    callers="${CALLERS[$func_name]}"
    callees="${CALLEES[$func_name]}"

    # 转义文件路径中的双引号
    escaped_file=$(echo "$file" | sed 's/"/\\"/g')

    # 将逗号分隔的列表转换为 JSON 数组
    callers_array=$(echo "$callers" | awk -F',' '{for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i<NF?",":"")}')
    callees_array=$(echo "$callees" | awk -F',' '{for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i<NF?",":"")}')

    # 检查是否是递归函数
    is_recursive="false"
    if echo "$callees" | grep -q "$func_name"; then
        is_recursive="true"
    fi

    # 检查是否是导出函数
    is_exported="true"
    if [ "$is_static" = "1" ]; then
        is_exported="false"
    fi

    echo -n '    "'"$func_name"'": {' >> "$TMP_GRAPH"
    echo -n ' "file": "'"$escaped_file"'",' >> "$TMP_GRAPH"
    echo -n ' "line": '"$line"',' >> "$TMP_GRAPH"
    echo -n ' "callers": ['"$callers_array"'],' >> "$TMP_GRAPH"
    echo -n ' "callees": ['"$callees_array"'],' >> "$TMP_GRAPH"
    echo -n ' "is_recursive": '"$is_recursive"',' >> "$TMP_GRAPH"
    echo -n ' "is_exported": '"$is_exported"'' >> "$TMP_GRAPH"
    echo -n ' }' >> "$TMP_GRAPH"
done

echo "" >> "$TMP_GRAPH"
echo "  }," >> "$TMP_GRAPH"

# 输出全局函数列表
echo '  "global_functions": [' >> "$TMP_GRAPH"
FIRST=true
for func_name in "${!FUNCTION_IS_STATIC[@]}"; do
    if [ "${FUNCTION_IS_STATIC[$func_name]}" = "0" ]; then
        if [ "$FIRST" = false ]; then
            echo "," >> "$TMP_GRAPH"
        fi
        FIRST=false
        echo -n '    "'"$func_name"'"' >> "$TMP_GRAPH"
    fi
done
echo "" >> "$TMP_GRAPH"
echo "  ]," >> "$TMP_GRAPH"

# 输出静态函数列表
echo '  "static_functions": [' >> "$TMP_GRAPH"
FIRST=true
for func_name in "${!FUNCTION_IS_STATIC[@]}"; do
    if [ "${FUNCTION_IS_STATIC[$func_name]}" = "1" ]; then
        if [ "$FIRST" = false ]; then
            echo "," >> "$TMP_GRAPH"
        fi
        FIRST=false
        echo -n '    "'"$func_name"'"' >> "$TMP_GRAPH"
    fi
done
echo "" >> "$TMP_GRAPH"
echo "  ]" >> "$TMP_GRAPH"
echo "}" >> "$TMP_GRAPH"

echo "[4/4] 格式化输出..."
# 格式化 JSON（如果 jq 可用）
if command -v jq &> /dev/null; then
    jq '.' "$TMP_GRAPH" > "$OUTPUT_GRAPH"
else
    cp "$TMP_GRAPH" "$OUTPUT_GRAPH"
fi

echo "✓ 调用图构建完成: $OUTPUT_GRAPH"
echo "  - 函数总数: $TOTAL_FUNCTIONS"
echo "  - 函数调用总数: $TOTAL_CALLS"
echo "  - 导出函数: $(echo "$TOTAL_FUNCTIONS" - $(grep -c '"is_exported": false' "$TMP_GRAPH" 2>/dev/null || echo 0) | bc)"
echo "  - 静态函数: $(grep -c '"is_exported": false' "$TMP_GRAPH" 2>/dev/null || echo 0)"
echo "  - 递归函数: $(grep -c '"is_recursive": true' "$TMP_GRAPH" 2>/dev/null || echo 0)"
