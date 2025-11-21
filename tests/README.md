# Ziglog Integration Tests

This directory contains integration tests for Ziglog using `.pl` (Prolog) files.

## Test File Format

Test files use a simple format with special comment directives:

```prolog
% Regular comments are ignored (Prolog standard % syntax)

% Facts and rules are loaded into the engine
person(alice, female).
person(bob, male).

parent(X, Y) :- mother(X, Y).
parent(X, Y) :- father(X, Y).

% EXPECT: <expected output>
% Use EXPECT directives to specify what the next query should produce
% Multiple EXPECT lines test for multiple solutions

% EXPECT: true
?- person(alice, female).

% EXPECT: X = alice
% EXPECT: Y = female
?- person(X, Y).

% EXPECT: false
% Use "false" to test that a query should fail
?- person(charlie, male).
```

## Directives

### `% EXPECT: <output>`
Specifies expected output for the next query. Multiple `EXPECT` lines can be used to verify multiple solutions.

**Examples:**

```prolog
% Expect success with no variables
% EXPECT: true
?- likes(mary, wine).

% Expect specific variable bindings
% EXPECT: X = 5
?- X is 2 + 3.

% Expect multiple solutions
% EXPECT: X = 1
% EXPECT: X = 2
?- member(X, [1, 2]).

% Expect failure
% EXPECT: false
?- member(5, [1, 2, 3]).

% Expect multiple variable bindings
% EXPECT: X = a
% EXPECT: Y = b
?- foo(X, Y) = foo(a, b).
```

## Running Tests

```bash
# Run only integration tests
zig build test-integration

# Run only unit tests
zig build test

# Run all tests
zig build test-all
```

## Test Organization

- **basic.pl** - Core Prolog functionality (facts, rules, unification, arithmetic)
- **family.pl** - Family relationships (tests the indexing bug fix)
- **lists.pl** - List operations (append, member, length, reverse)
- **dcg.pl** - Definite Clause Grammars

## Adding New Tests

1. Create a new `.pl` file in `tests/integration/`
2. Add facts, rules, and queries with EXPECT directives
3. Add the file to `src/integration_test_main.zig` in the `test_files` array
4. Run `zig build test-integration` to verify

## Test Output

The test runner will:
- ✓ Show a checkmark for passing tests
- ❌ Show an X for failing tests with details
- Display a summary at the end

Example output:
```
Running tests/integration/family.pl...
✓ tests/integration/family.pl:18
✓ tests/integration/family.pl:21
✓ tests/integration/family.pl:25
✓ tests/integration/family.pl:29
✓ tests/integration/family.pl:33
✓ tests/integration/family.pl:37

tests/integration/family.pl: 6/6 queries passed

✅ All tests passed!
```

## Why Integration Tests?

Integration tests complement unit tests by:

1. **Testing real-world usage** - Uses actual Prolog syntax, not Zig API calls
2. **Better coverage** - Easy to add many test cases
3. **More readable** - Prolog syntax is clearer than Zig construction
4. **Catches integration bugs** - Tests the full parser → engine → output pipeline
5. **User-friendly** - Non-Zig developers can contribute tests

The family.pl test file specifically caught the indexing bug where rules with variable first arguments were not being matched against ground queries!
