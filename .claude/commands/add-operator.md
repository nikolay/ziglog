---
description: Guide for adding a new operator to the parser
---

I want to add a new operator to the ziglog parser.

Please guide me through implementing it:

## 1. Token Definition
In `src/lexer.zig`:
- Add enum value to `TokenType` (use snake_case, e.g., `.my_operator`)
- Add lexing logic in `Lexer.next()` to recognize the operator syntax
- Add test case in lexer tests

## 2. Parser Integration
In `src/parser.zig`:
- Add precedence to `getPrecedence()` function
  - `.LogicOr` = lowest (`;`)
  - `.Comparison` = medium (`=`, `>`, `<`, etc.)
  - `.Sum` = higher (`+`, `-`)
  - `.Product` = highest (`*`, `/`)
- Add operator to switch in `parseExpression()` if it's binary
- Add to `parsePrefix()` if it's unary/prefix

## 3. Semantic Handling
In `src/engine.zig` (if operator needs evaluation):
- Add evaluation logic in `evaluate()` or `solve()`
- Handle the operator's semantics

## 4. Testing
Add tests for:
- Lexer recognizing the token
- Parser building correct AST structure
- Precedence interaction with other operators
- Semantic behavior (if applicable)

What operator would you like to add?
