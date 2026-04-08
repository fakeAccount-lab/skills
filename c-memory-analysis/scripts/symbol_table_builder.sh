#!/bin/bash
# symbol_table_builder.sh - 最小可用版本
set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_TABLE="$2"

mkdir -p "$(dirname "$OUTPUT_TABLE")"

echo "[1/2] 扫描文件和变量..."
var_count=$(find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) | wc -l)

echo "[2/2] 生成符号表（简化版）..."
cat > "$OUTPUT_TABLE" << EOF
{
  "project_dir": "$PROJECT_DIR",
  "timestamp": $(date +%s),
  "variables": [],
  "statistics": {
    "total_variables": 0,
    "global_variables": 0,
    "local_variables": 0,
    "pointer_variables": 0,
    "variables_with_malloc": 0,
    "variables_with_free": 0
  },
  "note": "简化版符号表，变量识别功能待完善"
}
EOF

echo "✓ 符号表构建完成: $OUTPUT_TABLE"
echo "  - 扫描文件: $var_count"
echo "  - 变量总数: 0 (简化版)"
echo ""
echo "注意：当前为简化版本，变量识别功能待完善"
