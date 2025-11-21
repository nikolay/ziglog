const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig").Lexer;
const TokenType = @import("lexer.zig").TokenType;
const ast = @import("ast.zig");
const Term = ast.Term;
const Rule = ast.Rule;

pub const Parser = struct {
    lexer: Lexer,
    alloc: Allocator,

    // NOTE: Explicit Error Set to resolve recursive inference cycle
    pub const ParseError = Allocator.Error || std.fmt.ParseIntError || error{
        UnexpectedToken,
        InvalidTermStart,
        ExpectedPeriodOrTurnstile,
    };

    pub fn init(alloc: Allocator, source: []const u8) Parser {
        return Parser{
            .lexer = Lexer.init(alloc, source),
            .alloc = alloc,
        };
    }

    fn expect(self: *Parser, tag: TokenType) ParseError!void {
        const tok = self.lexer.next();
        if (tok.tag != tag) return error.UnexpectedToken;
    }

    const Precedence = enum(u8) {
        Lowest,
        LogicOr,
        IfThen,
        Comparison,
        Sum,
        Product,
        Prefix,
        Call,
        fn int(self: Precedence) u8 {
            return @intFromEnum(self);
        }
    };

    fn getPrecedence(tag: TokenType) Precedence {
        return switch (tag) {
            .semicolon => .LogicOr,
            .if_then => .IfThen,
            .equal, .greater, .less, .greater_equal, .less_equal, .not_equal, .arith_equal, .arith_not_equal, .is => .Comparison,
            .plus, .minus => .Sum,
            .mul, .div, .int_div => .Product,
            .lparen => .Call,
            else => .Lowest,
        };
    }

    /// Removes digit grouping separators from numeric literals.
    /// Handles underscores, spaces (radix ≤ 10), and block comments.
    /// Returns original string if no separators found (zero-copy optimization).
    ///
    /// Examples:
    ///   "1_000" -> "1000"
    ///   "0xDE_AD" -> "0xDEAD"
    ///   "1_/*comment*/234" -> "1234"
    ///   "42" -> "42" (no allocation)
    fn stripDigitSeparators(self: *Parser, value: []const u8) ![]const u8 {
        // Fast path: check if stripping is needed
        const needs_stripping = blk: {
            for (value) |c| {
                if (c == '_' or c == ' ' or c == '/') break :blk true;
            }
            break :blk false;
        };

        if (!needs_stripping) return value; // Zero-copy for clean numbers

        // Pre-allocate buffer to exact size to avoid reallocations
        var buf = try std.ArrayListUnmanaged(u8).initCapacity(self.alloc, value.len);
        defer buf.deinit(self.alloc);

        var i: usize = 0;
        while (i < value.len) {
            const c = value[i];
            switch (c) {
                '_', ' ' => i += 1, // Skip separator
                '/' => {
                    if (i + 1 < value.len and value[i + 1] == '*') {
                        // Skip block comment
                        i += 2;
                        while (i + 1 < value.len) : (i += 1) {
                            if (value[i] == '*' and value[i + 1] == '/') {
                                i += 2;
                                break;
                            }
                        }
                    } else {
                        buf.appendAssumeCapacity(c);
                        i += 1;
                    }
                },
                else => {
                    buf.appendAssumeCapacity(c);
                    i += 1;
                },
            }
        }
        return buf.toOwnedSlice(self.alloc);
    }

    /// Parses integer literals with support for multiple notations.
    /// Handles ISO syntax (0b, 0o, 0x), Edinburgh syntax (radix'number), and decimal.
    /// Automatically strips digit grouping separators before parsing.
    ///
    /// Supported formats:
    ///   - Decimal: 42, 1_000_000
    ///   - Binary (ISO): 0b1010, 0B1111_0000
    ///   - Octal (ISO): 0o755, 0O777_000
    ///   - Hexadecimal (ISO): 0xFF, 0xDEAD_BEEF
    ///   - Edinburgh: 2'1010, 16'FF, 36'Z
    fn parseIntegerLiteral(self: *Parser, value: []const u8) ParseError!i64 {
        // Strip digit separators (underscores, spaces, comments)
        const clean_value = try self.stripDigitSeparators(value);

        // ISO syntax: 0b, 0o, 0x
        if (clean_value.len >= 2 and clean_value[0] == '0') {
            const prefix = clean_value[1];
            if (prefix == 'b' or prefix == 'B') {
                // Binary
                return try std.fmt.parseInt(i64, clean_value[2..], 2);
            } else if (prefix == 'o' or prefix == 'O') {
                // Octal
                return try std.fmt.parseInt(i64, clean_value[2..], 8);
            } else if (prefix == 'x' or prefix == 'X') {
                // Hexadecimal
                return try std.fmt.parseInt(i64, clean_value[2..], 16);
            }
        }

        // Edinburgh syntax: radix'number
        if (std.mem.indexOfScalar(u8, clean_value, '\'')) |quote_pos| {
            const radix_str = clean_value[0..quote_pos];
            const number_str = clean_value[quote_pos + 1 ..];

            // Parse radix (must be 2-36)
            const radix = try std.fmt.parseInt(u8, radix_str, 10);
            if (radix < 2 or radix > 36) {
                return error.UnexpectedToken;
            }

            // Parse number in specified radix
            return try std.fmt.parseInt(i64, number_str, radix);
        }

        // Regular decimal
        return try std.fmt.parseInt(i64, clean_value, 10);
    }

    fn isInfixAtom(value: []const u8) bool {
        return std.mem.eql(u8, value, "div") or
               std.mem.eql(u8, value, "mod") or
               std.mem.eql(u8, value, "rem") or
               std.mem.eql(u8, value, "min") or
               std.mem.eql(u8, value, "max");
    }

    pub fn parseTerm(self: *Parser) ParseError!*Term {
        return self.parseExpression(.Lowest);
    }

    fn parseExpression(self: *Parser, precedence: Precedence) ParseError!*Term {
        var left = try self.parsePrefix();

        while (true) {
            const tok = self.lexer.peek();

            // Check if next token is an infix operator (including special atoms)
            const is_infix_op = switch (tok.tag) {
                .plus, .minus, .mul, .div, .int_div, .greater, .less, .greater_equal, .less_equal, .not_equal, .equal, .arith_equal, .arith_not_equal, .is, .semicolon, .if_then => true,
                .atom => isInfixAtom(tok.value),
                else => false,
            };

            if (!is_infix_op) break;

            const op_prec = if (tok.tag == .atom and isInfixAtom(tok.value))
                Precedence.Product
            else
                getPrecedence(tok.tag);

            if (precedence.int() >= op_prec.int()) break;

            _ = self.lexer.next();
            const right = try self.parseExpression(op_prec);
            var args = std.ArrayListUnmanaged(*Term){};
            try args.append(self.alloc, left);
            try args.append(self.alloc, right);
            left = try Term.createStructure(self.alloc, tok.value, try args.toOwnedSlice(self.alloc));
        }
        return left;
    }

    /// Parses floating-point literals including special values (Infinity, NaN).
    /// Handles digit grouping separators in mantissa.
    ///
    /// Supported formats:
    ///   - Regular: 3.14, 2.71828, 1_234.567_89
    ///   - Infinity: 1.0Inf, -1.0Inf, 999.0Inf
    ///   - NaN: 1.5NaN, 2.7NaN (all display as 1.5NaN)
    ///
    /// Note: For Infinity, the sign is determined from the mantissa value.
    fn parseFloat(self: *Parser, value: []const u8) ParseError!f64 {
        // Check for Inf or NaN suffix
        if (std.mem.endsWith(u8, value, "Inf")) {
            // Extract and validate mantissa
            const mantissa_value = value[0 .. value.len - 3];
            const clean_value = try self.stripDigitSeparators(mantissa_value);

            if (clean_value.len == 0) return error.UnexpectedToken;

            // Determine sign from first character (simpler than parsing)
            const is_negative = clean_value[0] == '-';
            return if (is_negative) -std.math.inf(f64) else std.math.inf(f64);
        } else if (std.mem.endsWith(u8, value, "NaN")) {
            // Validate mantissa exists (sign doesn't matter for NaN)
            const mantissa_value = value[0 .. value.len - 3];
            const clean_value = try self.stripDigitSeparators(mantissa_value);

            if (clean_value.len == 0) return error.UnexpectedToken;

            return std.math.nan(f64);
        } else {
            // Regular float
            const clean_value = try self.stripDigitSeparators(value);
            return try std.fmt.parseFloat(f64, clean_value);
        }
    }

    fn parsePrefix(self: *Parser) ParseError!*Term {
        const tok = self.lexer.next();
        switch (tok.tag) {
            .number => {
                // Check if it's a float (contains '.')
                if (std.mem.indexOfScalar(u8, tok.value, '.')) |_| {
                    const f = try self.parseFloat(tok.value);
                    return try Term.createFloat(self.alloc, f);
                } else {
                    // Parse non-decimal numbers
                    const n = try self.parseIntegerLiteral(tok.value);
                    return try Term.createNumber(self.alloc, n);
                }
            },
            .variable => return try Term.createVariable(self.alloc, tok.value),
            .atom => return try self.parseAtomOrStructure(tok.value),
            .string => return try Term.createString(self.alloc, tok.value),
            .lbracket => return try self.parseList(),
            .lbrace => {
                // Brace block { ... }
                // Treat as structure with functor "{}" and one argument (the content)
                // Standard Prolog: {Goal} is a term with functor {} and arg Goal.
                // But inside it can be a conjunction.
                const content = try self.parseTerm();
                try self.expect(.rbrace);
                return Term.createStructure(self.alloc, "{}", &[_]*Term{content});
            },
            .lparen => {
                const t = try self.parseTerm();
                try self.expect(.rparen);
                return t;
            },
            .not => {
                const right = try self.parseExpression(.Prefix);
                var args = std.ArrayListUnmanaged(*Term){};
                try args.append(self.alloc, right);
                return try Term.createStructure(self.alloc, "\\+", try args.toOwnedSlice(self.alloc));
            },
            else => return error.InvalidTermStart,
        }
    }

    fn parseList(self: *Parser) ParseError!*Term {
        if (self.lexer.peek().tag == .rbracket) {
            _ = self.lexer.next();
            return try Term.createAtom(self.alloc, "[]");
        }

        const head = try self.parseTerm();
        var tail: *Term = undefined;

        if (self.lexer.peek().tag == .comma) {
            _ = self.lexer.next();
            tail = try self.parseList();
        } else if (self.lexer.peek().tag == .bar) {
            _ = self.lexer.next();
            tail = try self.parseTerm();
            try self.expect(.rbracket);
        } else {
            try self.expect(.rbracket);
            tail = try Term.createAtom(self.alloc, "[]");
        }

        var args = std.ArrayListUnmanaged(*Term){};
        try args.append(self.alloc, head);
        try args.append(self.alloc, tail);
        return try Term.createStructure(self.alloc, ".", try args.toOwnedSlice(self.alloc));
    }

    fn parseAtomOrStructure(self: *Parser, name: []const u8) ParseError!*Term {
        if (self.lexer.peek().tag == .lparen) {
            _ = self.lexer.next();
            var args = std.ArrayListUnmanaged(*Term){};
            try args.append(self.alloc, try self.parseTerm());
            while (self.lexer.peek().tag == .comma) {
                _ = self.lexer.next();
                try args.append(self.alloc, try self.parseTerm());
            }
            try self.expect(.rparen);
            return try Term.createStructure(self.alloc, name, try args.toOwnedSlice(self.alloc));
        }
        return try Term.createAtom(self.alloc, name);
    }

    pub fn parseRule(self: *Parser) ParseError!Rule {
        const head = try self.parseTerm();
        var body = std.ArrayListUnmanaged(*Term){};
        const next_tok = self.lexer.next();
        if (next_tok.tag == .period) {
            return Rule{ .head = head, .body = try body.toOwnedSlice(self.alloc) };
        } else if (next_tok.tag == .turnstile) {
            try body.append(self.alloc, try self.parseTerm());
            while (self.lexer.peek().tag == .comma) {
                _ = self.lexer.next();
                try body.append(self.alloc, try self.parseTerm());
            }
            try self.expect(.period);
            return Rule{ .head = head, .body = try body.toOwnedSlice(self.alloc) };
        } else if (next_tok.tag == .arrow) {
            // DCG Rule: Head --> Body.
            // We need to expand this into Head(S0, S) :- Body(S0, S).

            // 1. Parse the body as a single term (or sequence of terms)
            // In DCG, the body is usually a sequence of terminals and non-terminals separated by commas.
            // My parser parses comma-separated terms as a list for the rule body.
            // But for DCG expansion, it's easier to treat the body as a single term (conjunction) first, or expand term by term.
            // Let's parse the body terms first.

            var dcg_body_terms = std.ArrayListUnmanaged(*Term){};
            try dcg_body_terms.append(self.alloc, try self.parseTerm());
            while (self.lexer.peek().tag == .comma) {
                _ = self.lexer.next();
                try dcg_body_terms.append(self.alloc, try self.parseTerm());
            }
            try self.expect(.period);

            // 2. Generate fresh variables for the difference list
            // We need a counter for variables.
            // S0, S1, S2, ... S_N
            // Head(S0, S_N) :- Body...

            // We need a way to generate fresh variable names.
            // Let's use a simple counter and a prefix.
            var var_counter: usize = 0;

            // Helper to create S_i variable
            const createVar = struct {
                fn call(a: Allocator, idx: usize) !*Term {
                    const name = try std.fmt.allocPrint(a, "__S{d}", .{idx});
                    return Term.createVariable(a, name);
                }
            }.call;

            const S0 = try createVar(self.alloc, var_counter);
            var_counter += 1;
            var current_S = S0;

            // 3. Expand body terms
            var expanded_body = std.ArrayListUnmanaged(*Term){};

            for (dcg_body_terms.items) |term| {
                const next_S = try createVar(self.alloc, var_counter);
                var_counter += 1;

                // Expand term(current_S, next_S)
                try self.expandDCGTerm(term, current_S, next_S, &expanded_body);
                current_S = next_S;
            }

            // 4. Expand head: Head(S0, current_S)
            // Head must be a structure or atom.
            // If atom 'p', becomes 'p'(S0, current_S).
            // If structure 'p(X)', becomes 'p'(X, S0, current_S).

            var new_head: *Term = undefined;
            if (head.* == .atom) {
                new_head = try Term.createStructure(self.alloc, head.atom, &[_]*Term{ S0, current_S });
            } else if (head.* == .structure) {
                var new_args = try std.ArrayListUnmanaged(*Term).initCapacity(self.alloc, head.structure.args.len + 2);
                try new_args.appendSlice(self.alloc, head.structure.args);
                try new_args.append(self.alloc, S0);
                try new_args.append(self.alloc, current_S);
                new_head = try Term.createStructure(self.alloc, head.structure.functor, try new_args.toOwnedSlice(self.alloc));
            } else {
                return error.InvalidTermStart; // Head must be atom or structure
            }

            return Rule{ .head = new_head, .body = try expanded_body.toOwnedSlice(self.alloc) };
        } else {
            return error.ExpectedPeriodOrTurnstile;
        }
    }

    fn expandDCGTerm(self: *Parser, term: *Term, S_in: *Term, S_out: *Term, out_goals: *std.ArrayListUnmanaged(*Term)) !void {
        // 1. List literal: [T1, T2] -> S_in = [T1, T2 | S_out]
        // Actually, [T] -> S_in = [T | S_out].
        // [T1, T2] -> S_in = [T1 | S1], S1 = [T2 | S_out].
        // Or simpler: S_in = [T1, T2 | S_out] (append S_out to the end of the list).
        // My list representation is nested dots.
        // [a, b] is .(a, .(b, [])).
        // We want .(a, .(b, S_out)).

        if (term.* == .structure and std.mem.eql(u8, term.structure.functor, ".")) {
            // It's a list (or partial list).
            // We need to replace the empty list tail with S_out.
            // But wait, what if it's [a | X]? Then X must be unified with S_out? No.
            // [a] --> S_in = [a|S_out].
            // [a, b] --> S_in = [a, b|S_out].

            // We need to traverse the list and replace the final [] with S_out.
            const new_list = try self.appendTail(term, S_out);
            const unify_goal = try Term.createStructure(self.alloc, "=", &[_]*Term{ S_in, new_list });
            try out_goals.append(self.alloc, unify_goal);
            return;
        }

        if (term.* == .atom and std.mem.eql(u8, term.atom, "[]")) {
            // Empty list literal [] -> S_in = S_out
            const unify_goal = try Term.createStructure(self.alloc, "=", &[_]*Term{ S_in, S_out });
            try out_goals.append(self.alloc, unify_goal);
            return;
        }

        // 2. Brace block: {Goal} -> Goal, S_in = S_out
        if (term.* == .structure and std.mem.eql(u8, term.structure.functor, "{}") and term.structure.args.len == 1) {
            try out_goals.append(self.alloc, term.structure.args[0]);
            const unify_goal = try Term.createStructure(self.alloc, "=", &[_]*Term{ S_in, S_out });
            try out_goals.append(self.alloc, unify_goal);
            return;
        }

        // 3. Non-terminal: p(X) -> p(X, S_in, S_out)
        // Atom p -> p(S_in, S_out)
        if (term.* == .atom) {
            const goal = try Term.createStructure(self.alloc, term.atom, &[_]*Term{ S_in, S_out });
            try out_goals.append(self.alloc, goal);
        } else if (term.* == .structure) {
            var new_args = try std.ArrayListUnmanaged(*Term).initCapacity(self.alloc, term.structure.args.len + 2);
            try new_args.appendSlice(self.alloc, term.structure.args);
            try new_args.append(self.alloc, S_in);
            try new_args.append(self.alloc, S_out);
            const goal = try Term.createStructure(self.alloc, term.structure.functor, try new_args.toOwnedSlice(self.alloc));
            try out_goals.append(self.alloc, goal);
        } else {
            // Variable or other? Treat as non-terminal call?
            // call(Var, S_in, S_out).
            // For now, assume structure or atom.
            return error.InvalidTermStart;
        }
    }

    fn appendTail(self: *Parser, list: *Term, tail: *Term) !*Term {
        if (list.* == .structure and std.mem.eql(u8, list.structure.functor, ".") and list.structure.args.len == 2) {
            const head = list.structure.args[0];
            const rest = list.structure.args[1];
            const new_rest = try self.appendTail(rest, tail);
            return Term.createStructure(self.alloc, ".", &[_]*Term{ head, new_rest });
        }
        if (list.* == .atom and std.mem.eql(u8, list.atom, "[]")) {
            return tail;
        }
        // If it's a variable or something else, we can't easily append.
        // But [H|T] syntax in DCG usually implies T is a list literal or we fail?
        // Standard Prolog: [a | T] is not valid DCG terminal unless T is [].
        // Actually [a, b] is valid.
        // Let's assume well-formed lists for now.
        return list;
    }

    pub fn parseQuery(self: *Parser) ParseError![]*Term {
        var goals = std.ArrayListUnmanaged(*Term){};
        try goals.append(self.alloc, try self.parseTerm());
        while (self.lexer.peek().tag == .comma) {
            _ = self.lexer.next();
            try goals.append(self.alloc, try self.parseTerm());
        }
        if (self.lexer.peek().tag == .period) {
            _ = self.lexer.next();
        }
        return goals.toOwnedSlice(self.alloc);
    }
};

