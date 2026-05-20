% Integration tests for advanced arithmetic functions
% Tests: floor, ceiling, round, truncate, float, sqrt, sin, cos, tan, atan, atan2, exp, log, **

% Test: floor function with positive float
% Expected: X = 3
?- X is floor(3.7).

% Test: floor function with negative float
% Expected: X = -4
?- X is floor(-3.2).

% Test: floor function with integer
% Expected: X = 5
?- X is floor(5).

% Test: ceiling function with positive float
% Expected: X = 4
?- X is ceiling(3.2).

% Test: ceiling function with negative float
% Expected: X = -3
?- X is ceiling(-3.7).

% Test: ceiling function with integer
% Expected: X = 5
?- X is ceiling(5).

% Test: round function with positive float (rounds up)
% Expected: X = 4
?- X is round(3.5).

% Test: round function with positive float (rounds down)
% Expected: X = 3
?- X is round(3.4).

% Test: round function with negative float
% Expected: X = -4
?- X is round(-3.5).

% Test: round function with integer
% Expected: X = 7
?- X is round(7).

% Test: truncate function with positive float
% Expected: X = 3
?- X is truncate(3.9).

% Test: truncate function with negative float
% Expected: X = -3
?- X is truncate(-3.9).

% Test: truncate function with integer
% Expected: X = 5
?- X is truncate(5).

% Test: float conversion from integer
% Expected: X = 42.0
?- X is float(42).

% Test: float conversion from float (identity)
% Expected: X = 3.14
?- X is float(3.14).

% Test: sqrt of perfect square
% Expected: X = 4.0
?- X is sqrt(16).

% Test: sqrt of non-perfect square
% Expected: X = 3.16227766016838 (approximately)
?- X is sqrt(10).

% Test: sqrt of float
% Expected: X = 2.0
?- X is sqrt(4.0).

% Test: exp(0) = 1
% Expected: X = 1.0
?- X is exp(0).

% Test: exp(1) = e
% Expected: X = 2.718281828459045 (approximately)
?- X is exp(1).

% Test: exp(2)
% Expected: X = 7.38905609893065 (approximately)
?- X is exp(2).

% Test: log(e) = 1
% Expected: X = 1.0 (approximately)
?- X is log(2.718281828459045).

% Test: log(1) = 0
% Expected: X = 0.0
?- X is log(1).

% Test: log(10)
% Expected: X = 2.302585092994046 (approximately)
?- X is log(10).

% Test: sin(0) = 0
% Expected: X = 0.0
?- X is sin(0).

% Test: sin(pi/2) = 1 (using approximate value for pi/2)
% Expected: X = 1.0 (approximately)
?- X is sin(1.5707963267948966).

% Test: sin(pi) = 0 (using approximate value for pi)
% Expected: X = 0.0 (approximately, near zero)
?- X is sin(3.141592653589793).

% Test: cos(0) = 1
% Expected: X = 1.0
?- X is cos(0).

% Test: cos(pi/2) = 0 (using approximate value for pi/2)
% Expected: X = 0.0 (approximately, near zero)
?- X is cos(1.5707963267948966).

% Test: cos(pi) = -1 (using approximate value for pi)
% Expected: X = -1.0 (approximately)
?- X is cos(3.141592653589793).

% Test: tan(0) = 0
% Expected: X = 0.0
?- X is tan(0).

% Test: tan(pi/4) = 1 (using approximate value for pi/4)
% Expected: X = 1.0 (approximately)
?- X is tan(0.7853981633974483).

% Test: atan(0) = 0
% Expected: X = 0.0
?- X is atan(0).

% Test: atan(1) = pi/4
% Expected: X = 0.7853981633974483 (approximately)
?- X is atan(1).

% Test: atan(-1) = -pi/4
% Expected: X = -0.7853981633974483 (approximately)
?- X is atan(-1).

% Test: atan2(0, 1) = 0 (point on positive x-axis)
% Expected: X = 0.0
?- X is atan2(0, 1).

% Test: atan2(1, 0) = pi/2 (point on positive y-axis)
% Expected: X = 1.5707963267948966 (approximately)
?- X is atan2(1, 0).

% Test: atan2(1, 1) = pi/4 (point in first quadrant)
% Expected: X = 0.7853981633974483 (approximately)
?- X is atan2(1, 1).

% Test: atan2(-1, 1) = -pi/4 (point in fourth quadrant)
% Expected: X = -0.7853981633974483 (approximately)
?- X is atan2(-1, 1).

% Test: power operator ** with integers
% Expected: X = 8.0
?- X is 2 ** 3.

% Test: power operator ** with floats
% Expected: X = 27.0
?- X is 3.0 ** 3.0.

% Test: power operator ** with negative exponent (via subtraction)
% Expected: X = 0.25
?- X is 2 ** (0 - 2).

% Test: power operator ** with fractional exponent (square root)
% Expected: X = 3.0
?- X is 9 ** 0.5.

% Test: power operator ^ (alternative syntax)
% Expected: X = 16.0
?- X is 2 ^ 4.

% Test: combining floor with arithmetic
% Expected: X = 5
?- X is floor(3.7 + 1.8).

% Test: combining sqrt with arithmetic
% Expected: X = 5.0
?- X is sqrt(9) + sqrt(4).

% Test: combining trigonometric functions
% Expected: X = 1.0 (sin^2 + cos^2 = 1)
?- X is sin(0.5) ** 2 + cos(0.5) ** 2.

% Test: exp and log are inverses
% Expected: X = 5.0 (approximately)
?- X is exp(log(5)).

% Test: complex arithmetic expression with new functions
% Expected: X = 10.0 (floor(sqrt(100)))
?- X is floor(sqrt(100)).

% Test: nested rounding functions
% Expected: X = 3
?- X is floor(ceiling(3.2)).

% Test: sqrt of expression
% Expected: X = 5.0
?- X is sqrt(16 + 9).

% Test: power with zero exponent
% Expected: X = 1.0
?- X is 42 ** 0.

% Test: power with base 0
% Expected: X = 0.0
?- X is 0 ** 5.

% Test: float conversion in expression
% Expected: X = 15.0
?- X is float(10) + float(5).

% Test: truncate for negative numbers
% Expected: X = -3
?- X is truncate(-3.7).

% Test: round with exactly 0.5
% Expected: X = 2
?- X is round(2.5).

% Test: combining atan2 with other operations
% Expected: X = 0.7853981633974483 (approximately, pi/4 in radians)
?- X is atan2(sqrt(2), sqrt(2)).
