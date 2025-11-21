---
description: Verify DCG (Definite Clause Grammar) transformation
---

I want to verify that a DCG rule is being transformed correctly.

## DCG Transformation Rules

Explain how ziglog transforms grammar rules:

### Basic Non-terminal
```prolog
% Input:
s --> np, vp.

% Output:
s(S0, S) :- np(S0, S1), vp(S1, S).
```

### Terminal List
```prolog
% Input:
det --> [the].

% Output:
det(S0, S) :- S0 = [the|S].
```

### Brace Goals
```prolog
% Input:
a --> {print(hello)}, [world].

% Output:
a(S0, S) :- print(hello), S0 = S1, S1 = [world|S].
```

## Analysis Steps

1. **Parse the DCG rule** in `src/parser.zig` (line ~171)
2. **Show transformation** applied by `expandDCGTerm()`
3. **Display resulting Prolog rule**
4. **Verify difference list threading**

## Code References

- Parser DCG handling: `src/parser.zig:157-243`
- DCG expansion: `src/parser.zig:246-301`
- Test cases: `src/parser.zig:387-444`

Provide your DCG rule and I'll show the transformation.
