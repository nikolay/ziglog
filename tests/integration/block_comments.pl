/* Single-line block comment at start */
/* Another single-line block comment */

person(alice). /* inline block comment */
person(bob).
person(charlie).

/* Block comment before rule */
human(X) :- person(X).

/* Test queries below */

% Basic fact query
% EXPECT: true
?- person(alice).

% Query with variable
% EXPECT: X = alice
?- person(X).

/* Block comment before query */
% EXPECT: true
?- human(bob).

% Test non-existent person
% EXPECT: false
?- person(dave).

/* Block comment with nested asterisks * ** *** */
% EXPECT: true
?- person(charlie).

/* Another block comment */
% EXPECT: X = alice
?- human(X).

/* Final test: mix of comment styles */
% Line comment
% EXPECT: true
?- human(alice).
