const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const Term = ast.Term;
const Rule = ast.Rule;

/// First-argument indexing for Prolog clauses
/// Speeds up clause selection from O(N) to O(1) average case
pub const ClauseIndex = struct {
    alloc: Allocator,

    /// Index by functor/arity: "parent/2" -> [0, 1, 5, ...]
    by_functor: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(usize)),

    /// Index by first argument hash (for ground terms)
    /// Hash of Term -> [clause indices]
    by_first_arg: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(usize)),

    /// Clauses with variable first argument (indexed by functor)
    /// "parent/2" -> [clause indices with variable first arg]
    var_first_arg: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(usize)),

    /// Clauses that can't be indexed (variable in head, complex patterns)
    unindexed: std.ArrayListUnmanaged(usize),

    pub fn init(alloc: Allocator) ClauseIndex {
        return .{
            .alloc = alloc,
            .by_functor = .{},
            .by_first_arg = .{},
            .var_first_arg = .{},
            .unindexed = .{},
        };
    }

    pub fn deinit(self: *ClauseIndex) void {
        // Free functor index
        var functor_iter = self.by_functor.iterator();
        while (functor_iter.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.by_functor.deinit(self.alloc);

        // Free first-arg index
        var arg_iter = self.by_first_arg.iterator();
        while (arg_iter.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.by_first_arg.deinit(self.alloc);

        // Free var_first_arg index
        var var_iter = self.var_first_arg.iterator();
        while (var_iter.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.var_first_arg.deinit(self.alloc);

        // Free unindexed list
        self.unindexed.deinit(self.alloc);
    }

    /// Add a clause to the index
    pub fn addClause(self: *ClauseIndex, clause_idx: usize, rule: Rule) !void {
        const head = rule.head;

        switch (head.*) {
            .structure => |s| {
                // Index by functor/arity
                const functor_key = try std.fmt.allocPrint(
                    self.alloc,
                    "{s}/{d}",
                    .{ s.functor, s.args.len },
                );
                var functor_entry = try self.by_functor.getOrPut(self.alloc, functor_key);
                if (!functor_entry.found_existing) {
                    functor_entry.value_ptr.* = .{};
                }
                try functor_entry.value_ptr.append(self.alloc, clause_idx);

                // Index by first argument if it's ground (atom, number, float, or string)
                if (s.args.len > 0) {
                    const first_arg = s.args[0];
                    switch (first_arg.*) {
                        .atom, .number, .float, .string => {
                            const hash = first_arg.hash();
                            var arg_entry = try self.by_first_arg.getOrPut(self.alloc, hash);
                            if (!arg_entry.found_existing) {
                                arg_entry.value_ptr.* = .{};
                            }
                            try arg_entry.value_ptr.append(self.alloc, clause_idx);
                        },
                        .variable => {
                            // Track clauses with variable first argument
                            var var_entry = try self.var_first_arg.getOrPut(self.alloc, functor_key);
                            if (!var_entry.found_existing) {
                                var_entry.value_ptr.* = .{};
                            }
                            try var_entry.value_ptr.append(self.alloc, clause_idx);
                        },
                        .structure => {
                            // Complex structures in first arg - just use functor index
                        },
                    }
                }
            },
            .atom => {
                // Atom as head (e.g., "true." or "fail.")
                const functor_key = try std.fmt.allocPrint(self.alloc, "{s}/0", .{head.atom});
                var functor_entry = try self.by_functor.getOrPut(self.alloc, functor_key);
                if (!functor_entry.found_existing) {
                    functor_entry.value_ptr.* = .{};
                }
                try functor_entry.value_ptr.append(self.alloc, clause_idx);
            },
            .variable => {
                // Variable as head - can't index, must check against all queries
                try self.unindexed.append(self.alloc, clause_idx);
            },
            .number, .float, .string => {
                // Unusual but possible - index by value
                const hash = head.hash();
                var arg_entry = try self.by_first_arg.getOrPut(self.alloc, hash);
                if (!arg_entry.found_existing) {
                    arg_entry.value_ptr.* = .{};
                }
                try arg_entry.value_ptr.append(self.alloc, clause_idx);
            },
        }
    }

    /// Get candidate clause indices for a goal
    /// Returns the most specific index available
    pub fn getCandidates(self: *ClauseIndex, goal: *Term) !std.ArrayListUnmanaged(usize) {
        var candidates = std.ArrayListUnmanaged(usize){};

        switch (goal.*) {
            .structure => |s| {
                // Try functor/arity index first
                const functor_key = try std.fmt.allocPrint(
                    self.alloc,
                    "{s}/{d}",
                    .{ s.functor, s.args.len },
                );
                defer self.alloc.free(functor_key);

                if (self.by_functor.get(functor_key)) |functor_matches| {
                    // Try to narrow by first arg if it's ground
                    if (s.args.len > 0) {
                        const first_arg = s.args[0];
                        switch (first_arg.*) {
                            .atom, .number, .float, .string => {
                                // Query has ground first arg: include clauses with matching first arg
                                const hash = first_arg.hash();
                                if (self.by_first_arg.get(hash)) |arg_matches| {
                                    try candidates.appendSlice(self.alloc, arg_matches.items);
                                }
                                // Also include clauses with variable first arg (they can match anything)
                                if (self.var_first_arg.get(functor_key)) |var_matches| {
                                    try candidates.appendSlice(self.alloc, var_matches.items);
                                }
                                return candidates;
                            },
                            .variable, .structure => {
                                // Query has variable/complex first arg: fall through to return all functor matches
                            },
                        }
                    }

                    // Return all functor matches (no first-arg narrowing)
                    try candidates.appendSlice(self.alloc, functor_matches.items);
                    return candidates;
                }

                // No functor matches - include unindexed clauses
                try candidates.appendSlice(self.alloc, self.unindexed.items);
                return candidates;
            },
            .atom => {
                // Query is an atom (e.g., "true" or "fail")
                const functor_key = try std.fmt.allocPrint(self.alloc, "{s}/0", .{goal.atom});
                defer self.alloc.free(functor_key);

                if (self.by_functor.get(functor_key)) |matches| {
                    try candidates.appendSlice(self.alloc, matches.items);
                }
                try candidates.appendSlice(self.alloc, self.unindexed.items);
                return candidates;
            },
            .variable => {
                // Query is a variable - must check all clauses
                // Return all indices (0..N)
                var functor_iter = self.by_functor.iterator();
                while (functor_iter.next()) |entry| {
                    try candidates.appendSlice(self.alloc, entry.value_ptr.items);
                }
                try candidates.appendSlice(self.alloc, self.unindexed.items);
                return candidates;
            },
            .number, .float, .string => {
                // Direct match on value
                const hash = goal.hash();
                if (self.by_first_arg.get(hash)) |matches| {
                    try candidates.appendSlice(self.alloc, matches.items);
                }
                try candidates.appendSlice(self.alloc, self.unindexed.items);
                return candidates;
            },
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ClauseIndex - basic functor indexing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var index = ClauseIndex.init(alloc);
    defer index.deinit();

    // Create rules: parent(john, mary). parent(john, bob).
    const empty_body1: []*Term = &[_]*Term{};
    const r1 = Rule{
        .head = try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createAtom(alloc, "john"),
            try Term.createAtom(alloc, "mary"),
        }),
        .body = empty_body1,
    };

    const empty_body2: []*Term = &[_]*Term{};
    const r2 = Rule{
        .head = try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createAtom(alloc, "john"),
            try Term.createAtom(alloc, "bob"),
        }),
        .body = empty_body2,
    };

    try index.addClause(0, r1);
    try index.addClause(1, r2);

    // Query: parent(_, _)
    const query = try Term.createStructure(alloc, "parent", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createVariable(alloc, "Y"),
    });

    var candidates = try index.getCandidates(query);
    defer candidates.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), candidates.items.len);
}

