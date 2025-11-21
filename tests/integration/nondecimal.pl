% Test file for non-decimal number syntax
% Tests both ISO syntax (0b, 0o, 0x) and Edinburgh syntax (radix'number)

% ISO Binary syntax: 0b prefix
?- 0b100 =:= 4.
% Expected: true

?- 0b1111 =:= 15.
% Expected: true

?- 0b10101010 =:= 170.
% Expected: true

?- X is 0b11 + 0b1.
% Expected: X = 4

% ISO Octal syntax: 0o prefix
?- 0o10 =:= 8.
% Expected: true

?- 0o17 =:= 15.
% Expected: true

?- 0o377 =:= 255.
% Expected: true

?- X is 0o10 + 0o7.
% Expected: X = 15

% ISO Hexadecimal syntax: 0x prefix
?- 0x10 =:= 16.
% Expected: true

?- 0xf =:= 15.
% Expected: true

?- 0xFF =:= 255.
% Expected: true

?- 0xf00 =:= 3840.
% Expected: true

?- X is 0x10 + 0xf.
% Expected: X = 31

% Uppercase prefixes
?- 0XFF =:= 255.
% Expected: true

?- 0B1010 =:= 10.
% Expected: true

?- 0O77 =:= 63.
% Expected: true

% Edinburgh Binary syntax: 2'number
?- 2'100 =:= 4.
% Expected: true

?- 2'1111 =:= 15.
% Expected: true

?- 2'10101010 =:= 170.
% Expected: true

% Edinburgh Octal syntax: 8'number
?- 8'10 =:= 8.
% Expected: true

?- 8'17 =:= 15.
% Expected: true

?- 8'377 =:= 255.
% Expected: true

% Edinburgh Hexadecimal syntax: 16'number
?- 16'10 =:= 16.
% Expected: true

?- 16'F =:= 15.
% Expected: true

?- 16'FF =:= 255.
% Expected: true

?- 16'f00 =:= 3840.
% Expected: true

% Other radix values (2-36)
?- 3'12 =:= 5.
% Expected: true

?- 5'43 =:= 23.
% Expected: true

?- 10'123 =:= 123.
% Expected: true

?- 36'Z =:= 35.
% Expected: true

?- 36'10 =:= 36.
% Expected: true

% Mixed operations
?- X is 0b100 + 0o10 + 0x10.
% Expected: X = 28

?- X is 2'100 + 8'10 + 16'10.
% Expected: X = 28

?- X is 0xFF * 2.
% Expected: X = 510

?- X is 16'A + 10.
% Expected: X = 20

% Comparisons
?- 0b1000 > 0o7.
% Expected: true

?- 0x10 =< 16.
% Expected: true

?- 2'101 =\= 6.
% Expected: true

?- 16'FF =:= 8'377.
% Expected: true

% Complex expressions
?- X is (0b100 + 0b11) * 2.
% Expected: X = 14

?- X is 0xF div 0b11.
% Expected: X = 5

?- X is 8'100 mod 10.
% Expected: X = 4
