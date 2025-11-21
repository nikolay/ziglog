---
description: Review code for Zig 0.15.2 best practices compliance
---

Review the code in the current context for Zig 0.15.2 best practices compliance. Check for:

## Naming Conventions
- [ ] Enum values use snake_case (e.g., `.lparen`, `.atom`, not `.LParen`, `.Atom`)
- [ ] Struct/type names use PascalCase
- [ ] Function names use camelCase
- [ ] Variable names use snake_case

## Tagged Unions
- [ ] Union fields match enum values exactly (lowercase)
- [ ] Constructor functions use `create` prefix to avoid naming conflicts
- [ ] Example: `Term.createAtom()` not `Term.atom()`

## Memory Management
- [ ] ArenaAllocator used for term allocation
- [ ] Proper `defer arena.deinit()` in tests
- [ ] No manual `destroy()` calls
- [ ] All heap allocations tracked

## Error Handling
- [ ] Specific error sets, not `anyerror`
- [ ] Errors propagate with `try` or explicit `catch`
- [ ] Error types match actual failure modes

## Testing
- [ ] Each new feature has test coverage
- [ ] Tests use ArenaAllocator with defer cleanup
- [ ] Test descriptions are clear

Provide a summary of issues found and suggest fixes with code examples.
