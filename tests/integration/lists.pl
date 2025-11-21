% List operations tests

% append/3
append([], L, L).
append([H|T], L, [H|R]) :- append(T, L, R).

% EXPECT: X = [1, 2, 3]
?- append([1, 2], [3], X).

% EXPECT: X = [a, b, c, d]
?- append([a, b], [c, d], X).

% EXPECT: true
?- append([1], [2], [1, 2]).

% EXPECT: false
?- append([1], [2], [1, 3]).

% member/2
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% EXPECT: true
?- member(2, [1, 2, 3]).

% EXPECT: false
?- member(4, [1, 2, 3]).

% EXPECT: X = 1
% EXPECT: X = 2
% EXPECT: X = 3
?- member(X, [1, 2, 3]).

% length/2
length([], 0).
length([_|T], N) :- length(T, M), N is M + 1.

% EXPECT: X = 3
?- length([a, b, c], X).

% EXPECT: X = 0
?- length([], X).

% EXPECT: true
?- length([1, 2], 2).

% last/2
last([X], X).
last([_|T], X) :- last(T, X).

% EXPECT: X = c
?- last([a, b, c], X).

% EXPECT: true
?- last([hello], hello).

% reverse/2
reverse([], []).
reverse([H|T], R) :- reverse(T, Rev), append(Rev, [H], R).

% EXPECT: X = [3, 2, 1]
?- reverse([1, 2, 3], X).

% EXPECT: true
?- reverse([a, b], [b, a]).
