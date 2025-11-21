% Format Predicate Integration Tests
% Tests format/1 and format/2 predicates with various directives

% format/1 - plain text
% EXPECT: Hello, World!
?- format('Hello, World!').

% format/1 - with newline
% EXPECT: Line 1
?- format('Line 1~n').

% format/2 - ~w (write term)
% EXPECT: Value: 42
?- format('Value: ~w', [42]).

% format/2 - ~d (decimal integer)
% EXPECT: Number: 123
?- format('Number: ~d', [123]).

% format/2 - ~f (float)
% EXPECT: Float: 3.14
?- format('Float: ~f', [3.14]).

% format/2 - ~a (atom)
% EXPECT: Atom: hello
?- format('Atom: ~a', [hello]).

% format/2 - ~s (string)
% EXPECT: String: world
?- format('String: ~s', ["world"]).

% format/2 - multiple arguments
% EXPECT: x = 10, y = 20
?- format('~a = ~d, ~a = ~d', [x, 10, y, 20]).

% format/2 - mixed types
% EXPECT: Int: 5, Float: 2.5
?- format('Int: ~d, Float: ~f', [5, 2.5]).

% format/2 - escaped tilde
% EXPECT: Tilde: ~
?- format('Tilde: ~~', []).

% format/2 - structure with ~w
% EXPECT: Term: foo(a, b)
?- format('Term: ~w', [foo(a, b)]).

% format/2 - list with ~w
% EXPECT: List: [1, 2, 3]
?- format('List: ~w', [[1, 2, 3]]).

% Using format in rules
print_person(Name, Age) :- format('~a is ~d years old~n', [Name, Age]).

% EXPECT: alice is 30 years old
?- print_person(alice, 30).

% EXPECT: bob is 25 years old
?- print_person(bob, 25).

% Complex formatting with variables
describe(X, Y) :- format('Value of ~a is ~w~n', [X, Y]).

% EXPECT: Value of result is 42
?- describe(result, 42).

% EXPECT: Value of status is ok
?- describe(status, ok).

% Format with computed values (single line)
show_sum(A, B) :- Sum is A + B, format('~d + ~d = ~d~n', [A, B, Sum]).

% EXPECT: 5 + 3 = 8
?- show_sum(5, 3).

% EXPECT: 10 + 20 = 30
?- show_sum(10, 20).

% Format with float computations (single line)
show_area(Radius) :- Area is 3.14159 * Radius * Radius, format('Area of circle with radius ~w is ~f~n', [Radius, Area]).

% EXPECT: Area of circle with radius 2.0 is 12.56636
?- show_area(2.0).
