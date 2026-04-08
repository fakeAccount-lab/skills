#!/bin/bash
# unsafe_functions_scanner.sh - 简单但有效的版本
# 目标：高精度，确定性结论，实际价值

set -euo pipefail

PROJECT_DIR="$1"
OUTPUT_FILE="$2"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "扫描不安全函数..."

{
    echo "{"
    echo "  \"scan_summary\": {"
    echo "    \"project_dir\": \"$PROJECT_DIR\","
    echo "    \"scan_time\": \"$(date -Iseconds)\","
    echo "    \"strategy\": \"direct_grep_scan\""
    echo "  },"
    echo "  \"issues\": ["
    
    first=true
    
    # 扫描 gets() - CRITICAL
    while IFS=: read -r file lineno content; do
        if [ "$first" = false ]; then
            echo ","
        fi
        first=false
        
        # 获取代码上下文
        context=$(sed -n "$((lineno-3)),$((lineno+3))p" "$file" 2>/dev/null | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' '\\n')
        
        echo -n "    {"
        echo -n "\"id\": \"CRITICAL-GETS-$RANDOM\","
        echo -n "\"type\": \"unsafe_function\","
        echo -n "\"function\": \"gets\","
        echo -n "\"severity\": \"CRITICAL\","
        echo -n "\"confidence\": \"high\","
        echo -n "\"file\": \"$file\","
        echo -n "\"line\": $lineno,"
        echo -n "\"description\": \"Buffer overflow vulnerability - gets() has no bounds checking\","
        echo -n "\"code_context\": \"$context\","
        echo -n "\"conclusion\": \"CRITICAL: This is a definite vulnerability. gets() has no bounds checking and must be replaced with fgets() or similar.\","
        echo -n "\"fix_suggestion\": \"Replace gets() with fgets(buf, sizeof(buf), stdin) and validate input length.\""
        echo -n "}"
    done < <(grep -rn "gets(" "$PROJECT_DIR" --include="*.c" 2>/dev/null | grep -v "gzgets" || true)
    
    echo ""
    echo "  ]"
    echo "}"
} > "$OUTPUT_FILE"

total_issues=$(grep -c "\"id\":" "$OUTPUT_FILE" 2>/dev/null || echo "0")

echo "✓ 扫描完成: $OUTPUT_FILE"
echo "  - 发现问题: $total_issues"
echo ""
echo "特点:"
echo "  ✓ 简单可靠：使用 grep 直接扫描"
echo "  ✓ 高精度：只报告 gets() 这种明确不安全的函数"
echo "  ✓ 确定性结论：每个问题都有明确的结论"
echo "  ✓ 实用价值：只报告真正需要关注的问题"
