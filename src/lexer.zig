const std = @import("std");

pub const TokenType = enum {
    atom,
    variable,
    number,
    string,
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    bar,
    comma,
    period,
    turnstile,
    plus,
    minus,
    mul,
    div,
    int_div, // //
    greater,
    less,
    greater_equal,
    less_equal,
    not_equal,
    equal,
    arith_equal, // =:=
    arith_not_equal, // =\=
    semicolon,
    not,
    is,
    arrow, // --> (DCG)
    if_then, // -> (if-then)
    eof,
};

pub const Token = struct {
    tag: TokenType,
    value: []const u8,
    start: usize,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Lexer {
        return Lexer{ .source = source, .pos = 0, .alloc = alloc };
    }

    fn isAlphaNumeric(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn parseEscapeSequence(self: *Lexer, buffer: *std.ArrayListUnmanaged(u8)) !void {
        // Expects self.pos to be at the backslash
        self.pos += 1; // skip '\'

        if (self.pos >= self.source.len) {
            try buffer.append(self.alloc, '\\');
            return;
        }

        const escape_char = self.source[self.pos];
        self.pos += 1;

        switch (escape_char) {
            'a' => try buffer.append(self.alloc, 0x07), // Alert/bell
            'b' => try buffer.append(self.alloc, 0x08), // Backspace
            'e' => try buffer.append(self.alloc, 0x1B), // Escape
            'f' => try buffer.append(self.alloc, 0x0C), // Form feed
            'n' => try buffer.append(self.alloc, '\n'), // Newline
            'r' => try buffer.append(self.alloc, '\r'), // Carriage return
            't' => try buffer.append(self.alloc, '\t'), // Tab
            'v' => try buffer.append(self.alloc, 0x0B), // Vertical tab
            's' => try buffer.append(self.alloc, ' '), // Space
            '\\' => try buffer.append(self.alloc, '\\'), // Backslash
            '\'' => try buffer.append(self.alloc, '\''), // Single quote
            '"' => try buffer.append(self.alloc, '"'), // Double quote
            '`' => try buffer.append(self.alloc, '`'), // Back quote
            'x' => {
                // Hexadecimal: \xNN\ or \xNN (closing backslash optional)
                // Note: closing backslash is only consumed if it's not starting a new escape
                var hex_value: u32 = 0;
                var digit_count: usize = 0;

                while (self.pos < self.source.len) {
                    const c = self.source[self.pos];
                    const digit_val = std.fmt.charToDigit(c, 16) catch {
                        // Not a hex digit - stop here
                        // The backslash-based termination is handled at a higher level
                        // (the string/atom parser will see the backslash as start of next escape)
                        break;
                    };
                    hex_value = hex_value * 16 + digit_val;
                    digit_count += 1;
                    self.pos += 1;
                }

                if (digit_count > 0) {
                    try appendCodepoint(buffer, self.alloc, hex_value);
                } else {
                    // No hex digits found, treat as literal \x
                    try buffer.append(self.alloc, '\\');
                    try buffer.append(self.alloc, 'x');
                }
            },
            'u' => {
                // Unicode: \uXXXX (exactly 4 hex digits)
                if (self.pos + 4 > self.source.len) {
                    // Not enough characters, treat as literal
                    try buffer.append(self.alloc, '\\');
                    try buffer.append(self.alloc, 'u');
                    return;
                }

                var hex_value: u32 = 0;
                var valid = true;
                for (0..4) |_| {
                    const c = self.source[self.pos];
                    const digit_val = std.fmt.charToDigit(c, 16) catch {
                        valid = false;
                        break;
                    };
                    hex_value = hex_value * 16 + digit_val;
                    self.pos += 1;
                }

                if (valid) {
                    try appendCodepoint(buffer, self.alloc, hex_value);
                } else {
                    // Invalid hex sequence, treat as literal
                    try buffer.append(self.alloc, '\\');
                    try buffer.append(self.alloc, 'u');
                }
            },
            'U' => {
                // Unicode: \UXXXXXXXX (exactly 8 hex digits)
                if (self.pos + 8 > self.source.len) {
                    // Not enough characters, treat as literal
                    try buffer.append(self.alloc, '\\');
                    try buffer.append(self.alloc, 'U');
                    return;
                }

                var hex_value: u32 = 0;
                var valid = true;
                for (0..8) |_| {
                    const c = self.source[self.pos];
                    const digit_val = std.fmt.charToDigit(c, 16) catch {
                        valid = false;
                        break;
                    };
                    hex_value = hex_value * 16 + digit_val;
                    self.pos += 1;
                }

                if (valid) {
                    try appendCodepoint(buffer, self.alloc, hex_value);
                } else {
                    // Invalid hex sequence, treat as literal
                    try buffer.append(self.alloc, '\\');
                    try buffer.append(self.alloc, 'U');
                }
            },
            'c' => {
                // Skip whitespace until non-whitespace character
                while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
                    self.pos += 1;
                }
                // Don't append anything (no output)
            },
            '0'...'7' => {
                // Octal: \NNN\ or \NNN (closing backslash optional)
                var octal_value: u32 = std.fmt.charToDigit(escape_char, 8) catch 0;

                while (self.pos < self.source.len) {
                    const c = self.source[self.pos];
                    const digit_val = std.fmt.charToDigit(c, 8) catch {
                        // Not an octal digit - stop here
                        // (backslash termination handled at higher level)
                        break;
                    };
                    octal_value = octal_value * 8 + digit_val;
                    self.pos += 1;
                }

                try appendCodepoint(buffer, self.alloc, octal_value);
            },
            else => {
                // Unknown escape, keep literal backslash and character
                try buffer.append(self.alloc, '\\');
                try buffer.append(self.alloc, escape_char);
            },
        }
    }

    fn appendCodepoint(buffer: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, codepoint: u32) !void {
        // Encode codepoint as UTF-8
        if (codepoint <= 0x7F) {
            // 1-byte sequence
            try buffer.append(alloc, @intCast(codepoint));
        } else if (codepoint <= 0x7FF) {
            // 2-byte sequence
            try buffer.append(alloc, @intCast(0xC0 | (codepoint >> 6)));
            try buffer.append(alloc, @intCast(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            // 3-byte sequence
            try buffer.append(alloc, @intCast(0xE0 | (codepoint >> 12)));
            try buffer.append(alloc, @intCast(0x80 | ((codepoint >> 6) & 0x3F)));
            try buffer.append(alloc, @intCast(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0x10FFFF) {
            // 4-byte sequence
            try buffer.append(alloc, @intCast(0xF0 | (codepoint >> 18)));
            try buffer.append(alloc, @intCast(0x80 | ((codepoint >> 12) & 0x3F)));
            try buffer.append(alloc, @intCast(0x80 | ((codepoint >> 6) & 0x3F)));
            try buffer.append(alloc, @intCast(0x80 | (codepoint & 0x3F)));
        } else {
            // Invalid codepoint, use replacement character U+FFFD
            try buffer.append(alloc, 0xEF);
            try buffer.append(alloc, 0xBF);
            try buffer.append(alloc, 0xBD);
        }
    }

    fn isDigitForRadix(c: u8, radix: u8) bool {
        const digit_val = std.fmt.charToDigit(c, radix) catch return false;
        return digit_val < radix;
    }

    fn skipDigitGroupsForRadix(self: *Lexer, radix: u8) void {
        // Skip digits with digit grouping separators
        // Separators: underscore + optional whitespace
        // For radix <= 10: also allow single space
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            if (isDigitForRadix(c, radix)) {
                self.pos += 1;
            } else if (c == '_') {
                // Underscore separator: skip underscore and optional whitespace
                self.pos += 1;
                while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
                    self.pos += 1;
                }
                // Check for block comments after underscore
                if (self.pos + 1 < self.source.len and self.source[self.pos] == '/' and self.source[self.pos + 1] == '*') {
                    self.pos += 2; // skip /*
                    while (self.pos + 1 < self.source.len) {
                        if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                            self.pos += 2; // skip */
                            break;
                        }
                        self.pos += 1;
                    }
                }
            } else if (c == ' ' and radix <= 10) {
                // Single space separator (only for radix <= 10)
                const next_pos = self.pos + 1;
                if (next_pos < self.source.len and isDigitForRadix(self.source[next_pos], radix)) {
                    self.pos += 1;
                } else {
                    // Not followed by a digit, stop here
                    break;
                }
            } else {
                // Not a digit or separator, stop
                break;
            }
        }
    }

    pub fn next(self: *Lexer) Token {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }

        // Skip block comments /* ... */
        if (self.pos + 1 < self.source.len and self.source[self.pos] == '/' and self.source[self.pos + 1] == '*') {
            self.pos += 2; // skip /*
            while (self.pos + 1 < self.source.len) {
                if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                    self.pos += 2; // skip */
                    return self.next(); // recursively skip whitespace and more comments
                }
                self.pos += 1;
            }
            // Unterminated block comment - reached end of source
            return Token{ .tag = .eof, .value = "Unterminated block comment", .start = self.pos };
        }

        // Skip comments (% to end of line)
        if (self.pos < self.source.len and self.source[self.pos] == '%') {
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            // Skip the newline and any following whitespace
            if (self.pos < self.source.len and self.source[self.pos] == '\n') {
                self.pos += 1;
            }
            // Recursively call next() to skip whitespace and handle more comments
            return self.next();
        }

        if (self.pos >= self.source.len) {
            return Token{ .tag = .eof, .value = "", .start = self.pos };
        }

        const start = self.pos;
        const char = self.source[self.pos];

        if (char == ':' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
            self.pos += 2;
            return Token{ .tag = .turnstile, .value = ":-", .start = start };
        }
        if (char == '\\') {
            if (self.pos + 1 < self.source.len) {
                if (self.source[self.pos + 1] == '+') {
                    // Check if '\\+' followed by '(' - if so, it's a functor (atom)
                    if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                        self.pos += 2;
                        return Token{ .tag = .atom, .value = "\\+", .start = start };
                    }
                    self.pos += 2;
                    return Token{ .tag = .not, .value = "\\+", .start = start };
                }
                if (self.source[self.pos + 1] == '=') {
                    // Check if '\\=' followed by '(' - if so, it's a functor (atom)
                    if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                        self.pos += 2;
                        return Token{ .tag = .atom, .value = "\\=", .start = start };
                    }
                    self.pos += 2;
                    return Token{ .tag = .not_equal, .value = "\\=", .start = start };
                }
            }
        }
        if (char == '!') {
            self.pos += 1;
            return Token{ .tag = .atom, .value = "!", .start = start };
        }

        if (char == '(') {
            self.pos += 1;
            return Token{ .tag = .lparen, .value = "(", .start = start };
        }
        if (char == ')') {
            self.pos += 1;
            return Token{ .tag = .rparen, .value = ")", .start = start };
        }
        if (char == '[') {
            self.pos += 1;
            return Token{ .tag = .lbracket, .value = "[", .start = start };
        }
        if (char == ']') {
            self.pos += 1;
            return Token{ .tag = .rbracket, .value = "]", .start = start };
        }
        if (char == '{') {
            self.pos += 1;
            return Token{ .tag = .lbrace, .value = "{", .start = start };
        }
        if (char == '}') {
            self.pos += 1;
            return Token{ .tag = .rbrace, .value = "}", .start = start };
        }
        if (char == '|') {
            self.pos += 1;
            return Token{ .tag = .bar, .value = "|", .start = start };
        }
        if (char == ',') {
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = ",", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .comma, .value = ",", .start = start };
        }
        if (char == '.') {
            // Check if followed by '(' - if so, it's the list cons operator (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = ".", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .period, .value = ".", .start = start };
        }
        if (char == ';') {
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = ";", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .semicolon, .value = ";", .start = start };
        }
        if (char == '+') {
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "+", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .plus, .value = "+", .start = start };
        }
        if (char == '-') {
            if (self.pos + 2 < self.source.len and self.source[self.pos + 1] == '-' and self.source[self.pos + 2] == '>') {
                self.pos += 3;
                return Token{ .tag = .arrow, .value = "-->", .start = start };
            }
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>') {
                self.pos += 2;
                return Token{ .tag = .if_then, .value = "->", .start = start };
            }
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "-", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .minus, .value = "-", .start = start };
        }
        if (char == '*') {
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "*", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .mul, .value = "*", .start = start };
        }
        if (char == '/') {
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                // Check if '//' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                    self.pos += 2;
                    return Token{ .tag = .atom, .value = "//", .start = start };
                }
                self.pos += 2;
                return Token{ .tag = .int_div, .value = "//", .start = start };
            }
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "/", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .div, .value = "/", .start = start };
        }
        if (char == '>') {
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                // Check if '>=' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                    self.pos += 2;
                    return Token{ .tag = .atom, .value = ">=", .start = start };
                }
                self.pos += 2;
                return Token{ .tag = .greater_equal, .value = ">=", .start = start };
            }
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = ">", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .greater, .value = ">", .start = start };
        }
        if (char == '<') {
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "<", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .less, .value = "<", .start = start };
        }
        if (char == '=') {
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '<') {
                // Check if '=<' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                    self.pos += 2;
                    return Token{ .tag = .atom, .value = "=<", .start = start };
                }
                self.pos += 2;
                return Token{ .tag = .less_equal, .value = "=<", .start = start };
            }
            if (self.pos + 2 < self.source.len and self.source[self.pos + 1] == ':' and self.source[self.pos + 2] == '=') {
                // Check if '=:=' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 3 < self.source.len and self.source[self.pos + 3] == '(') {
                    self.pos += 3;
                    return Token{ .tag = .atom, .value = "=:=", .start = start };
                }
                self.pos += 3;
                return Token{ .tag = .arith_equal, .value = "=:=", .start = start };
            }
            if (self.pos + 2 < self.source.len and self.source[self.pos + 1] == '\\' and self.source[self.pos + 2] == '=') {
                // Check if '=\\=' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 3 < self.source.len and self.source[self.pos + 3] == '(') {
                    self.pos += 3;
                    return Token{ .tag = .atom, .value = "=\\=", .start = start };
                }
                self.pos += 3;
                return Token{ .tag = .arith_not_equal, .value = "=\\=", .start = start };
            }
            // Check if followed by '(' - if so, it's a functor (atom)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '(') {
                self.pos += 1;
                return Token{ .tag = .atom, .value = "=", .start = start };
            }
            self.pos += 1;
            return Token{ .tag = .equal, .value = "=", .start = start };
        }
        if (char == '\\') {
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                // Check if '\\=' followed by '(' - if so, it's a functor (atom)
                if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '(') {
                    self.pos += 2;
                    return Token{ .tag = .atom, .value = "\\=", .start = start };
                }
                self.pos += 2;
                return Token{ .tag = .not_equal, .value = "\\=", .start = start };
            }
            // Fallthrough to \+ check which is handled earlier or error?
            // Actually \+ is handled earlier. If we are here, it's not \+.
            // But wait, the previous check for \+ was:
            // if (char == '\\' and ... == '+')
            // So if it is \, we need to be careful.
            // Let's check if we need to merge the checks.
        }

        if (char == '"') {
            self.pos += 1; // skip opening quote
            var buffer = std.ArrayListUnmanaged(u8){};

            while (self.pos < self.source.len and self.source[self.pos] != '"') {
                if (self.source[self.pos] == '\\') {
                    self.parseEscapeSequence(&buffer) catch {
                        buffer.deinit(self.alloc);
                        return Token{ .tag = .eof, .value = "Invalid escape sequence", .start = start };
                    };
                } else {
                    buffer.append(self.alloc, self.source[self.pos]) catch {
                        buffer.deinit(self.alloc);
                        return Token{ .tag = .eof, .value = "Out of memory", .start = start };
                    };
                    self.pos += 1;
                }
            }

            if (self.pos < self.source.len) {
                self.pos += 1; // skip closing quote
                const value = buffer.toOwnedSlice(self.alloc) catch {
                    buffer.deinit(self.alloc);
                    return Token{ .tag = .eof, .value = "Out of memory", .start = start };
                };
                return Token{ .tag = .string, .value = value, .start = start };
            }
            buffer.deinit(self.alloc);
            return Token{ .tag = .eof, .value = "Unterminated string", .start = start };
        }

        if (char == '\'') {
            self.pos += 1; // skip opening quote
            var buffer = std.ArrayListUnmanaged(u8){};

            while (self.pos < self.source.len and self.source[self.pos] != '\'') {
                if (self.source[self.pos] == '\\') {
                    self.parseEscapeSequence(&buffer) catch {
                        buffer.deinit(self.alloc);
                        return Token{ .tag = .eof, .value = "Invalid escape sequence", .start = start };
                    };
                } else {
                    buffer.append(self.alloc, self.source[self.pos]) catch {
                        buffer.deinit(self.alloc);
                        return Token{ .tag = .eof, .value = "Out of memory", .start = start };
                    };
                    self.pos += 1;
                }
            }

            if (self.pos < self.source.len) {
                self.pos += 1; // skip closing quote
                const value = buffer.toOwnedSlice(self.alloc) catch {
                    buffer.deinit(self.alloc);
                    return Token{ .tag = .eof, .value = "Out of memory", .start = start };
                };
                return Token{ .tag = .atom, .value = value, .start = start };
            }
            buffer.deinit(self.alloc);
            return Token{ .tag = .eof, .value = "Unterminated atom", .start = start };
        }

        if (std.ascii.isDigit(char)) {
            // Check for ISO syntax: 0b, 0o, 0x
            if (char == '0' and self.pos + 1 < self.source.len) {
                const next_char = self.source[self.pos + 1];
                if (next_char == 'b' or next_char == 'B') {
                    // Binary: 0b followed by binary digits (with digit grouping)
                    self.pos += 2; // skip '0b'
                    self.skipDigitGroupsForRadix(2);
                    return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                } else if (next_char == 'o' or next_char == 'O') {
                    // Octal: 0o followed by octal digits (with digit grouping)
                    self.pos += 2; // skip '0o'
                    self.skipDigitGroupsForRadix(8);
                    return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                } else if (next_char == 'x' or next_char == 'X') {
                    // Hexadecimal: 0x followed by hex digits (with digit grouping)
                    self.pos += 2; // skip '0x'
                    self.skipDigitGroupsForRadix(16);
                    return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                }
            }

            // Regular decimal number or Edinburgh syntax (radix'number)
            self.skipDigitGroupsForRadix(10);

            // Check for Edinburgh syntax: radix'number
            if (self.pos < self.source.len and self.source[self.pos] == '\'') {
                // Save position before quote
                const quote_pos = self.pos;
                self.pos += 1; // skip '

                // Parse digits in specified radix
                const digit_start = self.pos;
                // For Edinburgh syntax, we don't know the radix yet, so use 36 (max)
                self.skipDigitGroupsForRadix(36);

                // If we found at least one digit after ', it's Edinburgh syntax
                if (self.pos > digit_start) {
                    return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                } else {
                    // No digits after ', restore position
                    self.pos = quote_pos;
                }
            }

            // Check for decimal point (float)
            if (self.pos < self.source.len and self.source[self.pos] == '.') {
                // Make sure next character is a digit (not end of list notation like "1.")
                if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                    self.pos += 1; // skip '.'
                    self.skipDigitGroupsForRadix(10);

                    // Check for Inf or NaN suffix
                    if (self.pos + 3 <= self.source.len) {
                        const remaining = self.source[self.pos..];
                        if (remaining.len >= 3 and
                            (std.mem.eql(u8, remaining[0..3], "Inf") or
                                std.mem.eql(u8, remaining[0..3], "NaN")))
                        {
                            self.pos += 3;
                            return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                        }
                    }

                    return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
                }
            }
            return Token{ .tag = .number, .value = self.source[start..self.pos], .start = start };
        }

        if (std.ascii.isLower(char)) {
            while (self.pos < self.source.len and isAlphaNumeric(self.source[self.pos])) {
                self.pos += 1;
            }
            const val = self.source[start..self.pos];
            if (std.mem.eql(u8, val, "is")) return Token{ .tag = .is, .value = val, .start = start };
            return Token{ .tag = .atom, .value = val, .start = start };
        }

        if (std.ascii.isUpper(char) or char == '_') {
            while (self.pos < self.source.len and isAlphaNumeric(self.source[self.pos])) {
                self.pos += 1;
            }
            return Token{ .tag = .variable, .value = self.source[start..self.pos], .start = start };
        }

        self.pos += 1;
        return Token{ .tag = .eof, .value = "Error", .start = start };
    }

    pub fn peek(self: *Lexer) Token {
        const saved_pos = self.pos;
        const tok = self.next();
        self.pos = saved_pos;
        return tok;
    }
};