test "Parser - simple fact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "likes(john, pizza).";
    var parser = Parser.init(alloc, source);
    const rule = try parser.parseRule();

    try std.testing.expectEqualStrings("likes", rule.head.structure.functor);
    try std.testing.expectEqual(2, rule.head.structure.args.len);
    try std.testing.expectEqualStrings("john", rule.head.structure.args[0].atom);
    try std.testing.expectEqualStrings("pizza", rule.head.structure.args[1].atom);
    try std.testing.expectEqual(0, rule.body.len);
}

test "Parser - rule with body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "grandparent(X, Y) :- parent(X, Z), parent(Z, Y).";
    var parser = Parser.init(alloc, source);
    const rule = try parser.parseRule();

    try std.testing.expectEqualStrings("grandparent", rule.head.structure.functor);
    try std.testing.expectEqual(2, rule.body.len);
    try std.testing.expectEqualStrings("parent", rule.body[0].structure.functor);
    try std.testing.expectEqualStrings("parent", rule.body[1].structure.functor);
}

test "Parser - arithmetic precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "X is 1 + 2 * 3.";
    var parser = Parser.init(alloc, source);
    const rule = try parser.parseRule();

    // Head: is(X, +(1, *(2, 3)))
    const expr = rule.head.structure.args[1];
    try std.testing.expectEqualStrings("+", expr.structure.functor);
    try std.testing.expectEqual(1, expr.structure.args[0].number);

    const right = expr.structure.args[1];
    try std.testing.expectEqualStrings("*", right.structure.functor);
    try std.testing.expectEqual(2, right.structure.args[0].number);
    try std.testing.expectEqual(3, right.structure.args[1].number);
}

