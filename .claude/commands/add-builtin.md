---
description: Guide for adding a new Prolog built-in predicate
---

I want to add a new built-in predicate to the ziglog Prolog engine.

Please help me implement it following this workflow:

## 1. Specification
Ask me:
- Predicate name and arity (e.g., `append/3`)
- Expected behavior and unification semantics
- Success/failure conditions
- Error conditions (if any)

## 2. Implementation
Add handler in `src/engine.zig` in the `Engine.solve()` function:
- Pattern match on goal structure functor and arity
- Implement unification logic
- Handle special cases (unbound variables, type errors)
- Use existing predicates as examples

## 3. Testing
Create test cases in `src/engine.zig`:
- Success cases with various input patterns
- Failure cases
- Error cases (type errors, instantiation errors)
- Backtracking behavior if applicable

## 4. Documentation
- Add example to CLAUDE.md under "Common Development Tasks"
- Include usage examples in comments

Follow the pattern of existing built-ins like `is/2` or `=/2`.
