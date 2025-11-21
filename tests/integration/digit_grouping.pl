% Tests for digit grouping syntax (SWI-Prolog extension)
% Per https://www.swi-prolog.org/pldoc/man?section=digitgroupsyntax

% Test underscore separators in decimal
?- 1_000_000 =:= 1000000.
% Expected: yes

% Test underscore separators in binary
?- 0b1111_0000 =:= 240.
% Expected: yes

% Test underscore separators in octal
?- 0o7_777 =:= 4095.
% Expected: yes

% Test underscore separators in hexadecimal
?- 0xDEAD_BEEF =:= 3735928559.
% Expected: yes

% Test underscore separators in Edinburgh syntax
?- 16'FF_00 =:= 65280.
% Expected: yes

% Test space separators in decimal (radix <= 10)
?- 1 000 000 =:= 1000000.
% Expected: yes

% Test space separators in binary (radix <= 10)
?- 0b1111 0000 =:= 240.
% Expected: yes

% Test space separators in octal (radix <= 10)
?- 0o777 000 =:= 261632.
% Expected: yes

% Test block comment within digit group
?- 1_000_/*comment*/000 =:= 1000000.
% Expected: yes

% Test block comment in hex
?- 0xDE_/*sep*/AD =:= 57005.
% Expected: yes

% Test float with underscores
?- X is 3.141_592_653, X > 3.141, X < 3.142.
% Expected: yes

% Test mixed grouping in arithmetic
?- X is 1_000 + 2_000, X =:= 3000.
% Expected: yes

% Test grouping in comparisons
?- 1_000_000 > 999_999.
% Expected: yes

% Test grouping preserves value in is/2
?- X is 0b1111_1111, X =:= 255.
% Expected: yes

% Test multiple underscores (grouped by thousands)
?- 123_456_789 =:= 123456789.
% Expected: yes

% Test Edinburgh syntax with space (radix 10)
?- 10'123 456 =:= 123456.
% Expected: yes
