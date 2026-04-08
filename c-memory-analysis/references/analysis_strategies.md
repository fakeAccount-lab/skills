# C 语言内存漏洞分析策略

本文档描述了如何利用完整的程序分析基础设施和 AI Agent 的深度分析能力来检测 C 语言内存漏洞。

---

## 核心原则

1. **基础设施先行**：先构建调用图、符号表、控制流图，再进行分析
2. **基于分析包分析**：每个可疑点都有完整的上下文信息
3. **跨文件分析**：利用调用图进行跨文件依赖分析
4. **数据流追踪**：理解数据在程序中的流动
5. **理解代码意图**：判断代码是否 intentional 的（如缓存、单例等）
6. **业务场景分析**：分析漏洞在什么情况下会被触发
7. **提供证据链**：清晰展示分析过程，便于人工确认

---

## 分析流程

### Phase 0: 基础设施构建（脚本完成）

**目标**：构建完整的程序分析基础设施

**步骤**：
1. `call_graph_builder.sh` - 构建函数调用图
2. `symbol_table_builder.sh` - 构建符号表
3. `controlflow_analyzer.sh` - 构建控制流图
4. `analysis_package_generator.sh` - 生成分析包

**输出**：
- `call_graph.json` - 完整的函数调用关系图
- `symbol_table.json` - 所有变量信息（类型、作用域、生命周期）
- `controlflow.json` - 控制流分析（基本块、分支、循环）
- `analysis_packages/suspicious_*.json` - 每个可疑点的分析包

**时间成本**（30k 行代码）：
- 调用图：5-10 分钟
- 符号表：5-10 分钟
- 控制流：5-10 分钟
- 分析包：2-3 分钟
- **总计**：17-33 分钟

---

### Phase 1: 可疑点识别（脚本完成）

**目标**：识别所有可疑模式

**步骤**：
1. 扫描所有 C 文件
2. 匹配可疑模式（10 类漏洞）
3. 为每个可疑点提取上下文（前后 20 行）
4. 从基础设施中提取相关信息
5. 生成分析包

**可疑模式**：
1. 返回局部变量地址：`return &local_var`
2. 内存泄漏：`malloc`/`calloc`/`realloc` 无配对 `free`
3. Double Free：同一指针多次 `free`
4. Use-After-Free：`free` 后继续使用
5. 堆溢出：`malloc` 大小与写入不匹配
6. 空指针解引用：未检查指针直接使用
7. 数组越界：索引可能超出边界
8. 未初始化内存：`malloc` 后立即读取
9. 格式化字符串：`printf(user_input)` 无 `"%s"`
10. 不安全函数：`gets`, `strcpy`, `strcat`, `sprintf`

**输出**：
- 分析包列表（每个包包含完整的上下文信息）

---

### Phase 2: 上下文理解（AI Agent 完成）

**目标**：理解可疑点的上下文

**步骤**：
1. **读取分析包**
2. **审查代码片段**：
   - 理解可疑点前后的代码逻辑
   - 识别变量的用途
   - 理解函数的业务逻辑
3. **检查变量信息**：
   - 变量的类型和作用域
   - 变量的生命周期（栈/堆/全局）
   - 是否有内存操作（malloc/free）
4. **检查调用关系**：
   - 谁调用了这个函数？（调用者）
   - 这个函数调用了谁？（被调用者）
   - 是否有跨文件依赖？
5. **分析控制流**：
   - 是否有条件分支？
   - 是否有循环？
   - 有哪些退出路径？

**输出**：
- 对可疑点的初步理解
- 识别出需要进一步分析的关键点

---

### Phase 3: 数据流分析（AI Agent 完成）

**目标**：追踪数据的流动

**步骤**：
1. **追溯数据来源**：
   - 数据从哪里来？（用户输入、配置文件、内部计算、函数参数）
   - 数据是否经过验证？
   - 数据是否经过转换？
2. **追溯数据去向**：
   - 数据流向哪里？（内存写入、函数参数、返回值）
   - 是否有边界检查？
   - 是否有危险操作？
