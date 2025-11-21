const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const ast = @import("ast.zig");
const Term = ast.Term;
const Rule = ast.Rule;
const indexing = @import("indexing.zig");
const ClauseIndex = indexing.ClauseIndex;
const arithmetic = @import("arithmetic.zig");
const NumericValue = arithmetic.NumericValue;

/// Error set for solution handler callbacks.
/// Replaces anyerror for better type safety and explicit error documentation.
pub const SolutionHandlerError = error{
    OutOfMemory,
    InstantiationError,
    TypeException,
    UnknownOperator,
    NegationFound,     // Used internally for negation-as-failure
    ConditionSucceeded, // Used internally for if-then-else
    SystemResources,   // For I/O operations (write, format)
};

pub const RuleList = ArrayListUnmanaged(Rule);
pub const EnvMap = StringHashMapUnmanaged(*Term);

pub fn createEnv() EnvMap {
    return .{};
}

fn evaluate(term: *Term, env: *EnvMap) !NumericValue {
    return arithmetic.evaluate(term, env, resolve);
}

pub fn resolve(term: *Term, env: *EnvMap) *Term {
    if (term.* == .variable) {
        if (env.get(term.variable)) |bound_term| {
            return resolve(bound_term, env);
        }
    }
    return term;
}

pub fn unify(alloc: Allocator, t1: *Term, t2: *Term, env: *EnvMap) bool {
    const r1 = resolve(t1, env);
    const r2 = resolve(t2, env);
    if (r1 == r2) return true;
    if (r1.* == .variable) {
        env.put(alloc, r1.variable, t2) catch return false;
        return true;
    }
    if (r2.* == .variable) {
        env.put(alloc, r2.variable, t1) catch return false;
        return true;
    }
    if (r1.* == .number and r2.* == .number) return r1.number == r2.number;
    if (r1.* == .float and r2.* == .float) return r1.float == r2.float;
    if (r1.* == .atom and r2.* == .atom) return std.mem.eql(u8, r1.atom, r2.atom);
    if (r1.* == .string and r2.* == .string) return std.mem.eql(u8, r1.string, r2.string);
    if (r1.* == .structure and r2.* == .structure) {
        const s1 = r1.structure;
        const s2 = r2.structure;
        if (!std.mem.eql(u8, s1.functor, s2.functor)) return false;
        if (s1.args.len != s2.args.len) return false;
        for (s1.args, 0..) |arg1, i| {
            if (!unify(alloc, arg1, s2.args[i], env)) return false;
        }
        return true;
    }
    return false;
}

fn copyTermWithSuffix(alloc: Allocator, term: *Term, suffix: usize) !*Term {
    switch (term.*) {
        .number => return term,
        .float => return term,
        .atom => return term,
        .string => return term,
        .variable => |name| {
            const new_name = try std.fmt.allocPrint(alloc, "{s}_{d}", .{ name, suffix });
            return Term.createVariable(alloc, new_name);
        },
        .structure => |s| {
            var new_args = ArrayListUnmanaged(*Term){};
            for (s.args) |arg| {
                try new_args.append(alloc, try copyTermWithSuffix(alloc, arg, suffix));
            }
            return Term.createStructure(alloc, s.functor, try new_args.toOwnedSlice(alloc));
        },
    }
}

pub fn copyTerm(alloc: Allocator, term: *Term, env: EnvMap) !*Term {
    switch (term.*) {
        .atom, .number, .float, .string => return term,
        .variable => |name| {
            if (env.get(name)) |val| {
                return copyTerm(alloc, val, env);
            }
            return term;
        },
        .structure => |s| {
            var new_args = try alloc.alloc(*Term, s.args.len);
            for (s.args, 0..) |arg, i| {
                new_args[i] = try copyTerm(alloc, arg, env);
            }
            return Term.createStructure(alloc, s.functor, new_args);
        },
    }
}

