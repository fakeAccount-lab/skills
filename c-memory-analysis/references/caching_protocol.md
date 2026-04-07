# 缓存协议

本文档描述了 C 内存分析 Skill 的缓存机制和协议。

---

## 缓存目录结构

```
.c-memory-analysis-cache/
├── file_hash/           # 文件哈希存储
│   ├── connection.c.md5
│   ├── main.c.md5
│   └── ...
├── analysis_results/    # 分析结果缓存
│   ├── connection.c.json
│   ├── main.c.json
│   └── ...
└── metadata.json        # 缓存元数据
```

---

## 缓存机制

### 文件哈希

每个文件计算 MD5 哈希值，存储在 `file_hash/` 目录中：

```
.c-memory-analysis-cache/file_hash/connection.c.md5
内容：a1b2c3d4e5f6...
```

**用途**：
- 检测文件是否被修改
- 增量分析时跳过未修改的文件

---

### 分析结果

每个文件的分析结果存储在 `analysis_results/` 目录中：

```json
.c-memory-analysis-cache/analysis_results/connection.c.json
{
  "file": "src/network/connection.c",
  "hash": "a1b2c3d4e5f6...",
  "analyzed_at": 1712467200,
  "issues": [
    {
      "type": "memory_leak",
      "severity": "high",
      "line": 45,
      ...
    }
  ]
}
```

---

### 元数据

`metadata.json` 存储缓存的全局信息：

```json
{
  "version": "1.0",
  "created_at": 1712467200,
  "last_updated": 1712553600,
  "total_files": 100,
  "cached_files": 95
}
```

---

## 缓存操作

### 初始化缓存

```bash
cache_manager.sh init /path/to/project
```

**操作**：
- 创建 `.c-memory-analysis-cache/` 目录
- 创建子目录：`file_hash/`、`analysis_results/`
- 创建 `metadata.json`

---

### 检查缓存

```bash
cache_manager.sh check /path/to/file.c /path/to/project
```

**返回**：
- `true` - 文件在缓存中且哈希匹配
- `false` - 文件不在缓存中或哈希不匹配

**内部逻辑**：
1. 计算当前文件哈希：`md5sum file.c`
2. 读取缓存的哈希：`.c-memory-analysis-cache/file_hash/file.c.md5`
3. 比较哈希值

---

### 获取缓存

```bash
cache_manager.sh get /path/to/file.c /path/to/project
```

**返回**：
- JSON 格式的分析结果
- `null` - 如果缓存不存在

---

### 设置缓存

```bash
cache_manager.sh set /path/to/file.c /path/to/project /path/to/result.json
```

**操作**：
1. 计算文件哈希
2. 保存哈希到 `file_hash/file.c.md5`
3. 保存结果到 `analysis_results/file.c.json`
4. 更新 `metadata.json` 中的 `last_updated`

---

### 使缓存失效

```bash
cache_manager.sh invalidate /path/to/file.c /path/to/project
```

**操作**：
1. 删除 `file_hash/file.c.md5`
2. 删除 `analysis_results/file.c.json`

**使用场景**：
- 文件被修改
- 手动触发重新分析

---

### 清理缓存

```bash
cache_manager.sh clean /path/to/project [max_age_days]
```

**参数**：
- `max_age_days` - 缓存过期天数（默认 30 天）

**操作**：
1. 遍历 `analysis_results/` 目录
2. 删除超过 `max_age_days` 的缓存文件
3. 删除对应的哈希文件

---

## 增量分析流程

### 步骤 1: 检查缓存

```bash
# 对每个文件
for file in $(find . -name "*.c"); do
    cached=$(cache_manager.sh check "$file" /path/to/project)

    if [ "$cached" = "true" ]; then
        # 使用缓存结果
        result=$(cache_manager.sh get "$file" /path/to/project)
        echo "$result" >> output.json
    else
        # 重新分析
        analyze_file "$file" > /tmp/result.json
        cache_manager.sh set "$file" /path/to/project /tmp/result.json
        cat /tmp/result.json >> output.json
    fi
done
```

