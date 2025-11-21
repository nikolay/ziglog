% Integration tests for Unicode support and character escapes
% Tests SWI-Prolog compatible escape sequences

% Test 1: Basic escape sequences (newline)
?- X = "Hello\nWorld", write(X), nl.

% Test 2: Tab escape
?- X = "Col1\tCol2\tCol3", write(X), nl.

% Test 3: Escaped quotes and backslashes
?- X = "She said \"Hello\"", X = "She said \"Hello\"".

% Test 4: Backslash escape
?- X = "Path\\to\\file", X = "Path\\to\\file".

% Test 5: Hex escape \xNN
?- X = "\x48\x65\x6C\x6C\x6F", X = "Hello".

% Test 6: Unicode escape \uXXXX - é (e with acute)
?- X = "\u00e9", X = "é".

% Test 7: Unicode escape \uXXXX - Chinese character
?- X = "\u4E2D", X = "中".

% Test 8: Emoji via \U (grinning face)
?- X = "\U0001F600", X = "😀".

% Test 9: Octal escape \NNN
?- X = "\110\145\154\154\157", X = "Hello".

% Test 10: Mixed escapes
?- X = "Line 1\nLine 2\tTabbed", write(X), nl.

% Test 11: Direct UTF-8 in strings
?- X = "café", X = "café".

% Test 12: Direct UTF-8 emoji
?- X = "Hello 👋 World", X = "Hello 👋 World".

% Test 13: Russian text
?- X = "Привет мир", X = "Привет мир".

% Test 14: Japanese text
?- X = "こんにちは", X = "こんにちは".

% Test 15: Escape sequences in single-quoted atoms
?- X = '\n\t', write(X), nl.

% Test 16: Unicode in atoms
?- X = 'café', X = 'café'.

% Test 17: Special escapes (bell, escape, form feed)
?- X = "\a\e\f", X = "\x07\x1B\x0C".

% Test 18: Backspace and vertical tab
?- X = "\b\v", X = "\x08\x0B".

% Test 19: Space escape \s
?- X = "word\sword", X = "word word".