test "ClauseIndex - first argument indexing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var index = ClauseIndex.init(alloc);
    defer index.deinit();

    // Add many parent facts with different first arguments
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const name = try std.fmt.allocPrint(alloc, "person_{d}", .{i});
        const empty_body: []*Term = &[_]*Term{};
        const rule = Rule{
            .head = try Term.createStructure(alloc, "parent", &[_]*Term{
                try Term.createAtom(alloc, name),
                try Term.createAtom(alloc, "child"),
            }),
            .body = empty_body,
        };
        try index.addClause(i, rule);
    }

    // Query: parent(person_50, X)
    const query = try Term.createStructure(alloc, "parent", &[_]*Term{
        try Term.createAtom(alloc, "person_50"),
        try Term.createVariable(alloc, "X"),
    });

    var candidates = try index.getCandidates(query);
    defer candidates.deinit(alloc);

    // Should only return 1 candidate (person_50), not all 100
    try std.testing.expectEqual(@as(usize, 1), candidates.items.len);
    try std.testing.expectEqual(@as(usize, 50), candidates.items[0]);
}

test "ClauseIndex - unindexed variable head" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var index = ClauseIndex.init(alloc);
    defer index.deinit();

    // Rule with variable as head: X :- true.
    var body_terms = [_]*Term{try Term.createAtom(alloc, "true")};
    const body: []*Term = &body_terms;
    const rule = Rule{
        .head = try Term.createVariable(alloc, "X"),
        .body = body,
    };

    try index.addClause(0, rule);

    // Should be in unindexed list
    try std.testing.expectEqual(@as(usize, 1), index.unindexed.items.len);
}
