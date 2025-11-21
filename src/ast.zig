const std = @import("std");
const Allocator = std.mem.Allocator;

/// SWI-Prolog canonical representations for special float values.
/// These constants ensure consistent formatting across the codebase.
const INF_REPR = "1.0Inf";
const NEG_INF_REPR = "-1.0Inf";
const NAN_REPR = "1.5NaN";

/// Range for displaying whole floats with .0 suffix.
/// Beyond this range, exponential notation is more appropriate.
const WHOLE_FLOAT_MAX = 1e15;

pub const TermType = enum {
    atom,
    variable,
    structure,
    number,
    float,
    string,
};

pub const Term = union(TermType) {
    atom: []const u8,
    variable: []const u8,
    structure: struct {
        functor: []const u8,
        args: []*Term,
    },
    number: i64,
    float: f64,
    string: []const u8,

    pub fn createAtom(alloc: Allocator, s: []const u8) !*Term {
        const t = try alloc.create(Term);
        const s_copy = try alloc.dupe(u8, s);
        t.* = Term{ .atom = s_copy };
        return t;
    }

    pub fn createVariable(alloc: Allocator, s: []const u8) !*Term {
        const t = try alloc.create(Term);
        const s_copy = try alloc.dupe(u8, s);
        t.* = Term{ .variable = s_copy };
        return t;
    }

    pub fn createStructure(alloc: Allocator, name: []const u8, args: []const *Term) !*Term {
        const t = try alloc.create(Term);
        const args_copy = try alloc.dupe(*Term, args);
        const name_copy = try alloc.dupe(u8, name);
        t.* = Term{ .structure = .{ .functor = name_copy, .args = args_copy } };
        return t;
    }

    pub fn createNumber(alloc: Allocator, val: i64) !*Term {
        const t = try alloc.create(Term);
        t.* = Term{ .number = val };
        return t;
    }

    pub fn createFloat(alloc: Allocator, val: f64) !*Term {
        const t = try alloc.create(Term);
        t.* = Term{ .float = val };
        return t;
    }

    pub fn createString(alloc: Allocator, s: []const u8) !*Term {
        const t = try alloc.create(Term);
        const s_copy = try alloc.dupe(u8, s);
        t.* = Term{ .string = s_copy };
        return t;
    }

    pub fn hash(self: Term) u64 {
        var hasher = std.hash.Wyhash.init(0);
        self.hashInto(&hasher);
        return hasher.final();
    }

    pub fn hashInto(self: Term, hasher: *std.hash.Wyhash) void {
        std.hash.autoHash(hasher, std.meta.activeTag(self));
        switch (self) {
            .atom => |a| hasher.update(a),
            .variable => |v| hasher.update(v),
            .number => |n| std.hash.autoHash(hasher, n),
            .float => |f| {
                // Hash the bit representation of the float
                const bits: u64 = @bitCast(f);
                std.hash.autoHash(hasher, bits);
            },
            .string => |s| hasher.update(s),
            .structure => |s| {
                hasher.update(s.functor);
                for (s.args) |arg| {
                    arg.hashInto(hasher);
                }
            },
        }
    }

    pub fn format(self: Term, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .atom => |s| {
                var needs_quotes = false;
                if (s.len == 0) {
                    needs_quotes = true;
                } else {
                    if (!std.ascii.isLower(s[0])) needs_quotes = true;
                    for (s) |c| {
                        if (!std.ascii.isAlphanumeric(c) and c != '_') {
                            needs_quotes = true;
                            break;
                        }
                    }
                }

                if (needs_quotes) {
                    try writer.print("'", .{});
                    for (s) |c| {
                        if (c == '\'') {
                            try writer.print("''", .{});
                        } else {
                            try writer.print("{c}", .{c});
                        }
                    }
                    try writer.print("'", .{});
                } else {
                    try writer.print("{s}", .{s});
                }
            },
            .variable => |s| try writer.print("{s}", .{s}),
            .number => |n| try writer.print("{d}", .{n}),
            .float => |f| {
                // Handle special float values
                if (std.math.isInf(f)) {
                    const repr = if (f > 0) INF_REPR else NEG_INF_REPR;
                    try writer.print("{s}", .{repr});
                } else if (std.math.isNan(f)) {
                    try writer.print("{s}", .{NAN_REPR});
                } else if (f == @trunc(f) and @abs(f) <= WHOLE_FLOAT_MAX) {
                    // Whole number float - format with .0
                    try writer.print("{d}.0", .{@as(i64, @intFromFloat(f))});
                } else {
                    try writer.print("{d}", .{f});
                }
            },
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .structure => |s| {
                if (s.args.len == 2 and (std.mem.eql(u8, s.functor, "+") or
                    std.mem.eql(u8, s.functor, "-") or
                    std.mem.eql(u8, s.functor, "*") or
                    std.mem.eql(u8, s.functor, "/") or
                    std.mem.eql(u8, s.functor, ">") or
                    std.mem.eql(u8, s.functor, "<") or
                    std.mem.eql(u8, s.functor, ">=") or
                    std.mem.eql(u8, s.functor, "=<") or
                    std.mem.eql(u8, s.functor, "\\=") or
                    std.mem.eql(u8, s.functor, "=") or
                    std.mem.eql(u8, s.functor, "is") or
                    std.mem.eql(u8, s.functor, ";")))
                {
                    try s.args[0].format(fmt, options, writer);
                    try writer.print(" {s} ", .{s.functor});
                    try s.args[1].format(fmt, options, writer);
                } else if (std.mem.eql(u8, s.functor, ".") and s.args.len == 2) {
                    // List printing
                    try writer.print("[", .{});
                    try s.args[0].format(fmt, options, writer);
                    var current = s.args[1];
                    print_tail: while (true) {
                        switch (current.*) {
                            .atom => |a| {
                                if (std.mem.eql(u8, a, "[]")) {
                                    break :print_tail;
                                }
                                try writer.print("|{s}", .{a});
                                break :print_tail;
                            },
                            .structure => |st| {
                                if (std.mem.eql(u8, st.functor, ".") and st.args.len == 2) {
                                    try writer.print(", ", .{});
                                    try st.args[0].format(fmt, options, writer);
                                    current = st.args[1];
                                } else {
                                    try writer.print("|", .{});
                                    try current.format(fmt, options, writer);
                                    break :print_tail;
                                }
                            },
                            else => {
                                try writer.print("|", .{});
                                try current.format(fmt, options, writer);
                                break :print_tail;
                            },
                        }
                    }
                    try writer.print("]", .{});
                } else {
                    try writer.print("{s}(", .{s.functor});
                    for (s.args, 0..) |arg, i| {
                        if (i > 0) try writer.print(", ", .{});
                        try arg.format(fmt, options, writer);
                    }
                    try writer.print(")", .{});
                }
            },
        }
    }
};

