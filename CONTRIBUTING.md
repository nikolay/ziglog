# Contributing to Ziglog

Thank you for your interest in contributing to Ziglog! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- **Zig 0.15.2** - [Download here](https://ziglang.org/download/)
- Git
- A GitHub account

### Development Setup

1. **Fork the repository** on GitHub

2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ziglog.git
   cd ziglog
   ```

3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/nikolay/ziglog.git
   ```

4. **Verify everything works**:
   ```bash
   zig build test-all
   ```

## Making Changes

### Branching Strategy

- Create a new branch for your feature or fix:
  ```bash
  git checkout -b feature/my-new-feature
  # or
  git checkout -b fix/issue-123
  ```

### Code Style

Ziglog follows Zig 0.15.2 conventions:

- **Enum values**: Use snake_case (e.g., `.lparen`, not `.LParen`)
- **Functions**: Use camelCase (e.g., `parseExpression`)
- **Constructor functions**: Prefix with `create` (e.g., `createAtom`)
- **Variables**: Use snake_case
- **Constants**: Use SCREAMING_SNAKE_CASE

**Format your code** before committing:
```bash
zig fmt .
```

### Testing

All new features must include tests:

1. **Unit tests**: Add inline tests in the relevant `src/*.zig` file
2. **Integration tests**: Add test cases to `tests/integration/*.pl`

Run tests before submitting:
```bash
zig build test          # Unit tests
zig build test-integration  # Integration tests
zig build test-all      # All tests
```

### Documentation

When adding features, update:

1. **README.md** - User-facing documentation with examples
2. **CLAUDE.md** - Technical architecture details
3. **CHANGELOG.md** - Add entry describing your change
4. Code comments for non-obvious logic

See `CLAUDE.md` for the complete documentation requirements checklist.

## Submitting Changes

### Commit Messages

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Build process or auxiliary tool changes

**Examples**:
```
feat(lexer): add support for hexadecimal escape sequences

Implements \xNN escape sequences in strings and atoms,
following SWI-Prolog specification.

Closes #42
```

```
fix(parser): handle nested structures correctly

Fixes parsing of deeply nested compound terms that
previously caused stack overflow.
```

### Pull Request Process

1. **Update your branch** with latest upstream:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

3. **Create a Pull Request** on GitHub

4. **Wait for CI checks** - All tests must pass on Linux, macOS, and Windows

5. **Address review feedback** if requested

6. **Squash commits** if asked to clean up history

### PR Checklist

Before submitting, ensure:

- [ ] All tests pass (`zig build test-all`)
- [ ] Code is formatted (`zig fmt .`)
- [ ] New features have tests
- [ ] Documentation is updated
- [ ] CHANGELOG.md has an entry
- [ ] Commit messages follow conventions
- [ ] No merge commits (rebase instead)

## Project Structure

```
ziglog/
├── src/
│   ├── ast.zig           # Abstract Syntax Tree definitions
│   ├── lexer.zig         # Tokenization
│   ├── parser.zig        # Pratt parser
│   ├── engine.zig        # Unification and resolution
│   ├── indexing.zig      # First-argument indexing
│   ├── arithmetic.zig    # Arithmetic evaluation
│   ├── main.zig          # REPL implementation
│   └── test_runner.zig   # Integration test framework
├── tests/
│   └── integration/      # .pl integration test files
├── .github/
│   ├── workflows/        # CI/CD workflows
│   └── renovate.json     # Dependency update config
├── README.md             # User documentation
├── CLAUDE.md             # Developer documentation
├── CHANGELOG.md          # Version history
└── CONTRIBUTING.md       # This file
```

## Areas for Contribution

### High Priority

- **Full tail-call optimization** - Currently partial, needs completion
- **More built-in predicates** - findall, bagof, setof, sort, etc.
- **Performance benchmarks** - Comprehensive benchmark suite
- **Error messages** - Better error reporting with line numbers

### Medium Priority

- **Module system** - Namespace support for predicates
- **Assert/retract** - Dynamic predicate modification
- **Debugging support** - trace, spy, and breakpoint functionality
- **More DCG features** - Advanced grammar constructs

### Nice to Have

- **Constraint logic programming (CLP)** - CLP(FD) support
- **Tabling/memoization** - Performance optimization
- **Foreign function interface (FFI)** - Call Zig/C from Prolog
- **JIT compilation** - Runtime code generation
- **WASM target** - WebAssembly compilation

## Continuous Integration

All PRs are automatically tested via GitHub Actions on:

- **Linux**: x86_64, ARM64
- **macOS**: Intel, Apple Silicon
- **Windows**: x86_64, ARM64

Dependencies are auto-updated via Renovate bot.

## Code of Conduct

### Our Standards

- **Be respectful** and constructive in discussions
- **Welcome newcomers** and help them contribute
- **Focus on the code**, not the person
- **Give credit** where it's due

### Enforcement

Violations of these standards may result in:
- Warning
- Temporary ban from the project
- Permanent ban from the project

Report issues to the project maintainers.

## Questions?

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Documentation**: See CLAUDE.md for architecture details

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Ziglog! 🚀