pub const Engine = struct {
    alloc: Allocator,
    db: RuleList,
    index: ClauseIndex,

    const MAX_DEPTH = 600;

    pub fn init(alloc: Allocator) Engine {
        return Engine{
            .alloc = alloc,
            .db = RuleList{},
            .index = ClauseIndex.init(alloc),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.db.deinit(self.alloc);
        self.index.deinit();
    }

    pub fn addRule(self: *Engine, rule: Rule) !void {
        const clause_idx = self.db.items.len;
        try self.db.append(self.alloc, rule);
        try self.index.addClause(clause_idx, rule);
    }

    pub const SolutionHandler = struct {
        context: ?*anyopaque,
        handle: *const fn (context: ?*anyopaque, env: EnvMap, engine: *Engine) SolutionHandlerError!void,
    };

    pub const SolveResult = union(enum) {
        Normal,
        Cut: usize,
    };

    // Helper: Convert a term to string (for format strings)
    fn termToString(self: *Engine, term: *Term) ![]u8 {
        switch (term.*) {
            .atom => |a| return try self.alloc.dupe(u8, a),
            .string => |s| return try self.alloc.dupe(u8, s),
            else => return error.InvalidFormatString,
        }
    }

    // Helper: Convert a term to a list of terms
    fn termToList(self: *Engine, term: *Term, env: *EnvMap) ![]*Term {
        var result = ArrayListUnmanaged(*Term){};
        errdefer result.deinit(self.alloc);

        var current = resolve(term, env);
        while (true) {
            if (current.* == .atom and std.mem.eql(u8, current.atom, "[]")) {
                break;
            }
            if (current.* == .structure and std.mem.eql(u8, current.structure.functor, ".") and current.structure.args.len == 2) {
                try result.append(self.alloc, resolve(current.structure.args[0], env));
                current = resolve(current.structure.args[1], env);
            } else {
                // Not a proper list
                return error.InvalidArgumentList;
            }
        }

        return try result.toOwnedSlice(self.alloc);
    }

    // Helper: Process format string with arguments
    fn processFormat(_: *Engine, format_str: []const u8, args: []*Term, env: *EnvMap, writer: anytype) !void {
        var i: usize = 0;
        var arg_idx: usize = 0;

        while (i < format_str.len) {
            if (format_str[i] == '~') {
                i += 1;
                if (i >= format_str.len) break;

                const directive = format_str[i];
                i += 1;

                switch (directive) {
                    'w' => {
                        // Write term
                        if (arg_idx >= args.len) return error.NotEnoughArguments;
                        const term = resolve(args[arg_idx], env);
                        try term.format("", .{}, writer);
                        arg_idx += 1;
                    },
                    'd' => {
                        // Decimal integer
                        if (arg_idx >= args.len) return error.NotEnoughArguments;
                        const term = resolve(args[arg_idx], env);
                        if (term.* == .number) {
                            try writer.print("{d}", .{term.number});
                        } else {
                            return error.ExpectedInteger;
                        }
                        arg_idx += 1;
                    },
                    'f' => {
                        // Float
                        if (arg_idx >= args.len) return error.NotEnoughArguments;
                        const term = resolve(args[arg_idx], env);
                        if (term.* == .float) {
                            try writer.print("{d}", .{term.float});
                        } else if (term.* == .number) {
                            try writer.print("{d}.0", .{term.number});
                        } else {
                            return error.ExpectedNumber;
                        }
                        arg_idx += 1;
                    },
                    'a' => {
                        // Atom
                        if (arg_idx >= args.len) return error.NotEnoughArguments;
                        const term = resolve(args[arg_idx], env);
                        if (term.* == .atom) {
                            try writer.print("{s}", .{term.atom});
                        } else {
                            return error.ExpectedAtom;
                        }
                        arg_idx += 1;
                    },
                    's' => {
                        // String
                        if (arg_idx >= args.len) return error.NotEnoughArguments;
                        const term = resolve(args[arg_idx], env);
                        if (term.* == .string) {
                            try writer.print("{s}", .{term.string});
                        } else if (term.* == .atom) {
                            try writer.print("{s}", .{term.atom});
                        } else {
                            return error.ExpectedString;
                        }
                        arg_idx += 1;
                    },
                    'n' => {
                        // Newline
                        try writer.print("\n", .{});
                    },
                    '~' => {
                        // Escaped tilde
                        try writer.print("~", .{});
                    },
                    else => {
                        // Unknown directive - just print it
                        try writer.print("~{c}", .{directive});
                    },
                }
            } else {
                try writer.print("{c}", .{format_str[i]});
                i += 1;
            }
        }
    }

    pub fn solve(
        self: *Engine,
        goals: []*Term,
        env: *EnvMap,
        depth: usize,
        scope_id: usize,
        handler: SolutionHandler,
        writer: anytype,
    ) !SolveResult {
        // OPTIMIZATION: Tail-Call Optimization (Partial)
        // Wrap entire function in a loop to handle certain tail calls iteratively.
        // Optimizes: $end_scope, phrase/2, phrase/3
        // Not optimized: main clause matching (requires result processing)
        var current_goals_param = goals;
        var current_env_param = env;
        const current_depth = depth;
        var current_scope_id = scope_id;

        while (true) {
            if (current_depth > MAX_DEPTH) return error.StackOverflow;
            var current_env = current_env_param;
            if (current_goals_param.len == 0) {
                try handler.handle(handler.context, current_env.*, self);
                return .Normal;
            }

            var current_goals = ArrayListUnmanaged(*Term){};
            defer current_goals.deinit(self.alloc);
            try current_goals.appendSlice(self.alloc, current_goals_param);
            const goal = resolve(current_goals.orderedRemove(0), current_env_param);

            // Handle Cut !
            if (goal.* == .atom and std.mem.eql(u8, goal.atom, "!")) {
                // Note: Cut is NOT a pure tail call because we must transform the result
                // (.Normal -> .Cut). We still recurse here.
                current_goals_param = try current_goals.toOwnedSlice(self.alloc);
                current_env_param = current_env;

                const res = try self.solve(current_goals_param, current_env_param, current_depth, current_scope_id, handler, writer);
                switch (res) {
                    .Normal => return .{ .Cut = current_scope_id },
                    .Cut => |id| return .{ .Cut = id },
                }
            }

            // Handle internal $end_scope(id, parent_scope)
            // This is a true tail call - updates params and continues loop
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "$end_scope") and goal.structure.args.len == 2) {
                const parent_scope_term = goal.structure.args[1];
                current_goals_param = try current_goals.toOwnedSlice(self.alloc);
                current_env_param = current_env;

                if (parent_scope_term.* == .number) {
                    current_scope_id = @as(usize, @intCast(parent_scope_term.number));
                }
                // Else: keep current_scope_id unchanged (shouldn't happen)

                continue; // Tail call optimization
            }
        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "phrase") and (goal.structure.args.len == 2 or goal.structure.args.len == 3)) {
            const dcg_goal = goal.structure.args[0];
            const input_list = goal.structure.args[1];
            var rest_list: *Term = undefined;

            if (goal.structure.args.len == 2) {
                rest_list = try Term.createAtom(self.alloc, "[]");
            } else {
                rest_list = goal.structure.args[2];
            }

            var new_goal: *Term = undefined;
            if (dcg_goal.* == .atom) {
                // Atom p -> p(Input, Rest)
                new_goal = try Term.createStructure(self.alloc, dcg_goal.atom, &[_]*Term{ input_list, rest_list });
            } else if (dcg_goal.* == .structure) {
                // Structure p(X) -> p(X, Input, Rest)
                var new_args = try std.ArrayListUnmanaged(*Term).initCapacity(self.alloc, dcg_goal.structure.args.len + 2);
                try new_args.appendSlice(self.alloc, dcg_goal.structure.args);
                try new_args.append(self.alloc, input_list);
                try new_args.append(self.alloc, rest_list);
                new_goal = try Term.createStructure(self.alloc, dcg_goal.structure.functor, try new_args.toOwnedSlice(self.alloc));
            } else {
                return .Normal; // Invalid goal for phrase
            }

                // Prepend new_goal to current_goals and use tail call optimization
                var next_goals = ArrayListUnmanaged(*Term){};
                try next_goals.append(self.alloc, new_goal);
                try next_goals.appendSlice(self.alloc, current_goals.items);

                current_goals_param = try next_goals.toOwnedSlice(self.alloc);
                current_env_param = current_env;
                continue; // Tail call optimization
            }

        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "distinct") and goal.structure.args.len == 2) {
            const template = goal.structure.args[0];
            const sub_goal = goal.structure.args[1];

            const CollectorContext = struct {
                alloc: Allocator,
                template: *Term,
                seen: *std.AutoHashMap(u64, void),
                original_handler: SolutionHandler,
                original_env: *EnvMap,
                engine: *Engine,
            };

            const seen = try self.alloc.create(std.AutoHashMap(u64, void));
            seen.* = std.AutoHashMap(u64, void).init(self.alloc);
            defer {
                seen.deinit();
                self.alloc.destroy(seen);
            }

            const wrapper = struct {
                fn handle(ctx_ptr: ?*anyopaque, match_env: EnvMap, _: *Engine) SolutionHandlerError!void {
                    const ctx: *CollectorContext = @ptrCast(@alignCast(ctx_ptr));

                    // Check if 'template' instantiated in 'match_env' is unique.
                    // distinct(X, Goal) filters solutions of Goal based on X.
                    // We use match_env to propagate bindings if the solution is accepted.

                    const term = try copyTerm(ctx.alloc, ctx.template, match_env);
                    const hash = term.hash(); // We need a hash function for Term

                    if (!ctx.seen.contains(hash)) {
                        try ctx.seen.put(hash, {});
                        try ctx.original_handler.handle(ctx.original_handler.context, match_env, ctx.engine);
                    }
                }
            };

            var distinct_ctx = CollectorContext{
                .alloc = self.alloc,
                .template = template,
                .seen = seen,
                .original_handler = handler,
                .original_env = current_env,
                .engine = self,
            };

            const distinct_handler = SolutionHandler{
                .context = &distinct_ctx,
                .handle = wrapper.handle,
            };

            // Solve sub_goal with distinct handler
            var sub_goals = ArrayListUnmanaged(*Term){};
            defer sub_goals.deinit(self.alloc);
            try sub_goals.append(self.alloc, sub_goal);
            try sub_goals.appendSlice(self.alloc, current_goals.items);

            return self.solve(try sub_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, distinct_handler, writer);
        }

        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "is") and goal.structure.args.len == 2) {
            const val = evaluate(goal.structure.args[1], current_env) catch {
                return .Normal;
            };
            const val_term = switch (val) {
                .int => |i| try Term.createNumber(self.alloc, i),
                .float => |f| try Term.createFloat(self.alloc, f),
            };
            if (unify(self.alloc, goal.structure.args[0], val_term, current_env)) {
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }
            return .Normal;
        }

        if (goal.* == .structure and goal.structure.args.len == 2) {
            const s = goal.structure;
            var is_cmp = true;
            var result = false;
            if (std.mem.eql(u8, s.functor, ">")) {
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() > r.toFloat();
            } else if (std.mem.eql(u8, s.functor, "<")) {
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() < r.toFloat();
            } else if (std.mem.eql(u8, s.functor, ">=")) {
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() >= r.toFloat();
            } else if (std.mem.eql(u8, s.functor, "=<")) {
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() <= r.toFloat();
            } else if (std.mem.eql(u8, s.functor, "=")) {
                result = unify(self.alloc, s.args[0], s.args[1], current_env);
            } else if (std.mem.eql(u8, s.functor, "\\=")) {
                // \= succeeds if unification FAILS
                // We need to try unification on a CLONE of the environment to avoid side effects
                var env_check = try current_env.clone(self.alloc);
                defer env_check.deinit(self.alloc);
                const unifies = unify(self.alloc, s.args[0], s.args[1], &env_check);
                result = !unifies;
            } else if (std.mem.eql(u8, s.functor, "=:=")) {
                // =:= is arithmetic equality (evaluates both sides first)
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() == r.toFloat();
            } else if (std.mem.eql(u8, s.functor, "=\\=")) {
                // =\= is arithmetic inequality (evaluates both sides first)
                const l = evaluate(s.args[0], current_env) catch return .Normal;
                const r = evaluate(s.args[1], current_env) catch return .Normal;
                result = l.toFloat() != r.toFloat();
            } else if (std.mem.eql(u8, s.functor, "->")) {
                // If-then: (Cond -> Then)
                // If Cond succeeds, execute Then; if Cond fails, the whole construct fails
                const cond = s.args[0];
                const then_branch = s.args[1];

                // Try to prove the condition
                const CondSuccess = error{ConditionSucceeded};
                const cond_check = struct {
                    fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                        return CondSuccess.ConditionSucceeded;
                    }
                };
                const cond_handler = SolutionHandler{ .context = null, .handle = cond_check.handle };

                var cond_env = try current_env.clone(self.alloc);
                defer cond_env.deinit(self.alloc);

                var cond_goals = ArrayListUnmanaged(*Term){};
                try cond_goals.append(self.alloc, cond);

                const cond_result = self.solve(try cond_goals.toOwnedSlice(self.alloc), &cond_env, depth + 1, scope_id, cond_handler, writer);

                if (cond_result) |_| {
                    // Condition failed (no solutions found)
                    return .Normal;
                } else |err| {
                    if (err == CondSuccess.ConditionSucceeded) {
                        // Condition succeeded - commit to this choice and execute Then
                        // Copy bindings from cond_env to current_env
                        var it = cond_env.iterator();
                        while (it.next()) |entry| {
                            try current_env.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
                        }
                        var then_goals = ArrayListUnmanaged(*Term){};
                        try then_goals.append(self.alloc, then_branch);
                        try then_goals.appendSlice(self.alloc, current_goals.items);
                        return self.solve(try then_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                    }
                    return err;
                }
            } else if (std.mem.eql(u8, s.functor, ";")) {
                // Check if this is if-then-else: (Cond -> Then ; Else)
                const first_arg = s.args[0];
                if (first_arg.* == .structure and std.mem.eql(u8, first_arg.structure.functor, "->") and first_arg.structure.args.len == 2) {
                    // This is if-then-else
                    const cond = first_arg.structure.args[0];
                    const then_branch = first_arg.structure.args[1];
                    const else_branch = s.args[1];

                    // Try to prove the condition
                    const CondSuccess = error{ConditionSucceeded};
                    const cond_check = struct {
                        fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                            return CondSuccess.ConditionSucceeded;
                        }
                    };
                    const cond_handler = SolutionHandler{ .context = null, .handle = cond_check.handle };

                    var cond_env = try current_env.clone(self.alloc);
                    defer cond_env.deinit(self.alloc);

                    var cond_goals = ArrayListUnmanaged(*Term){};
                    try cond_goals.append(self.alloc, cond);

                    const cond_result = self.solve(try cond_goals.toOwnedSlice(self.alloc), &cond_env, depth + 1, scope_id, cond_handler, writer);

                    if (cond_result) |_| {
                        // Condition failed - execute Else
                        var else_goals = ArrayListUnmanaged(*Term){};
                        try else_goals.append(self.alloc, else_branch);
                        try else_goals.appendSlice(self.alloc, current_goals.items);
                        return self.solve(try else_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                    } else |err| {
                        if (err == CondSuccess.ConditionSucceeded) {
                            // Condition succeeded - commit and execute Then
                            // Copy bindings from cond_env to current_env
                            var it = cond_env.iterator();
                            while (it.next()) |entry| {
                                try current_env.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
                            }
                            var then_goals = ArrayListUnmanaged(*Term){};
                            try then_goals.append(self.alloc, then_branch);
                            try then_goals.appendSlice(self.alloc, current_goals.items);
                            return self.solve(try then_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                        }
                        return err;
                    }
                } else {
                    // Regular disjunction: (A ; B)
                    var env_a = try current_env.clone(self.alloc);
                    defer env_a.deinit(self.alloc);
                    var goals_a = ArrayListUnmanaged(*Term){};
                    try goals_a.append(self.alloc, s.args[0]);
                    try goals_a.appendSlice(self.alloc, current_goals.items);
                    const res_a = try self.solve(try goals_a.toOwnedSlice(self.alloc), &env_a, depth + 1, scope_id, handler, writer);
                    if (res_a != .Normal) return res_a;

                    var env_b = try current_env.clone(self.alloc);
                    defer env_b.deinit(self.alloc);
                    var goals_b = ArrayListUnmanaged(*Term){};
                    try goals_b.append(self.alloc, s.args[1]);
                    try goals_b.appendSlice(self.alloc, current_goals.items);
                    return self.solve(try goals_b.toOwnedSlice(self.alloc), &env_b, depth + 1, scope_id, handler, writer);
                }
            } else {
                is_cmp = false;
            }

            if (is_cmp) {
                if (result) return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                return .Normal;
            }
        }

        if (goal.* == .structure and (std.mem.eql(u8, goal.structure.functor, "\\+") or std.mem.eql(u8, goal.structure.functor, "not"))) {
            const NegationError = error{NegationFound};
            const negation_check = struct {
                fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                    return NegationError.NegationFound;
                }
            };
            const neg_handler = SolutionHandler{ .context = null, .handle = negation_check.handle };

            var neg_env = try current_env.clone(self.alloc);
            defer neg_env.deinit(self.alloc);

            var neg_goals = ArrayListUnmanaged(*Term){};
            try neg_goals.append(self.alloc, goal.structure.args[0]);

            const res = self.solve(try neg_goals.toOwnedSlice(self.alloc), &neg_env, depth + 1, scope_id, neg_handler, writer);

            if (res) |_| {
                // solve returned .Normal (or .Cut), meaning NO solution was found (because if one was found, we would have errored).
                // So negation SUCCEEDS.
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            } else |err| {
                if (err == NegationError.NegationFound) {
                    // Found a solution, so negation FAILS.
                    return .Normal;
                }
                return err;
            }
        }

        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "write") and goal.structure.args.len == 1) {
            const t = resolve(goal.structure.args[0], current_env);
            try t.format("", .{}, writer);
            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
        }

        if (goal.* == .atom and std.mem.eql(u8, goal.atom, "nl")) {
            try writer.print("\n", .{});
            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
        }

        // format/1: format(FormatString)
        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "format") and goal.structure.args.len == 1) {
            const format_term = resolve(goal.structure.args[0], current_env);
            const format_str = try self.termToString(format_term);
            defer self.alloc.free(format_str);

            try self.processFormat(format_str, &[_]*Term{}, current_env, writer);
            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
        }

        // format/2: format(FormatString, Arguments)
        if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "format") and goal.structure.args.len == 2) {
            const format_term = resolve(goal.structure.args[0], current_env);
            const format_str = try self.termToString(format_term);
            defer self.alloc.free(format_str);

            const args_term = resolve(goal.structure.args[1], current_env);
            const args = try self.termToList(args_term, current_env);
            defer self.alloc.free(args);

            try self.processFormat(format_str, args, current_env, writer);
            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
        }

        if (goal.* == .atom and std.mem.eql(u8, goal.atom, "true")) {
            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
        }

        if (goal.* == .atom and (std.mem.eql(u8, goal.atom, "false") or std.mem.eql(u8, goal.atom, "fail"))) {
            return .Normal;
        }

        if (goal.* == .atom and std.mem.eql(u8, goal.atom, "repeat")) {
            // repeat/0 always succeeds and provides infinite choice points
            // Try to solve remaining goals repeatedly until cut
            while (true) {
                var env_clone = try current_env.clone(self.alloc);
                defer env_clone.deinit(self.alloc);
                var goals_clone = ArrayListUnmanaged(*Term){};
                try goals_clone.appendSlice(self.alloc, current_goals.items);
                const result = try self.solve(try goals_clone.toOwnedSlice(self.alloc), &env_clone, depth, scope_id, handler, writer);
                // If cut, stop repeating
                if (result != .Normal) return result;
                // Otherwise, keep repeating (backtrack to repeat)
            }
        }

        // Use indexing to get candidate clauses
        var candidates = try self.index.getCandidates(goal);
        defer candidates.deinit(self.alloc);

        // OPTIMIZATION: Choice Point Elimination
        // If there's only one candidate, we don't need to clone the environment
        // for backtracking since there's nothing to backtrack to.
        const is_deterministic = candidates.items.len == 1;

        for (candidates.items) |clause_idx| {
            const rule = self.db.items[clause_idx];

            // For deterministic clauses, use the environment directly (no clone)
            // For non-deterministic, clone for backtracking
            var env_storage = if (!is_deterministic) try current_env.clone(self.alloc) else EnvMap{};
            defer if (!is_deterministic) env_storage.deinit(self.alloc);

            const new_env = if (is_deterministic) current_env else &env_storage;

            // Rename variables in rule to avoid clashes.
            // Use a combination of depth and rule index to generate a unique suffix for this instantiation.
            const suffix = depth * 10000 + clause_idx;

            const fresh_head = try copyTermWithSuffix(self.alloc, rule.head, suffix);

            if (unify(self.alloc, goal, fresh_head, new_env)) {
                var next_goals = ArrayListUnmanaged(*Term){};

                // Add body goals
                for (rule.body) |b_term| {
                    try next_goals.append(self.alloc, try copyTermWithSuffix(self.alloc, b_term, suffix));
                }

                // Add $end_scope marker
                const new_scope_id = suffix + 1;
                const end_scope_term = try Term.createStructure(self.alloc, "$end_scope", &[_]*Term{ try Term.createNumber(self.alloc, @intCast(new_scope_id)), try Term.createNumber(self.alloc, @intCast(scope_id)) });
                try next_goals.append(self.alloc, end_scope_term);

                // Add remaining goals
                for (current_goals.items) |rem_g| {
                    try next_goals.append(self.alloc, rem_g);
                }

                const res = try self.solve(try next_goals.toOwnedSlice(self.alloc), new_env, depth + 1, new_scope_id, handler, writer);

                switch (res) {
                    .Normal => {}, // Continue to next rule
                    .Cut => |cut_scope| {
                        if (cut_scope == new_scope_id) {
                            // Cut was for this rule, stop trying other rules
                            return .Normal;
                        } else {
                            // Cut is for a parent scope, propagate
                            return .{ .Cut = cut_scope };
                        }
                    },
                }
            }
        }
        return .Normal;
        } // end while (true) - Tail-Call Optimization loop
    }
};

