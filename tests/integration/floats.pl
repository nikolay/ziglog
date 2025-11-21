% Float Arithmetic Integration Tests
% Tests floating-point numbers and mixed int/float arithmetic

% Basic float literals
% EXPECT: X = 3.14
?- X = 3.14.

% EXPECT: X = 2.71828
?- X = 2.71828.

% Float addition
% EXPECT: X = 4.0
?- X is 2.5 + 1.5.

% EXPECT: X = 5.7
?- X is 3.2 + 2.5.

% Float subtraction
% EXPECT: X = 3.0
?- X is 5.5 - 2.5.

% EXPECT: X = 1.5
?- X is 4.0 - 2.5.

% Float multiplication
% EXPECT: X = 10.0
?- X is 2.5 * 4.0.

% EXPECT: X = 6.25
?- X is 2.5 * 2.5.

% Float division (always returns float)
% EXPECT: X = 3.5
?- X is 7 / 2.

% EXPECT: X = 2.5
?- X is 5.0 / 2.0.

% Mixed int/float arithmetic
% EXPECT: X = 3.5
?- X is 2 + 1.5.

% EXPECT: X = 5.5
?- X is 8.0 - 2.5.

% EXPECT: X = 7.5
?- X is 3 * 2.5.

% EXPECT: X = 4.0
?- X is 10 / 2.5.

% Unary operators with floats
% EXPECT: X = 3.14
?- Y is 0.0 - 3.14, X is abs(Y).

% EXPECT: X = 3.14
?- X is abs(3.14).

% EXPECT: X = -1.0
?- Y is 0.0 - 3.14, X is sign(Y).

% EXPECT: X = 1.0
?- X is sign(3.14).

% EXPECT: X = 0.0
?- X is sign(0.0).

% Min/max with floats
% EXPECT: X = 2.5
?- X is min(2.5, 5.0).

% EXPECT: X = 5.0
?- X is max(2.5, 5.0).

% Mixed min/max
% EXPECT: X = 2.0
?- X is min(2, 5.5).

% EXPECT: X = 5.5
?- X is max(2, 5.5).

% EXPECT: X = 2.5
?- X is min(5, 2.5).

% Float comparisons with =:= and =\=
% EXPECT: true
?- 3.5 =:= 3.5.

% EXPECT: true
?- 2.0 + 1.5 =:= 3.5.

% EXPECT: true
?- 3.5 =\= 4.0.

% EXPECT: true
?- 2.0 + 1.0 =\= 4.0.

% Mixed type comparisons
% EXPECT: true
?- 3.0 =:= 3.

% EXPECT: true
?- 2 + 1.5 =:= 3.5.

% EXPECT: true
?- 2 =\= 3.5.

% Relational operators with floats
% EXPECT: true
?- 3.5 > 2.0.

% EXPECT: true
?- 1.5 < 2.5.

% EXPECT: true
?- 3.0 >= 3.0.

% EXPECT: true
?- 2.5 =< 3.5.

% Mixed type relational comparisons
% EXPECT: true
?- 3.5 > 2.

% EXPECT: true
?- 2 < 3.5.

% EXPECT: true
?- 3.0 >= 3.

% EXPECT: true
?- 3 =< 3.5.

% Complex float expressions
% EXPECT: X = 7.5
?- X is 2.5 * (1.0 + 2.0).

% EXPECT: X = 4.5
?- X is (2.0 + 3.0) - 0.5.

% EXPECT: X = 10.0
?- X is (2.0 + 3.0) * 2.0.

% Using floats in rules
double(X, Y) :- Y is X * 2.0.

% EXPECT: Y = 6.28
?- double(3.14, Y).

% EXPECT: Y = 10.0
?- double(5, Y).

% Area calculation with floats
area(Radius, Area) :- Area is 3.14159 * Radius * Radius.

% EXPECT: Area = 3.14159
?- area(1.0, Area).

% EXPECT: Area = 12.56636
?- area(2.0, Area).

% Temperature conversion (Celsius to Fahrenheit)
c_to_f(C, F) :- F is C * 1.8 + 32.0.

% EXPECT: F = 32.0
?- c_to_f(0.0, F).

% EXPECT: F = 98.6
?- c_to_f(37.0, F).

% EXPECT: F = 212.0
?- c_to_f(100.0, F).
