#!/bin/bash
# symbol_table_builder.sh - 符号表构建器
#
# 用法：
#   symbol_table_builder.sh /path/to/project /output/symbol_table.json
#
# 功能：
#   - 提取所有变量声明（局部变量、全局变量、静态变量）
#   - 记录变量的类型和作用域
#   - 记录变量的使用位置
#   - 识别生命周期（栈变量、堆变量、全局变量）
#   - 识别指针类型
#   - 记录内存分配和释放操作
#
# 输出格式：JSON
#
# 注意：
#   - 这是一个轻量级的静态分析工具
#   - 不处理复杂的宏和条件编译
#   - 不处理复杂的类型定义（结构体、联合体等）

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_TABLE="$2"

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$OUTPUT_TABLE" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /output/symbol_table.json" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$(dirname "$OUTPUT_TABLE")"

# 临时文件
TMP_VARS=$(mktemp)
TMP_SYMBOLS=$(mktemp)
TMP_TABLE=$(mktemp)

trap "rm -f $TMP_VARS $TMP_SYMBOLS $TMP_TABLE" EXIT

echo "[1/4] 扫描变量声明..."
# 扫描所有变量声明
# 匹配模式：
#   - [static] type name [= init];
#   - [static] type name, name2, ...;
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print | while IFS= read -r file; do
    awk -v filename="$file" '
    BEGIN {
        in_function = 0
        func_name = ""
        func_line = 0
        brace_count = 0
    }

    # 识别函数定义开始
    /^[a-zA-Z_]/ {
        if (in_function == 0) {
            # 检查是否是函数定义
            if (/\(/ && /\)/ && /\{/) {
                # 提取函数名
                match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*\(/)
                if (RSTART > 0) {
                    func_name = substr($0, RSTART, RLENGTH)
                    gsub(/[()\s]/, "", func_name)
                    in_function = 1
                    brace_count = 1
                }
            }
        }
    }

    # 计算大括号
    {
        if (in_function == 1) {
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }

            if (brace_count == 0) {
                in_function = 0
                func_name = ""
                func_line = 0
            }
        }
    }

    # 移除注释
    {
        # 移除单行注释
        gsub(/\/\/.*/, "")

        # 移除多行注释（简单处理，不处理跨行）
        gsub(/\/\*.*\*\//, "")
    }

    # 匹配变量声明
    {
        # 全局变量（在函数外部）
        if (in_function == 0) {
            # 匹配: [static] type name [= init];
            if (/(static|const|extern)\s+[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/ ||
                /^[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/) {

                # 排除函数定义
                if (!/\(.*\)\s*\{/) {
                    # 提取存储类型
                    is_static = 0
                    is_const = 0
                    is_extern = 0
                    if (/static/) is_static = 1
                    if (/const/) is_const = 1
                    if (/extern/) is_extern = 1

                    # 提取变量名
                    match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/)
                    if (RSTART > 0) {
                        var_line = NR
                        var_name = substr($0, RSTART, RLENGTH)
                        gsub(/[;=\s]/, "", var_name)

                        # 提取变量类型（简单处理）
                        match($0, /([a-zA-Z_][a-zA-Z0-9_]*\s*)+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/)
                        if (RSTART > 0) {
                            type_decl = substr($0, RSTART, RLENGTH)
                            # 移除变量名
                            gsub(/[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]$/, "", type_decl)
                            var_type = type_decl
                            gsub(/^\s+|\s+$/, "", var_type)
                        } else {
                            var_type = "unknown"
                        }

                        # 判断是否是指针
                        is_pointer = 0
                        if (/[*]/) is_pointer = 1

                        scope = "global"
                        lifetime = "global"

                        print filename "|" var_line "|" var_name "|" var_type "|" scope "|" lifetime "|" is_static "|" is_const "|" is_extern "|" is_pointer "|" func_name
                    }
                }
            }
        } else {
            # 局部变量（在函数内部）
            if (/(static|const)\s+[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/ ||
                /^[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/) {

                # 排除函数定义
                if (!/\(.*\)\s*\{/) {
                    # 提取存储类型
                    is_static = 0
                    is_const = 0
                    is_extern = 0
                    if (/static/) is_static = 1
                    if (/const/) is_const = 1

                    # 提取变量名
                    match($0, /[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/)
                    if (RSTART > 0) {
                        var_line = NR
                        var_name = substr($0, RSTART, RLENGTH)
                        gsub(/[;=\s]/, "", var_name)

                        # 提取变量类型
                        match($0, /([a-zA-Z_][a-zA-Z0-9_]*\s*)+[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]/)
                        if (RSTART > 0) {
                            type_decl = substr($0, RSTART, RLENGTH)
                            gsub(/[a-zA-Z_][a-zA-Z0-9_]*\s*[;=]$/, "", type_decl)
                            var_type = type_decl
                            gsub(/^\s+|\s+$/, "", var_type)
                        } else {
                            var_type = "unknown"
                        }

                        # 判断是否是指针
                        is_pointer = 0
                        if (/[*]/) is_pointer = 1

                        scope = "local"

                        # 判断生命周期
                        if (is_static == 1) {
                            lifetime = "static"
                        } else {
                            lifetime = "stack"
                        }

                        print filename "|" var_line "|" var_name "|" var_type "|" scope "|" lifetime "|" is_static "|" is_const "|" is_extern "|" is_pointer "|" func_name
                    }
                }
            }
        }
    }
    ' "$file"
done > "$TMP_VARS"

TOTAL_VARS=$(wc -l < "$TMP_VARS")
echo "    找到 $TOTAL_VARS 个变量声明"

echo "[2/4] 扫描内存操作..."
# 扫描内存分配和释放操作
# 对于每个变量，记录其内存操作
while IFS='|' read -r file line var_name var_type scope lifetime is_static is_const is_extern is_pointer func_name; do
    # 扫描变量的内存操作
    awk -v var="$var_name" -v filename="$file" -v varline="$line" '
    {
        gsub(/\/\/.*/, "")
        gsub(/\/\*.*\*\//, "")

        # 匹配 malloc/calloc/realloc
        if ($0 ~ /\b(malloc|calloc|realloc)\s*\(/) {
            # 检查是否赋值给该变量
            if ($0 ~ var "\\s*=") {
                print NR "|malloc|" $0
            }
        }

        # 匹配 free
        if ($0 ~ /\bfree\s*\(\s*/ var) {
            print NR "|free|" $0
        }

        # 匹配 realloc
        if ($0 ~ /\brealloc\s*\(/) {
            # 检查是否对该变量进行 realloc
            if ($0 ~ var "\\s*,") {
                print NR "|realloc|" $0
            }
        }
    }
    ' "$file"

done < "$TMP_VARS" | sort -u > "$TMP_SYMBOLS"

TOTAL_SYMBOLS=$(wc -l < "$TMP_SYMBOLS")
echo "    找到 $TOTAL_SYMBOLS 个内存操作"

echo "[3/4] 构建符号表..."
# 构建符号表
echo "{" > "$TMP_TABLE"
echo '  "project_dir": "'"$PROJECT_DIR"'",' >> "$TMP_TABLE"
echo '  "timestamp": '$(date +%s)',' >> "$TMP_TABLE"
echo '  "variables": {' >> "$TMP_TABLE"

FIRST_VAR=true

# 构建变量信息
declare -A VAR_ALLOCATIONS
declare -A VAR_DEALLOCATIONS
declare -A VAR_USES

# 读取内存操作
while IFS='|' read -r op_line op_type op_code; do
    # 提取变量名（简单启发式）
    var_name=$(echo "$op_code" | sed -n 's/.*\b\([a-zA-Z_][a-zA-Z0-9_]*\)\s*=.*malloc.*/\1/p')
    if [ -z "$var_name" ]; then
        var_name=$(echo "$op_code" | sed -n 's/.*free\s*(\s*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p')
    fi

    if [ -n "$var_name" ]; then
        if [ "$op_type" = "malloc" ] || [ "$op_type" = "calloc" ] || [ "$op_type" = "realloc" ]; then
            if [ -z "${VAR_ALLOCATIONS[$var_name]:-}" ]; then
                VAR_ALLOCATIONS[$var_name]="$op_line"
            else
                VAR_ALLOCATIONS[$var_name]="${VAR_ALLOCATIONS[$var_name]},$op_line"
            fi
        elif [ "$op_type" = "free" ]; then
            if [ -z "${VAR_DEALLOCATIONS[$var_name]:-}" ]; then
                VAR_DEALLOCATIONS[$var_name]="$op_line"
            else
                VAR_DEALLOCATIONS[$var_name]="${VAR_DEALLOCATIONS[$var_name]},$op_line"
            fi
        fi
    fi
done < "$TMP_SYMBOLS"

# 输出变量信息
while IFS='|' read -r file line var_name var_type scope lifetime is_static is_const is_extern is_pointer func_name; do
    if [ "$FIRST_VAR" = false ]; then
        echo "," >> "$TMP_TABLE"
    fi
    FIRST_VAR=false

    # 转义文件路径中的双引号
    escaped_file=$(echo "$file" | sed 's/"/\\"/g')

    # 获取内存操作
    allocations="${VAR_ALLOCATIONS[$var_name]:-}"
    deallocations="${VAR_DEALLOCATIONS[$var_name]:-}"

    # 转换为 JSON 数组
    alloc_array="[]"
    if [ -n "$allocations" ]; then
        alloc_array=$(echo "$allocations" | awk -F',' '{
            printf "["
            for(i=1;i<=NF;i++) {
                printf "{\"line\": %s, \"function\": \"malloc\"}", $i
                if (i<NF) printf ", "
            }
            printf "]"
        }')
    fi

    dealloc_array="[]"
    if [ -n "$deallocations" ]; then
        dealloc_array=$(echo "$deallocations" | awk -F',' '{
            printf "["
            for(i=1;i<=NF;i++) {
                printf "{\"line\": %s, \"function\": \"free\"}", $i
                if (i<NF) printf ", "
            }
            printf "]"
        }')
    fi

    echo -n '    "'"$var_name"'": {' >> "$TMP_TABLE"
    echo -n ' "file": "'"$escaped_file"'",' >> "$TMP_TABLE"
    echo -n ' "line": '"$line"',' >> "$TMP_TABLE"
    echo -n ' "function": "'"$func_name"'",' >> "$TMP_TABLE"
    echo -n ' "type": "'"$var_type"'",' >> "$TMP_TABLE"
    echo -n ' "scope": "'"$scope"'",' >> "$TMP_TABLE"
    echo -n ' "lifetime": "'"$lifetime"'",' >> "$TMP_TABLE"
    echo -n ' "is_pointer": '"$is_pointer"',' >> "$TMP_TABLE"
    echo -n ' "is_static": '"$is_static"',' >> "$TMP_TABLE"
    echo -n ' "is_const": '"$is_const"',' >> "$TMP_TABLE"
    echo -n ' "is_extern": '"$is_extern"',' >> "$TMP_TABLE"
    echo -n ' "allocations": '"$alloc_array"',' >> "$TMP_TABLE"
    echo -n ' "deallocations": '"$dealloc_array"'' >> "$TMP_TABLE"
    echo -n ' }' >> "$TMP_TABLE"

done < "$TMP_VARS"

echo "" >> "$TMP_TABLE"
echo "  }," >> "$TMP_TABLE"

# 输出统计信息
echo '  "statistics": {' >> "$TMP_TABLE"
echo '    "total_variables": '"$TOTAL_VARS"',' >> "$TMP_TABLE"
echo '    "global_variables": '"$(grep -c '|global|' "$TMP_VARS" 2>/dev/null || echo 0)"',' >> "$TMP_TABLE"
echo '    "local_variables": '"$(grep -c '|local|' "$TMP_VARS" 2>/dev/null || echo 0)"',' >> "$TMP_TABLE"
echo '    "pointer_variables": '"$(grep -c '|1$' "$TMP_VARS" 2>/dev/null || echo 0)"',' >> "$TMP_TABLE"
echo '    "variables_with_malloc": '"$(grep -c '|' "$TMP_SYMBOLS" 2>/dev/null || echo 0)"'' >> "$TMP_TABLE"
echo "  }" >> "$TMP_TABLE"
echo "}" >> "$TMP_TABLE"

echo "[4/4] 格式化输出..."
# 格式化 JSON
if command -v jq &> /dev/null; then
    jq '.' "$TMP_TABLE" > "$OUTPUT_TABLE"
else
    cp "$TMP_TABLE" "$OUTPUT_TABLE"
fi

echo "✓ 符号表构建完成: $OUTPUT_TABLE"
echo "  - 变量总数: $TOTAL_VARS"
echo "  - 全局变量: $(grep -c '|global|' "$TMP_VARS" 2>/dev/null || echo 0)"
echo "  - 局部变量: $(grep -c '|local|' "$TMP_VARS" 2>/dev/null || echo 0)"
echo "  - 指针变量: $(grep -c '|1$' "$TMP_VARS" 2>/dev/null || echo 0)"
echo "  - 涉及内存操作的变量: $(grep -c '|' "$TMP_SYMBOLS" 2>/dev/null || echo 0)"
