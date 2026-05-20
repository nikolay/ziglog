% Integration tests for term_variables/2

% ===============================================
% term_variables/2 Tests
% ===============================================

% Test 1: Empty list for atom
% EXPECT: Vars = []
?- term_variables(atom, Vars).

% Test 2: Empty list for number
% EXPECT: Vars = []
?- term_variables(42, Vars).

% Test 3: Empty list for string
% EXPECT: Vars = []
?- term_variables("hello", Vars).

% Test 4: Single unbound variable
% EXPECT: Vars = [X]
?- term_variables(X, Vars).

% Test 5: Structure with one variable
% EXPECT: Vars = [X]
?- term_variables(f(X), Vars).

% Test 6: Structure with multiple variables
% EXPECT: Vars = [X, Y, Z]
?- term_variables(f(X, Y, Z), Vars).

% Test 7: Duplicate variables (only unique variables)
% EXPECT: Vars = [X, Y]
?- term_variables(f(X, X, Y), Vars).

% Test 8: Duplicate variables multiple times
% EXPECT: Vars = [X, Y]
?- term_variables(f(X, Y, X, Y, X), Vars).

% Test 9: Nested structure
% EXPECT: Vars = [X, Y, Z]
?- term_variables(f(g(X, Y), h(Z)), Vars).

% Test 10: Deeply nested structure
% EXPECT: Vars = [X, Y]
?- term_variables(f(g(h(i(X))), h(j(k(Y)))), Vars).

% Test 11: List with variables
% EXPECT: Vars = [X, Y, Z]
?- term_variables([X, Y, Z], Vars).

% Test 12: List with duplicate variables
% EXPECT: Vars = [X, Y]
?- term_variables([X, Y, X], Vars).

% Test 13: Mixed list with atoms and variables
% EXPECT: Vars = [X, Y]
?- term_variables([a, X, b, Y, c], Vars).

% Test 14: Empty list has no variables
% EXPECT: Vars = []
?- term_variables([], Vars).

% Test 15: Bound variable (should not appear)
% EXPECT: Vars = []
?- X = a, term_variables(X, Vars).

% Test 16: Partially bound structure
% EXPECT: Vars = [Y]
?- X = a, term_variables(f(X, Y), Vars).

% Test 17: Mixed bound and unbound
% EXPECT: Vars = [Y, Z]
?- X = 1, term_variables(f(X, Y, Z), Vars).

% Test 18: Complex nested with bound variables
% EXPECT: Vars = [Y]
?- X = foo, term_variables(f(g(X), h(Y)), Vars).

% Test 19: Variable appears in multiple subterms
% EXPECT: Vars = [X, Y]
?- term_variables(f(g(X), h(X), i(Y)), Vars).

% Test 20: Order matters - depth-first, left-to-right
% EXPECT: Vars = [A, B, C, D]
?- term_variables(f(g(A, B), h(C, D)), Vars).

% Test 21: With anonymous variables (treated as same variable)
% EXPECT: Vars = [_]
?- term_variables(f(_, _), Vars).

% Test 22: Structure with only bound values
% EXPECT: Vars = []
?- X = 1, Y = 2, term_variables(f(X, Y), Vars).

% Test 23: Checking variable identity (variables share with original)
% EXPECT: X = a, Y = a
?- term_variables(f(X), [Y]), X = a.

% Test 24: Deep nesting with many variables
% EXPECT: Vars = [A, B, C, D, E]
?- term_variables(f(A, g(B, h(C, i(D, E)))), Vars).

% Test 25: List with nested structures
% EXPECT: Vars = [X, Y, Z]
?- term_variables([f(X), g(Y, Z)], Vars).

% Test 26: Result unifies with a list structure
% EXPECT: Vars = [X, Y]
?- term_variables(f(X, Y), Vars).

% Test 27: Single variable appears multiple times in complex term
% EXPECT: Vars = [X]
?- term_variables(f(g(X), h(X), i(X)), Vars).

% Test 28: Mixture of numbers, atoms, and variables
% EXPECT: Vars = [X, Y]
?- term_variables(f(1, X, atom, Y, 3.14), Vars).

% Test 29: Variables in list tail
% EXPECT: Vars = [T]
?- term_variables([1, 2|T], Vars).

% Test 30: Verify variables share with original term
% EXPECT: X = bound, H = bound
?- term_variables(f(X, Y), [H|_]), X = bound, H = bound.
