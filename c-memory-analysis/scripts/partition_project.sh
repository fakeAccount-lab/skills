#!/bin/bash
# partition_project.sh - 智能分批，将大项目划分为可管理的批次
#
# 用法：
#   partition_project.sh /path/to/project /output/batches/directory [--strategy files|modules|functions] [--max-batch-size 10]
#
# 分批策略：
#   - files: 按文件分批，每批最多 N 个文件
#   - modules: 按模块（目录）分批
#   - functions: 按函数分批（未来扩展）
#
# 输出：
#   在输出目录创建批次文件：batch_001.txt, batch_002.txt, ...
#   每个批次文件包含该批次的所有文件路径，每行一个

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_DIR="$2"
STRATEGY="files"
MAX_BATCH_SIZE=10

# 解析可选参数
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --strategy)
            STRATEGY="$2"
            shift 2
            ;;
        --max-batch-size)
            MAX_BATCH_SIZE="$2"
            shift 2
            ;;
        *)
            echo "警告：未知参数 $1" >&2
            shift
            ;;
    esac
done

# 验证参数
if [ -z "$PROJECT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/project /output/batches/directory [--strategy files|modules] [--max-batch-size N]" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：项目目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 扫描所有 C 文件
TEMP_FILES=$(mktemp)
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print > "$TEMP_FILES"
TOTAL_FILES=$(wc -l < "$TEMP_FILES")

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "警告：未找到任何 C 源文件" >&2
    rm "$TEMP_FILES"
    exit 0
fi

echo "找到 $TOTAL_FILES 个 C 源文件"

# 根据策略分批
case "$STRATEGY" in
    files)
        # 按文件数量分批
        BATCH_NUM=1
        COUNT=0
        CURRENT_BATCH="$OUTPUT_DIR/batch_$(printf '%03d' $BATCH_NUM).txt"

        while IFS= read -r file; do
            if [ $COUNT -ge $MAX_BATCH_SIZE ]; then
                BATCH_NUM=$((BATCH_NUM + 1))
                CURRENT_BATCH="$OUTPUT_DIR/batch_$(printf '%03d' $BATCH_NUM).txt"
                COUNT=0
            fi
            echo "$file" >> "$CURRENT_BATCH"
            COUNT=$((COUNT + 1))
        done < "$TEMP_FILES"
        ;;

    modules)
        # 按模块（目录）分批
        BATCH_NUM=1
        CURRENT_BATCH="$OUTPUT_DIR/batch_$(printf '%03d' $BATCH_NUM).txt"
        CURRENT_MODULE=""
        CURRENT_MODULE_COUNT=0

        while IFS= read -r file; do
            # 提取文件所在的模块（相对于项目根目录的路径）
            module=$(dirname "$file" | sed "s|^$PROJECT_DIR/||")

            if [ "$module" != "$CURRENT_MODULE" ] && [ "$CURRENT_MODULE_COUNT" -gt 0 ]; then
                BATCH_NUM=$((BATCH_NUM + 1))
                CURRENT_BATCH="$OUTPUT_DIR/batch_$(printf '%03d' $BATCH_NUM).txt"
                CURRENT_MODULE_COUNT=0
            fi

            echo "$file" >> "$CURRENT_BATCH"
            CURRENT_MODULE="$module"
            CURRENT_MODULE_COUNT=$((CURRENT_MODULE_COUNT + 1))
        done < "$TEMP_FILES"
        ;;

    *)
        echo "错误：不支持的分批策略: $STRATEGY" >&2
        echo "支持策略: files, modules" >&2
        rm "$TEMP_FILES"
        exit 1
        ;;
esac

# 清理临时文件
rm "$TEMP_FILES"

# 统计批次数量
TOTAL_BATCHES=$(ls -1 "$OUTPUT_DIR"/batch_*.txt 2>/dev/null | wc -l)
echo "已创建 $TOTAL_BATCHES 个批次"
