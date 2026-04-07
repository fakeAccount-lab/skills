# C 语言内存漏洞分析策略

本文档描述了如何利用 AI Agent 的深度分析能力来检测 C 语言内存漏洞。

---

## 核心原则

1. **先模式匹配，再深度分析**：先找到可疑模式，再深入确认是否真的有问题
2. **跨文件分析**：理解调用链和数据流，不只看单个文件
3. **理解代码意图**：判断代码是否 intentional 的（如缓存、单例等）
4. **提供证据链**：清晰展示分析过程，便于人工确认

---

## 分析流程

### Phase 1: 预扫描（辅助脚本）

**目标**：快速扫描项目，生成基础索引

**步骤**：
1. `scan_c_files.sh` - 扫描所有 .c/.h 文件
2. `build_file_index.sh` - 构建文件级索引（函数、可疑函数调用）
3. `partition_project.sh` - 智能分批（按文件/模块）

**输出**：
- 文件列表
- 批次文件（batch_001.txt, batch_002.txt, ...）
- 文件索引（函数、可疑调用）

---

### Phase 2: 可疑点检测（AI Agent，模式匹配）

**目标**：在每个批次中找到可疑模式

**步骤**：
1. 读取批次文件中的所有文件
2. 对每种漏洞类型进行模式匹配：
   - 返回局部变量：`return &local_var`
   - 内存泄漏：`malloc` 无配对 `free`
   - Double Free：同一指针多次 `free`
   - Use-After-Free：`free` 后继续使用
   - 堆溢出：`malloc` 大小与写入不匹配
   - 空指针解引用：未检查指针直接使用
   - 数组越界：索引可能超出边界
   - 未初始化内存：`malloc` 后立即读取
   - 格式化字符串：`printf(user_input)`
   - 不安全函数：`gets/strcpy/strcat/sprintf`

**输出**：
- 可疑点列表（每个点包含：文件、行号、漏洞类型）

---

### Phase 3: 深度分析（AI Agent，逐个确认）

**目标**：对每个可疑点进行深度分析，确认是否真的是漏洞

**步骤**：
1. **提取上下文**：读取可疑点前后的代码（前后 20 行）
2. **追溯数据流**：
   - 数据从哪里来？（用户输入、配置文件、内部计算）
   - 数据流向哪里？（内存写入、函数参数、返回值）
3. **追溯调用链**：
   - 谁调用了这个函数？
   - 在什么上下文中被调用？
   - 调用链中是否有保护逻辑？
4. **分析控制流**：
   - 是否有条件分支保护？
   - 是否有异常路径？
   - 是否有前置校验？
5. **理解代码意图**：
   - 这是 intentional 的设计吗？（如缓存、单例）
   - 是否有设计文档或注释说明？
   - 是否符合项目规范？

**输出**：
- 确认的漏洞列表
- 每个漏洞的详细分析报告

---

### Phase 4: 报告生成（AI Agent）

**目标**：生成清晰、详细的漏洞报告

**报告格式**：

```json
{
  "summary": {
    "total_files": 100,
    "analyzed_files": 100,
    "found_issues": 25,
    "critical_issues": 5,
    "high_issues": 10,
    "medium_issues": 8,
    "low_issues": 2
  },
  "issues": [
    {
      "id": "ISSUE-001",
      "type": "memory_leak",
      "severity": "high",
      "confidence": "high",
      "file": "src/network/connection.c",
      "line": 45,
      "function": "create_connection",
      "title": "Memory Leak: malloc not freed",
      "description": "Memory allocated at line 45 is never freed in any execution path.",
      "evidence_chain": [
        "1. Line 45: ptr = malloc(1024);",
        "2. Traced ptr lifecycle: used in lines 50, 60, 80",
        "3. No free(ptr) found in any execution path",
        "4. Pointer not stored in global data structures"
      ],
      "false_positive_check": [
        "Checked if ptr is stored in global cache: No",
        "Checked if free exists in other modules: No",
        "Checked if intentional long-lifetime object: No evidence in code/comments"
      ],
      "manual_verification_needed": false,
      "fix_suggestion": "Add free(ptr) before function return or in cleanup function"
    }
  ]
}
```

---

## 分批分析策略

### 策略 1: 按文件分批（默认）

**适用场景**：大多数项目

**优点**：
- 简单直接
- 每批次独立，无状态依赖
- 易于并行处理

