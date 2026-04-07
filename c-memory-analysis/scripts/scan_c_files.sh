#!/bin/bash
# scan_c_files.sh - 扫描目标目录下所有 C 源文件
#
# 用法：
#   scan_c_files.sh /path/to/project
#
# 输出：
#   输出所有 .c 和 .h 文件的绝对路径，每行一个

set -euo pipefail

PROJECT_DIR="$1"

# 验证参数
if [ -z "$PROJECT_DIR" ]; then
    echo "错误：缺少项目目录参数" >&2
    echo "用法：$0 /path/to/project" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误：目录不存在: $PROJECT_DIR" >&2
    exit 1
fi

# 扫描所有 C 文件
find "$PROJECT_DIR" -type f \( -name "*.c" -o -name "*.h" \) -print
