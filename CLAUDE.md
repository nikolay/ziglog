# Claude Code Project Context: ziglog

## Project Overview

**ziglog** is a Prolog interpreter and engine written in Zig 0.15.2. It implements core Prolog functionality including unification, SLD resolution, and Definite Clause Grammar (DCG) support.

## Architecture

### Core Components

#### 1. Abstract Syntax Tree (`src/ast.zig`)
- **Term**: Tagged union representing Prolog terms
  - `atom`: Atomic values (e.g., `hello`, `[]`)
  - `variable`: Logic variables (e.g., `X`, `_`)
  - `structure`: Compound terms (e.g., `parent(john, mary)`)
  - `number`: Integer literals
  - `string`: String literals
- **Rule**: Represents Prolog clauses with head and body
- **Constructor functions**: `Term.createAtom()`, `Term.createVariable()`, etc.

#### 2. Lexer (`src/lexer.zig`)
- Tokenizes Prolog source code
- Supports operators: `:-`, `-->`, `;`, `\\+`, comparison operators
- Token types use snake_case enum values (e.g., `.lparen`, `.turnstile`)
- **Comment support**:
  - Line comments: `%` to end of line
  - Block comments: `/* ... */` spanning multiple lines
- **Unicode and Escape Sequences**:
  - Full UTF-8 support for strings and atoms
  - SWI-Prolog-compatible character escapes: `\n`, `\t`, `\r`, `\\`, `\"`, `\'`
  - Special escapes: `\a`, `\b`, `\e`, `\f`, `\v`, `\s`
  - Numeric escapes: `\xNN` (hex), `\uXXXX` (Unicode 4-digit), `\UXXXXXXXX` (Unicode 8-digit), `\NNN` (octal)
  - Escape processing in `parseEscapeSequence()` with UTF-8 encoding via `appendCodepoint()`
  - Uses ArrayListUnmanaged for efficient buffer management during escape processing
- **Non-Decimal Numbers**:
  - ISO syntax: `0b` (binary), `0o` (octal), `0x` (hexadecimal) prefixes
  - Edinburgh syntax: `radix'number` format (radix 2-36)
  - Example: `0b100`, `0xFF`, `16'FF`, `36'Z`
  - All non-decimal numbers are unsigned (per SWI-Prolog specification)
- **Digit Grouping**:
  - Underscore separators: `1_000_000`, `0xDEAD_BEEF`, `16'FF_00`
  - Space separators (radix ≤ 10): `1 000 000`, `0b1111 0000`
  - Block comments within groups: `1_000_/*thousands*/000`
  - Implementation: `skipDigitGroupsForRadix()` handles all number bases
  - Lexer preserves separators in token value; parser strips them via `stripDigitSeparators()`
- **Infinity and NaN**:
  - Syntax: `<digit>.<digit>+Inf` or `<digit>.<digit>+NaN`
  - Examples: `1.0Inf`, `2.5NaN`, `1_000.0Inf`
  - Detected by checking for `Inf` or `NaN` suffix after decimal point

#### 3. Parser (`src/parser.zig`)
- Pratt parser with operator precedence
- **DCG Expansion**: Transforms grammar rules into standard Prolog
  - `s --> np, vp.` becomes `s(S0, S) :- np(S0, S1), vp(S1, S).`
- Supports lists with dot notation: `[1,2]` → `.(1, .(2, []))`
- **Non-Decimal Number Parsing**: `parseIntegerLiteral()` function handles:
  - ISO syntax: Detects `0b`, `0o`, `0x` prefixes and parses with appropriate radix
  - Edinburgh syntax: Extracts radix and number from `radix'number` format
  - Validates radix range (2-36) for Edinburgh syntax