3. **跨文件数据流**：
   - 数据是否通过函数参数传递到其他文件？
   - 是否通过返回值传递？
   - 是否通过全局变量传递？
4. **识别所有路径**：
   - 正常路径（Happy Path）
   - 错误路径（Error Path）
   - 异常路径（Exception Path）

**示例**：
```c
// File: src/input/read.c
char* read_user_input() {
    char *buf = malloc(1024);
    read(stdin, buf, 1024);  // 数据来源：用户输入
    return buf;
}

// File: src/parse/process.c
void process_data(char *data) {
    char buffer[100];
    strcpy(buffer, data);  // 数据流向：strcpy，可能溢出
}

// File: src/main.c
int main() {
    char *input = read_user_input();
    process_data(input);  // 跨文件传递
    free(input);
}
```

**数据流追踪**：
1. `read_user_input()` - 从用户输入读取数据
2. 返回指针传递给 `main()`
3. `main()` 将数据传递给 `process_data()`
4. `process_data()` 使用 `strcpy` 复制数据（危险！）

**分析**：
- 没有验证输入长度
- `strcpy` 不检查边界
- 可能导致堆溢出

**输出**：
- 完整的数据流追踪
- 识别出的危险操作
- 缺失的验证点

---

### Phase 4: 跨文件依赖分析（AI Agent 完成）

**目标**：分析跨文件的依赖关系

**步骤**：
1. **使用调用图**：
   - 查找调用者的所有调用者（递归）
   - 查找被调用者的所有被调用者（递归）
   - 识别跨文件的调用链
2. **追踪指针传递**：
   - 指针是否通过参数传递到其他函数？
   - 指针是否通过返回值传递？
   - 指针是否存储在全局结构中？
3. **查找跨文件管理**：
   - 是否有其他文件负责释放内存？
   - 是否有 cleanup 函数在其他文件？
   - 是否有跨文件的生命周期管理？
4. **验证所有路径**：
   - 检查所有跨文件路径
   - 验证每个路径的内存管理
   - 识别遗漏的释放

**示例**：
```c
// File: src/memory/alloc.c
void* allocate_buffer(size_t size) {
    return malloc(size);  // 分配内存
}

// File: src/memory/free.c
void free_buffer(void *ptr) {
    free(ptr);  // 释放内存
}

// File: src/core/processor.c
void process_data() {
    void *buf = allocate_buffer(1024);
    // ... 使用 buf ...
    free_buffer(buf);  // 释放内存
}
```

**跨文件分析**：
1. `process_data()` 调用 `allocate_buffer()` (跨文件)
2. `process_data()` 调用 `free_buffer()` (跨文件)
3. 内存分配和释放在不同文件
4. 需要确保所有路径都调用 `free_buffer()`

**输出**：
- 完整的跨文件调用链
- 识别出的跨文件依赖
- 验证结果

---

### Phase 5: 代码意图理解（AI Agent 完成）

**目标**：判断代码是否 intentional 的设计

**常见模式**：

#### 1. 缓存模式（Cache Pattern）

```c
static buffer_t *global_cache = NULL;

buffer_t* get_cached_buffer() {
    if (global_cache == NULL) {
        global_cache = malloc(sizeof(buffer_t));
        // 初始化缓存
    }
    return global_cache;
}

// 特征：
// - 全局变量
// - 懒初始化
// - 长生命周期
// - 永不释放（intentional）
```

**识别方法**：
- 检查是否有全局/静态变量存储指针
- 检查是否只初始化一次
- 检查是否永不释放
- 查找注释或文档说明

#### 2. 单例模式（Singleton Pattern）

```c
instance_t* get_instance() {
    static instance_t *instance = NULL;
    if (instance == NULL) {
        instance = malloc(sizeof(instance_t));
        // 初始化单例
    }
    return instance;
}

// 特征：
// - static 变量
// - 懒初始化
// - 只分配一次
// - 永不释放（intentional）
```

**识别方法**：
- 检查是否有 static 变量
- 检查是否只初始化一次
- 检查是否永不释放
- 查找单例相关的命名（instance, singleton）

#### 3. 引用计数（Reference Counting）