test "Engine - unification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var env = createEnv();
    defer env.deinit(alloc);

    const t1 = try Term.createAtom(alloc, "a");
    const t2 = try Term.createAtom(alloc, "a");
    try std.testing.expect(unify(alloc, t1, t2, &env));

    const v1 = try Term.createVariable(alloc, "X");
    const t3 = try Term.createAtom(alloc, "b");
    try std.testing.expect(unify(alloc, v1, t3, &env));

    const resolved = resolve(v1, &env);
    try std.testing.expectEqualStrings("b", resolved.atom);
}

test "Engine - solve simple fact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // fact: p(a).
    const head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "a")});
    try eng.addRule(Rule{ .head = head, .body = &[_]*Term{} });

    // query: ?- p(X).
    const query_arg = try Term.createVariable(alloc, "X");
    const query = try Term.createStructure(alloc, "p", &[_]*Term{query_arg});

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    // We can't easily test stdout output here without capturing it,
    // but we can check if it runs without error.
    // For a real test we might want to refactor solve to write to a writer.
    var goals = [_]*Term{query};
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Check if X was bound to a in the env (though solve copies env, so we can't check original env easily unless we pass a pointer that persists)
    // Actually solve clones env for each branch.
}

const TestHandlerContext = struct {
    buf: *std.ArrayListUnmanaged(u8),
    alloc: Allocator,
    has_printed: *bool,
};

