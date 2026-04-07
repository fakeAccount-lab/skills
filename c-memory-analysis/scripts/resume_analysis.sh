#!/bin/bash
# resume_analysis.sh - 恢复中断的分析
#
# 用法：
#   resume_analysis.sh /path/to/batches/dir /path/to/output/dir /path/to/cache/dir
#
# 功能：
#   - 检查哪些批次已完成（存在 .done 标记）
#   - 检查哪些批次失败（存在 .failed 标记）
#   - 从最后一个未完成的批次继续分析
#
# 输出：
#   输出需要继续分析的批次列表

set -euo pipefail

BATCHES_DIR="$1"
OUTPUT_DIR="$2"
CACHE_DIR="$3"

# 验证参数
if [ -z "$BATCHES_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "错误：缺少必需参数" >&2
    echo "用法：$0 /path/to/batches/dir /path/to/output/dir [/path/to/cache/dir]" >&2
    exit 1
fi

if [ ! -d "$BATCHES_DIR" ]; then
    echo "错误：批次目录不存在: $BATCHES_DIR" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "正在检查批次状态..."

# 统计批次
total_batches=$(ls -1 "$BATCHES_DIR"/batch_*.txt 2>/dev/null | wc -l)
completed_batches=$(ls -1 "$BATCHES_DIR"/*.done 2>/dev/null | wc -l)
failed_batches=$(ls -1 "$BATCHES_DIR"/*.failed 2>/dev/null | wc -l)
pending_batches=$((total_batches - completed_batches - failed_batches))

echo "总批次数: $total_batches"
echo "已完成: $completed_batches"
echo "失败: $failed_batches"
echo "待分析: $pending_batches"

# 输出需要继续分析的批次
echo ""
echo "需要继续分析的批次："

found_pending=false
for batch_file in $(ls -1 "$BATCHES_DIR"/batch_*.txt 2>/dev/null | sort); do
    batch_name=$(basename "$batch_file" .txt)
    done_marker="$BATCHES_DIR/${batch_name}.done"
    failed_marker="$BATCHES_DIR/${batch_name}.failed"

    if [ ! -f "$done_marker" ] && [ ! -f "$failed_marker" ]; then
        echo "  - $batch_name"
        found_pending=true
    fi
done

if [ "$found_pending" = false ]; then
    echo "  无待分析批次（所有批次已完成）"
else
    echo ""
    echo "建议：从第一个待分析批次开始继续分析"
fi