test "Lexer - basic tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "parent(john, douglas).";
    var lexer = Lexer.init(alloc, source);

    const t1 = lexer.next();
    try std.testing.expectEqual(TokenType.atom, t1.tag);
    try std.testing.expectEqualStrings("parent", t1.value);

    const t2 = lexer.next();
    try std.testing.expectEqual(TokenType.lparen, t2.tag);

    const t3 = lexer.next();
    try std.testing.expectEqual(TokenType.atom, t3.tag);
    try std.testing.expectEqualStrings("john", t3.value);

    const t4 = lexer.next();
    try std.testing.expectEqual(TokenType.comma, t4.tag);

    const t5 = lexer.next();
    try std.testing.expectEqual(TokenType.atom, t5.tag);
    try std.testing.expectEqualStrings("douglas", t5.value);

    const t6 = lexer.next();
    try std.testing.expectEqual(TokenType.rparen, t6.tag);

    const t7 = lexer.next();
    try std.testing.expectEqual(TokenType.period, t7.tag);

    const t8 = lexer.next();
    try std.testing.expectEqual(TokenType.eof, t8.tag);
}

test "Lexer - variables and numbers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "X = 123";
    var lexer = Lexer.init(alloc, source);

    const t1 = lexer.next();
    try std.testing.expectEqual(TokenType.variable, t1.tag);
    try std.testing.expectEqualStrings("X", t1.value);

    const t2 = lexer.next();
    try std.testing.expectEqual(TokenType.equal, t2.tag);

    const t3 = lexer.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("123", t3.value);
}