```c
typedef struct {
    int ref_count;
    char *data;
} ref_buffer_t;

ref_buffer_t* acquire_buffer() {
    ref_buffer_t *buf = malloc(sizeof(ref_buffer_t));
    buf->ref_count = 1;
    buf->data = malloc(1024);
    return buf;
}

void release_buffer(ref_buffer_t *buf) {
    buf->ref_count--;
    if (buf->ref_count == 0) {
        free(buf->data);
        free(buf);
    }
}

void add_ref(ref_buffer_t *buf) {
    buf->ref_count++;
}

// 特征：
// - ref_count 字段
// - acquire/release 函数
// - 条件释放（ref_count == 0）
```

**识别方法**：
- 检查是否有 ref_count 字段
- 检查是否有 acquire/release 函数
- 检查是否在 ref_count == 0 时释放
- 查找 add_ref/increment 等函数

#### 4. 长生命周期对象（Long-Lifetime Objects）

```c
// 全局配置对象
static config_t *global_config = NULL;

void init_config() {
    global_config = malloc(sizeof(config_t));
    load_config(global_config);
}

// 程序运行期间一直存在，不释放
```

**识别方法**：
- 检查是否是全局配置/状态
- 检查是否有 init 函数但没有 cleanup 函数
- 查找文档说明

**验证步骤**：
1. 搜索全局变量和静态变量
2. 检查变量的使用模式
3. 查找设计文档（README, DESIGN.md, ARCHITECTURE.md）
4. 查找代码注释
5. 询问开发人员（如果可能）

---

### Phase 6: 业务场景分析（AI Agent 完成）

**目标**：分析漏洞在什么情况下会被触发，评估实际影响

**步骤**：
1. **理解业务逻辑**：
   - 这个函数在什么场景下被调用？
   - 调用频率如何？
   - 是否是关键路径？
2. **识别触发条件**：
   - 在什么情况下会触发漏洞？
   - 是否需要特定输入？
   - 是否需要特定条件？
3. **评估影响**：
   - 漏洞的严重程度如何？
   - 可利用性如何？
   - 对用户的影响是什么？
4. **优先级排序**：
   - 哪些漏洞最需要修复？
   - 哪些可以暂时忽略？

**示例**：

#### 场景 1：内存泄漏

```c
void handle_request(request_t *req) {
    char *buffer = malloc(req->size);
    process_request(buffer, req);

    // 忘记释放 buffer
    // return;
}
```

**业务场景分析**：
- **触发条件**：每次调用 `handle_request()` 都会泄漏内存
- **调用频率**：如果每秒处理 1000 个请求，每秒泄漏 1000 * size 字节
- **影响**：长时间运行的服务会耗尽内存，导致服务崩溃
- **严重程度**：高
- **优先级**：高（必须修复）

#### 场景 2：格式化字符串漏洞

```c
void log_message(char *user_input) {
    printf(user_input);  // 危险！
}
```

**业务场景分析**：
- **触发条件**：用户可以控制日志消息
- **可利用性**：高（攻击者可以构造恶意输入）
- **影响**：可能读取内存、写入内存、执行任意代码
- **严重程度**：严重
- **优先级**：紧急（立即修复）

#### 场景 3：数组越界（边界检查）

```c
void copy_data(char *src, int len) {
    char buffer[100];
    // 检查 len 是否超过 100
    if (len < 100) {
        memcpy(buffer, src, len);
    }
}
```

**业务场景分析**：
- **触发条件**：`len >= 100`
- **边界检查**：有检查，但只检查 `< 100`
- **影响**：当 `len >= 100` 时，不会复制数据，可能影响业务逻辑
- **严重程度**：低（不会导致崩溃或安全漏洞）
- **优先级**：低（可以考虑修复，但不紧急）

---

### Phase 7: 证据链生成（AI Agent 完成）

**目标**：生成清晰、详细的证据链

**证据链结构**：