fn testHandle(ctx_ptr: ?*anyopaque, env: EnvMap, _: *Engine) !void {
    const ctx: *TestHandlerContext = @ptrCast(@alignCast(ctx_ptr));
    const out_writer = ctx.buf.writer(ctx.alloc);
    if (ctx.has_printed.*) {
        try out_writer.print("\n", .{});
    }

    var found_vars = false;
    var it = env.iterator();
    while (it.next()) |entry| {
        if (std.mem.indexOf(u8, entry.key_ptr.*, "_") == null) {
            if (found_vars) try out_writer.print(", ", .{});
            const val = try copyTerm(ctx.alloc, entry.value_ptr.*, env);
            try out_writer.print("{s} = ", .{entry.key_ptr.*});
            try val.format("", .{}, out_writer);
            found_vars = true;
        }
    }

    if (!found_vars) {
        try out_writer.print("  true.", .{});
    }
    ctx.has_printed.* = true;
}

test "Engine - solve simple fact 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // fact: p(a).
    const head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "a")});
    try eng.addRule(Rule{ .head = head, .body = &[_]*Term{} });

    // query: ?- p(X).
    const query_arg = try Term.createVariable(alloc, "X");
    const query = try Term.createStructure(alloc, "p", &[_]*Term{query_arg});

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    // We can't easily test stdout output here without capturing it,
    // but we can check if it runs without error.
    // For a real test we might want to refactor solve to write to a writer.
    var goals = [_]*Term{query};
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Check if X was bound to a in the env (though solve copies env, so we can't check original env easily unless we pass a pointer that persists)
    // Actually solve clones env for each branch.
}

test "Engine - duplicate true output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // parent(galya, victoria).
    const p1 = try Term.createStructure(alloc, "parent", &[_]*Term{ try Term.createAtom(alloc, "galya"), try Term.createAtom(alloc, "victoria") });
    try eng.addRule(Rule{ .head = p1, .body = &[_]*Term{} });

    // parent(dimitar, victoria).
    const p2 = try Term.createStructure(alloc, "parent", &[_]*Term{ try Term.createAtom(alloc, "dimitar"), try Term.createAtom(alloc, "victoria") });
    try eng.addRule(Rule{ .head = p2, .body = &[_]*Term{} });

    // human(X) :- parent(_, X).
    // Head: human(X)
    const h_head = try Term.createStructure(alloc, "human", &[_]*Term{try Term.createVariable(alloc, "X")});
    // Body: parent(_, X)
    const b_term = try Term.createStructure(alloc, "parent", &[_]*Term{ try Term.createVariable(alloc, "_"), try Term.createVariable(alloc, "X") });
    var body_terms = [_]*Term{b_term};
    try eng.addRule(Rule{ .head = h_head, .body = &body_terms });

    // Query: ?- human(victoria).
    const query = try Term.createStructure(alloc, "human", &[_]*Term{try Term.createAtom(alloc, "victoria")});

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect two "  true.\n" because there are two ways to prove human(victoria)
    try std.testing.expectEqualStrings("  true.\n  true.", buf.items);
}

test "Engine - multiple solutions with variables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // man(nikolay).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "man", &[_]*Term{try Term.createAtom(alloc, "nikolay")}), .body = &[_]*Term{} });
    // man(yavor).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "man", &[_]*Term{try Term.createAtom(alloc, "yavor")}), .body = &[_]*Term{} });

    // human(X) :- man(X).
    const h_head = try Term.createStructure(alloc, "human", &[_]*Term{try Term.createVariable(alloc, "X")});
    const b_term = try Term.createStructure(alloc, "man", &[_]*Term{try Term.createVariable(alloc, "X")});
    var body_terms = [_]*Term{b_term};
    try eng.addRule(Rule{ .head = h_head, .body = &body_terms });

    // Query: ?- human(X).
    const query = try Term.createStructure(alloc, "human", &[_]*Term{try Term.createVariable(alloc, "X")});

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect X = nikolay and X = yavor
    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "X = nikolay") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "X = yavor") != null);
}