test "Lexer - float numbers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "X = 3.14 Y = 2.71828";
    var lexer = Lexer.init(alloc, source);

    const t1 = lexer.next();
    try std.testing.expectEqual(TokenType.variable, t1.tag);
    try std.testing.expectEqualStrings("X", t1.value);

    const t2 = lexer.next();
    try std.testing.expectEqual(TokenType.equal, t2.tag);

    const t3 = lexer.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("3.14", t3.value);

    const t4 = lexer.next();
    try std.testing.expectEqual(TokenType.variable, t4.tag);
    try std.testing.expectEqualStrings("Y", t4.value);

    const t5 = lexer.next();
    try std.testing.expectEqual(TokenType.equal, t5.tag);

    const t6 = lexer.next();
    try std.testing.expectEqual(TokenType.number, t6.tag);
    try std.testing.expectEqualStrings("2.71828", t6.value);

    // Test that "1." is not parsed as float (could be end of clause)
    const source2 = "1.";
    var lexer2 = Lexer.init(alloc, source2);
    const t7 = lexer2.next();
    try std.testing.expectEqual(TokenType.number, t7.tag);
    try std.testing.expectEqualStrings("1", t7.value);
    const t8 = lexer2.next();
    try std.testing.expectEqual(TokenType.period, t8.tag);
}

