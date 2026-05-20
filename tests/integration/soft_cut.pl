% Tests for soft cut (*->) operator
% Soft cut commits to first solution of condition but allows backtracking in then-branch

% Fact database for testing
choice(1).
choice(2).
choice(3).

result(a).
result(b).

% Test 1: Basic soft cut - commits to first condition solution, allows backtracking in then
% EXPECT: Y = a
% EXPECT: Y = b
?- choice(X) *-> result(Y).

% Test 2: Soft cut with failure in condition
?- choice(4) *-> result(Y).

% Test 3: Soft cut with if-then-else (condition succeeds)
% EXPECT: Y = a
% EXPECT: Y = b
?- (choice(1) *-> result(Y) ; result(z)).

% Test 4: Soft cut with if-then-else (condition fails, executes else)
% EXPECT: Y = c
?- (choice(4) *-> result(Y) ; Y = c).

% Test 5: Soft cut in compound goal
% EXPECT: Y = a
% EXPECT: Y = b
?- (choice(X) *-> true), result(Y).

% Test 6: Soft cut with unification
% EXPECT: X = 1
?- (X = 1 *-> choice(X)).

% Test 7: Soft cut with failing then-branch
?- choice(X) *-> fail.

% Test 8: Soft cut commits to first condition, then backtracks correctly
% EXPECT: X = 1
?- choice(X) *-> X = 1.
