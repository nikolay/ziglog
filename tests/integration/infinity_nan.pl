% Tests for Infinity and NaN float syntax (SWI-Prolog extension)
% Per https://www.swi-prolog.org/pldoc/man?section=floatsyntax

% Test positive infinity
?- X is 1.0Inf, X > 0.
% Expected: yes

% Test that infinity is greater than any finite number
?- 1.0Inf > 999999999.
% Expected: yes

% Test infinity in arithmetic
?- X is 1.0Inf + 100, X > 0.
% Expected: yes

% Test negative infinity (created via subtraction in is/2)
?- X is 0 - 1.0Inf, X < 0.
% Expected: yes

% Test that negative infinity is less than any finite number
?- X is 0 - 1.0Inf, X < 0, X < (0 - 999999999).
% Expected: yes

% Test NaN
?- X is 1.5NaN.
% Expected: X = 1.5NaN

% Test NaN with different mantissa
?- X is 2.7NaN.
% Expected: X = 1.5NaN (all NaNs display as 1.5NaN)

% Test NaN comparison fails (NaN is not equal to itself arithmetically)
?- X is 1.5NaN, Y is 1.5NaN, \+ (X =:= Y).
% Expected: yes

% Test NaN unifies with itself structurally
?- X is 1.5NaN, Y is 1.5NaN, X = Y.
% Expected: yes

% Test infinity with digit grouping
?- X is 1_000.0Inf, X > 0.
% Expected: yes

% Test infinity is not equal to finite numbers
?- \+ (1.0Inf =:= 999999999).
% Expected: yes

% Test infinity arithmetic: inf + inf
?- X is 1.0Inf + 1.0Inf, X > 0.
% Expected: yes

% Test infinity arithmetic: inf * 2
?- X is 1.0Inf * 2, X > 0.
% Expected: yes

% Test NaN in comparisons
?- X is 1.5NaN, \+ (X > 0).
% Expected: yes

% Test NaN in comparisons
?- X is 1.5NaN, \+ (X < 0).
% Expected: yes

% Test NaN in comparisons
?- X is 1.5NaN, \+ (X =:= 0).
% Expected: yes

% Test infinity comparison
?- 1.0Inf =:= 1.0Inf.
% Expected: yes

% Test different infinities
?- X is 0 - 1.0Inf, Y is 1.0Inf, X < Y.
% Expected: yes

% Test nan/0 function
?- X is nan.
% Expected: X = 1.5NaN

% Test nan/0 unification
?- X is nan, Y is nan, X = Y.
% Expected: yes

% Test nan/0 arithmetic comparison fails
?- X is nan, Y is nan, \+ (X =:= Y).
% Expected: yes

% Test inf/0 function
?- X is inf.
% Expected: X = 1.0Inf

% Test inf/0 is positive
?- X is inf, X > 0.
% Expected: yes

% Test negative inf via unary minus
?- X is -(inf).
% Expected: X = -1.0Inf

% Test inf/0 in comparisons
?- inf > 999999999.
% Expected: yes

% Test inf/0 equals infinity literal
?- inf =:= 1.0Inf.
% Expected: yes
