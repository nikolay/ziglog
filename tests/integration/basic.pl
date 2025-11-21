% Basic Prolog functionality tests

% Simple facts
likes(mary, food).
likes(mary, wine).
likes(john, wine).
likes(john, mary).

% EXPECT: true
?- likes(mary, food).

% EXPECT: true
?- likes(john, wine).

% EXPECT: false
?- likes(john, food).

% EXPECT: X = food
% EXPECT: X = wine
?- likes(mary, X).

% Simple rule
happy(X) :- likes(X, wine).

% EXPECT: true
?- happy(mary).

% EXPECT: true
?- happy(john).

% EXPECT: X = mary
% EXPECT: X = john
?- happy(X).

% Conjunction
% EXPECT: true
?- likes(mary, wine), likes(john, wine).

% EXPECT: false
?- likes(mary, wine), likes(mary, beer).

% Negation
% EXPECT: true
?- \+ likes(mary, beer).

% EXPECT: false
?- \+ likes(mary, wine).

% Arithmetic
% EXPECT: X = 5
?- X is 2 + 3.

% EXPECT: true
?- 10 > 5.

% EXPECT: false
?- 3 > 7.

% Unification
% EXPECT: X = hello
?- X = hello.

% EXPECT: true
?- foo(a, b) = foo(a, b).

% EXPECT: X = a
% EXPECT: Y = b
?- foo(X, Y) = foo(a, b).