- **Digit Separator Stripping**: `stripDigitSeparators()` removes underscores, spaces, and block comments from number tokens before parsing
- **Infinity and NaN Parsing**: `parseFloat()` function handles special float values
  - Detects `Inf` and `NaN` suffixes using `std.mem.endsWith()`
  - Returns `std.math.inf(f64)` or `-std.math.inf(f64)` for infinity
  - Returns `std.math.nan(f64)` for NaN
- **AST Formatting**: `Term.format()` in `src/ast.zig` displays special floats
  - Infinity: `1.0Inf` (positive) or `-1.0Inf` (negative)
  - NaN: `1.5NaN` (all NaN values display the same)
- **Arithmetic Functions**: `src/arithmetic.zig` implements `nan/0` function
  - Nullary function: `X is nan` returns NaN
  - Also supported as structure: `nan()` (0-argument functor)
  - Handled in both atom and structure cases in `evaluate()`

#### 4. Engine (`src/engine.zig`)
- **Unification**: `unify(t1, t2, env)` - pattern matching algorithm
- **Resolution**: SLD resolution with backtracking
- **Environment**: Variable bindings stored in `EnvMap`
- **Arithmetic**: Evaluates `is/2` expressions
- **Scoping**: Cut (`!`) operator with scope management
- **Control Predicates**:
  - `true/0`, `false/0`, `fail/0` - Basic success/failure
  - `repeat/0` - Infinite choice points (use with cut)
  - `(Cond -> Then)` - If-then (commits on first solution)
  - `(Cond -> Then ; Else)` - If-then-else
  - `;/2` - Disjunction (OR)
  - `\+/1`, `not/1` - Negation as failure
- **I/O Predicates**: `write/1`, `nl/0`, `format/1`, `format/2`
- **Meta-predicates**: `distinct/2`, `phrase/2`, `phrase/3` (DCG)

#### 5. Engine Optimizations
- **First-Argument Indexing** (`src/indexing.zig`): O(1) clause lookup by functor and first argument
- **Choice Point Elimination**: Skips environment cloning when only one clause matches
- Both optimizations are transparent and preserve Prolog semantics

#### 6. REPL (`src/main.zig`)
- Interactive query interface powered by replxx (C++ readline alternative)
- **Editing Features**:
  - **Live syntax highlighting**: Real-time colorization as you type
  - Tab completion for built-in and user-defined predicates
  - Syntax hints showing predicate arity
  - Command history with Up/Down arrow navigation
  - History search with Ctrl+R
  - Persistent history saved to `.ziglog_history`
  - Multi-line editing with indentation
- **Commands**: `:help`, `:load <file>`, `:quit`, `:clear`
- **Tab Completion** (`src/completion.zig`): Completes REPL commands, built-ins, and user predicates
- **Syntax Highlighting** (`src/highlighter.zig`):
  - `highlightForReplxx()`: Fills replxx color buffer for live highlighting
  - `highlight()`: ANSI color codes for terminal output
  - Separate color mappings for both modes
- **Replxx Integration** (`src/replxx.zig`, `src/replxx/`): Zig wrapper around ClickHouse fork of replxx (BSD-licensed C++ library with 18 source files)
- **Replxx Helper** (`src/replxx/replxx_helper.cxx`): C++ glue code to instantiate replxx with stdin/stdout/stderr
- Displays all solutions with backtracking

## Code Style & Standards

### Zig 0.15.2 Best Practices

1. **Enum Naming**: Use snake_case for enum values
   ```zig
   pub const TokenType = enum {
       lparen,    // NOT LParen
       comma,     // NOT Comma
       eof,       // NOT EOF
   };
   ```

2. **Tagged Unions**: Fields match enum values exactly
   ```zig
   pub const Term = union(TermType) {
       atom: []const u8,      // matches .atom enum value
       variable: []const u8,  // matches .variable
   };
   ```

3. **Constructor Functions**: Use `create` prefix to avoid naming conflicts
   ```zig
   pub fn createAtom(alloc: Allocator, s: []const u8) !*Term
   ```