test "Engine - distinct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // p(1).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 1)}), .body = &[_]*Term{} });
    // p(2).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 2)}), .body = &[_]*Term{} });
    // p(1).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 1)}), .body = &[_]*Term{} });
    // p(2).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 2)}), .body = &[_]*Term{} });

    // Query: ?- distinct(X, p(X)).
    const X = try Term.createVariable(alloc, "X");
    const pX = try Term.createStructure(alloc, "p", &[_]*Term{X});
    const query = try Term.createStructure(alloc, "distinct", &[_]*Term{ X, pX });

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect X = 1 and X = 2, but only once each.
    // The output format is "X = 1\n  true.\nX = 2\n  true.\n" or similar depending on how testHandle formats.
    // testHandle appends "  {s}\n" for each solution.

    // Count occurrences of "X = 1" and "X = 2"
    var count1: usize = 0;
    var count2: usize = 0;

    var it = std.mem.splitSequence(u8, buf.items, "\n");
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, "X = 1") != null) count1 += 1;
        if (std.mem.indexOf(u8, line, "X = 2") != null) count2 += 1;
    }

    try std.testing.expectEqual(@as(usize, 1), count1);
    try std.testing.expectEqual(@as(usize, 1), count2);
}

test "Engine - cut operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // p(1).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 1)}), .body = &[_]*Term{} });
    // p(2).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 2)}), .body = &[_]*Term{} });

    // q(X) :- p(X), !.
    // Head: q(X)
    const q_head = try Term.createStructure(alloc, "q", &[_]*Term{try Term.createVariable(alloc, "X")});
    // Body: p(X), !
    const b1 = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createVariable(alloc, "X")});
    const b2 = try Term.createAtom(alloc, "!");
    var body_terms = [_]*Term{ b1, b2 };
    try eng.addRule(Rule{ .head = q_head, .body = &body_terms });

    // q(3).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "q", &[_]*Term{try Term.createNumber(alloc, 3)}), .body = &[_]*Term{} });

    // Query: ?- q(X).
    const query = try Term.createStructure(alloc, "q", &[_]*Term{try Term.createVariable(alloc, "X")});

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect only X = 1.
    // X = 2 is pruned by cut (backtracking to p(X) prevented).
    // X = 3 is pruned by cut (next rule for q prevented).

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "X = 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "X = 2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "X = 3") == null);
}

test "Engine - lists and strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // append([], L, L).
    // append([H|T], L, [H|R]) :- append(T, L, R).

    // Rule 1: append([], L, L).
    const empty_list = try Term.createAtom(alloc, "[]");
    const L = try Term.createVariable(alloc, "L");
    const head1 = try Term.createStructure(alloc, "append", &[_]*Term{ empty_list, L, L });
    try eng.addRule(Rule{ .head = head1, .body = &[_]*Term{} });

    // Rule 2: append([H|T], L, [H|R]) :- append(T, L, R).
    const H = try Term.createVariable(alloc, "H");
    const T = try Term.createVariable(alloc, "T");
    const R = try Term.createVariable(alloc, "R");

    // [H|T] -> .(H, T)
    const list_HT = try Term.createStructure(alloc, ".", &[_]*Term{ H, T });
    // [H|R] -> .(H, R)
    const list_HR = try Term.createStructure(alloc, ".", &[_]*Term{ H, R });

    const head2 = try Term.createStructure(alloc, "append", &[_]*Term{ list_HT, L, list_HR });
    const body2 = try Term.createStructure(alloc, "append", &[_]*Term{ T, L, R });
    var body_terms = [_]*Term{body2};
    try eng.addRule(Rule{ .head = head2, .body = &body_terms });

    // Query: ?- append([1, 2], [3], X).
    // [1, 2] -> .(1, .(2, []))
    const l1 = try Term.createStructure(alloc, ".", &[_]*Term{ try Term.createNumber(alloc, 1), try Term.createStructure(alloc, ".", &[_]*Term{ try Term.createNumber(alloc, 2), empty_list }) });
    // [3] -> .(3, [])
    const l2 = try Term.createStructure(alloc, ".", &[_]*Term{ try Term.createNumber(alloc, 3), empty_list });
    const X = try Term.createVariable(alloc, "X");

    const query = try Term.createStructure(alloc, "append", &[_]*Term{ l1, l2, X });

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect X = [1, 2, 3]
    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "X = [1, 2, 3]") != null);

    // Test strings
    // s("hello").
    const s_head = try Term.createStructure(alloc, "s", &[_]*Term{try Term.createString(alloc, "hello")});
    try eng.addRule(Rule{ .head = s_head, .body = &[_]*Term{} });

    // Query: ?- s(X).
    const query_s = try Term.createStructure(alloc, "s", &[_]*Term{X});

    // Reset buffer
    buf.clearRetainingCapacity();
    has_printed = false;

    var goals_s = [_]*Term{query_s};
    _ = try eng.solve(&goals_s, &env, 0, 0, handler, buf.writer(alloc));

    const output_s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output_s, "X = \"hello\"") != null);
}

test "Engine - true and false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // p :- true.
    var body_p = [_]*Term{try Term.createAtom(alloc, "true")};
    try eng.addRule(Rule{ .head = try Term.createAtom(alloc, "p"), .body = &body_p });

    // q :- false.
    var body_q = [_]*Term{try Term.createAtom(alloc, "false")};
    try eng.addRule(Rule{ .head = try Term.createAtom(alloc, "q"), .body = &body_q });

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // Query: ?- p.
    var goals_p = [_]*Term{try Term.createAtom(alloc, "p")};
    _ = try eng.solve(&goals_p, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "true") != null);

    // Query: ?- q.
    buf.clearRetainingCapacity();
    has_printed = false;
    var goals_q = [_]*Term{try Term.createAtom(alloc, "q")};
    _ = try eng.solve(&goals_q, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("", buf.items); // Should fail silently (no output)
}

test "Engine - arithmetic and comparison" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var eng = Engine.init(alloc);
    defer eng.deinit();
    var env = createEnv();
    defer env.deinit(alloc);
    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // X is 1 + 2.
    const X = try Term.createVariable(alloc, "X");
    const expr = try Term.createStructure(alloc, "+", &[_]*Term{ try Term.createNumber(alloc, 1), try Term.createNumber(alloc, 2) });
    const goal1 = try Term.createStructure(alloc, "is", &[_]*Term{ X, expr });

    var goals1 = [_]*Term{goal1};
    _ = try eng.solve(&goals1, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("X = 3", buf.items);

    // 3 > 2.
    buf.clearRetainingCapacity();
    env.clearRetainingCapacity();
    has_printed = false;
    const goal2 = try Term.createStructure(alloc, ">", &[_]*Term{ try Term.createNumber(alloc, 3), try Term.createNumber(alloc, 2) });
    var goals2 = [_]*Term{goal2};
    _ = try eng.solve(&goals2, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("  true.", buf.items);
}

test "Engine - missing comparisons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    var env = EnvMap{};
    defer env.deinit(alloc);

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // 3 >= 2
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, ">=", &[_]*Term{ try Term.createNumber(alloc, 3), try Term.createNumber(alloc, 2) });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.items);
    }

    // 2 >= 2
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, ">=", &[_]*Term{ try Term.createNumber(alloc, 2), try Term.createNumber(alloc, 2) });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.items);
    }

    // 2 =< 3
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "=<", &[_]*Term{ try Term.createNumber(alloc, 2), try Term.createNumber(alloc, 3) });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.items);
    }

    // a \= b
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "\\=", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createAtom(alloc, "b") });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.items);
    }

    // a \= a (should fail, so no output)
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "\\=", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createAtom(alloc, "a") });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.items);
    }
}

