#!/bin/bash
# analysis_package_generator.sh - 简化版
set -euo pipefail

PROJECT_DIR="$1"
CALL_GRAPH="$2"
SYMBOL_TABLE="$3"
CONTROLFLOW="$4"
OUTPUT_DIR="$5"

mkdir -p "$OUTPUT_DIR"

echo "[1/5] 扫描可疑模式..."
# 简化版：只扫描不安全函数
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -exec grep -l -E '\b(gets|strcpy|strcat|sprintf)\s*\(' {} \; 2>/dev/null | head -20 > /tmp/suspicious_files.txt

suspicious_count=$(wc -l < /tmp/suspicious_files.txt)
echo "    找到 $suspicious_count 个可疑文件"

echo "[2/5] 生成分析包..."
pkg_counter=0

while IFS= read -r file; do
    pkg_counter=$((pkg_counter + 1))
    pkg_file="$OUTPUT_DIR/suspicious_${pkg_counter}.json"

    # 提取可疑函数调用
    suspicious_lines=$(grep -n -E '\b(gets|strcpy|strcat|sprintf)\s*\(' "$file" 2>/dev/null | head -5)

    cat > "$pkg_file" << EOF
{
  "package_id": "$pkg_counter",
  "suspicious_point": {
    "file": "$file",
    "type": "unsafe_function",
    "description": "Found unsafe function calls (gets, strcpy, strcat, sprintf)"
  },
  "context": {
    "suspicious_lines": $(echo "$suspicious_lines" | head -1 | jq -Rs '.' 2>/dev/null || echo '"[]"')
  },
  "call_chain": {},
  "controlflow": {},
  "analysis_hints": {
    "check_for": [
      "Verify if input is properly validated",
      "Check for buffer size checks",
      "Consider using safer alternatives (fgets, strncpy, strncat, snprintf)"
    ]
  }
}
EOF

done < /tmp/suspicious_files.txt

rm -f /tmp/suspicious_files.txt

echo "✓ 分析包生成完成: $OUTPUT_DIR"
echo "  - 分析包数量: $pkg_counter"
echo ""
echo "注意：当前为简化版本，仅识别不安全函数调用"