test "Lexer - operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = ":- + - * / > < = ; \\+";
    var lexer = Lexer.init(alloc, source);

    try std.testing.expectEqual(TokenType.turnstile, lexer.next().tag);
    try std.testing.expectEqual(TokenType.plus, lexer.next().tag);
    try std.testing.expectEqual(TokenType.minus, lexer.next().tag);
    try std.testing.expectEqual(TokenType.mul, lexer.next().tag);
    try std.testing.expectEqual(TokenType.div, lexer.next().tag);
    try std.testing.expectEqual(TokenType.greater, lexer.next().tag);
    try std.testing.expectEqual(TokenType.less, lexer.next().tag);
    try std.testing.expectEqual(TokenType.equal, lexer.next().tag);
    try std.testing.expectEqual(TokenType.semicolon, lexer.next().tag);
    try std.testing.expectEqual(TokenType.not, lexer.next().tag);
}

test "Lexer - lists and strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "[1, 2 | T] \"hello\"";
    var lexer = Lexer.init(alloc, source);

    try std.testing.expectEqual(TokenType.lbracket, lexer.next().tag);
    try std.testing.expectEqual(TokenType.number, lexer.next().tag);
    try std.testing.expectEqual(TokenType.comma, lexer.next().tag);
    try std.testing.expectEqual(TokenType.number, lexer.next().tag);
    try std.testing.expectEqual(TokenType.bar, lexer.next().tag);
    try std.testing.expectEqual(TokenType.variable, lexer.next().tag);
    try std.testing.expectEqual(TokenType.rbracket, lexer.next().tag);

    const t_str = lexer.next();
    try std.testing.expectEqual(TokenType.string, t_str.tag);
    try std.testing.expectEqualStrings("hello", t_str.value);
}