test "Engine - disjunction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var eng = Engine.init(alloc);
    defer eng.deinit();

    // p(a). p(b).
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "a")}), .body = &[_]*Term{} });
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "b")}), .body = &[_]*Term{} });

    // ?- p(a); p(b).
    // This is parsed as ;(p(a), p(b)).
    const pa = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "a")});
    const pb = try Term.createStructure(alloc, "p", &[_]*Term{try Term.createAtom(alloc, "b")});
    const query = try Term.createStructure(alloc, ";", &[_]*Term{ pa, pb });

    var env = createEnv();
    defer env.deinit(alloc);
    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Should print true twice (once for a, once for b)
    // Actually, since there are no variables, it prints "true." twice.
    // We can count occurrences of "true."
    var count: usize = 0;
    var it = std.mem.splitSequence(u8, buf.items, "\n");
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, "true") != null) count += 1;
    }
    try std.testing.expect(count >= 2);
}

test "Engine - recursion (length)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var eng = Engine.init(alloc);
    defer eng.deinit();

    // length([], 0).
    const empty = try Term.createAtom(alloc, "[]");
    const zero = try Term.createNumber(alloc, 0);
    const head1 = try Term.createStructure(alloc, "length", &[_]*Term{ empty, zero });
    try eng.addRule(Rule{ .head = head1, .body = &[_]*Term{} });

    // length([_|T], N) :- length(T, M), N is M + 1.
    const anon = try Term.createVariable(alloc, "_");
    const T = try Term.createVariable(alloc, "T");
    const N = try Term.createVariable(alloc, "N");
    const M = try Term.createVariable(alloc, "M");
    const list = try Term.createStructure(alloc, ".", &[_]*Term{ anon, T });

    const head2 = try Term.createStructure(alloc, "length", &[_]*Term{ list, N });
    const b1 = try Term.createStructure(alloc, "length", &[_]*Term{ T, M });
    const expr = try Term.createStructure(alloc, "+", &[_]*Term{ M, try Term.createNumber(alloc, 1) });
    const b2 = try Term.createStructure(alloc, "is", &[_]*Term{ N, expr });

    var body2 = [_]*Term{ b1, b2 };
    try eng.addRule(Rule{ .head = head2, .body = &body2 });

    // ?- length([a, b], X).
    // [a, b] -> .(a, .(b, []))
    const l = try Term.createStructure(alloc, ".", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createStructure(alloc, ".", &[_]*Term{ try Term.createAtom(alloc, "b"), empty }) });
    const X = try Term.createVariable(alloc, "X");
    const query = try Term.createStructure(alloc, "length", &[_]*Term{ l, X });

    var env = createEnv();
    defer env.deinit(alloc);
    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf.items, "X = 2") != null);
}

test "Engine - DCG Advanced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const Parser = @import("parser.zig").Parser;

    var engine = Engine.init(alloc);
    defer engine.deinit();

    // Advanced DCG: Agreement
    // s(N) --> np(N), vp(N).
    // np(sg) --> [the], [cat].
    // np(pl) --> [the], [cats].
    // vp(sg) --> [sleeps].
    // vp(pl) --> [sleep].
    {
        var p1 = Parser.init(alloc, "s(N) --> np(N), vp(N).");
        try engine.addRule(try p1.parseRule());

        var p2 = Parser.init(alloc, "np(sg) --> [the], [cat].");
        try engine.addRule(try p2.parseRule());

        var p3 = Parser.init(alloc, "np(pl) --> [the], [cats].");
        try engine.addRule(try p3.parseRule());

        var p4 = Parser.init(alloc, "vp(sg) --> [sleeps].");
        try engine.addRule(try p4.parseRule());

        var p5 = Parser.init(alloc, "vp(pl) --> [sleep].");
        try engine.addRule(try p5.parseRule());

        // phrase(s(X), [the, cat, sleeps]). -> X = sg
        {
            const source = "phrase(s(X), [the, cat, sleeps]).";
            var parser = Parser.init(alloc, source);
            const goals = try parser.parseQuery();

            var has_printed = false;
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(alloc);
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expect(std.mem.indexOf(u8, buf.items, "X = sg") != null);
        }

        // phrase(s(X), [the, cats, sleep]). -> X = pl
        {
            const source = "phrase(s(X), [the, cats, sleep]).";
            var parser = Parser.init(alloc, source);
            const goals = try parser.parseQuery();

            var has_printed = false;
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(alloc);
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expect(std.mem.indexOf(u8, buf.items, "X = pl") != null);
        }

        // phrase(s(X), [the, cat, sleep]). -> Fail
        {
            const source = "phrase(s(X), [the, cat, sleep]).";
            var parser = Parser.init(alloc, source);
            const goals = try parser.parseQuery();

            var has_printed = false;
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(alloc);
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expectEqual(0, buf.items.len);
        }
    }
}

test "Engine - stack overflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // loop :- loop.
    const loop_head = try Term.createAtom(alloc, "loop");
    var loop_body = [_]*Term{try Term.createAtom(alloc, "loop")};
    try eng.addRule(Rule{ .head = loop_head, .body = &loop_body });

    // ?- loop.
    const query = try Term.createAtom(alloc, "loop");
    var goals = [_]*Term{query};

    var env = EnvMap{};
    defer env.deinit(alloc);

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    const res = eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectError(error.StackOverflow, res);
}

test "Engine - phrase/3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // s --> [a], [b].
    var parser = Parser.init(alloc, "s --> [a], [b].");
    const rule = try parser.parseRule();
    try eng.addRule(rule);

    // ?- phrase(s, [a, b, c], [c]).
    // Should succeed.
    var parser_query = Parser.init(alloc, "phrase(s, [a, b, c], [c]).");
    const goals = try parser_query.parseQuery();

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var env = EnvMap{};
    defer env.deinit(alloc);

    _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("  true.", buf.items);
}

test "Engine - DCG bug reproduction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // sentence --> noun_phrase, verb_phrase.
    // noun_phrase --> det, noun.
    // verb_phrase --> verb, noun_phrase.
    // det --> [the].
    // noun --> [cat].
    // verb --> [eats].

    const rules = [_][]const u8{
        "sentence --> noun_phrase, verb_phrase.",
        "noun_phrase --> det, noun.",
        "verb_phrase --> verb, noun_phrase.",
        "det --> [the].",
        "noun --> [cat].",
        "verb --> [eats].",
    };

    for (rules) |r| {
        var p = Parser.init(alloc, r);
        try eng.addRule(try p.parseRule());
    }

    // ?- sentence(X, []).
    var parser_query = Parser.init(alloc, "sentence(X, []).");
    const goals = try parser_query.parseQuery();

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var env = EnvMap{};
    defer env.deinit(alloc);

    _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));

    // We expect X to be fully instantiated.
    // X = [the, cat, eats, the, cat]
    // The output format might be:
    // X = [the, cat, eats, the, cat]
    // or
    // X = [the|[cat|[eats|[the|[cat|[]]]]]]

    // Let's just check if it contains "cat" and "eats".
    // If it's [the|Var], it won't contain "eats".
    if (std.mem.indexOf(u8, buf.items, "eats") == null) {
        std.debug.print("\nOUTPUT: {s}\n", .{buf.items});
        return error.TestFailed;
    }
}

test "Engine - negation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // p(a).
    // q(b).
    var p1 = Parser.init(alloc, "p(a).");
    try eng.addRule(try p1.parseRule());
    var p2 = Parser.init(alloc, "q(b).");
    try eng.addRule(try p2.parseRule());

    // ?- \+ p(a). -> false
    {
        var parser_query = Parser.init(alloc, "\\+ p(a).");
        const goals = try parser_query.parseQuery();
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.items); // No output means false
    }

    // ?- \+ p(b). -> true
    {
        var parser_query = Parser.init(alloc, "\\+ p(b).");
        const goals = try parser_query.parseQuery();
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.items);
    }

    // ?- not(p(a)). -> false
    {
        var parser_query = Parser.init(alloc, "not(p(a)).");
        const goals = try parser_query.parseQuery();
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.items);
    }
}