```json
{
  "evidence_chain": {
    "step1_pattern_detection": {
      "description": "发现可疑模式",
      "details": "Line 45: ptr = malloc(1024) without matching free"
    },
    "step2_lifecycle_trace": {
      "description": "追踪变量生命周期",
      "details": "ptr allocated at line 45, used at lines 50, 60, never freed",
      "dataflow_trace": [
        "Line 45: ptr = malloc(1024)",
        "Line 50: memcpy(ptr, src, 100)",
        "Line 60: strcpy(ptr, data)",
        "Function exit: ptr lost"
      ]
    },
    "step3_call_chain_analysis": {
      "description": "分析调用链",
      "details": "create_connection called by main (line 100) and process_data (line 200)",
      "cross_file_analysis": "Checked callers in other files, no cleanup function found"
    },
    "step4_controlflow_analysis": {
      "description": "分析控制流",
      "details": "No null check before use, no exception handling",
      "exit_paths": [
        "Path 1: Line 45 -> 50 -> 60 -> return (no free)",
        "Path 2: Line 45 -> 50 -> 55 -> return (no free)"
      ]
    },
    "step5_code_intent": {
      "description": "理解代码意图",
      "details": "No global storage, no cache pattern, no long-lifetime design evidence",
      "false_positive_checks": [
        "Check 1: Is ptr stored globally? - No",
        "Check 2: Is there a cleanup function? - No",
        "Check 3: Is this intentional design? - No evidence in comments/docs"
      ]
    },
    "step6_business_scenario": {
      "description": "业务场景分析",
      "details": "create_connection used for temporary data processing, should be freed after use",
      "trigger_conditions": [
        "When main() or process_data() is called",
        "Normal operation (no error paths)"
      ],
      "impact_assessment": {
        "severity": "high",
        "reproducibility": "always",
        "user_impact": "memory leak, long-running processes will exhaust memory"
      }
    },
    "step7_conclusion": {
      "description": "结论",
      "result": "CONFIRMED_VULNERABILITY",
      "confidence": "high",
      "reason": "Clear evidence of memory leak, no false positive indicators"
    }
  }
}
```

---

### Phase 8: 报告生成（AI Agent 完成）

**目标**：生成清晰、详细的漏洞报告

**报告格式**：

```json
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
  "evidence_chain": { /* ... */ },
  "manual_verification_steps": [
    {
      "step": 1,
      "action": "检查是否存储在全局数据结构中",
      "how_to": "Search for 'buffer' in global variables and struct fields",
      "expected_result": "Not found",
      "verification_result": "✓ Confirmed: no global storage"
    }
  ],
  "fix_suggestion": "Add free(ptr) before function return or in cleanup function"
}
```

---

## 分批分析策略

### 策略 1: 按分析包分批（推荐）

**适用场景**：大多数项目

**优点**：
- 每个分析包独立，无状态依赖
- 易于并行处理
- 易于恢复和断点续传

**实现**：
```bash
# 分析包已经在 Phase 0 生成
# 每个分析包可以独立分析
for pkg in /tmp/analysis_packages/suspicious_*.json; do
    analyze_package "$pkg"
done
```

---

### 策略 2: 按文件分批

**适用场景**：需要一次查看一个文件的所有问题

**优点**：
- 便于人工审查
- 便于理解文件的整体情况

**缺点**：
- 可能忽略跨文件的依赖关系

**实现**：
```bash
# 按文件分组分析包
for file in $(jq -r '.[].suspicious_point.file' /tmp/analysis_packages/*.json | sort -u); do
    analyze_files_in_group "$file"
done
```

---

## 增量分析策略

### 触发条件
- 代码被修改（git diff 检测）
- 用户手动触发

### 分析流程

#### 方案 1: 全量重建（简单）

**步骤**：
1. 重新构建基础设施（调用图、符号表、控制流）
2. 重新生成所有分析包
3. 重新分析所有分析包

**优点**：
- 简单可靠
- 不会遗漏任何问题

**缺点**：
- 速度慢（17-33 分钟，30k 行代码）

#### 方案 2: 增量更新（复杂，但快速）

**步骤**：
1. 检测修改的文件（git diff）
2. 只重新构建受影响部分的基础设施
3. 只重新生成受影响的分析包
4. 只重新分析受影响的分析包

