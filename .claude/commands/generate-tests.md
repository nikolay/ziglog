---
description: Generate comprehensive test cases for a feature
---

Generate comprehensive test cases for a ziglog feature.

## Test Structure

Follow the ziglog test pattern:

```zig
test "Component - specific behavior" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Setup
    // ...

    // Execute
    // ...

    // Assert
    try std.testing.expectEqual(expected, actual);
}
```

## Test Categories

Generate tests for:

1. **Happy Path**:
   - Normal usage scenarios
   - Common patterns
   - Expected inputs

2. **Edge Cases**:
   - Empty inputs
   - Boundary conditions
   - Special values ([], nil, etc.)

3. **Error Cases**:
   - Type errors
   - Instantiation errors
   - Invalid input

4. **Integration**:
   - Feature working with other components
   - Complex scenarios
   - Backtracking behavior

## Requirements

- Use `Term.createX()` constructors
- Include descriptive test names
- Add comments explaining complex setups
- Use ArenaAllocator pattern
- Group related tests

What feature should I generate tests for?