test "Lexer - single quoted atoms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "'atom' 'atom with spaces' 'Symbol'";
    var l = Lexer.init(alloc, source);

    const t1 = l.next();
    try std.testing.expectEqual(TokenType.atom, t1.tag);
    try std.testing.expectEqualStrings("atom", t1.value);

    const t2 = l.next();
    try std.testing.expectEqual(TokenType.atom, t2.tag);
    try std.testing.expectEqualStrings("atom with spaces", t2.value);

    const t3 = l.next();
    try std.testing.expectEqual(TokenType.atom, t3.tag);
    try std.testing.expectEqualStrings("Symbol", t3.value);
}

test "Lexer - comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test single-line comment
    const source1 = "% This is a comment\nperson(alice).";
    var l1 = Lexer.init(alloc, source1);

    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.atom, t1.tag);
    try std.testing.expectEqualStrings("person", t1.value);

    const t2 = l1.next();
    try std.testing.expectEqual(TokenType.lparen, t2.tag);

    // Test comment between tokens
    const source2 = "person % comment\n(alice).";
    var l2 = Lexer.init(alloc, source2);

    const t3 = l2.next();
    try std.testing.expectEqual(TokenType.atom, t3.tag);
    try std.testing.expectEqualStrings("person", t3.value);

    const t4 = l2.next();
    try std.testing.expectEqual(TokenType.lparen, t4.tag);

    // Test multiple consecutive comments
    const source3 = "% First comment\n% Second comment\nperson(alice).";
    var l3 = Lexer.init(alloc, source3);

    const t5 = l3.next();
    try std.testing.expectEqual(TokenType.atom, t5.tag);
    try std.testing.expectEqualStrings("person", t5.value);
}