test "Engine - indexing benchmark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add 1000 parent facts with different first arguments
    // parent(person_0, child_0). parent(person_1, child_1). ... parent(person_999, child_999).
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const parent_name = try std.fmt.allocPrint(alloc, "person_{d}", .{i});
        const child_name = try std.fmt.allocPrint(alloc, "child_{d}", .{i});
        const head = try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createAtom(alloc, parent_name),
            try Term.createAtom(alloc, child_name),
        });
        try eng.addRule(Rule{ .head = head, .body = &[_]*Term{} });
    }

    // Query: ?- parent(person_500, X).
    // With indexing, this should only check 1 clause instead of 1000
    const query = try Term.createStructure(alloc, "parent", &[_]*Term{
        try Term.createAtom(alloc, "person_500"),
        try Term.createVariable(alloc, "X"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var has_printed = false;
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Verify that we found the correct solution
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "X = child_500") != null);

    // The real benefit is in performance: with 1000 clauses, indexing makes this O(1) instead of O(N)
    // Without indexing, we would scan all 1000 clauses. With indexing, we check only 1.
}

test "Engine - choice point elimination" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Deterministic predicate - only one clause
    const unique_head = try Term.createStructure(alloc, "unique", &[_]*Term{try Term.createAtom(alloc, "alice")});
    try eng.addRule(Rule{ .head = unique_head, .body = &[_]*Term{} });

    // Non-deterministic predicate - multiple clauses
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createAtom(alloc, "bob")}), .body = &[_]*Term{} });
    try eng.addRule(Rule{ .head = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createAtom(alloc, "charlie")}), .body = &[_]*Term{} });

    // Query deterministic predicate
    const query_unique = try Term.createStructure(alloc, "unique", &[_]*Term{try Term.createAtom(alloc, "alice")});

    var env1 = createEnv();
    defer env1.deinit(alloc);

    var has_printed1 = false;
    var buf1 = std.ArrayListUnmanaged(u8){};
    defer buf1.deinit(alloc);

    var ctx1 = TestHandlerContext{ .buf = &buf1, .alloc = alloc, .has_printed = &has_printed1 };
    const handler1 = Engine.SolutionHandler{ .context = &ctx1, .handle = testHandle };

    var goals1 = [_]*Term{query_unique};
    _ = try eng.solve(&goals1, &env1, 0, 0, handler1, buf1.writer(alloc));

    // Should succeed with "true"
    try std.testing.expect(std.mem.indexOf(u8, buf1.items, "true") != null);

    // Query non-deterministic predicate
    const query_person = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createVariable(alloc, "X")});

    var env2 = createEnv();
    defer env2.deinit(alloc);

    var has_printed2 = false;
    var buf2 = std.ArrayListUnmanaged(u8){};
    defer buf2.deinit(alloc);

    var ctx2 = TestHandlerContext{ .buf = &buf2, .alloc = alloc, .has_printed = &has_printed2 };
    const handler2 = Engine.SolutionHandler{ .context = &ctx2, .handle = testHandle };

    var goals2 = [_]*Term{query_person};
    _ = try eng.solve(&goals2, &env2, 0, 0, handler2, buf2.writer(alloc));

    // Should have two solutions
    try std.testing.expect(std.mem.indexOf(u8, buf2.items, "X = bob") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf2.items, "X = charlie") != null);

    // The optimization: deterministic queries skip environment cloning
    // For non-deterministic queries, environments are cloned for backtracking
}

test "Engine - arithmetic operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test div (floored division)
    // 7 div 3 = 2, -7 div 3 = -3 (rounds towards -infinity)
    var env1 = createEnv();
    const expr1 = try Term.createStructure(alloc, "is", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createStructure(alloc, "div", &[_]*Term{
            try Term.createNumber(alloc, 7),
            try Term.createNumber(alloc, 3),
        }),
    });
    const result1 = try evaluate(expr1.structure.args[1], &env1);
    try std.testing.expect(result1.isInt());
    try std.testing.expectEqual(@as(i64, 2), result1.int);

    // Test mod (modulo with floored division)
    // 7 mod 3 = 1, -7 mod 3 = 2
    const expr2 = try Term.createStructure(alloc, "mod", &[_]*Term{
        try Term.createNumber(alloc, 7),
        try Term.createNumber(alloc, 3),
    });
    const result2 = try evaluate(expr2, &env1);
    try std.testing.expect(result2.isInt());
    try std.testing.expectEqual(@as(i64, 1), result2.int);

    const expr3 = try Term.createStructure(alloc, "mod", &[_]*Term{
        try Term.createNumber(alloc, -7),
        try Term.createNumber(alloc, 3),
    });
    const result3 = try evaluate(expr3, &env1);
    try std.testing.expect(result3.isInt());
    try std.testing.expectEqual(@as(i64, 2), result3.int);

    // Test rem (remainder with truncated division)
    // 7 rem 3 = 1, -7 rem 3 = -1
    const expr4 = try Term.createStructure(alloc, "rem", &[_]*Term{
        try Term.createNumber(alloc, 7),
        try Term.createNumber(alloc, 3),
    });
    const result4 = try evaluate(expr4, &env1);
    try std.testing.expect(result4.isInt());
    try std.testing.expectEqual(@as(i64, 1), result4.int);

    const expr5 = try Term.createStructure(alloc, "rem", &[_]*Term{
        try Term.createNumber(alloc, -7),
        try Term.createNumber(alloc, 3),
    });
    const result5 = try evaluate(expr5, &env1);
    try std.testing.expect(result5.isInt());
    try std.testing.expectEqual(@as(i64, -1), result5.int);

    // Test abs
    const expr6 = try Term.createStructure(alloc, "abs", &[_]*Term{
        try Term.createNumber(alloc, -42),
    });
    const result6 = try evaluate(expr6, &env1);
    try std.testing.expect(result6.isInt());
    try std.testing.expectEqual(@as(i64, 42), result6.int);

    // Test sign
    const expr7 = try Term.createStructure(alloc, "sign", &[_]*Term{
        try Term.createNumber(alloc, -42),
    });
    const result7 = try evaluate(expr7, &env1);
    try std.testing.expect(result7.isInt());
    try std.testing.expectEqual(@as(i64, -1), result7.int);

    const expr8 = try Term.createStructure(alloc, "sign", &[_]*Term{
        try Term.createNumber(alloc, 42),
    });
    const result8 = try evaluate(expr8, &env1);
    try std.testing.expect(result8.isInt());
    try std.testing.expectEqual(@as(i64, 1), result8.int);

    const expr9 = try Term.createStructure(alloc, "sign", &[_]*Term{
        try Term.createNumber(alloc, 0),
    });
    const result9 = try evaluate(expr9, &env1);
    try std.testing.expect(result9.isInt());
    try std.testing.expectEqual(@as(i64, 0), result9.int);

    // Test min/max
    const expr10 = try Term.createStructure(alloc, "min", &[_]*Term{
        try Term.createNumber(alloc, 5),
        try Term.createNumber(alloc, 10),
    });
    const result10 = try evaluate(expr10, &env1);
    try std.testing.expect(result10.isInt());
    try std.testing.expectEqual(@as(i64, 5), result10.int);

    const expr11 = try Term.createStructure(alloc, "max", &[_]*Term{
        try Term.createNumber(alloc, 5),
        try Term.createNumber(alloc, 10),
    });
    const result11 = try evaluate(expr11, &env1);
    try std.testing.expect(result11.isInt());
    try std.testing.expectEqual(@as(i64, 10), result11.int);

    // Test // (integer division, same as truncating)
    const expr12 = try Term.createStructure(alloc, "//", &[_]*Term{
        try Term.createNumber(alloc, 7),
        try Term.createNumber(alloc, 3),
    });
    const result12 = try evaluate(expr12, &env1);
    try std.testing.expect(result12.isInt());
    try std.testing.expectEqual(@as(i64, 2), result12.int);
}