test "Parser - DCG expansion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // s --> np, vp.
    // s(S0, S2) :- np(S0, S1), vp(S1, S2).
    {
        const source = "s --> np, vp.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();

        try std.testing.expectEqualStrings("s", rule.head.structure.functor);
        try std.testing.expectEqual(2, rule.head.structure.args.len); // s(S0, S2)

        try std.testing.expectEqual(2, rule.body.len);
        try std.testing.expectEqualStrings("np", rule.body[0].structure.functor);
        try std.testing.expectEqual(2, rule.body[0].structure.args.len); // np(S0, S1)

        try std.testing.expectEqualStrings("vp", rule.body[1].structure.functor);
        try std.testing.expectEqual(2, rule.body[1].structure.args.len); // vp(S1, S2)
    }

    // [det] --> [the].
    // .(det, [])(S0, S1) :- S0 = .(the, S1).
    // Wait, [det] is a list literal in the head?
    // No, DCG head must be non-terminal.
    // det --> [the].
    // det(S0, S1) :- S0 = [the|S1].
    {
        const source = "det --> [the].";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();

        try std.testing.expectEqualStrings("det", rule.head.structure.functor);
        try std.testing.expectEqual(2, rule.head.structure.args.len);

        try std.testing.expectEqual(1, rule.body.len);
        try std.testing.expectEqualStrings("=", rule.body[0].structure.functor);
        // S0 = [the|S1]
    }

    // Brace block: a --> {print(hello)}, [world].
    // a(S0, S2) :- print(hello), S0=S1, S1=[world|S2].
    // Optimized: a(S0, S2) :- print(hello), S0=S1, S1=[world|S2].
    // My impl: {G} -> G, S_in = S_out.
    {
        const source = "a --> {print(hello)}, [world].";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();

        // Body: print(hello), S0=S1, S1=[world|S2]
        try std.testing.expectEqual(3, rule.body.len);
        try std.testing.expectEqualStrings("print", rule.body[0].structure.functor);
        try std.testing.expectEqualStrings("=", rule.body[1].structure.functor); // S0=S1
        try std.testing.expectEqualStrings("=", rule.body[2].structure.functor); // S1=[world|S2]
    }
}

