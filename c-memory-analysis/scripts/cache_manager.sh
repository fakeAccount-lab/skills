#!/bin/bash
# cache_manager.sh - 管理分析缓存
#
# 用法：
#   cache_manager.sh init /path/to/cache/dir              # 初始化缓存目录
#   cache_manager.sh check /path/to/file /path/to/cache/dir  # 检查文件是否在缓存中
#   cache_manager.sh get /path/to/file /path/to/cache/dir    # 获取文件的缓存结果
#   cache_manager.sh set /path/to/file /path/to/cache/dir /path/to/result.json  # 设置缓存
#   cache_manager.sh invalidate /path/to/file /path/to/cache/dir  # 使缓存失效
#   cache_manager.sh clean /path/to/cache/dir             # 清理过期缓存
#
# 缓存结构：
#   .c-memory-analysis-cache/
#   ├── file_hash/           # 文件哈希
#   │   ├── file1.md5
#   │   └── file2.md5
#   ├── analysis_results/    # 分析结果
#   │   ├── file1.json
#   │   └── file2.json
#   └── metadata.json        # 缓存元数据

set -euo pipefail

CACHE_ROOT=".c-memory-analysis-cache"

# 初始化缓存目录
init_cache() {
    local cache_dir="$1"
    mkdir -p "$cache_dir/$CACHE_ROOT/file_hash"
    mkdir -p "$cache_dir/$CACHE_ROOT/analysis_results"

    # 创建元数据文件
    cat > "$cache_dir/$CACHE_ROOT/metadata.json" << EOF
{
  "version": "1.0",
  "created_at": $(date +%s),
  "last_updated": $(date +%s)
}
EOF

    echo "缓存目录已初始化: $cache_dir/$CACHE_ROOT"
}

# 检查文件是否在缓存中
check_cache() {
    local file="$1"
    local cache_dir="$2"

    if [ ! -d "$cache_dir/$CACHE_ROOT" ]; then
        echo "false"
        return
    fi

    # 计算当前文件哈希
    local current_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

    # 读取缓存的哈希
    local cache_hash_file="$cache_dir/$CACHE_ROOT/file_hash/$(basename "$file").md5"

    if [ ! -f "$cache_hash_file" ]; then
        echo "false"
        return
    fi

    local cached_hash=$(cat "$cache_hash_file")

    # 比较哈希
    if [ "$current_hash" = "$cached_hash" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# 获取文件的缓存结果
get_cache() {
    local file="$1"
    local cache_dir="$2"

    local cache_result="$cache_dir/$CACHE_ROOT/analysis_results/$(basename "$file").json"

    if [ -f "$cache_result" ]; then
        cat "$cache_result"
    else
        echo "null"
    fi
}

# 设置缓存
set_cache() {
    local file="$1"
    local cache_dir="$2"
    local result_file="$3"

    # 确保缓存目录存在
    mkdir -p "$cache_dir/$CACHE_ROOT/file_hash"
    mkdir -p "$cache_dir/$CACHE_ROOT/analysis_results"

    # 计算文件哈希
    local file_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

    # 保存哈希
    echo "$file_hash" > "$cache_dir/$CACHE_ROOT/file_hash/$(basename "$file").md5"

    # 保存结果
    cp "$result_file" "$cache_dir/$CACHE_ROOT/analysis_results/$(basename "$file").json"

    # 更新元数据
    local metadata_file="$cache_dir/$CACHE_ROOT/metadata.json"
    if [ -f "$metadata_file" ]; then
        # 使用 sed 更新 last_updated（简化版）
        local timestamp=$(date +%s)
        sed -i "s/\"last_updated\": [0-9]*/\"last_updated\": $timestamp/" "$metadata_file"
    fi

    echo "缓存已设置: $file"
}

# 使缓存失效
invalidate_cache() {
    local file="$1"
    local cache_dir="$2"

    local hash_file="$cache_dir/$CACHE_ROOT/file_hash/$(basename "$file").md5"
    local result_file="$cache_dir/$CACHE_ROOT/analysis_results/$(basename "$file").json"

    # 删除缓存文件
    [ -f "$hash_file" ] && rm "$hash_file"
    [ -f "$result_file" ] && rm "$result_file"

    echo "缓存已失效: $file"
}

# 清理过期缓存
clean_cache() {
    local cache_dir="$1"
    local max_age_days=${2:-30}

    if [ ! -d "$cache_dir/$CACHE_ROOT" ]; then
        echo "缓存目录不存在: $cache_dir/$CACHE_ROOT"
        return
    fi

    local max_age_seconds=$((max_age_days * 86400))
    local current_time=$(date +%s)
    local cleaned_count=0

    # 遍历分析结果目录
    find "$cache_dir/$CACHE_ROOT/analysis_results" -name "*.json" -type f | while IFS= read -r result_file; do
        local file_mtime=$(stat -c %Y "$result_file" 2>/dev/null || echo "0")
        local age=$((current_time - file_mtime))

        if [ $age -gt $max_age_seconds ]; then
            rm "$result_file"
            rm "$cache_dir/$CACHE_ROOT/file_hash/$(basename "$result_file" .json).md5" 2>/dev/null || true
            cleaned_count=$((cleaned_count + 1))
        fi
    done

    echo "已清理 $cleaned_count 个过期缓存文件"
}

# 主函数
main() {
    local command="$1"
    shift

    case "$command" in
        init)
            init_cache "$@"
            ;;
        check)
            check_cache "$@"
            ;;
        get)
            get_cache "$@"
            ;;
        set)
            set_cache "$@"
            ;;
        invalidate)
            invalidate_cache "$@"
            ;;
        clean)
            clean_cache "$@"
            ;;
        *)
            echo "错误：未知命令: $command" >&2
            echo "可用命令: init, check, get, set, invalidate, clean" >&2
            exit 1
            ;;
    esac
}

main "$@"