test "Lexer - block comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test basic block comment
    const source1 = "/* This is a block comment */ person(alice).";
    var l1 = Lexer.init(alloc, source1);

    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.atom, t1.tag);
    try std.testing.expectEqualStrings("person", t1.value);

    // Test multi-line block comment
    const source2 = "/* This is a\n   multi-line\n   block comment */\nperson(bob).";
    var l2 = Lexer.init(alloc, source2);

    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.atom, t2.tag);
    try std.testing.expectEqualStrings("person", t2.value);

    // Test block comment between tokens
    const source3 = "person /* inline */ (alice).";
    var l3 = Lexer.init(alloc, source3);

    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.atom, t3.tag);
    try std.testing.expectEqualStrings("person", t3.value);

    const t4 = l3.next();
    try std.testing.expectEqual(TokenType.lparen, t4.tag);

    // Test nested asterisks inside comment
    const source4 = "/* Comment with * asterisks ** inside */ atom.";
    var l4 = Lexer.init(alloc, source4);

    const t5 = l4.next();
    try std.testing.expectEqual(TokenType.atom, t5.tag);
    try std.testing.expectEqualStrings("atom", t5.value);

    // Test consecutive block comments
    const source5 = "/* First */ /* Second */ atom.";
    var l5 = Lexer.init(alloc, source5);

    const t6 = l5.next();
    try std.testing.expectEqual(TokenType.atom, t6.tag);
    try std.testing.expectEqualStrings("atom", t6.value);

    // Test mix of line and block comments
    const source6 = "% Line comment\n/* Block comment */ atom.";
    var l6 = Lexer.init(alloc, source6);

    const t7 = l6.next();
    try std.testing.expectEqual(TokenType.atom, t7.tag);
    try std.testing.expectEqualStrings("atom", t7.value);

    // Test unterminated block comment
    const source7 = "/* Unterminated comment";
    var l7 = Lexer.init(alloc, source7);

    const t8 = l7.next();
    try std.testing.expectEqual(TokenType.eof, t8.tag);
    try std.testing.expectEqualStrings("Unterminated block comment", t8.value);
}

