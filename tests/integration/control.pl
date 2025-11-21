% Control predicates tests: fail/0, repeat/0, if-then (->), if-then-else (-> ;)

% ======================
% fail/0 tests
% ======================

% EXPECT: false
?- fail.

% EXPECT: false
?- true, fail.

% EXPECT: true
?- true, true.

% ======================
% if-then (->) tests
% ======================

% EXPECT: true
?- (true -> true).

% EXPECT: false
?- (fail -> true).

% EXPECT: false
?- (true -> fail).

% EXPECT: X = 1
?- (true -> X = 1).

% EXPECT: false
?- (fail -> X = 1).

% With unification in condition
% EXPECT: X = 5
?- (X = 5 -> true).

% EXPECT: false
?- (1 = 2 -> true).

% Nested if-then
% EXPECT: true
?- ((true -> true) -> true).

% ======================
% if-then-else (-> ; ) tests
% ======================

% EXPECT: true
?- (true -> true ; fail).

% EXPECT: true
?- (fail -> fail ; true).

% EXPECT: false
?- (true -> fail ; true).

% EXPECT: false
?- (fail -> true ; fail).

% With unification
% EXPECT: X = yes
?- (true -> X = yes ; X = no).

% EXPECT: X = no
?- (fail -> X = yes ; X = no).

% Multiple choice in condition
person(alice).
person(bob).

% If-then commits to first solution
% EXPECT: X = alice
?- (person(X) -> X = alice ; fail).

% With arithmetic
% EXPECT: X = positive
?- (5 > 0 -> X = positive ; X = negative).

% EXPECT: X = negative
?- (0 - 5 > 0 -> X = positive ; X = negative).

% Nested if-then-else
% EXPECT: X = 1
?- (true -> (true -> X = 1 ; X = 2) ; X = 3).

% EXPECT: X = 2
?- (true -> (fail -> X = 1 ; X = 2) ; X = 3).

% EXPECT: X = 3
?- (fail -> X = 1 ; X = 3).

% ======================
% Note: repeat/0 tests are challenging in this test framework
% because repeat creates infinite choice points and must be
% terminated with cut (!). Testing repeat would require
% interactive REPL testing or special test framework support.
% ======================

% ======================
% Combined control flow tests
% ======================

max(X, Y, X) :- X >= Y, !.
max(_, Y, Y).

% EXPECT: Z = 10
?- max(10, 5, Z).

% EXPECT: Z = 7
?- max(3, 7, Z).

% Using if-then-else instead of cut
max2(X, Y, X) :- X >= Y.
max2(X, Y, Y) :- X < Y.

max_ite(X, Y, Z) :- (X >= Y -> Z = X ; Z = Y).

% EXPECT: Z = 10
?- max_ite(10, 5, Z).

% EXPECT: Z = 7
?- max_ite(3, 7, Z).

% ======================
% If-then with multiple solutions
% ======================

choice(a).
choice(b).
choice(c).

% Should only get first solution due to ->
% EXPECT: X = a
?- (choice(X) -> X = a ; fail).

% ======================
% Edge cases
% ======================

% Empty condition with true
% EXPECT: true
?- (true -> true ; true).

% Condition with side effects (unification)
% EXPECT: X = 5, Y = 5
?- (X = 5 -> Y = X ; Y = 0).

% Complex nested structure
% EXPECT: R = ok
?- (1 = 1 -> (2 = 2 -> R = ok ; R = fail1) ; R = fail2).
