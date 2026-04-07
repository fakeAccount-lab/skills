---
name: c-memory-analysis
description: Comprehensive C memory vulnerability detection for large-scale codebases. Use when analyzing C projects for memory-related issues including buffer overflows, memory leaks, double free, use-after-free, heap overflows, null pointer dereferences, array out-of-bounds, uninitialized memory usage, format string vulnerabilities, and unsafe function usage. Supports full-scan, incremental analysis, and resume capabilities for projects from 3k to 300k+ lines. Pure white-box analysis with no external tool dependencies.
allowed-tools: Bash(/tmp/skills/c-memory-analysis/scripts/*), Read, Write, Edit
---

# C Memory Vulnerability Analysis

## When to Use

Use this skill when you need to:
- Detect memory vulnerabilities in C codebases
- Analyze projects from 3k to 300k+ lines
- Perform incremental analysis on modified code
- Resume interrupted analysis
- Generate detailed vulnerability reports with evidence chains

---

## Core Workflow

### 1. Full Analysis (First Run)

```bash
# Step 1: Scan project structure
/tmp/skills/c-memory-analysis/scripts/scan_c_files.sh /path/to/project > files.txt

# Step 2: Build file index
/tmp/skills/c-memory-analysis/scripts/build_file_index.sh /path/to/project /tmp/index.json

# Step 3: Partition into batches (10 files per batch)
/tmp/skills/c-memory-analysis/scripts/partition_project.sh /path/to/project /tmp/batches --strategy files --max-batch-size 10

# Step 4: Analyze each batch (you must perform this)
# For each batch file in /tmp/batches/batch_*.txt:
#   1. Read all files in the batch
#   2. Use AI Agent to perform deep analysis on suspicious patterns
#   3. Generate detailed vulnerability reports
#   4. Create batch_XXX.done or batch_XXX.failed marker

# Step 5: Aggregate results
# Combine all batch results into final report
```

---

### 2. Incremental Analysis (After Modifications)

```bash
# Check cache for each modified file
for file in $(git diff --name-only --diff-filter=d '*.c' '*.h'); do
    cached=$(/tmp/skills/c-memory-analysis/scripts/cache_manager.sh check "$file" /path/to/project)

    if [ "$cached" = "false" ]; then
        # Reanalyze this file
        # Use AI Agent to analyze the file
        # Update cache: /tmp/skills/c-memory-analysis/scripts/cache_manager.sh set "$file" /path/to/project result.json
    fi
done

# Also reanalyze files that depend on modified files (call chain)
```

---

### 3. Resume Analysis (After Interruption)

```bash
# Check batch status
/tmp/skills/c-memory-analysis/scripts/resume_analysis.sh /tmp/batches /tmp/output /path/to/project

# Continue from pending batches
# Skip batches with .done marker
# Retry batches with .failed marker
# Analyze pending batches
```

---

## AI Agent Analysis Protocol

### Phase 1: Pattern Matching (Find Suspicious Points)

For each file in the batch, search for suspicious patterns:

1. **Return local variable address**: `return &local_var`
2. **Memory leaks**: `malloc`/`calloc`/`realloc` without matching `free`
3. **Double free**: Same pointer `free`'d multiple times
4. **Use-after-free**: Pointer used after `free`
5. **Heap overflow**: `malloc(size)` mismatched with write size
6. **Null pointer dereference**: Pointer used without null check
7. **Array out-of-bounds**: Array index may exceed bounds
8. **Uninitialized memory**: `malloc` followed by read without init
9. **Format string**: `printf(user_input)` without `"%s"`
10. **Unsafe functions**: `gets`, `strcpy`, `strcat`, `sprintf`

---

### Phase 2: Deep Analysis (Confirm Vulnerabilities)

For each suspicious point:

1. **Extract context** (±20 lines around the suspicious point)
2. **Trace data flow**:
   - Where does the data come from? (user input, config, internal computation)
   - Where does it flow to? (memory write, function parameter, return value)
3. **Trace call chain**:
   - Who calls this function?
   - In what context?
   - Is there protection logic in the call chain?
4. **Analyze control flow**:
   - Are there conditional branches protecting the code?
   - Are there exception paths?
   - Is there pre-validation?
5. **Understand code intent**:
   - Is this intentional? (e.g., cache, singleton)
   - Are there design docs or comments?
   - Does it follow project conventions?

---

### Phase 3: Generate Report

For each confirmed vulnerability, provide:

```json
{
  "id": "ISSUE-XXX",
  "type": "vulnerability_type",
  "severity": "critical|high|medium|low",
  "confidence": "high|medium|low",
  "file": "path/to/file.c",
  "line": 45,
  "function": "function_name",
  "title": "Brief description",
  "description": "Detailed explanation",
  "evidence_chain": [
    "Step 1: What I found",
    "Step 2: How I traced it",
    "Step 3: Conclusion"
  ],
  "false_positive_check": [
    "Checked for global cache storage: No",
    "Checked for free in other modules: No",
    "Checked for intentional design: No evidence"
  ],
  "manual_verification_needed": false,
  "fix_suggestion": "How to fix it"
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

### Batch Size

- **Default**: 10 files per batch
- **Large files** (>500 lines): 5 files per batch
- **Small files** (<200 lines): 20 files per batch

### Parallel Analysis

```bash
MAX_PARALLEL=4

for batch in batches/batch_*.txt; do
    analyze_batch "$batch" &

    if [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; then
        wait -n
    fi
done

wait
```

### Estimated Time

| Code Size | Full Scan | Incremental (1% change) |
|-----------|-----------|------------------------|
| 3k lines  | 5-10 min  | 30 sec                  |
| 30k lines | 2-4 hours | 3-5 min                 |
| 300k lines| 20-40 hours| 15-30 min               |

---

## Cache Management

### Initialize Cache

```bash
/tmp/skills/c-memory-analysis/scripts/cache_manager.sh init /path/to/project
```

### Use Cache in Analysis

```bash
# Check if cached
cached=$(/tmp/skills/c-memory-analysis/scripts/cache_manager.sh check file.c /path/to/project)

if [ "$cached" = "true" ]; then
    # Use cached result
    /tmp/skills/c-memory-analysis/scripts/cache_manager.sh get file.c /path/to/project
else
    # Reanalyze and cache
    analyze_file.c > result.json
    /tmp/skills/c-memory-analysis/scripts/cache_manager.sh set file.c /path/to/project result.json
fi
```

### Clean Old Cache

```bash
# Remove cache older than 30 days
/tmp/skills/c-memory-analysis/scripts/cache_manager.sh clean /path/to/project 30
```

---

## References

Load these references when needed:

- **Vulnerability Types**: See [references/vuln_types.md](file:///tmp/skills/c-memory-analysis/references/vuln_types.md) for detailed vulnerability definitions and detection methods
- **Analysis Strategies**: See [references/analysis_strategies.md](file:///tmp/skills/c-memory-analysis/references/analysis_strategies.md) for analysis workflows and strategies
- **Caching Protocol**: See [references/caching_protocol.md](file:///tmp/skills/c-memory-analysis/references/caching_protocol.md) for cache management details

---

## Output Format

### Final Report Structure

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
    // Individual vulnerability reports
  ]
}
```

### Issue Report Fields

- `id`: Unique identifier (e.g., "ISSUE-001")
- `type`: Vulnerability type
- `severity`: critical | high | medium | low
- `confidence`: high | medium | low
- `file`: File path
- `line`: Line number
- `function`: Function name
- `title`: Brief description
- `description`: Detailed explanation
- `evidence_chain`: Array of analysis steps
- `false_positive_check`: Array of verification checks
- `manual_verification_needed`: Boolean
- `fix_suggestion`: How to fix

---

## Best Practices

1. **Always use evidence chains**: Show your analysis process for each finding
2. **Consider code intent**: Some "vulnerabilities" may be intentional designs
3. **Check for false positives**: Look for protection logic, global storage, etc.
4. **Provide fix suggestions**: Help developers understand how to fix issues
5. **Use caching**: For large projects, always use cache for incremental analysis
6. **Batch appropriately**: Adjust batch size based on file complexity
7. **Parallelize wisely**: Don't exceed available CPU cores

---

## Troubleshooting

### Cache Issues

If cache seems outdated or corrupted:
```bash
rm -rf /path/to/project/.c-memory-analysis-cache/
/tmp/skills/c-memory-analysis/scripts/cache_manager.sh init /path/to/project
```

### Analysis Hangs

If analysis hangs on a specific batch:
1. Check batch file content
2. Look for extremely large files (>10k lines)
3. Reduce batch size and retry

### High False Positive Rate

If you see many false positives:
1. Review your analysis strategy
2. Check if you're considering code intent
3. Verify you're checking for protection logic
4. Look at references/analysis_strategies.md for guidance

---

## Notes

- This skill is designed for **pure white-box analysis** with **no external tool dependencies**
- All analysis is performed by AI Agent with script assistance
- Caching and incremental analysis are essential for large codebases
- Manual verification is encouraged for medium/low confidence findings