---

### 步骤 2: 分析受影响的文件

当一个文件被修改时，需要重新分析：
1. 该文件本身
2. 调用该文件中函数的所有文件
3. 被该文件中函数调用的所有文件

**原因**：
- 调用链可能改变（如函数签名变化）
- 数据流可能改变（如参数类型变化）

---

### 步骤 3: 更新缓存

所有重新分析的文件都要更新缓存。

---

## 缓存失效策略

### 自动失效

当以下情况发生时，缓存自动失效：
- 文件哈希不匹配
- 超过 `max_age_days` 未使用

---

### 手动失效

用户可以手动触发缓存失效：
```bash
cache_manager.sh invalidate /path/to/file.c /path/to/project
```

---

### 批量失效

用户可以批量失效所有缓存：
```bash
rm -rf /path/to/project/.c-memory-analysis-cache/
```

---

## 缓存清理策略

### 定时清理

建议每月清理一次过期缓存：
```bash
cache_manager.sh clean /path/to/project 30
```

---

### 清理触发条件

- 缓存文件超过 30 天未访问
- 缓存目录大小超过限制（如 1GB）
- 磁盘空间不足

---

## 缓存性能影响

### 缓存命中率

典型缓存命中率：
- 小型项目（< 10w 行）：80-90%
- 中型项目（10-50w 行）：70-80%
- 大型项目（> 50w 行）：60-70%

---

### 性能对比

| 操作 | 无缓存 | 有缓存 | 加速比 |
|-----|-------|-------|-------|
| 首次分析 | 4 小时 | 4 小时 | 1x |
| 修改 1% 代码（无缓存） | 4 小时 | - | - |
| 修改 1% 代码（有缓存） | - | 3 分钟 | 80x |
| 修改 10% 代码（无缓存） | 4 小时 | - | - |
| 修改 10% 代码（有缓存） | - | 25 分钟 | 9.6x |

---

## 缓存存储建议

### 磁盘空间

预估缓存大小：
- 每个文件：~10KB（哈希 + 分析结果）
- 1000 个文件：~10MB
- 10000 个文件：~100MB
- 100000 个文件：~1GB

---

### 存储位置

建议将缓存存储在：
- 项目根目录：`/path/to/project/.c-memory-analysis-cache/`
- 或者系统缓存目录：`~/.cache/c-memory-analysis/`

---

### Git 忽略

建议将缓存目录添加到 `.gitignore`：
```
.c-memory-analysis-cache/
```

---

## 缓存安全性

### 敏感代码

如果代码包含敏感信息：
- 缓存可能包含代码片段（上下文）
- 建议加密缓存（未来扩展）

### 访问控制

建议设置缓存目录权限：
```bash
chmod 700 /path/to/project/.c-memory-analysis-cache/
```

---

## 缓存错误处理

### 缓存损坏

如果缓存文件损坏：
1. 删除损坏的缓存文件
2. 重新分析对应的源文件
3. 更新缓存

### 缓存版本不匹配

如果缓存格式版本不匹配：
1. 清空所有缓存
2. 重新分析

---

## 缓存调试

### 查看缓存状态

```bash
# 统计缓存文件数量
ls -1 /path/to/project/.c-memory-analysis-cache/analysis_results/ | wc -l

# 查看缓存大小
du -sh /path/to/project/.c-memory-analysis-cache/

# 查看缓存元数据
cat /path/to/project/.c-memory-analysis-cache/metadata.json
```

---

### 验证缓存完整性

```bash
# 对所有缓存文件
for hash_file in /path/to/project/.c-memory-analysis-cache/file_hash/*.md5; do
    file=$(basename "$hash_file" .md5)
    cached_hash=$(cat "$hash_file")
    current_hash=$(md5sum "/path/to/project/$file" | cut -d' ' -f1)

    if [ "$cached_hash" != "$current_hash" ]; then
        echo "缓存失效: $file"
    fi
done
```
