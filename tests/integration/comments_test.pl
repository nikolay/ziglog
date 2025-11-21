% Test file specifically for comment handling
% This demonstrates that .pl files with extensive comments
% are valid and can be loaded into the interpreter

% Define some facts
person(alice).   % inline comment should work too
person(bob).

% Define a simple rule
% with multi-line comments
human(X) :- person(X).

% Test basic query
% EXPECT: true
?- person(alice).

% Test with variable
% EXPECT: X = alice
?- person(X).

% Test the rule
% EXPECT: true
?- human(bob).

%%% Triple comment
% EXPECT: false
?- person(charlie).
