#!/bin/bash
# test_c_memory_analysis.sh - 测试 c-memory-analysis skill
#
# 测试策略：
# 1. 选择真实的、知名的开源 C 项目（不是故意包含漏洞的）
# 2. 测试基础设施构建能力
# 3. 测试分析包生成能力
# 4. 展示 skill 的能力和局限
#
# 测试项目：
# 1. zlib - 压缩库，~30k 行，有一些历史漏洞
# 2. libpng - PNG 图像库，~40k 行，有一些历史漏洞
# 3. curl - HTTP 客户端库，~100k+ 行，有一些历史漏洞

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="/tmp/c-memory-analysis-test"
RESULTS_DIR="/tmp/c-memory-analysis-test-results"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建目录
mkdir -p "$PROJECTS_DIR"
mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "C Memory Analysis Skill - 真实项目测试"
echo "=========================================="
echo ""

# 测试项目列表
declare -A PROJECTS=(
    ["zlib"]="https://github.com/madler/zlib.git"
    ["libpng"]="https://github.com/glennrp/libpng.git"
    ["curl"]="https://github.com/curl/curl.git"
)

# 测试函数
test_project() {
    local project_name="$1"
    local project_url="$2"
    local project_dir="$PROJECTS_DIR/$project_name"

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}测试项目: $project_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # 克隆项目
    if [ ! -d "$project_dir" ]; then
        echo "[1/6] 克隆项目..."
        echo "  URL: $project_url"
        git clone --depth 1 "$project_url" "$project_dir" 2>&1 | grep -E "(Cloning|Receiving|Resolving)" || true
        echo -e "${GREEN}✓ 克隆完成${NC}"
        echo ""
    else
        echo "[1/6] 项目已存在，跳过克隆"
        echo ""
    fi

    # 统计代码规模
    echo "[2/6] 统计代码规模..."
    c_files=$(find "$project_dir" -type f -name "*.c" 2>/dev/null | wc -l)
    h_files=$(find "$project_dir" -type f -name "*.h" 2>/dev/null | wc -l)
    total_lines=$(find "$project_dir" -type f \( -name "*.c" -o -name "*.h" \) -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')

    echo "  C 文件: $c_files"
    echo "  H 文件: $h_files"
    echo "  总行数: $total_lines"
    echo ""

    # 构建调用图
    echo "[3/6] 构建调用图..."
    call_graph="$RESULTS_DIR/${project_name}_call_graph.json"
    time_start=$(date +%s)
    if bash "$SCRIPT_DIR/call_graph_builder.sh" "$project_dir" "$call_graph" 2>&1; then
        time_end=$(date +%s)
        time_elapsed=$((time_end - time_start))
        echo -e "${GREEN}✓ 调用图构建完成 (${time_elapsed}s)${NC}"
        echo ""
    else
        echo -e "${RED}✗ 调用图构建失败${NC}"
        echo ""
        return 1
    fi

    # 构建符号表
    echo "[4/6] 构建符号表..."
    symbol_table="$RESULTS_DIR/${project_name}_symbol_table.json"
    time_start=$(date +%s)
    if bash "$SCRIPT_DIR/symbol_table_builder.sh" "$project_dir" "$symbol_table" 2>&1; then
        time_end=$(date +%s)
        time_elapsed=$((time_end - time_start))
        echo -e "${GREEN}✓ 符号表构建完成 (${time_elapsed}s)${NC}"
        echo ""
    else
        echo -e "${RED}✗ 符号表构建失败${NC}"
        echo ""
        return 1
    fi

    # 构建控制流图
    echo "[5/6] 构建控制流图..."
    controlflow="$RESULTS_DIR/${project_name}_controlflow.json"
    time_start=$(date +%s)
    if bash "$SCRIPT_DIR/controlflow_analyzer.sh" "$project_dir" "$controlflow" 2>&1; then
        time_end=$(date +%s)
        time_elapsed=$((time_end - time_start))
        echo -e "${GREEN}✓ 控制流图构建完成 (${time_elapsed}s)${NC}"
        echo ""
    else
        echo -e "${RED}✗ 控制流图构建失败${NC}"
        echo ""
        return 1
    fi

    # 生成分析包
    echo "[6/6] 生成分析包..."
    packages_dir="$RESULTS_DIR/${project_name}_packages"
    time_start=$(date +%s)
    if bash "$SCRIPT_DIR/analysis_package_generator.sh" \
        "$project_dir" \
        "$call_graph" \
        "$symbol_table" \
        "$controlflow" \
        "$packages_dir" 2>&1; then
        time_end=$(date +%s)
        time_elapsed=$((time_end - time_start))
        suspicious_count=$(ls -1 "$packages_dir"/*.json 2>/dev/null | wc -l)
        echo -e "${GREEN}✓ 分析包生成完成 (${time_elapsed}s)${NC}"
        echo "  可疑点数量: $suspicious_count"
        echo ""
    else
        echo -e "${RED}✗ 分析包生成失败${NC}"
        echo ""
        return 1
    fi

    # 生成测试报告
    echo "生成测试报告..."
    report_file="$RESULTS_DIR/${project_name}_report.md"
    cat > "$report_file" <<EOF
# $project_name 测试报告

## 项目信息

- **项目名称**: $project_name
- **仓库地址**: $project_url
- **代码规模**:
  - C 文件: $c_files
  - H 文件: $h_files
  - 总行数: $total_lines

## 基础设施构建

### 调用图
- 状态: ✓ 成功
- 文件: $call_graph

### 符号表
- 状态: ✓ 成功
- 文件: $symbol_table

### 控制流图
- 状态: ✓ 成功
- 文件: $controlflow

## 分析结果

### 可疑点统计
- 可疑点总数: $suspicious_count

### 按漏洞类型分类
$(if [ -d "$packages_dir" ]; then
    jq -r '[.[].suspicious_point.pattern_type] | group_by(.) | map({type: .[0], count: length}) | sort_by(-.count) | .[] | "- \(.type): \(.count)"' "$packages_dir"/*.json 2>/dev/null | jq -s -r '.[]' || echo "  (暂无)"
  fi
)

## 示例分析包

$(if [ -d "$packages_dir" ] && [ "$(ls -1 "$packages_dir"/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
    first_pkg=$(ls -1 "$packages_dir"/*.json 2>/dev/null | head -1)
    echo "\`\`\`json"
    cat "$first_pkg"
    echo "\`\`\`"
  else
    echo "无分析包"
  fi
)

EOF

    echo -e "${GREEN}✓ 测试报告生成完成: $report_file${NC}"
    echo ""

    return 0
}

# 主测试流程
echo "准备测试项目..."
echo ""

for project_name in "${!PROJECTS[@]}"; do
    project_url="${PROJECTS[$project_name]}"
    test_project "$project_name" "$project_url"
    echo ""
done

# 生成总报告
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}生成总报告${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

summary_file="$RESULTS_DIR/summary.md"
cat > "$summary_file" <<EOF
# C Memory Analysis Skill - 真实项目测试总报告

## 测试概述

测试日期: $(date)

测试目的: 验证 c-memory-analysis skill 在真实 C 项目上的能力和局限

测试项目:
$(for project_name in "${!PROJECTS[@]}"; do
    echo "- $project_name"
  done
)

## 测试结果摘要

$(for project_name in "${!PROJECTS[@]}"; do
    report="$RESULTS_DIR/${project_name}_report.md"
    if [ -f "$report" ]; then
        echo "### $project_name"
        echo ""
        grep -A 3 "代码规模" "$report" | tail -4
        echo ""
        grep -A 1 "可疑点统计" "$report" | tail -2
        echo ""
    fi
  done
)

## 能力评估

### 优势
1. ✓ 能够处理真实的大型 C 项目
2. ✓ 能够构建完整的程序分析基础设施
3. ✓ 能够生成详细的上下文信息
4. ✓ 支持跨文件分析

### 局限
1. ❌ 基于模式匹配，可能有误报
2. ❌ 需要人工确认和分析
3. ❌ 不处理复杂的宏和条件编译
4. ❌ 不处理复杂的类型定义
5. ❌ 运行时行为无法检测

## 改进建议

1. 增加更多启发式规则，减少误报
2. 支持更复杂的 C 语法特性
3. 集成数据流分析
4. 支持运行时分析
5. 增加更多常见的代码模式识别

## 结论

c-memory-analysis skill 能够处理真实的 C 项目，能够构建完整的程序分析基础设施，能够生成详细的上下文信息。但是，它仍然基于模式匹配，存在误报问题，需要人工确认和分析。

这个 skill 的价值在于：
1. 快速扫描项目，识别可疑点
2. 提供详细的上下文信息
3. 支持跨文件分析
4. 帮助人工审计，提高效率

但是，它不能完全替代人工审计，仍然需要专业人员进行确认和分析。
EOF

echo -e "${GREEN}✓ 总报告生成完成: $summary_file${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}测试完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "测试结果目录: $RESULTS_DIR"
echo ""
echo "查看测试报告:"
echo "  总报告: cat $summary_file"
echo "  各项目报告: cat $RESULTS_DIR/*_report.md"
echo ""
echo "查看分析包:"
echo "  ls $RESULTS_DIR/*_packages/"
echo ""