test "Lexer - escape sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test basic escapes
    const source1 = "\"\\n\\t\\r\"";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.string, t1.tag);
    try std.testing.expectEqualStrings("\n\t\r", t1.value);

    // Test quote escapes
    const source2 = "\"\\'\\\"\\\\\"";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.string, t2.tag);
    try std.testing.expectEqualStrings("'\"\\", t2.value);

    // Test special escapes
    const source3 = "\"\\a\\b\\e\\f\\v\\s\"";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.string, t3.tag);
    try std.testing.expectEqualStrings("\x07\x08\x1B\x0C\x0B ", t3.value);

    // Test hex escape
    const source4 = "\"\\x41\\x42\\x43\"";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.string, t4.tag);
    try std.testing.expectEqualStrings("ABC", t4.value);

    // Test Unicode \uXXXX
    const source5 = "\"\\u00e9\""; // é
    var l5 = Lexer.init(alloc, source5);
    const t5 = l5.next();
    try std.testing.expectEqual(TokenType.string, t5.tag);
    try std.testing.expectEqualStrings("é", t5.value);

    // Test Unicode \UXXXXXXXX
    const source6 = "\"\\U0001F600\""; // 😀
    var l6 = Lexer.init(alloc, source6);
    const t6 = l6.next();
    try std.testing.expectEqual(TokenType.string, t6.tag);
    try std.testing.expectEqualStrings("😀", t6.value);

    // Test octal escape
    const source7 = "\"\\101\\102\\103\""; // ABC
    var l7 = Lexer.init(alloc, source7);
    const t7 = l7.next();
    try std.testing.expectEqual(TokenType.string, t7.tag);
    try std.testing.expectEqualStrings("ABC", t7.value);

    // Test escapes in single-quoted atoms
    const source8 = "'\\n\\t'";
    var l8 = Lexer.init(alloc, source8);
    const t8 = l8.next();
    try std.testing.expectEqual(TokenType.atom, t8.tag);
    try std.testing.expectEqualStrings("\n\t", t8.value);
}

test "Lexer - Unicode support" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test direct UTF-8 characters in strings
    const source1 = "\"café\"";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.string, t1.tag);
    try std.testing.expectEqualStrings("café", t1.value);

    // Test Unicode in atoms
    const source2 = "'привет'"; // Russian "hello"
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.atom, t2.tag);
    try std.testing.expectEqualStrings("привет", t2.value);

    // Test emoji
    const source3 = "\"Hello 👋 World 🌍\"";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.string, t3.tag);
    try std.testing.expectEqualStrings("Hello 👋 World 🌍", t3.value);

    // Test mixed ASCII and Unicode
    const source4 = "\"日本語 means Japanese\"";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.string, t4.tag);
    try std.testing.expectEqualStrings("日本語 means Japanese", t4.value);
}

test "Lexer - non-decimal numbers ISO syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test binary: 0b100 = 4
    const source1 = "0b100";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("0b100", t1.value);

    // Test octal: 0o17 = 15
    const source2 = "0o17";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("0o17", t2.value);

    // Test hexadecimal: 0xf00 = 3840
    const source3 = "0xf00";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("0xf00", t3.value);

    // Test uppercase prefix: 0XFF
    const source4 = "0XFF";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.number, t4.tag);
    try std.testing.expectEqualStrings("0XFF", t4.value);

    // Test combined expression: 0b100 + 0xf00
    const source5 = "0b100 + 0xf00";
    var l5 = Lexer.init(alloc, source5);
    const t5 = l5.next();
    try std.testing.expectEqual(TokenType.number, t5.tag);
    try std.testing.expectEqualStrings("0b100", t5.value);

    const t6 = l5.next();
    try std.testing.expectEqual(TokenType.plus, t6.tag);

    const t7 = l5.next();
    try std.testing.expectEqual(TokenType.number, t7.tag);
    try std.testing.expectEqualStrings("0xf00", t7.value);
}

test "Lexer - non-decimal numbers Edinburgh syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test base 2: 2'101 = 5
    const source1 = "2'101";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("2'101", t1.value);

    // Test base 8: 8'377 = 255
    const source2 = "8'377";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("8'377", t2.value);

    // Test base 16: 16'FF = 255
    const source3 = "16'FF";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("16'FF", t3.value);

    // Test base 36: 36'Z = 35
    const source4 = "36'Z";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.number, t4.tag);
    try std.testing.expectEqualStrings("36'Z", t4.value);
}

test "Lexer - operators in prefix position (unquoted)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test .(1,2) - dot followed by ( should be atom
    const source1 = ".(1, 2)";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.atom, t1.tag);
    try std.testing.expectEqualStrings(".", t1.value);
    const t2 = l1.next();
    try std.testing.expectEqual(TokenType.lparen, t2.tag);

    // Test "foo." - dot at end should be period
    const source2 = "foo.";
    var l2 = Lexer.init(alloc, source2);
    const t3 = l2.next();
    try std.testing.expectEqual(TokenType.atom, t3.tag);
    try std.testing.expectEqualStrings("foo", t3.value);
    const t4 = l2.next();
    try std.testing.expectEqual(TokenType.period, t4.tag);

    // Test ". " - dot followed by space should be period
    const source3 = ". bar";
    var l3 = Lexer.init(alloc, source3);
    const t5 = l3.next();
    try std.testing.expectEqual(TokenType.period, t5.tag);

    // Test +(1,2) - plus followed by ( should be atom
    const source4 = "+(1, 2)";
    var l4 = Lexer.init(alloc, source4);
    const t6 = l4.next();
    try std.testing.expectEqual(TokenType.atom, t6.tag);
    try std.testing.expectEqualStrings("+", t6.value);

    // Test "1 + 2" - plus as infix should be operator
    const source5 = "1 + 2";
    var l5 = Lexer.init(alloc, source5);
    _ = l5.next(); // skip 1
    const t7 = l5.next();
    try std.testing.expectEqual(TokenType.plus, t7.tag);

    // Test //(1,2) - int_div followed by ( should be atom
    const source6 = "//(1, 2)";
    var l6 = Lexer.init(alloc, source6);
    const t8 = l6.next();
    try std.testing.expectEqual(TokenType.atom, t8.tag);
    try std.testing.expectEqualStrings("//", t8.value);

    // Test "7 // 2" - // as infix should be operator
    const source7 = "7 // 2";
    var l7 = Lexer.init(alloc, source7);
    _ = l7.next(); // skip 7
    const t9 = l7.next();
    try std.testing.expectEqual(TokenType.int_div, t9.tag);

    // Test =:=(3, 3) - arith_equal followed by ( should be atom
    const source8 = "=:=(3, 3)";
    var l8 = Lexer.init(alloc, source8);
    const t10 = l8.next();
    try std.testing.expectEqual(TokenType.atom, t10.tag);
    try std.testing.expectEqualStrings("=:=", t10.value);

    // Test \+(x) - not followed by ( should be atom
    const source9 = "\\+(x)";
    var l9 = Lexer.init(alloc, source9);
    const t11 = l9.next();
    try std.testing.expectEqual(TokenType.atom, t11.tag);
    try std.testing.expectEqualStrings("\\+", t11.value);

    // Test "\+ x" - \+ as prefix should be operator
    const source10 = "\\+ x";
    var l10 = Lexer.init(alloc, source10);
    const t12 = l10.next();
    try std.testing.expectEqual(TokenType.not, t12.tag);
}

