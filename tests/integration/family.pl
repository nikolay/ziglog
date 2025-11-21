% Family relationships test
% This test caught the indexing bug where rules with variable
% first arguments were not matched against ground queries.

person(nikolay, male).
person(yavor, male).
person(petya, female).
person(raya, female).

parent(nikolay, yavor).
parent(nikolay, raya).
parent(petya, yavor).
parent(petya, raya).

% Rules with variable in first argument position
mother(X) :- person(X, female), parent(X, _).
father(X) :- person(X, male), parent(X, _).

% Test ground queries (this is what was broken!)
% EXPECT: true
?- mother(petya).

% EXPECT: true
?- father(nikolay).

% Test that non-parents fail
% EXPECT: false
?- mother(raya).

% EXPECT: false
?- father(yavor).

% Test variable queries
% EXPECT: X = petya
?- mother(X).

% EXPECT: X = nikolay
?- father(X).

% Test with multiple solutions
child(X) :- parent(_, X).

% EXPECT: X = yavor
% EXPECT: X = raya
?- child(X).
