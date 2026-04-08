#!/bin/bash
# analysis_package_generator.sh - 分析包生成器
#
# 用法：
#   analysis_package_generator.sh /path/to/project /path/to/call_graph.json /path/to/symbol_table.json /path/to/controlflow.json /output/packages/
#
# 功能：
#   - 扫描所有 C 文件，识别可疑模式
#   - 为每个可疑点生成完整的"分析包"
#   - 分析包包含：代码上下文、变量信息、调用关系、控制流信息
#   - 为 AI Agent 提供足够的上下文进行深度分析
#
# 输出格式：
#   - 每个可疑点生成一个 JSON 文件
#   - 文件名格式: suspicious_XXX_YYYY.json (XXX = 文件索引, YYYY = 行号)
#
# 可疑模式：
#   1. 返回局部变量地址: return &local_var
#   2. 内存泄漏: malloc/calloc/realloc without matching free
#   3. Double Free: same pointer freed multiple times
#   4. Use-After-Free: pointer used after free
#   5. 堆溢出: malloc(size) mismatched with write size
#   6. 空指针解引用: pointer used without null check
#   7. 数组越界: array index may exceed bounds
#   8. 未初始化内存: malloc followed by read without init
#   9. 格式化字符串: printf(user_input) without "%s"
#   10. 不安全函数: gets, strcpy, strcat, sprintf

set -euo pipefail

PROJECT_DIR="$1"
CALL_GRAPH="$2"
SYMBOL_TABLE="$3"
CONTROLFLOW="$4"
OUTPUT_DIR="$5"

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$CALL_GRAPH" ] || [ -z "$SYMBOL_TABLE" ] || [ -z "$CONTROLFLOW" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /path/to/call_graph.json /path/to/symbol_table.json /path/to/controlflow.json /output/packages/" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

if [ ! -f "$CALL_GRAPH" ]; then
    echo "错误：调用图文件不存在: $CALL_GRAPH" >&2
    exit 1
fi

if [ ! -f "$SYMBOL_TABLE" ]; then
    echo "错误：符号表文件不存在: $SYMBOL_TABLE" >&2
    exit 1
fi

if [ ! -f "$CONTROLFLOW" ]; then
    echo "错误：控制流文件不存在: $CONTROLFLOW" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 临时文件
TMP_SUSPICIOUS=$(mktemp)
TMP_FILE_INDEX=$(mktemp)
FILE_COUNTER=0

trap "rm -f $TMP_SUSPICIOUS $TMP_FILE_INDEX" EXIT

