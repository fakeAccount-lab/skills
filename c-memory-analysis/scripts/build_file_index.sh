#!/bin/bash
# build_file_index.sh - 构建文件级索引（轻量级）
#
# 用法：
#   build_file_index.sh /path/to/project /output/index.json
#
# 索引内容：
#   - 所有 C 文件的路径
#   - 每个文件的哈希值（用于增量分析）
#   - 每个文件的大致行数
#   - 文件中定义的函数列表（通过简单模式匹配）
#   - 文件中调用的可疑函数（malloc, free, strcpy 等）
#
# 输出格式：JSON

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_INDEX="$2"

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$OUTPUT_INDEX" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /output/index.json" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$(dirname "$OUTPUT_INDEX")"

# 脚本开始输出 JSON
echo "{"
echo '  "project_dir": "'"$PROJECT_DIR"'",'
echo '  "timestamp": '$(date +%s)','
echo '  "files": ['

FIRST_FILE=true

# 扫描所有 C 文件
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print | while IFS= read -r file; do
    # 添加逗号分隔符
    if [ "$FIRST_FILE" = false ]; then
        echo ","
    fi
    FIRST_FILE=false

    # 计算文件哈希（MD5）
    file_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

    # 计算行数
    line_count=$(wc -l < "$file" 2>/dev/null || echo "0")

    # 提取函数定义（简单模式匹配）
    functions=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\([^)]*\)\s*\{' "$file" 2>/dev/null | sed 's/.*\([a-zA-Z_][a-zA-Z0-9_]*\)\s*(.*/\1/' | head -20 || true)

    # 提取可疑函数调用（malloc, free, strcpy, sprintf, gets, printf 等）
    suspicious_calls=$(grep -oE '\b(malloc|free|calloc|realloc|strcpy|strcat|sprintf|gets|printf|scanf)\s*\(' "$file" 2>/dev/null | sort -u || true)

    # 转义文件路径中的双引号
    escaped_file=$(echo "$file" | sed 's/"/\\"/g')

    # 输出文件信息
    echo -n "    {"
    echo -n ' "path": "'"$escaped_file"'",'
    echo -n ' "hash": "'"$file_hash"'",'
    echo -n ' "line_count": '"$line_count"','
    echo -n ' "functions": ['

    # 输出函数列表
    first_func=true
    if [ -n "$functions" ]; then
        echo "$functions" | while IFS= read -r func; do
            if [ "$first_func" = false ]; then
                echo -n ","
            fi
            first_func=false
            echo -n '"'"$func"'"'
        done
    fi

    echo -n '], "suspicious_calls": ['

    # 输出可疑函数调用
    first_call=true
    if [ -n "$suspicious_calls" ]; then
        echo "$suspicious_calls" | while IFS= read -r call; do
            if [ "$first_call" = false ]; then
                echo -n ","
            fi
            first_call=false
            echo -n '"'"${call%\(}"'"'
        done
    fi

    echo -n '] }'
done

echo ""
echo "  ]"
echo "}"
