% Family relationships
parent(john, mary).
parent(jane, mary).
parent(john, tom).
parent(mary, ann).

grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
