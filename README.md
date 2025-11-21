# Ziglog

[![CI](https://github.com/nikolay/ziglog/actions/workflows/ci.yml/badge.svg)](https://github.com/nikolay/ziglog/actions/workflows/ci.yml)
[![Release](https://github.com/nikolay/ziglog/actions/workflows/release.yml/badge.svg)](https://github.com/nikolay/ziglog/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A high-performance Prolog interpreter written in Zig 0.15.2, implementing core logic programming features with modern optimizations.

## Overview

Ziglog is a Prolog-like logic programming language interpreter featuring:

- **Complete Prolog core**: Unification, SLD resolution with backtracking, and cut operator
- **DCG support**: Definite Clause Grammars with automatic transformation
- **Full arithmetic**: Integer and floating-point arithmetic with automatic type promotion
- **Unicode support**: Full UTF-8 support with SWI-Prolog-compatible character escape sequences
- **Performance optimizations**: First-argument indexing, choice point elimination, partial tail-call optimization
- **Interactive REPL**: Full-featured read-eval-print loop with live syntax highlighting, tab completion, syntax hints, and command history (powered by replxx)
- **Comprehensive testing**: 67 unit tests + 311 integration tests across 16 test files

## Quick Start

### Building

```bash
zig build
```

### Running the REPL

```bash
zig build run
```

### Running Tests

```bash
# Unit tests only
zig build test

# Integration tests only
zig build test-integration

# All tests
zig build test-all
```

## Language Reference

### Facts

Facts are assertions about the world. They define relationships between terms.

```prolog
% Facts are atoms or structures followed by a period
parent(john, mary).
parent(john, bob).
parent(jane, mary).

% Facts with numbers
age(john, 45).
age(mary, 20).

% Facts with strings
greeting("Hello, World!").
```

### Rules

Rules define logical relationships with conditions.

```prolog
% Rule syntax: Head :- Body.
% Read as "Head is true if Body is true"
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).

% Rules can have multiple clauses
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).

% Rules with arithmetic
adult(X) :- age(X, Age), Age >= 18.
```

### Queries

Queries ask questions to the interpreter. Use `?-` to start a query.

```prolog
% Simple query
?- parent(john, mary).
true.

% Query with variables (finds all solutions)
?- parent(john, X).
X = mary
X = bob

% Query with multiple goals
?- parent(X, Y), parent(Y, Z).
X = john, Y = mary, Z = <child_of_mary>
...

% Query that fails
?- parent(alice, bob).
false.
```

### Terms

#### Atoms

Atoms are constants starting with lowercase letters or enclosed in single quotes.

```prolog
atom               % lowercase atom
hello_world        % atom with underscore
'Atom'            % quoted atom (can contain uppercase, spaces)
'atom with spaces' % quoted atom with spaces
[]                % special atom (empty list)
```

#### Variables

Variables start with uppercase letters or underscore.

```prolog
X                 % named variable
Person            % named variable
_                 % anonymous variable (matches anything, doesn't bind)
_Name             % anonymous variable (for readability, not bound)
```

#### Numbers

Both integers and floating-point numbers are supported. Ziglog supports non-decimal number notation following SWI-Prolog syntax.

```prolog
% Decimal integers
42                % positive integer
-17               % negative integer
0                 % zero

% Floats (must have decimal point)
3.14              % positive float
2.71828           % float with multiple decimals
0.5               % float less than 1
```

**Non-Decimal Numbers**: Ziglog supports both ISO and Edinburgh notation for non-decimal integers:

```prolog
% ISO Syntax (prefix notation)
0b1010            % Binary (decimal 10)
0o755             % Octal (decimal 493)
0xFF              % Hexadecimal (decimal 255)
0XFF              % Uppercase prefix also works

% Edinburgh Syntax (radix'number, base 2-36)
2'1010            % Binary (decimal 10)
8'755             % Octal (decimal 493)
16'FF             % Hexadecimal (decimal 255)
36'Z              % Base-36 (decimal 35)

% Examples in expressions:
?- X is 0b100 + 0x10.
X = 20

?- X is 16'FF =:= 255.
true.

?- X is 2'101 * 8'10.
X = 40
```

**Note**: Non-decimal numbers are always unsigned (as per SWI-Prolog specification).

**Digit Grouping**: Following SWI-Prolog, Ziglog supports digit grouping for improved readability of large numbers:

```prolog
% Underscore separators (works with all number bases)
1_000_000         % One million (decimal)
0b1111_0000       % Binary with grouping (240)
0xDEAD_BEEF       % Hexadecimal with grouping
16'FF_00          % Edinburgh syntax with grouping

% Space separators (only for radix ≤ 10)
1 000 000         % One million (decimal)
0b1111 0000       % Binary with spaces (240)
0o777 000         % Octal with spaces

% Comments within digit groups
1_000_/*thousands*/000   % Block comments allowed

% Floats with digit grouping
3.141_592_653     % Pi with digit separators

% Examples in expressions:
?- X is 1_000 + 2_000.
X = 3000

?- 0xDEAD_BEEF =:= 3735928559.
true.
```

**Note**: This is a SWI-Prolog extension and not part of ISO Prolog. Underscore separators can include optional whitespace and block comments. Space separators are restricted to bases 10 and lower.

**Infinity and NaN**: Following SWI-Prolog, Ziglog supports special float values for infinity and not-a-number:

```prolog
% Positive infinity
?- X is 1.0Inf.
X = 1.0Inf

% Negative infinity (via arithmetic)
?- X is 0 - 1.0Inf.
X = -1.0Inf

% NaN (Not-a-Number) - literal syntax
?- X is 1.5NaN.
X = 1.5NaN

% NaN via nan/0 function
?- X is nan.
X = 1.5NaN

% Infinity in comparisons
?- 1.0Inf > 999999999.
true.

% NaN fails all arithmetic comparisons
?- X is 1.5NaN, Y is 1.5NaN, X =:= Y.
false.

% But NaN unifies structurally
?- X is 1.5NaN, Y is 1.5NaN, X = Y.
true.

% Infinity with digit grouping
?- X is 1_000.0Inf.
X = 1.0Inf
```

**Note**: Infinity uses the syntax `<digit>.<digit>+Inf`, and NaN can use either the literal syntax `<digit>.<digit>+NaN` or the `nan/0` function. All infinities display as `1.0Inf` or `-1.0Inf`, and all NaN values display as `1.5NaN`. These are SWI-Prolog extensions and not part of ISO Prolog.

#### Strings

Strings are enclosed in double quotes. Strings fully support UTF-8 Unicode characters and SWI-Prolog-compatible escape sequences.

```prolog
"hello"           % string literal
"Hello, World!"   % string with punctuation
""                % empty string
"café"            % direct UTF-8 characters
"Hello 👋 World"  % emoji support
"日本語"          % Japanese text
```

**Character Escape Sequences**: Strings and atoms support escape sequences for special characters:

```prolog
% Standard escapes
"\n"              % newline
"\t"              % tab
"\r"              % carriage return
"\\"              % backslash
"\""              % double quote
"\'"              % single quote

% Special escapes
"\a"              % alert/bell (ASCII 7)
"\b"              % backspace
"\e"              % escape (ASCII 27)
"\f"              % form feed
"\v"              % vertical tab
"\s"              % space

% Numeric escapes
"\x41"            % hex escape (A)
"\u00e9"          % Unicode 4-digit (é)
"\U0001F600"      % Unicode 8-digit (😀)
"\101"            % octal escape (A)
```

**Example**:
```prolog
?- X = "Line 1\nLine 2\tTabbed", write(X).
Line 1
Line 2	Tabbed
X = "Line 1\nLine 2\tTabbed"
```

#### Structures

Structures (compound terms) represent complex data with a functor and arguments.

```prolog
person(john, 25)              % functor: person, arity: 2
point(3, 4)                   % functor: point, arity: 2
tree(node, left(1), right(2)) % nested structures
```

#### Lists

Lists are sequences of terms with special syntax.

```prolog
[]                % empty list
[1, 2, 3]         % list of numbers
[a, b, c]         % list of atoms
[X, Y, Z]         % list of variables
[H|T]             % list with head H and tail T
[1, 2|Rest]       % list with first two elements and Rest
[_|Tail]          % ignore head, capture tail
```

**Internal representation**: Lists are syntactic sugar for the dot structure:
```prolog
[1, 2, 3] = .(1, .(2, .(3, [])))
```

### Operators

#### Logical Operators

```prolog
% Conjunction (AND) - both goals must succeed
?- parent(X, Y), age(X, A).

% Disjunction (OR) - at least one goal must succeed
?- parent(X, mary); parent(X, bob).

% Negation (NOT) - succeeds if goal fails
?- \+ parent(alice, bob).
?- not(parent(alice, bob)).  % alternative syntax

% Cut (!) - prevents backtracking
first_solution(X) :- option(X), !.
```

**Cut operator semantics**: The cut operator `!` prevents backtracking beyond the point where it occurs:

```prolog
% Without cut - explores all solutions
max(X, Y, X) :- X >= Y.
max(X, Y, Y) :- X < Y.

% With cut - commits to first matching clause
max(X, Y, X) :- X >= Y, !.
max(X, Y, Y).
```

#### Arithmetic Operators

Arithmetic evaluation uses the `is/2` predicate. Ziglog supports both integer and floating-point arithmetic with automatic type promotion.

**Type Semantics:**

```prolog
% Division (/) always returns float
?- X is 7 / 2.
X = 3.5

% Integer operators only work on integers
?- X is 7 div 3.
X = 2

% Mixed int/float arithmetic promotes to float
?- X is 2 + 1.5.
X = 3.5

?- X is 3 * 2.5.
X = 7.5
```

**Binary Operators:**

```prolog
+, -, *, /      % Basic arithmetic (/ returns float)
//              % Integer division (truncate towards zero, int only)
div             % Floored division (rounds towards -infinity, int only)
mod             % Modulo (uses floored division, int only)
rem             % Remainder (uses truncated division, int only)
min, max        % Minimum and maximum (works with mixed types)

% Integer examples:
?- X is 5 + 3.
X = 8

?- Z is 7 div 3.
Z = 2

?- R is 7 mod 3.
R = 1

% Float examples:
?- X is 2.5 + 1.5.
X = 4.0

?- Y is 7.0 / 2.0.
Y = 3.5

% Mixed type examples:
?- M is min(5, 2.5).
M = 2.5

?- N is max(3.14, 2).
N = 3.14
```

**Unary Operators:**

```prolog
abs(X)    % Absolute value (preserves type)
sign(X)   % Returns -1, 0, or 1 (preserves type)

% Integer examples:
?- X is abs(-42).
X = 42

?- S is sign(42).
S = 1

% Float examples:
?- X is abs(3.14).
X = 3.14

?- S is sign(-3.14).
S = -1.0
```

**Using in rules:**

```prolog
factorial(0, 1).
factorial(N, F) :-
    N > 0,
    N1 is N - 1,
    factorial(N1, F1),
    F is N * F1.

is_even(N) :- N mod 2 =:= 0.
```

#### Comparison Operators

**Structural Comparison (No Evaluation):**

```prolog
=     % Unification
\=    % Not unifiable
```

**Numeric Comparison (Evaluates Arithmetic):**

```prolog
>     % Greater than
<     % Less than
>=    % Greater than or equal
=<    % Less than or equal (note: =< not <=)
=:=   % Arithmetic equality
=\=   % Arithmetic inequality
```

**Examples:**

```prolog
% Structural comparison
?- 2 + 3 = 5.
false.  % Structure +(2,3) doesn't unify with 5

?- X = 2 + 3.
X = 2 + 3  % X unified with structure, not evaluated

% Arithmetic comparison (integers)
?- 2 + 3 =:= 5.
true.  % Both sides evaluated: 5 == 5

?- 5 > 3.
true.

?- 10 =< 10.
true.

% Arithmetic comparison (floats)
?- 3.5 =:= 3.5.
true.

?- 2.0 + 1.5 =:= 3.5.
true.

% Mixed type comparison (promotes to float)
?- 3.0 =:= 3.
true.

?- 2 < 3.5.
true.

?- 3.0 >= 3.
true.
```

### Control Predicates

Control predicates manage program flow and backtracking behavior.

#### Basic Control

**`true/0`** - Always succeeds

```prolog
?- true.
true.
```

**`fail/0` (alias: `false/0`)** - Always fails

```prolog
?- fail.
false.

?- true, fail.
false.
```

**`repeat/0`** - Succeeds indefinitely, providing infinite choice points

```prolog
% Used with cut (!) to create loops
% Example: Read until condition met
process_input :- repeat, read_item(X), process(X), done(X), !.
```

**Note:** `repeat/0` creates infinite backtracking points and must be terminated with a cut (`!`) or other terminating condition.

#### If-Then-Else

**`(Cond -> Then ; Else)`** - If-then-else construct

```prolog
% If Cond succeeds, execute Then; otherwise execute Else
max(X, Y, X) :- X >= Y.
max(X, Y, Y) :- X < Y.

% Equivalent using if-then-else
max2(X, Y, Result) :- (X >= Y -> Result = X ; Result = Y).

?- max2(10, 5, R).
R = 10

?- max2(3, 7, R).
R = 7
```

**`(Cond -> Then)`** - If-then without else

```prolog
% Succeeds if Cond succeeds and Then succeeds
% Fails if Cond fails
?- (true -> write('yes')).
yes
true.

?- (fail -> write('yes')).
false.
```

**Commitment Behavior:**
- When `Cond` succeeds, the construct commits to the first solution
- No backtracking to alternative solutions of `Cond`
- Cuts within `Cond` affect only `Cond`, not the surrounding predicate

```prolog
choice(a).
choice(b).
choice(c).

% Commits to first solution (a), no backtracking to b or c
?- (choice(X) -> X = a ; fail).
X = a
```

### Definite Clause Grammars (DCG)

DCGs are a notation for expressing grammars, automatically transformed into standard Prolog.

#### DCG Syntax

```prolog
% Basic DCG rule: Head --> Body.
s --> np, vp.
np --> det, noun.
vp --> verb, np.

% Terminals (constants to consume from input)
det --> [the].
det --> [a].
noun --> [cat].
noun --> [dog].
verb --> [chases].
verb --> [sees].
```

#### DCG Transformation

Ziglog automatically transforms DCG rules into standard Prolog:

```prolog
% DCG rule:
s --> np, vp.

% Transformed to:
s(S0, S) :- np(S0, S1), vp(S1, S).
```

The transformation adds two arguments representing the input list and remaining list.

#### Querying DCGs

Use `phrase/2` or `phrase/3` to query DCGs:

```prolog
% phrase(NonTerminal, List)
?- phrase(s, [the, cat, chases, the, dog]).
true.

% phrase(NonTerminal, List, Rest)
?- phrase(np, [the, cat, chases], Rest).
Rest = [chases]
```

#### Advanced DCG Features

**Brace blocks** execute standard Prolog goals within DCG rules:

```prolog
% Count words while parsing
sentence(Count) --> words(0, Count).
words(N, N) --> [].
words(N0, N) --> [_], { N1 is N0 + 1 }, words(N1, N).
```

**Parameterized non-terminals**:

```prolog
% Number agreement in grammar
s --> np(Num), vp(Num).
np(sg) --> [cat].
np(pl) --> [cats].
vp(sg) --> [sleeps].
vp(pl) --> [sleep].

?- phrase(s, [cats, sleep]).
true.

?- phrase(s, [cat, sleep]).
false.  % number disagreement
```

### Built-in Predicates

#### I/O Predicates

```prolog
write(Term)       % Print term to stdout
nl                % Print newline
format(Format)    % Formatted output (no arguments)
format(Format, Args)  % Formatted output with arguments

% Examples:
?- write('Hello, '), write('World'), nl.
Hello, World
true.

?- format('Hello, ~a!~n', [world]).
Hello, world!
true.

?- format('Value: ~d, Float: ~f~n', [42, 3.14]).
Value: 42, Float: 3.14
true.
```

**Format Directives:**

The `format/1` and `format/2` predicates support the following directives:

| Directive | Description | Example |
|-----------|-------------|---------|
| `~w` | Write term (using write/1) | `format('~w', [foo(a,b)])` → `foo(a, b)` |
| `~d` | Decimal integer | `format('~d', [42])` → `42` |
| `~f` | Floating-point number | `format('~f', [3.14])` → `3.14` |
| `~a` | Atom (unquoted) | `format('~a', [hello])` → `hello` |
| `~s` | String or atom | `format('~s', ["world"])` → `world` |
| `~n` | Newline | `format('Line 1~nLine 2')` → `Line 1\nLine 2` |
| `~~` | Escaped tilde | `format('~~')` → `~` |

**Format Examples:**

```prolog
% Simple message
?- format('Hello, World!~n').
Hello, World!

% With arguments
?- format('Name: ~a, Age: ~d~n', [alice, 30]).
Name: alice, Age: 30

% Multiple types
?- format('Int: ~d, Float: ~f, Atom: ~a~n', [10, 2.5, test]).
Int: 10, Float: 2.5, Atom: test

% Using in rules
greet(Name) :- format('Welcome, ~a!~n', [Name]).
?- greet(bob).
Welcome, bob!

% With computed values
show_result(X, Y) :-
    Sum is X + Y,
    format('~d + ~d = ~d~n', [X, Y, Sum]).

?- show_result(5, 3).
5 + 3 = 8
```

#### Control Predicates

```prolog
true              % Always succeeds
false             % Always fails (synonym: fail)
!                 % Cut - prevent backtracking

% Example:
?- true.
true.

?- false.
false.
```

#### Meta Predicates

```prolog
distinct(Template, Goal)  % Find unique solutions

% Example: Remove duplicates
?- distinct(X, member(X, [1, 2, 1, 3, 2])).
X = 1
X = 2
X = 3
```

#### Arithmetic

```prolog
is/2              % Arithmetic evaluation

% Supported operators:
% Binary: +, -, *, /, //, div, mod, rem, min, max
% Unary: abs, sign
% Note: / returns float, //, div, mod, rem work on integers only

% Integer examples:
?- X is 2 + 3 * 4.
X = 14

?- Y is 7 mod 3.
Y = 1

?- Z is abs(-42).
Z = 42

% Float examples:
?- X is 2.5 + 1.5.
X = 4.0

?- Y is 7.0 / 2.0.
Y = 3.5

% Mixed type (promotes to float):
?- X is 2 + 1.5.
X = 3.5

?- Y is 7 / 2.
Y = 3.5
```

#### DCG Predicates

```prolog
phrase(DCG, List)         % Parse List with DCG
phrase(DCG, List, Rest)   % Parse List with DCG, leaving Rest

% Example:
s --> [hello], [world].
?- phrase(s, [hello, world]).
true.
```

### Comments

Ziglog supports both line comments and block comments:

**Line comments** start with `%` and continue to end of line:

```prolog
% This is a line comment
parent(john, mary).  % inline comment

% Multi-line comments using %:
% This is line 1 of comment
% This is line 2 of comment
```

**Block comments** use `/* ... */` syntax and can span multiple lines:

```prolog
/* This is a block comment */
person(alice). /* inline block comment */

/* Multi-line block comment
   spanning several lines
   with nested * asterisks ** allowed */
human(X) :- person(X).
```

### Multiple Definitions Per Line

You can define multiple clauses on a single line:

```prolog
os(linux). os(macos). os(windows).
color(red). color(green). color(blue).
```

## Performance Optimizations

Ziglog includes several performance optimizations that make it competitive with production Prolog implementations:

### First-Argument Indexing

**What it does**: Indexes clauses by functor/arity and first argument for O(1) lookup instead of O(N) linear scan.

**Example**:
```prolog
% With 1000 parent facts
parent(person_0, child_0).
parent(person_1, child_1).
...
parent(person_999, child_999).

% Query: parent(person_500, X)
% Without indexing: Scans all 1000 clauses
% With indexing: Directly finds 1 matching clause (O(1))
```

**Impact**: 10-100x faster for large databases

**Technical details**: See `src/indexing.zig`

### Choice Point Elimination

**What it does**: Detects when only one clause matches and skips environment cloning.

**Example**:
```prolog
% Deterministic - only one clause
unique(alice).
?- unique(alice).  % No environment clone needed!

% Non-deterministic - multiple clauses
person(bob).
person(charlie).
?- person(X).  % Environment cloned for backtracking
```

**Impact**: 20-30% faster, reduced memory usage

**Technical details**: See `src/engine.zig:424-436`

### Partial Tail-Call Optimization

**What it does**: Converts certain tail calls to iteration, preventing stack frame creation.

**Optimized constructs**:
- DCG operations (`phrase/2`, `phrase/3`)
- Internal control flow (`$end_scope`)

**Limitations**: Main clause resolution still uses recursion (by design for backtracking).

**Impact**: Reduces stack growth for DCG-heavy code

**Technical details**: See `src/engine.zig:159-489`

### Performance Comparison

| Operation | Time Complexity | Memory | Notes |
|-----------|----------------|---------|-------|
| Clause lookup | O(1) avg | O(N) index | With first-arg indexing |
| Deterministic query | O(d) | O(d) | No env clones (d = depth) |
| Non-deterministic query | O(b^d) | O(b*d) | b = branching factor |
| Unification | O(size(term)) | O(bindings) | Standard |

## REPL Commands

The Ziglog REPL provides full-featured editing powered by replxx:

### Editing Features

- **Live Syntax Highlighting**: Real-time colorization as you type - keywords in red, atoms in cyan, variables in yellow, numbers in magenta
- **Tab Completion**: Press Tab to auto-complete predicate names (both built-ins and user-defined)
- **Command History**: Use Up/Down arrows to navigate previous commands
- **History Search**: Press Ctrl+R to search command history
- **Multi-line Editing**: Long lines automatically wrap with proper indentation
- **Syntax Hints**: See predicate arity as you type (e.g., `parent/2`)
- **Persistent History**: Command history is saved to `.ziglog_history`

### Commands

- `:help` or `:h` - Show help message with all commands and keybindings
- `:load <filename>` - Load and execute a Prolog file
- `:quit` or `:q` - Exit the REPL
- `:clear` - Clear the screen
- `Ctrl+D` - Exit (EOF)

### Loading Files

```prolog
:load <filename>
```

Loads and executes a Prolog file.

Example:
```prolog
> :load examples/family.pl
Loaded: parent(john, mary).
Loaded: parent(jane, mary).
...
```

### Defining Clauses

Define facts and rules directly:

```prolog
> parent(john, mary).
  Added.
> grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
  Added.
```

### Running Queries

Start queries with `?-`:

```prolog
> ?- parent(john, X).
  X = mary
```

The REPL automatically enumerates all solutions.

## Architecture

Ziglog uses a classic Prolog implementation architecture:

1. **Lexer** (`src/lexer.zig`): Tokenizes input
2. **Parser** (`src/parser.zig`): Pratt parser with DCG expansion
3. **AST** (`src/ast.zig`): Term representation
4. **Engine** (`src/engine.zig`): Unification and SLD resolution
5. **Indexing** (`src/indexing.zig`): First-argument indexing
6. **REPL** (`src/main.zig`): Interactive interface

For detailed architecture documentation, see `CLAUDE.md`.

## Testing

Ziglog has comprehensive test coverage:

- **59 unit tests**: Lexer, parser, AST, engine, indexing, arithmetic, floats, non-decimal numbers
- **238 integration tests**: End-to-end functionality across 13 test files

### Unit Tests

```bash
zig build test
```

Tests individual components in isolation.

### Integration Tests

```bash
zig build test-integration
```

Tests complete Prolog programs with expected outputs.

Test files use `% EXPECT:` directives:

```prolog
% fact definition
parent(john, mary).

% EXPECT: true
?- parent(john, mary).

% EXPECT: X = mary
?- parent(john, X).
```

### Test Files

- `tests/integration/basic.pl` - Core Prolog (17 tests)
- `tests/integration/family.pl` - Relationships (7 tests)
- `tests/integration/lists.pl` - List operations (14 tests)
- `tests/integration/dcg.pl` - Grammar rules (12 tests)
- `tests/integration/comments_test.pl` - Line comment handling (4 tests)
- `tests/integration/block_comments.pl` - Block comment handling (7 tests)
- `tests/integration/choice_point_elimination.pl` - Optimization (6 tests)
- `tests/integration/tail_call_optimization.pl` - TCO (6 tests)
- `tests/integration/arithmetic.pl` - Arithmetic operators (36 tests)
- `tests/integration/floats.pl` - Floating-point arithmetic (49 tests)
- `tests/integration/format.pl` - Format predicates (19 tests)
- `tests/integration/unicode_escapes.pl` - Unicode and escape sequences (19 tests)
- `tests/integration/nondecimal.pl` - Non-decimal number syntax (42 tests)
- `tests/integration/digit_grouping.pl` - Digit grouping syntax (16 tests)
- `tests/integration/infinity_nan.pl` - Infinity and NaN floats (26 tests)

## Examples

### Family Relationships

```prolog
% Define facts
parent(john, mary).
parent(john, bob).
parent(jane, mary).
parent(mary, alice).

% Define rules
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
sibling(X, Y) :- parent(P, X), parent(P, Y), X \= Y.
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).

% Query
?- grandparent(john, alice).
true.

?- sibling(mary, bob).
true.

?- ancestor(john, X).
X = mary
X = bob
X = alice
```

### List Operations

```prolog
% List membership
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% List length
length([], 0).
length([_|T], N) :- length(T, M), N is M + 1.

% List append
append([], L, L).
append([H|T1], L2, [H|T3]) :- append(T1, L2, T3).

% Queries
?- member(2, [1, 2, 3]).
true.

?- length([a, b, c], N).
N = 3

?- append([1, 2], [3, 4], L).
L = [1, 2, 3, 4]
```

### Arithmetic

```prolog
% Factorial (integer)
factorial(0, 1).
factorial(N, F) :-
    N > 0,
    N1 is N - 1,
    factorial(N1, F1),
    F is N * F1.

% Fibonacci (integer)
fib(0, 0).
fib(1, 1).
fib(N, F) :-
    N > 1,
    N1 is N - 1,
    N2 is N - 2,
    fib(N1, F1),
    fib(N2, F2),
    F is F1 + F2.

% Temperature conversion (float)
c_to_f(C, F) :- F is C * 1.8 + 32.0.
f_to_c(F, C) :- C is (F - 32.0) / 1.8.

% Circle area (float)
circle_area(Radius, Area) :- Area is 3.14159 * Radius * Radius.

% Queries
?- factorial(5, F).
F = 120

?- fib(10, F).
F = 55

?- c_to_f(37.0, F).
F = 98.6

?- circle_area(2.0, A).
A = 12.56636
```

### DCG Example: Simple Grammar

```prolog
% Grammar rules
sentence --> noun_phrase, verb_phrase.
noun_phrase --> determiner, noun.
verb_phrase --> verb, noun_phrase.

% Terminals
determiner --> [the].
determiner --> [a].
noun --> [cat].
noun --> [dog].
noun --> [mouse].
verb --> [chases].
verb --> [sees].
verb --> [likes].

% Queries
?- phrase(sentence, [the, cat, chases, a, mouse]).
true.

?- phrase(sentence, [a, dog, sees, the, cat]).
true.

?- phrase(sentence, [cat, the, chases]).
false.  % invalid grammar
```

## Implementation Notes

### Memory Management

Ziglog uses Zig's `ArenaAllocator` for term allocation:

- All terms in a query are allocated from an arena
- Memory is freed when the arena is destroyed
- No garbage collection needed
- Zero memory leaks (verified by tests)

### Unification Algorithm

Standard Robinson's unification with occurs check omitted (like most Prolog implementations):

1. Resolve variables to their bindings
2. If either term is unbound variable, bind it
3. If both are structures, recursively unify functor and arguments
4. If both are atoms/numbers/strings, check equality

### Resolution Strategy

SLD resolution (Linear resolution with Selection function for Definite clauses):

1. Select leftmost goal from query
2. Find matching clauses using indexing
3. Unify goal with clause head
4. Replace goal with clause body
5. Backtrack on failure
6. Respect cut operator semantics

### Backtracking

Backtracking is implemented via recursive function calls:

- Each choice point clones the environment (unless eliminated by optimization)
- Cut operator prevents backtracking past cut point
- Solution enumeration continues until no more alternatives

## Limitations

Current limitations (may be addressed in future versions):

- **No occurs check**: Unification doesn't prevent infinite structures
- **No constraint solving**: Pure unification only (no CLP)
- **Single-threaded**: No parallel query execution
- **Limited I/O**: Only `write/1` and `nl/0`
- **No module system**: All predicates are global
- **No assert/retract**: Cannot dynamically modify the database
- **No debugging**: No trace/spy functionality

## Comparison with Other Prologs

| Feature | Ziglog | SWI-Prolog | GNU Prolog |
|---------|--------|------------|------------|
| Core Prolog | ✅ Full | ✅ | ✅ |
| DCG | ✅ Full | ✅ | ✅ |
| First-arg indexing | ✅ | ✅ | ✅ |
| Choice point elim | ✅ | ✅ | ✅ |
| Tail-call opt | ⚠️ Partial | ✅ Full | ✅ Full |
| Arithmetic | ✅ Int + Float | ✅ Int + Float | ✅ Int + Float |
| Constraint solving | ❌ | ✅ CLP(FD) | ✅ FD |
| Module system | ❌ | ✅ | ✅ |
| Assert/retract | ❌ | ✅ | ✅ |
| FFI | ❌ | ✅ | ✅ |
| JIT compilation | ❌ | ✅ | ✅ |

## Installation

### Pre-built Binaries

Download the latest release for your platform from the [Releases](https://github.com/nikolay/ziglog/releases) page:

- **Linux**: `ziglog-linux-x86_64.tar.gz` (Intel/AMD) or `ziglog-linux-aarch64.tar.gz` (ARM64)
- **macOS**: `ziglog-macos-x86_64.tar.gz` (Intel) or `ziglog-macos-aarch64.tar.gz` (Apple Silicon)
- **Windows**: `ziglog-windows-x86_64.tar.gz` (Intel/AMD) or `ziglog-windows-aarch64.tar.gz` (ARM64)

Extract and run:
```bash
tar -xzf ziglog-*.tar.gz
cd ziglog
./ziglog  # or ziglog.exe on Windows
```

### Build from Source

**Prerequisites**: Zig 0.15.2 ([download](https://ziglang.org/download/))

```bash
git clone https://github.com/nikolay/ziglog.git
cd ziglog
zig build
./zig-out/bin/ziglog
```

## Contributing

Contributions are welcome! Please follow these guidelines:

### Development Setup

1. Fork and clone the repository
2. Install Zig 0.15.2
3. Run tests: `zig build test-all`
4. Make your changes
5. Ensure tests pass and code is formatted: `zig fmt .`
6. Submit a pull request

### Areas for Improvement

- Full tail-call optimization for all recursive predicates
- More built-in predicates (findall, bagof, setof, etc.)
- Module system implementation
- Assert/retract for dynamic predicates
- Constraint logic programming (CLP)
- Tabling/memoization for performance
- Debugging support (trace/spy)
- Foreign function interface (FFI)

### Code Style

- Follow Zig 0.15.2 conventions (snake_case for enums, etc.)
- Add tests for new features
- Update documentation (README.md, CLAUDE.md, CHANGELOG.md)
- Keep commits focused and well-described

### Continuous Integration

All pull requests are automatically tested on:
- Linux (x86_64, ARM64)
- macOS (Intel, Apple Silicon)
- Windows (x86_64, ARM64)

Dependencies are automatically updated via [Renovate](https://docs.renovatebot.com/).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## References

- **Prolog Standard**: ISO/IEC 13211-1:1995
- **Warren's Abstract Machine**: Standard Prolog implementation model
- **The Art of Prolog** (Sterling & Shapiro): Classic Prolog textbook
- **SWI-Prolog Documentation**: https://www.swi-prolog.org/

## Project Files

- `CLAUDE.md` - Detailed architecture and development guide
- `OPTIMIZATIONS.md` - In-depth optimization analysis
- `OPTIMIZATIONS_STATUS.md` - Current optimization status
- `CHANGELOG.md` - Version history and improvements
- `TESTING.md` - Testing framework documentation