test "Parser - new comparisons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // >=
    {
        var p = Parser.init(alloc, "X >= 10.");
        const t = try p.parseTerm();
        try std.testing.expectEqual(ast.TermType.structure, std.meta.activeTag(t.*));
        try std.testing.expectEqualStrings(">=", t.structure.functor);
        try std.testing.expectEqualStrings("X", t.structure.args[0].variable);
        try std.testing.expectEqual(@as(i64, 10), t.structure.args[1].number);
    }

    // =<
    {
        var p = Parser.init(alloc, "X =< 10.");
        const t = try p.parseTerm();
        try std.testing.expectEqual(ast.TermType.structure, std.meta.activeTag(t.*));
        try std.testing.expectEqualStrings("=<", t.structure.functor);
    }

    // \=
    {
        var p = Parser.init(alloc, "X \\= Y.");
        const t = try p.parseTerm();
        try std.testing.expectEqual(ast.TermType.structure, std.meta.activeTag(t.*));
        try std.testing.expectEqualStrings("\\=", t.structure.functor);
    }
}

test "Parser - lists and strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "p([1, 2], \"hello\").";
    var parser = Parser.init(alloc, source);
    const rule = try parser.parseRule();

    // p(.(1, .(2, [])), "hello")
    const args = rule.head.structure.args;
    const list = args[0];
    const str = args[1];

    try std.testing.expectEqualStrings(".", list.structure.functor); // List is dot structure
    try std.testing.expectEqualStrings("hello", str.string);
}