pub const Rule = struct {
    head: *Term,
    body: []*Term,
};

test "AST - create terms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const atom = try Term.createAtom(alloc, "hello");
    try std.testing.expectEqual(TermType.atom, std.meta.activeTag(atom.*));
    try std.testing.expectEqualStrings("hello", atom.atom);

    const num = try Term.createNumber(alloc, 42);
    try std.testing.expectEqual(TermType.number, std.meta.activeTag(num.*));
    try std.testing.expectEqual(42, num.number);

    const flt = try Term.createFloat(alloc, 3.14);
    try std.testing.expectEqual(TermType.float, std.meta.activeTag(flt.*));
    try std.testing.expectEqual(3.14, flt.float);

    const variable = try Term.createVariable(alloc, "X");
    try std.testing.expectEqual(TermType.variable, std.meta.activeTag(variable.*));
    try std.testing.expectEqualStrings("X", variable.variable);
}

test "AST - structure creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var args = std.ArrayListUnmanaged(*Term){};
    try args.append(alloc, try Term.createAtom(alloc, "a"));
    try args.append(alloc, try Term.createNumber(alloc, 1));

    const s = try Term.createStructure(alloc, "foo", try args.toOwnedSlice(alloc));
    try std.testing.expectEqual(TermType.structure, std.meta.activeTag(s.*));
    try std.testing.expectEqualStrings("foo", s.structure.functor);
    try std.testing.expectEqual(2, s.structure.args.len);
}

test "AST - formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = try Term.createStructure(alloc, "f", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createNumber(alloc, 10) });

    var buf = std.ArrayListUnmanaged(u8){};
    try t.format("", .{}, buf.writer(alloc));
    try std.testing.expectEqualStrings("f(a, 10)", buf.items);
}

test "AST - list formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // [1, 2] -> .(1, .(2, []))
    const empty = try Term.createAtom(alloc, "[]");
    const two = try Term.createNumber(alloc, 2);
    const l2 = try Term.createStructure(alloc, ".", &[_]*Term{ two, empty });
    const one = try Term.createNumber(alloc, 1);
    const l1 = try Term.createStructure(alloc, ".", &[_]*Term{ one, l2 });

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    try l1.format("", .{}, buf.writer(alloc));
    try std.testing.expectEqualStrings("[1, 2]", buf.items);
}

test "AST - formatting atoms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    // Simple atom
    {
        buf.clearRetainingCapacity();
        const t = try Term.createAtom(alloc, "simple");
        try t.format("", .{}, buf.writer(alloc));
        try std.testing.expectEqualStrings("simple", buf.items);
    }

    // Atom with space
    {
        buf.clearRetainingCapacity();
        const t = try Term.createAtom(alloc, "with space");
        try t.format("", .{}, buf.writer(alloc));
        try std.testing.expectEqualStrings("'with space'", buf.items);
    }

    // Atom with quote
    {
        buf.clearRetainingCapacity();
        const t = try Term.createAtom(alloc, "it's");
        try t.format("", .{}, buf.writer(alloc));
        try std.testing.expectEqualStrings("'it''s'", buf.items);
    }

    // Uppercase atom (symbol)
    {
        buf.clearRetainingCapacity();
        const t = try Term.createAtom(alloc, "Symbol");
        try t.format("", .{}, buf.writer(alloc));
        try std.testing.expectEqualStrings("'Symbol'", buf.items);
    }

    // Empty atom
    {
        buf.clearRetainingCapacity();
        const t = try Term.createAtom(alloc, "");
        try t.format("", .{}, buf.writer(alloc));
        try std.testing.expectEqualStrings("''", buf.items);
    }
}

test "AST - float creation and formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create float term
    const f = try Term.createFloat(alloc, 3.14159);
    try std.testing.expectEqual(TermType.float, std.meta.activeTag(f.*));
    try std.testing.expectEqual(3.14159, f.float);

    // Test float formatting
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    try f.format("", .{}, buf.writer(alloc));
    try std.testing.expectEqualStrings("3.14159", buf.items);

    // Test float hashing (should not crash)
    const hash1 = f.hash();
    const hash2 = f.hash();
    try std.testing.expectEqual(hash1, hash2); // Same value should hash the same

    // Different floats should (likely) have different hashes
    const f2 = try Term.createFloat(alloc, 2.71828);
    const hash3 = f2.hash();
    try std.testing.expect(hash1 != hash3);
}