4. **Memory Management**:
   - Use ArenaAllocator for term allocation
   - All terms are heap-allocated pointers
   - Parser/Engine own their allocators

5. **Error Handling**:
   - Use specific error sets, avoid `anyerror`
   - Propagate errors with `try`/`catch`

### File Organization

- **No circular dependencies**: lexer → parser → engine
- **Tests inline**: Each file contains its own tests
- **Minimal public API**: Only export what's necessary

## Common Development Tasks

### Adding a New Operator

1. Add token type to `TokenType` enum in `lexer.zig`
2. Add lexing logic in `Lexer.next()`
3. Add precedence in `Parser.getPrecedence()`
4. Handle in `Parser.parseExpression()` switch

### Adding a Built-in Predicate

1. Add handler in `Engine.solve()` switch on goal structure
2. Pattern match functor name and arity
3. Implement logic with unification
4. Add test case in `engine.zig`

### Extending Term Types

1. Add variant to `TermType` enum
2. Add field to `Term` union
3. Add constructor function with `create` prefix
4. Update `unify()`, `resolve()`, and `copyTerm()`
5. Add formatting in `Term.format()`

## Testing Strategy

### Unit Tests (Inline)
- **67 test cases** covering lexer, parser, AST, engine, indexing, arithmetic, floats, escape sequences, Unicode, non-decimal numbers, digit grouping, infinity/NaN
- Located inline in source files
- Run with: `zig build test`
- Use ArenaAllocator in tests for automatic cleanup

### Integration Tests (.pl files)
- **311 test queries** in `tests/integration/` across 16 test files
- Tests real-world Prolog usage with natural syntax
- Test files:
  - `basic.pl` - Core functionality (17 tests)
  - `family.pl` - Family relationships (7 tests)
  - `lists.pl` - List operations (14 tests)
  - `dcg.pl` - Definite Clause Grammars (12 tests)
  - `comments_test.pl` - Line comment handling (4 tests)
  - `block_comments.pl` - Block comment handling (7 tests)
  - `choice_point_elimination.pl` - Optimization (6 tests)
  - `tail_call_optimization.pl` - TCO (6 tests)
  - `arithmetic.pl` - Arithmetic operators (36 tests)
  - `floats.pl` - Floating-point arithmetic (49 tests)
  - `format.pl` - Format predicates (19 tests)
  - `unicode_escapes.pl` - Unicode and escape sequences (19 tests)
  - `nondecimal.pl` - Non-decimal number syntax (42 tests)
  - `digit_grouping.pl` - Digit grouping syntax (16 tests)
  - `infinity_nan.pl` - Infinity and NaN floats (26 tests)
  - `control.pl` - Control predicates (31 tests)
- Run with: `zig build test-integration`
- Format: See `tests/README.md`

### Running Tests
```bash
zig build test              # Unit tests only
zig build test-integration  # Integration tests only
zig build test-all          # Both unit and integration
```

## Important Patterns

### Unification
```zig
// Resolves variables, then unifies
const r1 = resolve(t1, env);
const r2 = resolve(t2, env);
if (r1.* == .variable) {
    env.put(alloc, r1.variable, t2);
}
```

### Resolution with Backtracking
```zig
// Try each matching rule
for (rules.items) |rule| {
    var new_env = env;
    if (unify(goal, rule.head, &new_env)) {
        // Recursively solve body goals
    }
}
```

### DCG Transformation
```zig
// `det --> [the].` becomes:
// det(S0, S1) :- S0 = [the|S1].
```

## Known Constraints

- **No garbage collection**: Uses arena allocation, memory freed on arena deinit
- **No tail call optimization**: Deep recursion may overflow stack
- **Single-threaded**: No parallel query execution
- **No constraint solving**: Pure unification only

## Future Enhancements

- Definite clause grammars with more complex bodies
- Tabling/memoization for performance
- Module system
- Foreign function interface
- Constraint logic programming

