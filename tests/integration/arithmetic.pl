% Arithmetic Operators Integration Tests
% Tests all arithmetic operators including division, modulo, and comparison

% Basic arithmetic (+, -, *, /)
% EXPECT: X = 8
?- X is 5 + 3.

% EXPECT: X = 7
?- X is 10 - 3.

% EXPECT: X = 20
?- X is 4 * 5.

% EXPECT: X = 3
?- X is 9 / 3.

% Integer division operators
% // is truncating division (rounds towards zero)
% EXPECT: X = 2
?- X is 7 // 3.

% div is floored division (rounds towards -infinity)
% EXPECT: X = 2
?- X is 7 div 3.

% Modulo and remainder
% mod uses floored division
% EXPECT: X = 1
?- X is 7 mod 3.

% rem uses truncated division
% EXPECT: X = 1
?- X is 7 rem 3.

% Unary operators
% abs - absolute value (ISO: preserves type)
% EXPECT: X = 42
?- X is abs(42).

% EXPECT: X = 5.5
?- X is abs(-5.5).

% EXPECT: X = 3.14
?- X is abs(3.14).

% sign - returns -1, 0, or 1 (ISO: preserves type)
% EXPECT: X = 1
?- X is sign(42).

% EXPECT: X = 0
?- X is sign(0).

% EXPECT: X = -1
?- X is sign(-10).

% EXPECT: X = 1.0
?- X is sign(3.14).

% EXPECT: X = -1.0
?- X is sign(-2.5).

% EXPECT: X = 0.0
?- X is sign(0.0).

% Min/max operators
% EXPECT: X = 3
?- X is min(3, 7).

% EXPECT: X = 7
?- X is max(3, 7).

% ISO Prolog: min/max preserve type of winning value
% EXPECT: X = 3
?- X is max(3, 2.5).

% EXPECT: X = 3
?- X is max(2.5, 3).

% EXPECT: X = 2
?- X is min(2, 5.5).

% EXPECT: X = 2
?- X is min(5.5, 2).

% When winner is float, result is float
% EXPECT: X = 2.5
?- X is max(2.5, 2).

% EXPECT: X = 2.5
?- X is max(2, 2.5).

% EXPECT: X = 5.5
?- X is min(5.5, 6).

% EXPECT: X = 5.5
?- X is min(6, 5.5).

% Comparison operators (existing)
% EXPECT: true
?- 5 > 3.

% EXPECT: true
?- 3 < 5.

% EXPECT: true
?- 5 >= 5.

% EXPECT: true
?- 5 =< 5.

% Arithmetic equality/inequality
% =:= evaluates both sides and compares numerically
% EXPECT: true
?- 2 + 3 =:= 5.

% EXPECT: true
?- 10 - 2 =:= 8.

% EXPECT: false
?- 2 + 3 =:= 6.

% =\= is arithmetic inequality
% EXPECT: true
?- 2 + 3 =\= 6.

% EXPECT: false
?- 2 + 3 =\= 5.

% Complex expressions
% EXPECT: X = 14
?- X is 2 + 3 * 4.

% EXPECT: X = 20
?- X is (2 + 3) * 4.

% EXPECT: X = 7
?- X is abs(5) + 2.

% Difference between = and =:=
% = is unification (doesn't evaluate)
% =:= is arithmetic equality (evaluates both sides)

% EXPECT: false
?- 2 + 3 = 5.

% EXPECT: true
?- 2 + 3 =:= 5.

% EXPECT: X = 2 + 3
?- X = 2 + 3.

% Using in rules
factorial(0, 1).
factorial(N, F) :- N > 0, N1 is N - 1, factorial(N1, F1), F is N * F1.

% EXPECT: F = 120
?- factorial(5, F).

% Modulo for even/odd checking
is_even(N) :- N mod 2 =:= 0.
is_odd(N) :- N mod 2 =:= 1.

% EXPECT: true
?- is_even(10).

% EXPECT: true
?- is_odd(7).

% EXPECT: false
?- is_even(7).

% Absolute difference
abs_diff(X, Y, D) :- D is abs(X - Y).

% EXPECT: D = 5
?- abs_diff(10, 5, D).

% EXPECT: D = 5
?- abs_diff(5, 10, D).

% Range checking with comparison
in_range(X, Min, Max) :- X >= Min, X =< Max.

% EXPECT: true
?- in_range(5, 1, 10).

% EXPECT: false
?- in_range(15, 1, 10).
