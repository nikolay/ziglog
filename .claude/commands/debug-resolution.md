---
description: Debug Prolog query resolution and backtracking
---

I need help debugging why a Prolog query isn't working as expected.

Please analyze the resolution process:

## Information Needed

1. **The query** that's not working
2. **The rules** loaded in the knowledge base
3. **Expected behavior** vs actual behavior
4. **Error message** (if any)

## Debugging Process

1. **Trace the resolution**:
   - Show SLD resolution steps
   - Display unification attempts
   - Track environment changes
   - Identify where backtracking occurs

2. **Check common issues**:
   - Variable naming conflicts
   - Missing base cases
   - Incorrect rule ordering
   - Infinite recursion
   - Cut operator placement

3. **Review the code path**:
   - `Engine.solve()` main loop
   - Rule matching and unification
   - Goal queue management
   - Scope handling for cut

4. **Suggest fixes**:
   - Rule modifications
   - Query reformulation
   - Additional base cases

## Code References

Point to:
- `src/engine.zig`: Resolution logic (lines ~110-280)
- `src/engine.zig`: Unification (line ~46)
- `src/engine.zig`: Backtracking via choice points

Provide the query and rules, and I'll trace through the resolution.
