% Tail-Call Optimization Tests
% These tests verify that deep recursion doesn't cause stack overflow

% Simple counting - tail recursive
% count_down(N) counts from N to 0
count_down(0).
count_down(N) :- N > 0, N1 is N - 1, count_down(N1).

% Test moderate depth (should work even without TCO)
% EXPECT: true
?- count_down(100).

% Test deeper recursion (benefits from partial TCO)
% Note: Full TCO would allow much deeper recursion
% Current implementation: TCO for control flow (phrase, $end_scope)
% EXPECT: true
?- count_down(500).

% List length - tail recursive
list_len([], 0).
list_len([_|T], N) :- list_len(T, M), N is M + 1.

% Build a long list
make_list(0, []).
make_list(N, [N|T]) :- N > 0, N1 is N - 1, make_list(N1, T).

% Test with moderate list
% EXPECT: N = 50
?- make_list(50, L), list_len(L, N).

% Mutual recursion - tests multiple tail call sites
even(0).
even(N) :- N > 0, N1 is N - 1, odd(N1).

odd(N) :- N > 0, N1 is N - 1, even(N1).

% EXPECT: true
?- even(100).

% EXPECT: true
?- odd(99).

% EXPECT: false
?- odd(100).
