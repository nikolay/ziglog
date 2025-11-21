---
description: Explain how unification works for given terms
---

I want to understand how unification works for specific Prolog terms.

Please explain the unification process step-by-step:

## Analysis Steps

1. **Read the terms** being unified
2. **Resolve variables** using the environment
3. **Show the unification steps**:
   - What gets compared at each step
   - Variable bindings created
   - Recursive unification for structures
4. **Show final environment** state

## Code References

Point to relevant code in:
- `src/engine.zig`: `unify()` function (line ~46)
- `src/engine.zig`: `resolve()` function (line ~37)

## Example Format

```
Unifying: parent(X, mary) with parent(john, Y)

Step 1: Resolve both terms (no bindings yet)
  t1 = parent(X, mary)
  t2 = parent(john, Y)

Step 2: Both are structures, check functor
  "parent" == "parent" ✓

Step 3: Check arity
  2 == 2 ✓

Step 4: Unify arguments pairwise
  - Unify X with john → bind X = john
  - Unify mary with Y → bind Y = mary

Result: Success
Environment: {X → john, Y → mary}
```

What terms would you like me to explain?
