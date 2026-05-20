% Integration tests for dynamic database predicates
% Tests: assert/1, asserta/1, assertz/1, retract/1, retractall/1, abolish/1, clause/2

% Test 1: Basic assert and query
% EXPECT: true
?- assert(person(alice)), person(alice).

% Test 2: Assert multiple facts with assertz
% EXPECT: X = bob
?- assertz(person(bob)), person(X).

% Test 3: Asserta adds to beginning
% EXPECT: X = charlie
?- asserta(person(charlie)), person(X).

% Test 4: Query all persons (charlie was added first via asserta)
% EXPECT: X = charlie
% EXPECT: X = alice
% EXPECT: X = bob
?- person(X).

% Test 5: Retract a specific fact
% EXPECT: true
?- retract(person(alice)).

% Test 6: Verify alice is gone
% EXPECT: X = charlie
% EXPECT: X = bob
?- person(X).

% Test 7: Add more facts for retractall test
% EXPECT: true
?- assertz(color(red)), assertz(color(green)), assertz(color(blue)).

% Test 8: Query colors
% EXPECT: X = red
% EXPECT: X = green
% EXPECT: X = blue
?- color(X).

% Test 9: Retract all colors
% EXPECT: true
?- retractall(color(_)).

% Test 10: Verify colors are gone
% EXPECT: false
?- color(_).

% Test 11: Add facts for rule test
% EXPECT: true
?- assert(parent(john, mary)), assert(parent(mary, sue)).

% Test 12: Query parent facts
% EXPECT: true
?- parent(john, mary).

% Test 13: Test retract with variables
% EXPECT: X = john, Y = mary
?- retract(parent(X, Y)).

% Test 14: Verify only first was retracted
% EXPECT: X = mary, Y = sue
?- parent(X, Y).

% Test 15: Re-add the fact
% EXPECT: true
?- assert(parent(john, mary)).

% Test 16: Test abolish with functor/arity
% EXPECT: true
?- assertz(age(alice, 30)), assertz(age(bob, 25)), assertz(name(charlie)).

% Test 17: Verify age facts exist
% EXPECT: P = alice, A = 30
% EXPECT: P = bob, A = 25
?- age(P, A).

% Test 18: Abolish age/2
% EXPECT: true
?- abolish(age/2).

% Test 19: Verify age facts are gone
% EXPECT: false
?- age(_, _).

% Test 20: Verify name/1 still exists
% EXPECT: X = charlie
?- name(X).

% Test 21: Test clause/2 to retrieve clauses
% EXPECT: true
?- assertz(fruit(apple)), assertz(fruit(banana)).

% Test 22: Retrieve specific clause (body should be 'true' for facts)
% EXPECT: Body = true
?- clause(fruit(apple), Body).

% Test 23: Retrieve another clause
% EXPECT: Body = true
?- clause(fruit(banana), Body).

% Test 24: Retract with pattern matching
% EXPECT: true
?- assertz(temp(1)), assertz(temp(2)), assertz(temp(3)).

% Test 25: Retract first matching temp
% EXPECT: X = 1
?- retract(temp(X)).

% Test 26: Verify only first was retracted
% EXPECT: X = 2
% EXPECT: X = 3
?- temp(X).

% Test 27: Test retract with unification
% EXPECT: true
?- assertz(point(1, 2)), assertz(point(3, 4)).

% Test 28: Retract with pattern
% EXPECT: X = 1, Y = 2
?- retract(point(X, Y)).

% Test 29: Verify only first point was retracted
% EXPECT: A = 3, B = 4
?- point(A, B).

% Test 30: Clean up - retractall person/1
% EXPECT: true
?- retractall(person(_)).

% Test 31: Clean up - abolish remaining predicates
% EXPECT: true
?- abolish(parent/2), abolish(name/1), abolish(fruit/1), abolish(temp/1), abolish(point/2).

% Test 32: Verify database is clean
% EXPECT: false
?- person(_).