test "Parser - complex terms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // p :- a, !; \+ b.
    // p :- ;((,(a, !)), \+(b))
    const source = "p :- a, !; \\+ b.";
    var parser = Parser.init(alloc, source);
    const rule = try parser.parseRule();

    try std.testing.expectEqual(2, rule.body.len); // The whole body is parsed as list of terms separated by comma
    // Wait, parseRule parses comma-separated terms into a list.
    // But ; binds looser than , ?
    // In standard Prolog, (a, b; c) is ;(,(a, b), c).
    // My parser parses comma-separated list for body.
    // So `a, !; \+ b` might be parsed as `a` AND `!; \+ b`?
    // Let's check precedence.
    // Semicolon is LogicOr. Comma is not in expression precedence, it's a separator in parseRule.
    // Ah, in parseRule:
    // while (peek == .Comma) { append(parseTerm()) }
    // So `a, !; \+ b` -> `a` , `!; \+ b`
    // `!; \+ b` -> `! ; (\+ b)`

    try std.testing.expectEqual(2, rule.body.len);
    try std.testing.expectEqualStrings("a", rule.body[0].atom);

    const second = rule.body[1];
    try std.testing.expectEqualStrings(";", second.structure.functor);
    try std.testing.expectEqualStrings("!", second.structure.args[0].atom);
    try std.testing.expectEqualStrings("\\+", second.structure.args[1].structure.functor);
}

