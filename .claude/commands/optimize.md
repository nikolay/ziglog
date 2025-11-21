---
description: Implement Prolog optimization techniques
---

I want to implement performance optimizations for the ziglog Prolog engine.

## Available Optimizations

Review `OPTIMIZATIONS.md` for detailed analysis. Priority order:

### 1. First-Argument Indexing (HIGHEST IMPACT)
**What**: Index clauses by first argument for O(1) lookup
**Impact**: 10-100x faster for large databases
**Difficulty**: Medium

**Implementation**:
- Add `ClauseIndex` structure to Engine
- Build indices when rules are added
- Use indices in `solve()` to filter candidates
- Test with large fact databases

### 2. Choice Point Elimination
**What**: Don't create choice points for deterministic clauses
**Impact**: 30% faster, less memory
**Difficulty**: Easy

**Implementation**:
- Count matching clauses before trying them
- Skip backtracking setup if count == 1
- Preserves cut semantics

### 3. Tail-Call Optimization
**What**: Reuse stack frame for tail-recursive calls
**Impact**: Prevents stack overflow
**Difficulty**: Hard

**Implementation**:
- Convert recursion to iteration for tail calls
- Detect tail position (last goal, no remaining)
- Replace goals instead of recursing

### 4. Environment Trimming
**What**: Remove dead variable bindings
**Impact**: Lower memory usage
**Difficulty**: Very Hard

**Status**: Skip - requires allocator redesign

## Implementation Guide

### Step 1: Choose Optimization
Recommended order:
1. First-Argument Indexing
2. Choice Point Elimination
3. Tail-Call Optimization
4. Skip Environment Trimming

### Step 2: Read Current Implementation
```
src/engine.zig:143-157  - solve() main loop
src/engine.zig:280-430  - clause matching
src/engine.zig:46-72    - unify() for indexing
```

### Step 3: Implement
Follow patterns in OPTIMIZATIONS.md with:
- Index structure definition
- Index building logic
- Index usage in queries
- Comprehensive tests

### Step 4: Benchmark
Create before/after benchmarks:
- Large fact databases (1000+ facts)
- Deep recursion (for TCO)
- Deterministic predicates (for CPE)

### Step 5: Verify
- All existing tests still pass
- New optimization tests pass
- Performance improves measurably

Which optimization would you like to implement?
