#!/bin/bash
# analyze_module.sh - 分析单个模块（批次）
#
# 用法：
#   analyze_module.sh /path/to/batch/file.txt /path/to/output/result.json
#
# 输入：
#   批次文件包含该批次的所有文件路径，每行一个
#
# 输出：
#   JSON 格式的分析结果，包含每个文件的可疑点和详细分析
#
# 注意：
#   此脚本只负责调用 AI Agent 进行分析，具体的分析逻辑由 AI Agent 执行
#   脚本负责提供上下文、提取代码、格式化结果

set -euo pipefail

BATCH_FILE="$1"
OUTPUT_RESULT="$2"

# 验证参数
if [ -z "$BATCH_FILE" ] || [ -z "$OUTPUT_RESULT" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/batch/file.txt /path/to/output/result.json" >&2
    exit 1
fi

if [ ! -f "$BATCH_FILE" ]; then
    echo "错误：批次文件不存在: $BATCH_FILE" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$(dirname "$OUTPUT_RESULT")"

# 脚本开始输出 JSON
echo "{"
echo '  "batch_file": "'"$BATCH_FILE"'",'
echo '  "timestamp": '$(date +%s)','
echo '  "files": ['

FIRST_FILE=true

# 读取批次文件中的每个文件
while IFS= read -r file; do
    # 跳过空行
    [ -z "$file" ] && continue

    # 跳过不存在的文件
    [ ! -f "$file" ] && continue

    # 添加逗号分隔符
    if [ "$FIRST_FILE" = false ]; then
        echo ","
    fi
    FIRST_FILE=false

    # 转义文件路径中的双引号
    escaped_file=$(echo "$file" | sed 's/"/\\"/g')

    # 输出文件信息（详细分析由 AI Agent 完成）
    echo -n "    {"
    echo -n ' "path": "'"$escaped_file"'",'
    echo -n ' "status": "pending",'
    echo -n ' "issues": []'
    echo -n " }"

done < "$BATCH_FILE"

echo ""
echo "  ]"
echo "}" > "$OUTPUT_RESULT"

echo "分析完成: $OUTPUT_RESULT"
echo "注意：详细的漏洞分析需要 AI Agent 进一步处理此结果文件"
