% Integration tests for occurs check functionality

% ===============================================
% unify_with_occurs_check/2 Tests
% ===============================================

% Test 1: Normal unification succeeds
% EXPECT: X = a
?- unify_with_occurs_check(X, a).

% Test 2: Unifying two atoms
% EXPECT: true
?- unify_with_occurs_check(foo, foo).

% Test 3: Unifying two different atoms fails
% EXPECT: false
?- unify_with_occurs_check(foo, bar).

% Test 4: Unifying structures
% EXPECT: X = 1, Y = 2
?- unify_with_occurs_check(f(X, Y), f(1, 2)).

% Test 5: Simple cyclic unification fails
% EXPECT: false
?- unify_with_occurs_check(X, f(X)).

% Test 6: Deep cyclic unification fails
% EXPECT: false
?- unify_with_occurs_check(X, f(g(h(X)))).

% Test 7: Cyclic unification in structure fails
% EXPECT: false
?- unify_with_occurs_check(X, [X]).

% Test 8: Cyclic unification with nested structure fails
% EXPECT: false
?- unify_with_occurs_check(X, f(a, g(X))).

% Test 9: Non-cyclic structure unification succeeds
% EXPECT: X = f(a, b)
?- unify_with_occurs_check(X, f(a, b)).

% Test 10: Unifying with already bound variable
% EXPECT: X = a
?- X = a, unify_with_occurs_check(X, a).

% Test 11: Unifying bound variable with different value fails
% EXPECT: false
?- X = a, unify_with_occurs_check(X, b).

% Test 12: List unification
% EXPECT: X = 1
?- unify_with_occurs_check([X, Y, Z], [1, 2, 3]).

% Test 13: Comparison with regular unification (= allows cycles)
% This demonstrates the difference between = and unify_with_occurs_check
% EXPECT: false
?- X = f(X), acyclic_term(X).

% Test 14: Cyclic case fails with occurs check
% EXPECT: false
?- unify_with_occurs_check(Y, g(Y)).

% Test 15: Complex structure without cycles succeeds
% EXPECT: X = f(a, g(b, h(c)))
?- unify_with_occurs_check(X, f(a, g(b, h(c)))).

% ===============================================
% acyclic_term/1 Tests
% ===============================================

% Test 16: Atom is acyclic
% EXPECT: true
?- acyclic_term(foo).

% Test 17: Number is acyclic
% EXPECT: true
?- acyclic_term(42).

% Test 18: Simple structure is acyclic
% EXPECT: true
?- acyclic_term(f(a, b)).

% Test 19: Nested structure is acyclic
% EXPECT: true
?- acyclic_term(f(g(h(a)), b)).

% Test 20: List is acyclic
% EXPECT: true
?- acyclic_term([1, 2, 3]).

% Test 21: Unbound variable is acyclic
% EXPECT: true
?- acyclic_term(X).

% Test 22: Variable bound to atom is acyclic
% EXPECT: X = a
?- X = a, acyclic_term(X).

% Test 23: Variable bound to structure is acyclic
% EXPECT: X = f(a, b)
?- X = f(a, b), acyclic_term(X).

% Test 24: After normal unification, term is still acyclic
% EXPECT: X = f(a, b), Y = b
?- X = f(a, Y), Y = b, acyclic_term(X).

% Test 25: Cyclic term created with = is cyclic (acyclic_term fails)
% EXPECT: false
?- X = f(X), acyclic_term(X).

% Test 26: Deep cyclic term is cyclic
% EXPECT: false
?- X = f(g(X)), acyclic_term(X).

% ===============================================
% Combined Tests
% ===============================================

% Test 27: unify_with_occurs_check prevents cycles, acyclic_term confirms
% EXPECT: false
?- unify_with_occurs_check(X, f(X)), acyclic_term(X).

% Test 28: Normal unification + acyclic_term check
% EXPECT: X = f(a)
?- unify_with_occurs_check(X, f(a)), acyclic_term(X).

% Test 29: Complex acyclic structure
% EXPECT: X = f(g(h(i(j(k(l(m(n(o(p(a)))))))))))
?- X = f(g(h(i(j(k(l(m(n(o(p(a))))))))))), acyclic_term(X).

% Test 30: Multiple variables in acyclic structure
% EXPECT: X = 1
?- unify_with_occurs_check(f(X, Y, Z), f(1, 2, 3)), acyclic_term(f(X, Y, Z)).