echo "[1/6] 扫描可疑模式..."
# 扫描所有 C 文件，识别可疑模式
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print | while IFS= read -r file; do
    # 为每个文件生成索引
    FILE_COUNTER=$((FILE_COUNTER + 1))
    echo "$FILE_COUNTER|$file"

    # 扫描可疑模式
    awk -v filename="$file" -v file_idx="$FILE_COUNTER" -v out_file="$TMP_SUSPICIOUS" '
    BEGIN {
        gsub(/\/\/.*/, "")
    }

    {
        # 移除注释
        gsub(/\/\/.*/, "")
        gsub(/\/\*.*\*\//, "")

        # 模式1: 返回局部变量地址
        if ($0 ~ /\breturn\s*&\s*[a-zA-Z_][a-zA-Z0-9_]*\b/) {
            match($0, /return\s*&\s*[a-zA-Z_][a-zA-Z0-9_]*/)
            if (RSTART > 0) {
                var_name = substr($0, RSTART+7, RLENGTH-7)
                print filename "|" NR "|" "return_local_address" "|" var_name >> out_file
            }
        }

        # 模式2: malloc/calloc/realloc without free (简单启发式：先记录malloc，稍后分析)
        if ($0 ~ /\b(malloc|calloc|realloc)\s*\(/) {
            match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*=\s*\b(malloc|calloc|realloc)\s*\(/)
            if (RSTART > 0) {
                var_name = substr($0, RSTART, RLENGTH)
                gsub(/\s*=\s*(malloc|calloc|realloc).*/, "", var_name)
                print filename "|" NR "|" "malloc_without_free" "|" var_name >> out_file
            }
        }

        # 模式4: Use-After-Free (free 后使用)
        if ($0 ~ /\bfree\s*\(/) {
            match($0, /free\s*\(\s*[a-zA-Z_][a-zA-Z0-9_]*/)
            if (RSTART > 0) {
                var_name = substr($0, RSTART+5, RLENGTH-5)
                gsub(/[\s\)]/, "", var_name)
                print filename "|" NR "|" "use_after_free" "|" var_name >> out_file
            }
        }

        # 模式6: 空指针解引用 (指针使用前没有检查)
        if ($0 ~ /\*\s*[a-zA-Z_][a-zA-Z0-9_]*\s*=/ || $0 ~ /->\s*[a-zA-Z_][a-zA-Z0-9_]*/) {
            # 简单启发式：直接使用指针，前面没有 if (ptr != NULL)
            print filename "|" NR "|" "null_pointer_dereference" "|" "unknown" >> out_file
        }

        # 模式8: 未初始化内存 (malloc 后立即读取)
        if ($0 ~ /\b(malloc|calloc)\s*\(/) {
            match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*=\s*(malloc|calloc)\s*\(/)
            if (RSTART > 0) {
                var_name = substr($0, RSTART, RLENGTH)
                gsub(/\s*=\s*(malloc|calloc).*/, "", var_name)
                print filename "|" NR "|" "uninitialized_memory" "|" var_name >> out_file
            }
        }

        # 模式9: 格式化字符串漏洞
        if ($0 ~ /\b(printf|fprintf|sprintf|snprintf)\s*\([^,)]*,\s*[^")]*\)/) {
            # 检查第二个参数是否是格式化字符串
            match($0, /(printf|fprintf|sprintf|snprintf)\s*\([^,)]*,\s*[^"'\)]/)
            if (RSTART > 0) {
                # 如果第二个参数不是字符串字面量，可能是漏洞
                if ($0 !~ /(printf|fprintf|sprintf|snprintf)\s*\([^,)]*,\s*"/) {
                    print filename "|" NR "|" "format_string" "|" "unknown" >> out_file
                }
            }
        }

        # 模式10: 不安全函数
        if ($0 ~ /\b(gets|strcpy|strcat|sprintf)\s*\(/) {
            if ($0 ~ /\bgets\s*\(/) {
                print filename "|" NR "|" "unsafe_function" "|" "gets" >> out_file
            }
            if ($0 ~ /\bstrcpy\s*\(/) {
                print filename "|" NR "|" "unsafe_function" "|" "strcpy" >> out_file
            }
            if ($0 ~ /\bstrcat\s*\(/) {
                print filename "|" NR "|" "unsafe_function" "|" "strcat" >> out_file
            }
            if ($0 ~ /\bsprintf\s*\(/ && !/snprintf/) {
                print filename "|" NR "|" "unsafe_function" "|" "sprintf" >> out_file
            }
        }
    }
    ' "$file"

done > "$TMP_FILE_INDEX"

TOTAL_SUSPICIOUS=$(wc -l < "$TMP_SUSPICIOUS 2>/dev/null" || echo 0)
echo "    找到 $TOTAL_SUSPICIOUS 个可疑点"

if [ "$TOTAL_SUSPICIOUS" -eq 0 ]; then
    echo "✓ 未发现可疑模式，无需生成分析包"
    exit 0
fi

echo "[2/6] 提取代码上下文..."
# 为每个可疑点提取代码上下文（前后20行）

echo "[3/6] 提取符号表信息..."

echo "[4/6] 提取调用关系..."

echo "[5/6] 提取控制流信息..."

echo "[6/6] 生成分析包..."

# 为每个可疑点生成分析包
PKG_COUNTER=0

while IFS='|' read -r file line pattern_type var_name; do
    PKG_COUNTER=$((PKG_COUNTER + 1))
    PKG_FILE="$OUTPUT_DIR/suspicious_${PKG_COUNTER}.json"

    # 提取代码上下文（前后20行）
    context_start=$((line - 20))
    if [ $context_start -lt 1 ]; then
        context_start=1
    fi
    context_end=$((line + 20))

    code_context=$(sed -n "${context_start},${context_end}p" "$file")

    # 转义代码中的双引号和换行符
    code_context_json=$(echo "$code_context" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' '\\n')

    # 提取函数名（简单启发式：向上查找函数定义）
    func_name=$(awk -v target_line="$line" '
    BEGIN {
        found = 0
        brace_count = 0
    }
    {
        if (NR <= target_line && !found) {
            if (/\{/ && !found) {
                # 找到一个可能的函数开始
                brace_count++
                if (brace_count == 1 && /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/) {
                    match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)
                    if (RSTART > 0) {
                        func = substr($0, RSTART, RLENGTH)
                        gsub(/[()\s]/, "", func)
                        print func
                        found = 1
                    }
                }
            }
        }
    }
    ' "$file" | tail -1)

    if [ -z "$func_name" ]; then
        func_name="unknown"
    fi

    # 从调用图中提取调用关系（使用 jq）
    callers="[]"
    callees="[]"
    if command -v jq &> /dev/null; then
        callers=$(jq -r --arg func "$func_name" '.functions[$func].callers // []' "$CALL_GRAPH" 2>/dev/null || echo "[]")
        callees=$(jq -r --arg func "$func_name" '.functions[$func].callees // []' "$CALL_GRAPH" 2>/dev/null || echo "[]")
    fi

    # 从符号表中提取变量信息
    var_info="null"
    if [ "$var_name" != "unknown" ] && command -v jq &> /dev/null; then
        var_info=$(jq --arg var "$var_name" '.variables[$var] // null' "$SYMBOL_TABLE" 2>/dev/null || echo "null")
    fi

    # 从控制流图中提取控制流信息
    controlflow_info="null"
    if command -v jq &> /dev/null; then
        controlflow_info=$(jq --arg func "$func_name" '.functions[$func] // null' "$CONTROLFLOW" 2>/dev/null || echo "null")
    fi

    # 生成分析包
    cat > "$PKG_FILE" <<EOF
{
  "package_id": "$PKG_COUNTER",
  "suspicious_point": {
    "file": "$file",
    "line": $line,
    "function": "$func_name",
    "pattern_type": "$pattern_type",
    "variable": "$var_name"
  },
  "context": {
    "code_snippet": "$code_context_json",
    "context_lines": {
      "start": $context_start,
      "end": $context_end
    }
  },
  "variable_info": $var_info,
  "call_chain": {
    "function": "$func_name",
    "callers": $callers,
    "callees": $callees
  },
  "controlflow": $controlflow_info,
  "analysis_hints": {
    "check_for": [
      "Verify if variable is stored in global data structures",
      "Check for cleanup functions in other modules",
      "Look for error handling paths that might free the memory",
      "Verify if this is intentional design (cache, singleton, etc.)",
      "Check comments and documentation for design intent"
    ],
    "dataflow_trace": [
      "Trace the lifecycle of the variable",
      "Identify all paths where the variable is used",
      "Check for exception paths",
      "Verify if all paths have proper memory management"
    ],
    "manual_verification_steps": [
      "1. Check the full function implementation",
      "2. Look for global variables or static variables that might store the pointer",
      "3. Search for other functions that might free this memory",
      "4. Review error handling paths",
      "5. Check project documentation for design intent"
    ]
  }
}
EOF

    if [ $((PKG_COUNTER % 100)) -eq 0 ]; then
        echo "    已生成 $PKG_COUNTER 个分析包..."
    fi

done < "$TMP_SUSPICIOUS"

echo "✓ 分析包生成完成: $OUTPUT_DIR"
echo "  - 可疑点总数: $TOTAL_SUSPICIOUS"
echo "  - 分析包总数: $PKG_COUNTER"
echo ""
echo "使用方法："
echo "  AI Agent 应该逐个读取分析包文件，结合上下文进行深度分析"
echo "  每个分析包包含："
echo "    - 可疑点信息（文件、行号、函数、模式类型）"
echo "    - 代码上下文（前后20行）"
echo "    - 变量信息（类型、生命周期、内存操作）"
echo "    - 调用关系（调用者、被调用者）"
echo "    - 控制流信息（基本块、分支、循环）"
echo "    - 分析提示（人工验证步骤、数据流追踪建议）"