**优点**：
- 速度快（3-5 分钟，30k 行代码，1% 修改）

**缺点**：
- 复杂
- 可能遗漏间接影响

**实现**：
```bash
# 检测修改的文件
modified_files=$(git diff --name-only --diff-filter=d '*.c' '*.h')

# 重新构建基础设施（只处理修改的文件）
# 重新生成分析包（只处理修改的文件）
# 重新分析（只分析新生成的包）
```

---

## 误报控制策略

### 高置信度规则

以下情况标记为 **高置信度**（误报率 < 5%）：
- 返回局部变量地址
- 格式化字符串漏洞（用户输入直接作为格式化字符串）
- 使用不安全函数（`gets`、`strcpy` 等）

**Action**: 标记为确认漏洞，无需人工验证。

---

### 中等置信度规则

以下情况标记为 **中等置信度**（误报率 10-20%）：
- 内存泄漏（未找到 `free`，但可能存储在全局结构中）
- Double Free（同一指针多次 `free`，但可能有保护逻辑）

**Action**: 标记为可疑漏洞，提供证据链和人工验证步骤。

**人工验证方法**：
1. 检查是否有全局数据结构存储指针
2. 检查是否有保护逻辑（引用计数、锁）
3. 检查是否有 cleanup 函数在其他模块
4. 检查代码注释和文档
5. 理解代码的设计意图

---

### 低置信度规则

以下情况标记为 **低置信度**（误报率 20-40%）：
- Use-After-Free（`free` 后使用，但可能在不同的条件分支）
- 数组越界（索引可能超出边界，但可能有边界检查）

**Action**: 标记为可疑点，提供详细上下文和完整的人工验证步骤。

**人工验证方法**：
1. 追踪 `free` 到 `use` 之间的控制流
2. 检查边界检查逻辑
3. 理解循环条件和终止条件
4. 检查是否有保护逻辑
5. 运行时验证（如果可能）

---

## 性能优化建议

### 1. 并行分析

**方法**：
- 多个分析包可以并行分析
- 每个分析包独立，无状态依赖

**实现**：
```bash
MAX_PARALLEL=4

for pkg in /tmp/analysis_packages/suspicious_*.json; do
    analyze_package "$pkg" &

    if [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; then
        wait -n
    fi
done

wait
```

**加速比**：
- 4 核 CPU：~3.5x 加速
- 8 核 CPU：~7x 加速

### 2. 缓存基础设施

**方法**：
- 缓存调用图、符号表、控制流图
- 只在文件修改时重新构建

**实现**：
```bash
# 使用文件哈希检测修改
file_hash=$(md5sum "$file")

# 如果哈希匹配，使用缓存
# 如果哈希不匹配，重新构建
```

### 3. 优先级排序

**方法**：
- 优先分析高置信度的可疑点
- 优先分析高频调用的函数
- 优先分析公共 API

**实现**：
```bash
# 从调用图中获取调用频率
high_freq_functions=$(jq -r '.functions | to_entries[] | select(.value.callers | length > 10) | .key' call_graph.json)

# 优先分析这些函数相关的可疑点
```

---

## 人工确认指南

当 AI Agent 标记一个可疑点时，人工确认应该：

1. **阅读证据链**：理解 AI Agent 的分析过程
2. **检查代码上下文**：查看可疑点前后的代码
3. **理解设计意图**：判断是否 intentional 的设计
4. **评估严重性**：判断漏洞的潜在影响
5. **确定修复方案**：制定修复计划

---

## 总结

这个分析策略的核心在于：

1. **基础设施先行**：构建完整的程序分析基础设施
2. **基于分析包**：每个可疑点都有完整的上下文
3. **跨文件分析**：利用调用图进行跨文件依赖分析
4. **数据流追踪**：理解数据的流动
5. **代码意图理解**：减少误报
6. **业务场景分析**：评估实际影响
7. **证据链**：清晰展示分析过程

通过这个策略，AI Agent 可以真正具备处理大型 C 项目的能力，而不是只能处理"玩具项目"。