**缺点**：
- 可能忽略跨文件的调用关系

**实现**：
```bash
partition_project.sh /path/to/project /output/batches --strategy files --max-batch-size 10
```

---

### 策略 2: 按模块分批

**适用场景**：大型项目，有清晰的模块划分

**优点**：
- 更符合项目结构
- 同一批次的文件相关性强

**缺点**：
- 可能产生不均匀的批次大小

**实现**：
```bash
partition_project.sh /path/to/project /output/batches --strategy modules
```

---

### 策略 3: 按函数分批（未来扩展）

**适用场景**：需要极其精细的分析

**优点**：
- 粒度最细
- 易于定位问题

**缺点**：
- 需要函数级索引
- 跨函数分析复杂

**实现**：
```bash
partition_project.sh /path/to/project /output/batches --strategy functions
```

---

## 增量分析策略

### 触发条件
- 代码被修改（git diff 检测）
- 用户手动触发

### 分析流程
1. 检查文件哈希（使用 `cache_manager.sh check`）
2. 如果哈希匹配：
   - 使用缓存结果（`cache_manager.sh get`）
3. 如果哈希不匹配：
   - 重新分析文件
   - 更新缓存（`cache_manager.sh set`）
4. 重新分析受影响的文件（调用链中依赖该文件的文件）

### 性能对比

| 修改比例 | 全量分析时间 | 增量分析时间 | 加速比 |
|---------|------------|------------|-------|
| 1% | 4 小时 | 3 分钟 | 80x |
| 5% | 4 小时 | 12 分钟 | 20x |
| 10% | 4 小时 | 25 分钟 | 9.6x |
| 20% | 4 小时 | 50 分钟 | 4.8x |

---

## 并行分析策略

### 并行度控制

**原则**：
- 并行度 ≤ CPU 核心数
- 预留 1-2 核给系统和其他进程

**实现**：
```bash
MAX_PARALLEL=4

for batch in $(ls batches/batch_*.txt); do
    analyze_module.sh "$batch" "output/$(basename $batch).json" &

    # 控制并发数
    if [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; then
        wait -n
    fi
done

wait  # 等待所有后台任务完成
```

---

## 恢复分析策略

### 检查点机制

**标记文件**：
- `batch_001.done` - 批次完成
- `batch_001.failed` - 批次失败

**恢复流程**：
1. 使用 `resume_analysis.sh` 检查批次状态
2. 跳过已完成的批次（`.done`）
3. 重新尝试失败的批次（`.failed`）
4. 继续分析未开始的批次

---

## 误报控制策略

### 高置信度规则

以下情况标记为 **高置信度**（误报率 < 5%）：
- 返回局部变量地址
- 格式化字符串漏洞（用户输入直接作为格式化字符串）
- 使用不安全函数（`gets`、`strcpy` 等）

---

### 中等置信度规则

以下情况标记为 **中等置信度**（误报率 10-20%）：
- 内存泄漏（未找到 `free`，但可能存储在全局结构中）
- Double Free（同一指针多次 `free`，但可能有保护逻辑）

**人工确认方法**：
- 检查是否有全局数据结构存储指针
- 检查 `free` 前的保护逻辑
- 理解代码的设计意图

---

### 低置信度规则

以下情况标记为 **低置信度**（误报率 20-40%）：
- Use-After-Free（`free` 后使用，但可能在不同的条件分支）
- 数组越界（索引可能超出边界，但可能有边界检查）

**人工确认方法**：
- 追踪 `free` 到 `use` 之间的控制流
- 检查边界检查逻辑
- 理解循环条件和终止条件

---

## 性能优化建议

### 1. 使用缓存

对于大项目，缓存分析结果可以大幅减少重复分析时间。

### 2. 并行处理

利用多核 CPU 并行分析多个批次，可以线性加速。

### 3. 增量分析

只分析修改的文件，而不是全量分析。

### 4. 智能分批

根据文件大小和复杂度调整批次大小，避免某些批次过大。

---

## 人工确认指南

当 AI Agent 标记一个可疑点时，人工确认应该：

1. **阅读证据链**：理解 AI Agent 的分析过程
2. **检查代码上下文**：查看可疑点前后的代码
3. **理解设计意图**：判断是否 intentional 的设计
4. **评估严重性**：判断漏洞的潜在影响
5. **确定修复方案**：制定修复计划
