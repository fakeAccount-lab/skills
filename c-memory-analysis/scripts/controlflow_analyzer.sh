#!/bin/bash
# controlflow_analyzer.sh - 简化版
set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_FLOW="$2"

mkdir -p "$(dirname "$OUTPUT_FLOW")"

echo "[1/2] 分析文件..."
func_count=$(find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) | wc -l)

echo "[2/2] 生成控制流图（简化版）..."
cat > "$OUTPUT_FLOW" << EOF
{
  "project_dir": "$PROJECT_DIR",
  "timestamp": $(date +%s),
  "functions": {},
  "statistics": {
    "total_functions": 0,
    "total_basic_blocks": 0,
    "total_branches": 0,
    "total_loops": 0,
    "avg_cyclomatic_complexity": 0
  },
  "note": "简化版控制流图，函数识别功能待完善"
}
EOF

echo "✓ 控制流图构建完成: $OUTPUT_FLOW"
echo "  - 扫描文件: $func_count"
echo "  - 函数总数: 0 (简化版)"
echo ""
echo "注意：当前为简化版本，函数识别功能待完善"