test "Engine - arithmetic comparison operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Test =:= (arithmetic equality)
    const query1 = try Term.createStructure(alloc, "=:=", &[_]*Term{
        try Term.createStructure(alloc, "+", &[_]*Term{
            try Term.createNumber(alloc, 2),
            try Term.createNumber(alloc, 3),
        }),
        try Term.createNumber(alloc, 5),
    });

    var env1 = createEnv();
    defer env1.deinit(alloc);

    var has_printed1 = false;
    var buf1 = std.ArrayListUnmanaged(u8){};
    defer buf1.deinit(alloc);

    var ctx1 = TestHandlerContext{ .buf = &buf1, .alloc = alloc, .has_printed = &has_printed1 };
    const handler1 = Engine.SolutionHandler{ .context = &ctx1, .handle = testHandle };

    var goals1 = [_]*Term{query1};
    _ = try eng.solve(&goals1, &env1, 0, 0, handler1, buf1.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf1.items, "true") != null);

    // Test =\= (arithmetic inequality)
    const query2 = try Term.createStructure(alloc, "=\\=", &[_]*Term{
        try Term.createStructure(alloc, "+", &[_]*Term{
            try Term.createNumber(alloc, 2),
            try Term.createNumber(alloc, 3),
        }),
        try Term.createNumber(alloc, 6),
    });

    var env2 = createEnv();
    defer env2.deinit(alloc);

    var has_printed2 = false;
    var buf2 = std.ArrayListUnmanaged(u8){};
    defer buf2.deinit(alloc);

    var ctx2 = TestHandlerContext{ .buf = &buf2, .alloc = alloc, .has_printed = &has_printed2 };
    const handler2 = Engine.SolutionHandler{ .context = &ctx2, .handle = testHandle };

    var goals2 = [_]*Term{query2};
    _ = try eng.solve(&goals2, &env2, 0, 0, handler2, buf2.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf2.items, "true") != null);
}

test "Engine - float arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var env = createEnv();

    // Test float literal
    const float_expr = try Term.createFloat(alloc, 3.14);
    const result1 = try evaluate(float_expr, &env);
    try std.testing.expect(!result1.isInt());
    try std.testing.expectEqual(@as(f64, 3.14), result1.float);

    // Test float addition
    const add_expr = try Term.createStructure(alloc, "+", &[_]*Term{
        try Term.createFloat(alloc, 2.5),
        try Term.createFloat(alloc, 1.5),
    });
    const result2 = try evaluate(add_expr, &env);
    try std.testing.expect(!result2.isInt());
    try std.testing.expectEqual(@as(f64, 4.0), result2.float);

    // Test mixed int/float addition (should return float)
    const mixed_add = try Term.createStructure(alloc, "+", &[_]*Term{
        try Term.createNumber(alloc, 2),
        try Term.createFloat(alloc, 1.5),
    });
    const result3 = try evaluate(mixed_add, &env);
    try std.testing.expect(!result3.isInt());
    try std.testing.expectEqual(@as(f64, 3.5), result3.float);

    // Test float subtraction
    const sub_expr = try Term.createStructure(alloc, "-", &[_]*Term{
        try Term.createFloat(alloc, 5.5),
        try Term.createFloat(alloc, 2.5),
    });
    const result4 = try evaluate(sub_expr, &env);
    try std.testing.expect(!result4.isInt());
    try std.testing.expectEqual(@as(f64, 3.0), result4.float);

    // Test float multiplication
    const mul_expr = try Term.createStructure(alloc, "*", &[_]*Term{
        try Term.createFloat(alloc, 2.5),
        try Term.createFloat(alloc, 4.0),
    });
    const result5 = try evaluate(mul_expr, &env);
    try std.testing.expect(!result5.isInt());
    try std.testing.expectEqual(@as(f64, 10.0), result5.float);

    // Test float division (always returns float)
    const div_expr = try Term.createStructure(alloc, "/", &[_]*Term{
        try Term.createNumber(alloc, 7),
        try Term.createNumber(alloc, 2),
    });
    const result6 = try evaluate(div_expr, &env);
    try std.testing.expect(!result6.isInt());
    try std.testing.expectEqual(@as(f64, 3.5), result6.float);

    // Test abs with float
    const abs_float = try Term.createStructure(alloc, "abs", &[_]*Term{
        try Term.createFloat(alloc, -3.14),
    });
    const result7 = try evaluate(abs_float, &env);
    try std.testing.expect(!result7.isInt());
    try std.testing.expectEqual(@as(f64, 3.14), result7.float);

    // Test sign with float
    const sign_float = try Term.createStructure(alloc, "sign", &[_]*Term{
        try Term.createFloat(alloc, -3.14),
    });
    const result8 = try evaluate(sign_float, &env);
    try std.testing.expect(!result8.isInt());
    try std.testing.expectEqual(@as(f64, -1.0), result8.float);

    // Test min with mixed types
    const min_mixed = try Term.createStructure(alloc, "min", &[_]*Term{
        try Term.createFloat(alloc, 5.5),
        try Term.createNumber(alloc, 10),
    });
    const result9 = try evaluate(min_mixed, &env);
    try std.testing.expect(!result9.isInt());
    try std.testing.expectEqual(@as(f64, 5.5), result9.float);

    // Test max with mixed types
    const max_mixed = try Term.createStructure(alloc, "max", &[_]*Term{
        try Term.createFloat(alloc, 5.5),
        try Term.createNumber(alloc, 3),
    });
    const result10 = try evaluate(max_mixed, &env);
    try std.testing.expect(!result10.isInt());
    try std.testing.expectEqual(@as(f64, 5.5), result10.float);
}

test "Engine - format predicates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Test format/1 with no arguments
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Hello, World!~n"),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Hello, World!\n") != null);
    }

    // Test format/2 with ~w (write)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Value: ~w~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createNumber(alloc, 42),
                try Term.createAtom(alloc, "[]"),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Value: 42\n") != null);
    }

    // Test format/2 with ~d (decimal)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Number: ~d~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createNumber(alloc, 123),
                try Term.createAtom(alloc, "[]"),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Number: 123\n") != null);
    }

    // Test format/2 with ~f (float)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Float: ~f~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createFloat(alloc, 3.14),
                try Term.createAtom(alloc, "[]"),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Float: 3.14") != null);
    }

    // Test format/2 with ~a (atom)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Atom: ~a~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createAtom(alloc, "hello"),
                try Term.createAtom(alloc, "[]"),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Atom: hello\n") != null);
    }

    // Test format/2 with ~s (string)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "String: ~s~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createString(alloc, "world"),
                try Term.createAtom(alloc, "[]"),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "String: world\n") != null);
    }

    // Test format/2 with multiple arguments
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "~a = ~d, ~a = ~f~n"),
            try Term.createStructure(alloc, ".", &[_]*Term{
                try Term.createAtom(alloc, "x"),
                try Term.createStructure(alloc, ".", &[_]*Term{
                    try Term.createNumber(alloc, 10),
                    try Term.createStructure(alloc, ".", &[_]*Term{
                        try Term.createAtom(alloc, "y"),
                        try Term.createStructure(alloc, ".", &[_]*Term{
                            try Term.createFloat(alloc, 2.5),
                            try Term.createAtom(alloc, "[]"),
                        }),
                    }),
                }),
            }),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "x = 10, y = 2.5\n") != null);
    }

    // Test format with escaped tilde (~~)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Tilde: ~~~n"),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.items, "Tilde: ~\n") != null);
    }
}