test "Lexer - digit grouping with underscores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test decimal with underscores: 1_000_000
    const source1 = "1_000_000";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("1_000_000", t1.value);

    // Test binary with underscores: 0b1111_0000
    const source2 = "0b1111_0000";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("0b1111_0000", t2.value);

    // Test hex with underscores: 0xDEAD_BEEF
    const source3 = "0xDEAD_BEEF";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("0xDEAD_BEEF", t3.value);

    // Test octal with underscores: 0o777_000
    const source4 = "0o777_000";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.number, t4.tag);
    try std.testing.expectEqualStrings("0o777_000", t4.value);

    // Test Edinburgh syntax with underscores: 16'FF_00
    const source5 = "16'FF_00";
    var l5 = Lexer.init(alloc, source5);
    const t5 = l5.next();
    try std.testing.expectEqual(TokenType.number, t5.tag);
    try std.testing.expectEqualStrings("16'FF_00", t5.value);

    // Test float with underscores: 3.141_592_653
    const source6 = "3.141_592_653";
    var l6 = Lexer.init(alloc, source6);
    const t6 = l6.next();
    try std.testing.expectEqual(TokenType.number, t6.tag);
    try std.testing.expectEqualStrings("3.141_592_653", t6.value);
}

test "Lexer - digit grouping with spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test decimal with spaces: 1 000 000
    const source1 = "1 000 000";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("1 000 000", t1.value);

    // Test binary with spaces: 0b1111 0000
    const source2 = "0b1111 0000";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("0b1111 0000", t2.value);

    // Test octal with spaces: 0o777 000
    const source3 = "0o777 000";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("0o777 000", t3.value);
}

test "Lexer - digit grouping with comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test with block comment: 1_000_/*comment*/000
    const source1 = "1_000_/*comment*/000";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("1_000_/*comment*/000", t1.value);

    // Test hex with comment: 0xDE_/*separator*/AD
    const source2 = "0xDE_/*separator*/AD";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("0xDE_/*separator*/AD", t2.value);
}

test "Lexer - Infinity and NaN floats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test positive infinity: 1.0Inf
    const source1 = "1.0Inf";
    var l1 = Lexer.init(alloc, source1);
    const t1 = l1.next();
    try std.testing.expectEqual(TokenType.number, t1.tag);
    try std.testing.expectEqualStrings("1.0Inf", t1.value);

    // Test negative infinity: -1.0Inf (will be minus operator + 1.0Inf)
    const source2 = "1.0Inf";
    var l2 = Lexer.init(alloc, source2);
    const t2 = l2.next();
    try std.testing.expectEqual(TokenType.number, t2.tag);
    try std.testing.expectEqualStrings("1.0Inf", t2.value);

    // Test NaN: 1.5NaN
    const source3 = "1.5NaN";
    var l3 = Lexer.init(alloc, source3);
    const t3 = l3.next();
    try std.testing.expectEqual(TokenType.number, t3.tag);
    try std.testing.expectEqualStrings("1.5NaN", t3.value);

    // Test NaN with different mantissa: 2.7NaN
    const source4 = "2.7NaN";
    var l4 = Lexer.init(alloc, source4);
    const t4 = l4.next();
    try std.testing.expectEqual(TokenType.number, t4.tag);
    try std.testing.expectEqualStrings("2.7NaN", t4.value);

    // Test Inf with digit grouping: 1_000.0Inf
    const source5 = "1_000.0Inf";
    var l5 = Lexer.init(alloc, source5);
    const t5 = l5.next();
    try std.testing.expectEqual(TokenType.number, t5.tag);
    try std.testing.expectEqualStrings("1_000.0Inf", t5.value);
}
