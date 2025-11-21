% Test Choice Point Elimination optimization
% Deterministic predicates (single matching clause) should not create choice points

% Deterministic fact - only one clause matches
unique_person(alice).

% Multiple facts - non-deterministic
person(bob).
person(charlie).

% Deterministic rule with guards
factorial(0, 1).
factorial(N, F) :- N > 0, N1 is N - 1, factorial(N1, F1), F is N * F1.

% Test deterministic fact
% EXPECT: true
?- unique_person(alice).

% Test non-deterministic facts
% EXPECT: X = bob
% EXPECT: X = charlie
?- person(X).

% Test deterministic factorial (each step is deterministic due to guards)
% EXPECT: F = 1
?- factorial(0, F).

% EXPECT: F = 120
?- factorial(5, F).

% Deterministic rule - only matches when conditions are met
is_adult(X) :- person(X), X = bob.

% EXPECT: true
?- is_adult(bob).

% EXPECT: false
?- is_adult(charlie).
