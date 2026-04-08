---
name: c-memory-analysis
description: Comprehensive C memory vulnerability detection for large-scale codebases. Use when analyzing C projects for memory-related issues including buffer overflows, memory leaks, double free, use-after-free, heap overflows, null pointer dereferences, array out-of-bounds, uninitialized memory usage, format string vulnerabilities, and unsafe function usage. Supports full-scan, incremental analysis, and resume capabilities for projects from 3k to 300k+ lines. Pure white-box analysis with complete program analysis infrastructure.
allowed-tools: Bash(/tmp/skills/c-memory-analysis/scripts/*), Read, Write, Edit
---

# C Memory Vulnerability Analysis

## When to Use

Use this skill when you need to:
- Detect memory vulnerabilities in C codebases
- Analyze projects from 3k to 300k+ lines with multi-file dependencies
- Perform cross-file analysis with call graph and data flow tracing
- Understand code intent and business scenarios
- Generate detailed vulnerability reports with evidence chains
- Perform incremental analysis on modified code
- Resume interrupted analysis

---

## Core Workflow

### 1. Infrastructure Setup (First Run)

**Step 1: Build Program Analysis Infrastructure**

```bash
# Build function call graph
/tmp/skills/c-memory-analysis/scripts/call_graph_builder.sh /path/to/project /tmp/call_graph.json

# Build symbol table
/tmp/skills/c-memory-analysis/scripts/symbol_table_builder.sh /path/to/project /tmp/symbol_table.json

# Build control flow graph
/tmp/skills/c-memory-analysis/scripts/controlflow_analyzer.sh /path/to/project /tmp/controlflow.json
```

**Step 2: Generate Analysis Packages**

```bash
# Generate analysis packages for all suspicious points
/tmp/skills/c-memory-analysis/scripts/analysis_package_generator.sh \
  /path/to/project \
  /tmp/call_graph.json \
  /tmp/symbol_table.json \
  /tmp/controlflow.json \
  /tmp/analysis_packages/
```

**Output**:
- `/tmp/call_graph.json` - Complete function call relationship graph
- `/tmp/symbol_table.json` - All variables with types, scopes, lifetimes
- `/tmp/controlflow.json` - Control flow analysis with basic blocks, branches, loops
- `/tmp/analysis_packages/suspicious_*.json` - Individual analysis packages for each suspicious point

---

### 2. Deep Analysis (AI Agent)

**For each analysis package** (`suspicious_*.json`):

```bash
# Read the analysis package
cat /tmp/analysis_packages/suspicious_001.json

# Perform deep analysis based on the provided context:
# 1. Review code context (±20 lines around suspicious point)
# 2. Examine variable information (type, lifetime, memory operations)
# 3. Trace call chain (who calls this function, what does it call)
# 4. Analyze control flow (branches, loops, exit paths)
# 5. Cross-file analysis (if needed, check other files using call graph)
# 6. Understand code intent (check for cache, singleton, reference counting patterns)
# 7. Identify false positives (look for protection logic, global storage, intentional design)
# 8. Generate evidence chain
# 9. Provide manual verification steps (if confidence is not high)
# 10. Suggest fixes
```

---

### 3. Report Generation

Aggregate all analysis results into a comprehensive report:

```json
{
  "summary": {
    "total_files_analyzed": 100,
    "suspicious_points_found": 50,
    "confirmed_vulnerabilities": 25,
    "false_positives": 15,
    "needs_manual_review": 10
  },
  "infrastructure": {
    "functions_analyzed": 500,
    "variables_analyzed": 2000,
    "basic_blocks_analyzed": 1500,
    "cyclomatic_complexity_avg": 5.2
  },
  "issues": [
    // Individual vulnerability reports with evidence chains
  ]
}
```

---

### 4. Incremental Analysis (After Modifications)

```bash
# Step 1: Rebuild infrastructure for modified files only
# (Optimization: Can cache and reuse unchanged parts)

# Step 2: Check which analysis packages are affected
# Compare file hashes and re-generate packages for modified files

# Step 3: Re-analyze affected packages only
# Skip unchanged packages using cache
```

---

### 5. Resume Analysis (After Interruption)

```bash
# Check which packages have been analyzed
ls /tmp/analysis_packages/

# Continue from unanalyzed packages
# Each package is independent, so you can resume at any point
```

---

## Analysis Package Structure

Each analysis package (`suspicious_XXX.json`) contains:

```json
{
  "package_id": "1",
  "suspicious_point": {
    "file": "src/memory.c",
    "line": 45,
    "function": "allocate_buffer",
    "pattern_type": "malloc_without_free",
    "variable": "buffer"
  },
  "context": {
    "code_snippet": "// 20 lines before and after the suspicious point\n...",
    "context_lines": {
      "start": 25,
      "end": 65
    }
  },
  "variable_info": {
    "file": "src/memory.c",
    "line": 45,
    "function": "allocate_buffer",
    "type": "char*",
    "scope": "local",
    "lifetime": "heap",
    "is_pointer": true,
    "allocations": [
      {"line": 45, "function": "malloc"}
    ],
    "deallocations": []
  },
  "call_chain": {
    "function": "allocate_buffer",
    "callers": ["main", "process_data"],
    "callees": []
  },
  "controlflow": {
    "file": "src/memory.c",
    "line": 10,
    "basic_blocks_count": 5,
    "branches_count": 2,
    "loops_count": 0,
    "cyclomatic_complexity": 3,
    "basic_blocks": [
      {"id": 1, "start": 10, "end": 12, "type": "entry", "end_type": "normal"},
      {"id": 2, "start": 13, "end": 15, "type": "normal", "end_type": "conditional"},
      ...
    ],
    "branches": [
      {"line": 13, "type": "if", "condition": "buffer != NULL"}
    ],
    "loops": []
  },
  "analysis_hints": {
    "check_for": [
      "Verify if variable is stored in global data structures",
      "Check for cleanup functions in other modules",
      "Look for error handling paths that might free the memory",
      "Verify if this is intentional design (cache, singleton, etc.)",
      "Check comments and documentation for design intent"
    ],
    "dataflow_trace": [
      "Trace the lifecycle of the variable",
      "Identify all paths where the variable is used",
      "Check for exception paths",
      "Verify if all paths have proper memory management"
    ],
    "manual_verification_steps": [
      "1. Check the full function implementation",
      "2. Look for global variables or static variables that might store the pointer",
      "3. Search for other functions that might free this memory",
      "4. Review error handling paths",
      "5. Check project documentation for design intent"
    ]
  }
}
```

---

## AI Agent Analysis Protocol

### Phase 1: Understand Context

1. **Read the analysis package**
2. **Review code snippet** - Understand the surrounding code
3. **Examine variable info** - Type, scope, lifetime, memory operations
4. **Check call chain** - Who calls this function? What does it call?
5. **Analyze control flow** - Branches, loops, exit paths

### Phase 2: Deep Analysis

1. **Trace data flow**:
   - Where does the data come from? (user input, config, internal computation)
   - Where does it flow to? (memory write, function parameter, return value)
   - Are there data transformations along the way?

2. **Analyze cross-file dependencies**:
   - Use call graph to trace dependencies
   - Check if the variable is passed to other functions
   - Verify if other functions might free/manage the memory

3. **Examine all execution paths**:
   - Happy path (normal operation)
   - Error paths (if conditions, goto, longjmp)
   - Exception paths (signal handlers, callbacks)

4. **Understand code intent**:
   - Is this intentional design? (cache, singleton, reference counting)
   - Are there design docs or comments?
   - Does it follow project conventions?

### Phase 3: Generate Evidence Chain

For each confirmed vulnerability, provide:

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
  },
  "manual_verification_steps": [
    {
      "step": 1,
      "action": "检查是否存储在全局数据结构中",
      "how_to": "Search for 'buffer' in global variables and struct fields",
      "expected_result": "Not found",
      "verification_result": "✓ Confirmed: no global storage"
    },
    {
      "step": 2,
      "action": "检查是否有 cleanup 函数",
      "how_to": "Search for functions that free 'buffer'",
      "expected_result": "Not found",
      "verification_result": "✓ Confirmed: no cleanup function"
    }
  ],
  "fix_suggestion": "Add free(ptr) before function return or in cleanup function"
}
```

---

## Vulnerability Types & Confidence Levels

### High Confidence (Low False Positive Rate <5%)

- **Return local variable address**: Clear pattern `return &local_var`
- **Format string vulnerabilities**: User input directly as format string
- **Unsafe function usage**: `gets`, `strcpy`, `strcat`, `sprintf`

**Action**: Mark as confirmed vulnerability, no manual verification needed.

---

### Medium Confidence (False Positive Rate 10-20%)

- **Memory leaks**: `malloc` without `free`, but may be stored in global structure
- **Double free**: Same pointer freed twice, but may have protection logic

**Action**: Mark as suspected vulnerability, provide evidence chain for manual verification.

**Manual Verification Steps**:
- Check if pointer is stored in global data structures
- Check for protection logic before `free`
- Understand code design intent

---

### Low Confidence (False Positive Rate 20-40%)

- **Use-after-free**: Pointer used after `free`, but may be in different branches
- **Array out-of-bounds**: Index may exceed bounds, but may have boundary checks

**Action**: Mark as suspicious point, provide detailed context and manual verification steps.

**Manual Verification Steps**:
- Trace control flow from `free` to `use`
- Check boundary check logic
- Understand loop conditions and termination

---

## Performance Guidelines

### Infrastructure Building Time

| Code Size | Call Graph | Symbol Table | Control Flow | Packages |
|-----------|-----------|-------------|--------------|----------|
| 3k lines  | 1-2 min   | 1-2 min     | 1-2 min      | 30 sec   |
| 30k lines | 5-10 min  | 5-10 min    | 5-10 min     | 2-3 min  |
| 300k lines| 30-60 min | 30-60 min   | 30-60 min    | 10-20 min|

### Deep Analysis Time (AI Agent)

| Suspicious Points | Analysis Time (per point) | Total Time |
|------------------|--------------------------|------------|
| 10               | 2-5 min                  | 20-50 min  |
| 50               | 2-5 min                  | 1.7-4.2h   |
| 200              | 2-5 min                  | 6.7-16.7h  |

**Note**: Deep analysis time depends on:
- Complexity of the suspicious point
- Cross-file dependencies
- Need for code intent understanding
- Quality of the code (comments, documentation)

---

## Cross-File Analysis Examples

### Example 1: Memory allocated in file A, freed in file B

**Scenario**:
- `src/network/connection.c:allocate_connection()` - allocates memory
- `src/network/cleanup.c:free_connection()` - frees memory

**Analysis**:
1. Read analysis package for `allocate_connection`
2. Check `call_chain.callers` - who calls this function?
3. Use call graph to trace where the returned pointer goes
4. Search for `free_connection` in the codebase
5. Verify that all paths from `allocate_connection` eventually call `free_connection`
6. Identify missing cleanup paths

### Example 2: User input flows through multiple functions

**Scenario**:
- `src/input/read_input()` - reads user input
- `src/parse/process_data()` - processes the input
- `src/memory/buffer.c:copy_to_buffer()` - copies to buffer (vulnerable)

**Analysis**:
1. Read analysis package for `copy_to_buffer` (unsafe strcpy)
2. Trace back the data source using call graph
3. Check if there's size validation in intermediate functions
4. Identify all input paths
5. Determine if any path lacks size validation

---

## Code Intent Recognition

### Cache Pattern

```c
// Global cache
static buffer_t *global_cache = NULL;

buffer_t* get_cached_buffer() {
    if (global_cache == NULL) {
        global_cache = malloc(sizeof(buffer_t));
    }
    return global_cache;
}

// Recognition:
// - Global variable
// - Lazy initialization
// - Long lifetime
// - Never freed (intentional)
```

### Singleton Pattern

```c
// Singleton object
instance_t* get_instance() {
    static instance_t *instance = NULL;
    if (instance == NULL) {
        instance = malloc(sizeof(instance_t));
    }
    return instance;
}

// Recognition:
// - Static variable
// - Lazy initialization
// - Only allocated once
// - Never freed (intentional)
```

### Reference Counting

```c
// Reference counting
typedef struct {
    int ref_count;
    char *data;
} ref_buffer_t;

ref_buffer_t* acquire_buffer() {
    ref_buffer_t *buf = malloc(sizeof(ref_buffer_t));
    buf->ref_count = 1;
    return buf;
}

void release_buffer(ref_buffer_t *buf) {
    buf->ref_count--;
    if (buf->ref_count == 0) {
        free(buf->data);
        free(buf);
    }
}

// Recognition:
// - ref_count field
// - acquire/release functions
// - Conditional free based on ref_count
```

---

## Best Practices

1. **Always use the infrastructure**: Don't skip building call graph, symbol table, control flow
2. **Leverage the analysis packages**: They provide all the context you need
3. **Cross-file analysis is key**: Real vulnerabilities often span multiple files
4. **Understand code intent**: Many "vulnerabilities" are intentional designs
5. **Provide detailed evidence chains**: Show your analysis process
6. **Consider business scenarios**: Analyze when and how vulnerabilities are triggered
7. **Check for false positives**: Look for protection logic, global storage, intentional design
8. **Provide fix suggestions**: Help developers understand how to fix issues

---

## Troubleshooting

### Infrastructure Building Fails

**Issue**: `call_graph_builder.sh` fails with syntax errors

**Solution**:
- Check that all C files are syntactically valid
- Ensure no malformed preprocessor directives
- Try building the project first to catch syntax errors

### No Analysis Packages Generated

**Issue**: `analysis_package_generator.sh` finds 0 suspicious points

**Solution**:
- Check if the project actually uses C (not C++)
- Verify that the project directory contains `.c` and `.h` files
- Some projects might not have obvious vulnerabilities (good!)

### High False Positive Rate

**Issue**: Many findings turn out to be false positives

**Solution**:
- Review the analysis hints in the analysis package
- Check for common patterns (cache, singleton, reference counting)
- Search for design documentation
- Ask developers about intentional design decisions

---

## References

Load these references when needed:

- **Vulnerability Types**: See [references/vuln_types.md](file:///tmp/skills/c-memory-analysis/references/vuln_types.md) for detailed vulnerability definitions
- **Analysis Strategies**: See [references/analysis_strategies.md](file:///tmp/skills/c-memory-analysis/references/analysis_strategies.md) for analysis workflows
- **Caching Protocol**: See [references/caching_protocol.md](file:///tmp/skills/c-memory-analysis/references/caching_protocol.md) for cache management

---

## Notes

- This skill is designed for **real-world C projects** with **complete program analysis infrastructure**
- Cross-file analysis is fully supported through call graph and data flow tracing
- Code intent understanding is emphasized to reduce false positives
- Business scenario analysis helps prioritize vulnerabilities
- Manual verification steps are provided for medium/low confidence findings
- Infrastructure building can be reused for incremental analysis