test "Parser - non-decimal numbers ISO syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Binary: 0b100 = 4
    {
        const source = "X is 0b100.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 4), expr.number);
    }

    // Octal: 0o17 = 15
    {
        const source = "X is 0o17.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 15), expr.number);
    }

    // Hexadecimal: 0xf00 = 3840
    {
        const source = "X is 0xf00.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 3840), expr.number);
    }

    // Uppercase: 0XFF = 255
    {
        const source = "X is 0XFF.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 255), expr.number);
    }
}

test "Parser - non-decimal numbers Edinburgh syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Base 2: 2'101 = 5
    {
        const source = "X is 2'101.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 5), expr.number);
    }

    // Base 8: 8'377 = 255
    {
        const source = "X is 8'377.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 255), expr.number);
    }

    // Base 16: 16'FF = 255
    {
        const source = "X is 16'FF.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 255), expr.number);
    }

    // Base 36: 36'Z = 35
    {
        const source = "X is 36'Z.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 35), expr.number);
    }
}

test "Parser - digit grouping with underscores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Decimal: 1_000_000 = 1000000
    {
        const source = "X is 1_000_000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 1_000_000), expr.number);
    }

    // Binary: 0b1111_0000 = 240
    {
        const source = "X is 0b1111_0000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 240), expr.number);
    }

    // Hex: 0xDEAD_BEEF = 3735928559
    {
        const source = "X is 0xDEAD_BEEF.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 3735928559), expr.number);
    }

    // Octal: 0o7_777 = 4095
    {
        const source = "X is 0o7_777.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 4095), expr.number);
    }

    // Edinburgh: 16'FF_00 = 65280
    {
        const source = "X is 16'FF_00.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 65280), expr.number);
    }

    // Float: 3.141_592_653
    {
        const source = "X is 3.141_592_653.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        const expected: f64 = 3.141592653;
        try std.testing.expectApproxEqAbs(expected, expr.float, 0.000000001);
    }
}

