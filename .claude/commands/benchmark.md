---
description: Create performance benchmarks for critical code paths
---

Create performance benchmarks for ziglog critical paths.

## Benchmark Areas

1. **Unification**:
   - Simple term unification
   - Deep structure unification
   - Variable resolution chains

2. **Resolution**:
   - Rule matching
   - Backtracking
   - Deep recursion

3. **Parsing**:
   - Lexer tokenization
   - Parser term building
   - DCG transformation

4. **Memory**:
   - ArenaAllocator allocation patterns
   - Peak memory usage
   - Cleanup time

## Benchmark Structure

```zig
const std = @import("std");
const Timer = std.time.Timer;

fn benchmarkUnification() !void {
    var timer = try Timer.start();

    // Setup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const iterations = 100_000;
    const start = timer.lap();

    // Benchmark code
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // ... operation to benchmark
    }

    const elapsed = timer.read();
    const ns_per_op = elapsed / iterations;

    std.debug.print("Unification: {} ns/op\n", .{ns_per_op});
}
```

## Metrics to Collect

- Time per operation (nanoseconds)
- Memory allocated
- Number of allocations
- Cache hit/miss (if applicable)

What would you like to benchmark?