## Working with Claude Code

When making changes:
1. **Always read files first** before modifying
2. **Run tests after changes**: `zig build test`
3. **Follow naming conventions**: snake_case enums, createX constructors
4. **Update tests** when changing behavior
5. **Use Edit tool** for existing files, not Write
6. **Preserve memory patterns**: ArenaAllocator for terms

## Quick Reference

```zig
// Creating terms
const atom = try Term.createAtom(alloc, "hello");
const var_x = try Term.createVariable(alloc, "X");
const struct_term = try Term.createStructure(alloc, "foo", &[_]*Term{atom});

// Pattern matching
switch (term.*) {
    .atom => |a| std.debug.print("{s}\n", .{a}),
    .variable => |v| ...,
    .structure => |s| {
        const functor = s.functor;
        const args = s.args;
    },
    .number => |n| ...,
    .string => |s| ...,
}

// Unification
if (unify(alloc, term1, term2, &env)) {
    // terms unified successfully
}
```

## Build System

- **Build**: `zig build`
- **Test**: `zig build test`
- **Run**: `zig build run`
- **Clean**: `zig build clean`
- **Package**: Defined in `build.zig.zon`

## Documentation Requirements

**IMPORTANT**: When adding new language features or modifying existing behavior, ALL documentation must be updated to reflect the changes. This ensures consistency across the project.

### Required Documentation Updates

When implementing new features (operators, built-ins, optimizations, etc.), update:

1. **README.md** - User-facing documentation
   - Language reference section (operators, built-ins, syntax)
   - Examples demonstrating the new feature
   - Test count updates (unit and integration)
   - Test files list

2. **CLAUDE.md** (this file) - Developer documentation
   - Architecture changes
   - Code patterns and conventions
   - Integration points
   - Testing strategy

3. **CHANGELOG.md** - Version history
   - Feature description with examples
   - Technical details and implementation notes
   - Test coverage information
   - Breaking changes (if any)

4. **OPTIMIZATIONS_STATUS.md** (if optimization-related)
   - Status update (implemented/partial/skipped)
   - Performance impact metrics
   - Technical implementation details

5. **Test Files**
   - Add integration tests in `tests/integration/`
   - Add unit tests in relevant `src/*.zig` files
   - Update `src/integration_test_main.zig` with new test files

### Example: Adding Arithmetic Operators

When adding `div`, `mod`, `rem`, `//`, `abs`, `sign`, `min`, `max`, `=:=`, `=\=`:

- ✅ **Implementation**: `src/engine.zig` (evaluate function), `src/lexer.zig` (tokens), `src/parser.zig` (parsing)
- ✅ **Unit Tests**: Added 2 tests in `src/engine.zig` (arithmetic operators, comparison operators)
- ✅ **Integration Tests**: Created `tests/integration/arithmetic.pl` with 36 tests
- ✅ **Test Runner**: Updated `src/integration_test_main.zig` to include arithmetic.pl
- ✅ **README.md**: Updated arithmetic operators section, comparison operators section, built-in predicates, test counts
- ✅ **CLAUDE.md**: Added this documentation requirements section
- ✅ **CHANGELOG.md**: Added entry for new arithmetic operators

### Verification Checklist

Before considering a feature complete:

- [ ] All tests pass (`zig build test-all`)
- [ ] README.md reflects new capability with examples
- [ ] CLAUDE.md documents implementation details
- [ ] CHANGELOG.md entry added
- [ ] Integration test file created (if applicable)
- [ ] Test counts updated in documentation
- [ ] No TODOs or FIXMEs left in code

### Documentation Style

- **README.md**: User-friendly, example-driven, assumes Prolog knowledge
- **CLAUDE.md**: Technical, implementation-focused, for future developers/AI
- **CHANGELOG.md**: Chronological, includes "why" not just "what"
- **Code comments**: Explain non-obvious logic, algorithm choices, optimization rationale