test "Parser - digit grouping with spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Decimal: 1 000 000 = 1000000
    {
        const source = "X is 1 000 000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 1_000_000), expr.number);
    }

    // Binary: 0b1111 0000 = 240
    {
        const source = "X is 0b1111 0000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 240), expr.number);
    }

    // Octal: 0o777 000 = 261632
    {
        const source = "X is 0o777 000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 261632), expr.number);
    }
}

test "Parser - digit grouping with comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // With block comment: 1_000_/*more*/000 = 1000000
    {
        const source = "X is 1_000_/*more*/000.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 1_000_000), expr.number);
    }

    // Hex with comment: 0xDE_/*sep*/AD = 57005
    {
        const source = "X is 0xDE_/*sep*/AD.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expectEqual(@as(i64, 57005), expr.number);
    }
}

test "Parser - Infinity and NaN floats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Positive infinity: 1.0Inf
    {
        const source = "X is 1.0Inf.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expect(std.math.isInf(expr.float));
        try std.testing.expect(expr.float > 0);
    }

    // Negative infinity via subtraction: 0 - 1.0Inf
    {
        const source = "X is 0 - 1.0Inf.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        // This will be a structure with functor "-"
        try std.testing.expectEqualStrings("-", expr.structure.functor);
        try std.testing.expect(std.math.isInf(expr.structure.args[1].float));
    }

    // NaN: 1.5NaN
    {
        const source = "X is 1.5NaN.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expect(std.math.isNan(expr.float));
    }

    // NaN with different mantissa: 2.7NaN
    {
        const source = "X is 2.7NaN.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expect(std.math.isNan(expr.float));
    }

    // Infinity with digit grouping: 1_000.0Inf
    {
        const source = "X is 1_000.0Inf.";
        var parser = Parser.init(alloc, source);
        const rule = try parser.parseRule();
        const expr = rule.head.structure.args[1];
        try std.testing.expect(std.math.isInf(expr.float));
        try std.testing.expect(expr.float > 0);
    }
}
