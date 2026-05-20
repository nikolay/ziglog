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
    NegationFound, // Used internally for negation-as-failure
    ConditionSucceeded, // Used internally for if-then-else
    SystemResources, // For I/O operations (write, format)
    WriteFailed,
};

pub const RuleList = ArrayListUnmanaged(Rule);
pub const EnvMap = StringHashMapUnmanaged(*Term);

pub fn createEnv() EnvMap {
    return .{};
}

/// Evaluate an arithmetic expression term.
/// Delegates to the arithmetic module for actual evaluation.
fn evaluate(term: *Term, env: *EnvMap) !NumericValue {
    return arithmetic.evaluate(term, env, resolve);
}

/// Dereference a term by following variable bindings in the environment.
/// If the term is a variable bound to another term, recursively resolves
/// until reaching an unbound variable or a non-variable term.
/// Returns the most dereferenced form of the term.
pub fn resolve(term: *Term, env: *EnvMap) *Term {
    if (term.* == .variable) {
        if (env.get(term.variable)) |bound_term| {
            return resolve(bound_term, env);
        }
    }
    return term;
}

/// Type testing predicate result.
/// Used by checkTypePredicate to indicate which type test to perform.
const TypeTestKind = enum {
    var_test,
    nonvar,
    atom,
    integer,
    float_test,
    number,
    atomic,
    compound,
    callable,
    ground,
    acyclic_term,
    not_type_test,
};

/// Determine which type-testing predicate (if any) a functor represents.
/// Returns .not_type_test if the functor is not a type-testing predicate.
fn getTypeTestKind(functor: []const u8) TypeTestKind {
    // Using a simple lookup - could use a hash table for more predicates
    if (std.mem.eql(u8, functor, "var")) return .var_test;
    if (std.mem.eql(u8, functor, "nonvar")) return .nonvar;
    if (std.mem.eql(u8, functor, "atom")) return .atom;
    if (std.mem.eql(u8, functor, "integer")) return .integer;
    if (std.mem.eql(u8, functor, "float")) return .float_test;
    if (std.mem.eql(u8, functor, "number")) return .number;
    if (std.mem.eql(u8, functor, "atomic")) return .atomic;
    if (std.mem.eql(u8, functor, "compound")) return .compound;
    if (std.mem.eql(u8, functor, "callable")) return .callable;
    if (std.mem.eql(u8, functor, "ground")) return .ground;
    if (std.mem.eql(u8, functor, "acyclic_term")) return .acyclic_term;
    return .not_type_test;
}

/// Check if a term satisfies a type-testing predicate.
/// Returns true if the term matches the type test, false otherwise.
/// For ground/1 and acyclic_term/1, additional traversal is required.
fn checkTypeTest(alloc: Allocator, kind: TypeTestKind, term: *Term, env: *EnvMap) bool {
    return switch (kind) {
        .var_test => term.* == .variable,
        .nonvar => term.* != .variable,
        .atom => term.* == .atom,
        .integer => term.* == .number,
        .float_test => term.* == .float,
        .number => term.* == .number or term.* == .float,
        .atomic => term.* == .atom or term.* == .number or term.* == .float,
        .compound => term.* == .structure,
        .callable => term.* == .atom or term.* == .structure,
        .ground => isGroundTerm(term, env),
        .acyclic_term => blk: {
            var visited = StringHashMapUnmanaged(void){};
            defer visited.deinit(alloc);
            break :blk isAcyclicTerm(alloc, term, env, &visited) catch false;
        },
        .not_type_test => false,
    };
}

/// Check if a variable occurs in a term (for occurs check during unification).
/// Returns true if the variable with name `var_name` appears anywhere in `term`
/// after resolving it in the environment.
fn occursIn(var_name: []const u8, term: *Term, env: *EnvMap) bool {
    const resolved = resolve(term, env);

    switch (resolved.*) {
        .variable => |name| return std.mem.eql(u8, var_name, name),
        .atom, .number, .float, .string => return false,
        .structure => |s| {
            for (s.args) |arg| {
                if (occursIn(var_name, arg, env)) return true;
            }
            return false;
        },
    }
}

/// Check if a term is ground (contains no unbound variables).
/// Returns true if the term contains no variables.
fn isGroundTerm(term: *Term, env: *EnvMap) bool {
    const resolved = resolve(term, env);

    switch (resolved.*) {
        .variable => return false,
        .atom, .number, .float, .string => return true,
        .structure => |s| {
            for (s.args) |arg| {
                if (!isGroundTerm(arg, env)) return false;
            }
            return true;
        },
    }
}

/// Check if a term is acyclic (contains no cycles).
/// Uses a visited set to detect cycles during traversal.
/// Returns true if the term is acyclic (no cycles found).
fn isAcyclicTerm(alloc: Allocator, term: *Term, env: *EnvMap, visited: *StringHashMapUnmanaged(void)) !bool {
    const resolved = resolve(term, env);

    // Use pointer address as unique identifier to detect if we've seen this exact term before
    const term_addr = @intFromPtr(resolved);
    const addr_str = try std.fmt.allocPrint(alloc, "{d}", .{term_addr});
    defer alloc.free(addr_str);

    // If we've already visited this term pointer, we have a cycle
    if (visited.contains(addr_str)) return false;

    // Mark this term as visited
    try visited.put(alloc, addr_str, {});
    defer _ = visited.remove(addr_str); // Remove after checking children (for proper traversal)

    switch (resolved.*) {
        .atom, .number, .float, .string => return true,
        .variable => return true, // Unbound variable is acyclic
        .structure => |s| {
            // Check all arguments for cycles
            for (s.args) |arg| {
                if (!try isAcyclicTerm(alloc, arg, env, visited)) return false;
            }
            return true;
        },
    }
}

/// Copy a term with fresh variables.
/// Creates a deep copy of the term, replacing all variables with new unique variables.
/// Non-variable terms (atoms, numbers, floats, strings) are shared.
/// Used by term_variables/2 to collect all unique variables from a term.
/// Variables are collected in depth-first, left-to-right order without duplicates.
/// The variables in the result share with (are the same as) the variables in the original term.
fn collectTermVariables(alloc: Allocator, term: *Term, env: *EnvMap, var_list: *ArrayListUnmanaged(*Term), seen_vars: *StringHashMapUnmanaged(void)) !void {
    const resolved = resolve(term, env);

    switch (resolved.*) {
        .atom, .number, .float, .string => {
            // Non-variable terms have no variables
            return;
        },
        .variable => |name| {
            // Only add if we haven't seen this variable before
            if (!seen_vars.contains(name)) {
                try seen_vars.put(alloc, name, {});
                try var_list.append(alloc, resolved);
            }
        },
        .structure => |s| {
            // Recursively collect from all arguments (depth-first, left-to-right)
            for (s.args) |arg| {
                try collectTermVariables(alloc, arg, env, var_list, seen_vars);
            }
        },
    }
}

/// Used by copy_term/2 to create a copy with renamed variables.
fn copyTermWithFreshVars(alloc: Allocator, term: *Term, env: *EnvMap, var_map: *StringHashMapUnmanaged(*Term), counter: *usize) !*Term {
    const resolved = resolve(term, env);

    switch (resolved.*) {
        .atom, .number, .float, .string => {
            // Non-variable terms are shared (not copied)
            return resolved;
        },
        .variable => |name| {
            // Check if we've already created a fresh variable for this one
            if (var_map.get(name)) |fresh_var| {
                return fresh_var;
            }
            // Create a new fresh variable
            const fresh_name = try std.fmt.allocPrint(alloc, "_G{d}", .{counter.*});
            counter.* += 1;
            const fresh_var = try Term.createVariable(alloc, fresh_name);
            try var_map.put(alloc, name, fresh_var);
            return fresh_var;
        },
        .structure => |s| {
            // Recursively copy arguments
            var new_args = try alloc.alloc(*Term, s.args.len);
            for (s.args, 0..) |arg, i| {
                new_args[i] = try copyTermWithFreshVars(alloc, arg, env, var_map, counter);
            }
            return try Term.createStructure(alloc, s.functor, new_args);
        },
    }
}

/// Internal unification implementation.
/// When `with_occurs_check` is true, prevents creating cyclic structures like X = f(X).
/// Returns true if unification succeeds.
fn unifyInternal(alloc: Allocator, t1: *Term, t2: *Term, env: *EnvMap, comptime with_occurs_check: bool) bool {
    const r1 = resolve(t1, env);
    const r2 = resolve(t2, env);

    // Same term (pointer equality after resolution)
    if (r1 == r2) return true;

    // Variable binding cases
    if (r1.* == .variable) {
        if (with_occurs_check and occursIn(r1.variable, r2, env)) return false;
        env.put(alloc, r1.variable, t2) catch return false;
        return true;
    }
    if (r2.* == .variable) {
        if (with_occurs_check and occursIn(r2.variable, r1, env)) return false;
        env.put(alloc, r2.variable, t1) catch return false;
        return true;
    }

    // Atomic term comparisons
    if (r1.* == .number and r2.* == .number) return r1.number == r2.number;
    if (r1.* == .float and r2.* == .float) return r1.float == r2.float;
    if (r1.* == .atom and r2.* == .atom) return std.mem.eql(u8, r1.atom, r2.atom);
    if (r1.* == .string and r2.* == .string) return std.mem.eql(u8, r1.string, r2.string);

    // Structure unification
    if (r1.* == .structure and r2.* == .structure) {
        const s1 = r1.structure;
        const s2 = r2.structure;
        if (!std.mem.eql(u8, s1.functor, s2.functor)) return false;
        if (s1.args.len != s2.args.len) return false;
        for (s1.args, 0..) |arg1, i| {
            if (!unifyInternal(alloc, arg1, s2.args[i], env, with_occurs_check)) return false;
        }
        return true;
    }

    return false;
}

/// Unify two terms without occurs check.
/// This is the standard Prolog unification - faster but can create cyclic terms.
pub fn unify(alloc: Allocator, t1: *Term, t2: *Term, env: *EnvMap) bool {
    return unifyInternal(alloc, t1, t2, env, false);
}

/// Unify two terms with occurs check.
/// Prevents creating cyclic structures like X = f(X).
/// Returns true if unification succeeds without creating cycles.
/// Used by unify_with_occurs_check/2 predicate.
pub fn unifyWithOccursCheck(alloc: Allocator, t1: *Term, t2: *Term, env: *EnvMap) bool {
    return unifyInternal(alloc, t1, t2, env, true);
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
            var new_args = ArrayListUnmanaged(*Term).empty;
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

/// The Prolog execution engine.
/// Implements SLD resolution with backtracking for query evaluation.
/// Uses first-argument indexing for efficient clause lookup.
pub const Engine = struct {
    /// Memory allocator for term and environment allocation
    alloc: Allocator,
    /// Database of Prolog clauses (facts and rules)
    db: RuleList,
    /// First-argument index for O(1) clause lookup
    index: ClauseIndex,

    /// Maximum recursion depth to prevent stack overflow
    const MAX_DEPTH = 200;

    /// Create a new Prolog engine with the given allocator.
    pub fn init(alloc: Allocator) Engine {
        return Engine{
            .alloc = alloc,
            .db = RuleList.empty,
            .index = ClauseIndex.init(alloc),
        };
    }

    /// Release all resources associated with the engine.
    pub fn deinit(self: *Engine) void {
        self.db.deinit(self.alloc);
        self.index.deinit();
    }

    /// Add a rule (fact or clause) to the database.
    /// Also updates the first-argument index for efficient lookup.
    pub fn addRule(self: *Engine, rule: Rule) !void {
        const clause_idx = self.db.items.len;
        try self.db.append(self.alloc, rule);
        try self.index.addClause(clause_idx, rule);
    }

    /// Assert a clause dynamically at runtime.
    /// If add_first is true, adds to the beginning (asserta), otherwise to end (assertz).
    fn assertClause(self: *Engine, clause_term: *Term, add_first: bool) !void {
        // Parse the clause term into head and body
        var head: *Term = undefined;
        var body: []*Term = &[_]*Term{};

        if (clause_term.* == .structure and std.mem.eql(u8, clause_term.structure.functor, ":-") and clause_term.structure.args.len == 2) {
            // Rule: Head :- Body
            head = clause_term.structure.args[0];

            // Convert body to array of goals
            var body_list = ArrayListUnmanaged(*Term).empty;
            try self.termToGoals(clause_term.structure.args[1], &body_list);
            body = try body_list.toOwnedSlice(self.alloc);
        } else {
            // Fact: just the head
            head = clause_term;
        }

        const rule = Rule{ .head = head, .body = body };

        if (add_first) {
            // Add to beginning
            try self.db.insert(self.alloc, 0, rule);
        } else {
            // Add to end
            try self.db.append(self.alloc, rule);
        }

        // Rebuild index after modification
        try self.rebuildIndex();
    }

    /// Convert a term to a list of goals by flattening conjunctions.
    /// The term `(a, b, c)` becomes the goal list `[a, b, c]`.
    fn termToGoals(self: *Engine, term: *Term, goals: *ArrayListUnmanaged(*Term)) !void {
        if (term.* == .structure and std.mem.eql(u8, term.structure.functor, ",") and term.structure.args.len == 2) {
            // Conjunction - recursively flatten
            try self.termToGoals(term.structure.args[0], goals);
            try self.termToGoals(term.structure.args[1], goals);
        } else {
            // Single goal
            try goals.append(self.alloc, term);
        }
    }

    /// Rebuild the clause index after database modifications.
    /// Required after assert/retract operations to maintain index consistency.
    fn rebuildIndex(self: *Engine) !void {
        self.index.deinit();
        self.index = ClauseIndex.init(self.alloc);

        for (self.db.items, 0..) |rule, idx| {
            try self.index.addClause(idx, rule);
        }
    }

    /// Convert a rule back to a term for unification (used by clause/2).
    fn ruleToTerm(self: *Engine, rule: Rule) !*Term {
        if (rule.body.len == 0) {
            // Fact - just return the head
            return rule.head;
        } else {
            // Rule - create Head :- Body
            const body_term = try self.goalsToTerm(rule.body);
            return try Term.createStructure(self.alloc, ":-", &[_]*Term{ rule.head, body_term });
        }
    }

    /// Convert body goals to a conjunction term: [a, b, c] -> (a, (b, c)).
    fn goalsToTerm(self: *Engine, body_goals: []*Term) !*Term {
        if (body_goals.len == 0) {
            return try Term.createAtom(self.alloc, "true");
        } else if (body_goals.len == 1) {
            return body_goals[0];
        } else {
            // Create right-associative conjunction: a, (b, (c, d))
            var result = body_goals[body_goals.len - 1];
            var i = body_goals.len - 1;
            while (i > 0) {
                i -= 1;
                result = try Term.createStructure(self.alloc, ",", &[_]*Term{ body_goals[i], result });
            }
            return result;
        }
    }

    /// Convert body array to term for clause/2 (empty body becomes 'true').
    fn bodyToTerm(self: *Engine, body_goals: []*Term) !*Term {
        if (body_goals.len == 0) {
            return try Term.createAtom(self.alloc, "true");
        } else {
            return try self.goalsToTerm(body_goals);
        }
    }

    /// Convert array of terms to Prolog list: [a, b, c] -> [a|[b|[c|[]]]].
    fn termsToList(self: *Engine, terms: []*Term) !*Term {
        var result = try Term.createAtom(self.alloc, "[]");

        // Build list from right to left
        var i = terms.len;
        while (i > 0) {
            i -= 1;
            result = try Term.createStructure(self.alloc, ".", &[_]*Term{ terms[i], result });
        }

        return result;
    }

    /// Sort terms in-place using ISO Prolog standard term ordering.
    fn sortTerms(self: *Engine, terms: []*Term) !void {
        // Simple bubble sort (good enough for small lists)
        // Standard term ordering: var < number < atom < string < structure
        const len = terms.len;
        if (len <= 1) return;

        var i: usize = 0;
        while (i < len - 1) : (i += 1) {
            var j: usize = 0;
            while (j < len - i - 1) : (j += 1) {
                if (try self.compareTerms(terms[j], terms[j + 1]) > 0) {
                    // Swap
                    const temp = terms[j];
                    terms[j] = terms[j + 1];
                    terms[j + 1] = temp;
                }
            }
        }
    }

    /// Compare two terms using ISO Prolog standard term ordering.
    /// Returns: <0 if t1 < t2, 0 if t1 == t2, >0 if t1 > t2.
    /// Order: variable < number < atom < string < structure.
    fn compareTerms(_: *Engine, t1: *Term, t2: *Term) !i32 {
        // ISO Prolog standard term ordering: variable < number < atom < string < structure
        // TermType enum order: atom(0), variable(1), structure(2), number(3), float(4), string(5)

        const type_order = [_]i32{ 2, 0, 4, 1, 1, 3 }; // indexed by TermType enum
        const t1_order = type_order[@intFromEnum(t1.*)];
        const t2_order = type_order[@intFromEnum(t2.*)];

        if (t1_order != t2_order) {
            return t1_order - t2_order;
        }

        // Same type - compare within type
        switch (t1.*) {
            .variable => |v1| {
                const v2 = t2.variable;
                return if (std.mem.order(u8, v1, v2) == .lt) @as(i32, -1) else if (std.mem.order(u8, v1, v2) == .gt) @as(i32, 1) else @as(i32, 0);
            },
            .number => |n1| {
                const n2 = t2.number;
                return if (n1 < n2) @as(i32, -1) else if (n1 > n2) @as(i32, 1) else @as(i32, 0);
            },
            .float => |f1| {
                const f2 = t2.float;
                return if (f1 < f2) @as(i32, -1) else if (f1 > f2) @as(i32, 1) else @as(i32, 0);
            },
            .atom => |a1| {
                const a2 = t2.atom;
                return if (std.mem.order(u8, a1, a2) == .lt) @as(i32, -1) else if (std.mem.order(u8, a1, a2) == .gt) @as(i32, 1) else @as(i32, 0);
            },
            .string => |s1| {
                const s2 = t2.string;
                return if (std.mem.order(u8, s1, s2) == .lt) @as(i32, -1) else if (std.mem.order(u8, s1, s2) == .gt) @as(i32, 1) else @as(i32, 0);
            },
            .structure => |s1| {
                const s2 = t2.structure;

                // Compare arity first
                if (s1.args.len != s2.args.len) {
                    return if (s1.args.len < s2.args.len) @as(i32, -1) else @as(i32, 1);
                }

                // Compare functor
                const functor_cmp = std.mem.order(u8, s1.functor, s2.functor);
                if (functor_cmp != .eq) {
                    return if (functor_cmp == .lt) @as(i32, -1) else @as(i32, 1);
                }

                // Compare arguments left to right
                for (s1.args, 0..) |arg1, idx| {
                    const arg2 = s2.args[idx];
                    const arg_cmp = try compareTerms(undefined, arg1, arg2);
                    if (arg_cmp != 0) {
                        return arg_cmp;
                    }
                }

                return 0;
            },
        }
    }

    /// Callback handler invoked for each solution found during query evaluation.
    /// The handler receives the current variable bindings (env) and can
    /// return an error to stop enumeration (e.g., for if-then-else).
    pub const SolutionHandler = struct {
        context: ?*anyopaque,
        handle: *const fn (context: ?*anyopaque, env: EnvMap, engine: *Engine) SolutionHandlerError!void,
    };

    /// Result of solve() indicating how resolution terminated.
    /// Normal: all solutions enumerated (or goal failed)
    /// Cut: a cut was executed, with the scope_id to cut to
    pub const SolveResult = union(enum) {
        Normal,
        Cut: usize,
    };

    /// Convert a term to a string for format/2.
    fn termToString(self: *Engine, term: *Term) ![]u8 {
        switch (term.*) {
            .atom => |a| return try self.alloc.dupe(u8, a),
            .string => |s| return try self.alloc.dupe(u8, s),
            else => return error.InvalidFormatString,
        }
    }

    /// Convert a Prolog list term to an array of terms.
    fn termToList(self: *Engine, term: *Term, env: *EnvMap) ![]*Term {
        var result = ArrayListUnmanaged(*Term).empty;
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

    /// Process a format string with arguments for format/2.
    /// Supports ~w (write term), ~a (atom), ~d (integer), ~s (string).
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

    /// Execute SLD resolution to find solutions to a list of goals.
    ///
    /// This is the core of the Prolog interpreter implementing:
    /// - Goal reduction via clause matching and unification
    /// - Backtracking through choice points
    /// - Built-in predicate handling
    /// - Cut (!) for pruning the search tree
    ///
    /// Parameters:
    /// - goals: List of goals to solve (consumed left-to-right)
    /// - env: Current variable bindings (modified during resolution)
    /// - depth: Current recursion depth (for stack overflow protection)
    /// - scope_id: Current cut scope (for implementing !/0)
    /// - handler: Callback invoked for each solution found
    /// - writer: Output stream for write/1, format/2, etc.
    ///
    /// Returns SolveResult indicating normal completion or cut.
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

            var current_goals = ArrayListUnmanaged(*Term).empty;
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
                var next_goals = ArrayListUnmanaged(*Term).empty;
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
                var sub_goals = ArrayListUnmanaged(*Term).empty;
                defer sub_goals.deinit(self.alloc);
                try sub_goals.append(self.alloc, sub_goal);
                try sub_goals.appendSlice(self.alloc, current_goals.items);

                return self.solve(try sub_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, distinct_handler, writer);
            }

            // findall/3: findall(Template, Goal, List)
            // Collects all solutions of Goal instantiated with Template into List
            // Always succeeds (returns [] if no solutions)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "findall") and goal.structure.args.len == 3) {
                const template = goal.structure.args[0];
                const sub_goal = goal.structure.args[1];
                const result_var = goal.structure.args[2];

                const FindallContext = struct {
                    alloc: Allocator,
                    template: *Term,
                    solutions: *ArrayListUnmanaged(*Term),
                };

                var solutions = ArrayListUnmanaged(*Term).empty;
                defer solutions.deinit(self.alloc);

                const wrapper = struct {
                    fn handle(ctx_ptr: ?*anyopaque, match_env: EnvMap, _: *Engine) SolutionHandlerError!void {
                        const ctx: *FindallContext = @ptrCast(@alignCast(ctx_ptr));
                        // Instantiate template with current bindings and add to solutions
                        const instantiated = try copyTerm(ctx.alloc, ctx.template, match_env);
                        try ctx.solutions.append(ctx.alloc, instantiated);
                    }
                };

                var findall_ctx = FindallContext{
                    .alloc = self.alloc,
                    .template = template,
                    .solutions = &solutions,
                };

                const findall_handler = SolutionHandler{
                    .context = &findall_ctx,
                    .handle = wrapper.handle,
                };

                // Solve sub_goal and collect all solutions
                var sub_goals = ArrayListUnmanaged(*Term).empty;
                defer sub_goals.deinit(self.alloc);
                try sub_goals.append(self.alloc, sub_goal);

                // We don't care about the result - findall always succeeds
                _ = self.solve(try sub_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, findall_handler, writer) catch |err| {
                    // If solving fails, that's ok - we just have no solutions
                    if (err != error.NegationFound and err != error.ConditionSucceeded) {
                        return err;
                    }
                };

                // Convert solutions to Prolog list
                const result_list = try self.termsToList(solutions.items);

                // Unify with result variable
                if (unify(self.alloc, result_var, result_list, current_env)) {
                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                }
                return .Normal;
            }

            // bagof/3: bagof(Template, Goal, List)
            // Like findall but fails if no solutions
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "bagof") and goal.structure.args.len == 3) {
                const template = goal.structure.args[0];
                const sub_goal = goal.structure.args[1];
                const result_var = goal.structure.args[2];

                const BagofContext = struct {
                    alloc: Allocator,
                    template: *Term,
                    solutions: *ArrayListUnmanaged(*Term),
                };

                var solutions = ArrayListUnmanaged(*Term).empty;
                defer solutions.deinit(self.alloc);

                const wrapper = struct {
                    fn handle(ctx_ptr: ?*anyopaque, match_env: EnvMap, _: *Engine) SolutionHandlerError!void {
                        const ctx: *BagofContext = @ptrCast(@alignCast(ctx_ptr));
                        const instantiated = try copyTerm(ctx.alloc, ctx.template, match_env);
                        try ctx.solutions.append(ctx.alloc, instantiated);
                    }
                };

                var bagof_ctx = BagofContext{
                    .alloc = self.alloc,
                    .template = template,
                    .solutions = &solutions,
                };

                const bagof_handler = SolutionHandler{
                    .context = &bagof_ctx,
                    .handle = wrapper.handle,
                };

                // Solve sub_goal and collect all solutions
                var sub_goals = ArrayListUnmanaged(*Term).empty;
                defer sub_goals.deinit(self.alloc);
                try sub_goals.append(self.alloc, sub_goal);

                _ = self.solve(try sub_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, bagof_handler, writer) catch |err| {
                    if (err != error.NegationFound and err != error.ConditionSucceeded) {
                        return err;
                    }
                };

                // bagof fails if no solutions found
                if (solutions.items.len == 0) {
                    return .Normal;
                }

                // Convert solutions to Prolog list
                const result_list = try self.termsToList(solutions.items);

                // Unify with result variable
                if (unify(self.alloc, result_var, result_list, current_env)) {
                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                }
                return .Normal;
            }

            // setof/3: setof(Template, Goal, List)
            // Like bagof but returns sorted unique solutions
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "setof") and goal.structure.args.len == 3) {
                const template = goal.structure.args[0];
                const sub_goal = goal.structure.args[1];
                const result_var = goal.structure.args[2];

                const SetofContext = struct {
                    alloc: Allocator,
                    template: *Term,
                    solutions: *ArrayListUnmanaged(*Term),
                    seen: *std.AutoHashMap(u64, void),
                };

                var solutions = ArrayListUnmanaged(*Term).empty;
                defer solutions.deinit(self.alloc);

                const seen = try self.alloc.create(std.AutoHashMap(u64, void));
                seen.* = std.AutoHashMap(u64, void).init(self.alloc);
                defer {
                    seen.deinit();
                    self.alloc.destroy(seen);
                }

                const wrapper = struct {
                    fn handle(ctx_ptr: ?*anyopaque, match_env: EnvMap, _: *Engine) SolutionHandlerError!void {
                        const ctx: *SetofContext = @ptrCast(@alignCast(ctx_ptr));
                        const instantiated = try copyTerm(ctx.alloc, ctx.template, match_env);

                        // Check if we've seen this solution before
                        const hash = instantiated.hash();
                        if (!ctx.seen.contains(hash)) {
                            try ctx.seen.put(hash, {});
                            try ctx.solutions.append(ctx.alloc, instantiated);
                        }
                    }
                };

                var setof_ctx = SetofContext{
                    .alloc = self.alloc,
                    .template = template,
                    .solutions = &solutions,
                    .seen = seen,
                };

                const setof_handler = SolutionHandler{
                    .context = &setof_ctx,
                    .handle = wrapper.handle,
                };

                // Solve sub_goal and collect all unique solutions
                var sub_goals = ArrayListUnmanaged(*Term).empty;
                defer sub_goals.deinit(self.alloc);
                try sub_goals.append(self.alloc, sub_goal);

                _ = self.solve(try sub_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, setof_handler, writer) catch |err| {
                    if (err != error.NegationFound and err != error.ConditionSucceeded) {
                        return err;
                    }
                };

                // setof fails if no solutions found
                if (solutions.items.len == 0) {
                    return .Normal;
                }

                // Sort solutions using standard term ordering
                try self.sortTerms(solutions.items);

                // Convert solutions to Prolog list
                const result_list = try self.termsToList(solutions.items);

                // Unify with result variable
                if (unify(self.alloc, result_var, result_list, current_env)) {
                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                }
                return .Normal;
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

            // ISO Prolog type testing predicates (arity 1)
            // Handle arity-1 type-testing predicates (var/1, nonvar/1, atom/1, etc.)
            if (goal.* == .structure and goal.structure.args.len == 1) {
                const s = goal.structure;
                const type_kind = getTypeTestKind(s.functor);

                if (type_kind != .not_type_test) {
                    const arg = resolve(s.args[0], current_env);
                    if (checkTypeTest(self.alloc, type_kind, arg, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                    return .Normal;
                }
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
                } else if (std.mem.eql(u8, s.functor, "unify_with_occurs_check") and s.args.len == 2) {
                    // ISO Prolog unify_with_occurs_check/2
                    // Sound unification that prevents cyclic structures
                    result = unifyWithOccursCheck(self.alloc, s.args[0], s.args[1], current_env);
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

                    // Error type used internally to signal that condition succeeded
                    const CondSucceeded = error{ConditionSucceeded};

                    // Handler that signals success on first solution
                    const cond_check = struct {
                        fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                            return CondSucceeded.ConditionSucceeded;
                        }
                    };
                    const cond_handler = SolutionHandler{ .context = null, .handle = cond_check.handle };

                    // Clone environment to test condition
                    var cond_env = try current_env.clone(self.alloc);
                    defer cond_env.deinit(self.alloc);

                    var cond_goals = ArrayListUnmanaged(*Term).empty;
                    try cond_goals.append(self.alloc, cond);

                    const cond_result = self.solve(
                        try cond_goals.toOwnedSlice(self.alloc),
                        &cond_env,
                        depth + 1,
                        scope_id,
                        cond_handler,
                        writer,
                    );

                    if (cond_result) |_| {
                        // Condition failed (returned normally)
                        return .Normal;
                    } else |err| {
                        if (err == CondSucceeded.ConditionSucceeded) {
                            // Condition succeeded - copy bindings and execute Then
                            var it = cond_env.iterator();
                            while (it.next()) |entry| {
                                try current_env.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
                            }
                            var then_goals = ArrayListUnmanaged(*Term).empty;
                            try then_goals.append(self.alloc, then_branch);
                            try then_goals.appendSlice(self.alloc, current_goals.items);
                            return self.solve(try then_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                        }
                        return err;
                    }
                } else if (std.mem.eql(u8, s.functor, "*->")) {
                    // Soft cut: (Cond *-> Then)
                    // Like if-then, but allows backtracking within Then
                    // Commits to first solution of Cond, but Then can produce multiple solutions
                    const cond = s.args[0];
                    const then_branch = s.args[1];

                    // Error type used internally to signal that condition succeeded
                    const CondSucceeded = error{ConditionSucceeded};

                    // Handler that signals success on first solution
                    const cond_check = struct {
                        fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                            return CondSucceeded.ConditionSucceeded;
                        }
                    };
                    const cond_handler = SolutionHandler{ .context = null, .handle = cond_check.handle };

                    // Clone environment to test condition
                    var cond_env = try current_env.clone(self.alloc);
                    defer cond_env.deinit(self.alloc);

                    var cond_goals = ArrayListUnmanaged(*Term).empty;
                    try cond_goals.append(self.alloc, cond);

                    const cond_result = self.solve(
                        try cond_goals.toOwnedSlice(self.alloc),
                        &cond_env,
                        depth + 1,
                        scope_id,
                        cond_handler,
                        writer,
                    );

                    if (cond_result) |_| {
                        // Condition failed (returned normally)
                        return .Normal;
                    } else |err| {
                        if (err == CondSucceeded.ConditionSucceeded) {
                            // Condition succeeded - copy bindings and execute Then
                            var it = cond_env.iterator();
                            while (it.next()) |entry| {
                                try current_env.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
                            }
                            var then_goals = ArrayListUnmanaged(*Term).empty;
                            try then_goals.append(self.alloc, then_branch);
                            try then_goals.appendSlice(self.alloc, current_goals.items);
                            return self.solve(try then_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                        }
                        return err;
                    }
                } else if (std.mem.eql(u8, s.functor, ";")) {
                    // Check if this is if-then-else: (Cond -> Then ; Else) or (Cond *-> Then ; Else)
                    const first_arg = s.args[0];
                    const is_hard_cut = first_arg.* == .structure and std.mem.eql(u8, first_arg.structure.functor, "->") and first_arg.structure.args.len == 2;
                    const is_soft_cut = first_arg.* == .structure and std.mem.eql(u8, first_arg.structure.functor, "*->") and first_arg.structure.args.len == 2;

                    if (is_hard_cut or is_soft_cut) {
                        // This is if-then-else (hard cut or soft cut)
                        const cond = first_arg.structure.args[0];
                        const then_branch = first_arg.structure.args[1];
                        const else_branch = s.args[1];

                        // Error type used internally to signal that condition succeeded
                        const CondSucceeded = error{ConditionSucceeded};

                        // Handler that signals success on first solution
                        const cond_check = struct {
                            fn handle(_: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
                                return CondSucceeded.ConditionSucceeded;
                            }
                        };
                        const cond_handler = SolutionHandler{ .context = null, .handle = cond_check.handle };

                        // Clone environment to test condition
                        var cond_env = try current_env.clone(self.alloc);
                        defer cond_env.deinit(self.alloc);

                        var cond_goals = ArrayListUnmanaged(*Term).empty;
                        try cond_goals.append(self.alloc, cond);

                        const cond_result = self.solve(
                            try cond_goals.toOwnedSlice(self.alloc),
                            &cond_env,
                            depth + 1,
                            scope_id,
                            cond_handler,
                            writer,
                        );

                        if (cond_result) |_| {
                            // Condition failed - execute Else branch
                            var else_goals = ArrayListUnmanaged(*Term).empty;
                            try else_goals.append(self.alloc, else_branch);
                            try else_goals.appendSlice(self.alloc, current_goals.items);
                            return self.solve(try else_goals.toOwnedSlice(self.alloc), current_env, depth + 1, scope_id, handler, writer);
                        } else |err| {
                            if (err == CondSucceeded.ConditionSucceeded) {
                                // Condition succeeded - copy bindings and execute Then
                                var it = cond_env.iterator();
                                while (it.next()) |entry| {
                                    try current_env.put(self.alloc, entry.key_ptr.*, entry.value_ptr.*);
                                }
                                var then_goals = ArrayListUnmanaged(*Term).empty;
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
                        var goals_a = ArrayListUnmanaged(*Term).empty;
                        try goals_a.append(self.alloc, s.args[0]);
                        try goals_a.appendSlice(self.alloc, current_goals.items);
                        const res_a = try self.solve(try goals_a.toOwnedSlice(self.alloc), &env_a, depth + 1, scope_id, handler, writer);
                        if (res_a != .Normal) return res_a;

                        var env_b = try current_env.clone(self.alloc);
                        defer env_b.deinit(self.alloc);
                        var goals_b = ArrayListUnmanaged(*Term).empty;
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

            // ISO Prolog functor/3 - functor(Term, Functor, Arity)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "functor") and goal.structure.args.len == 3) {
                const term_arg = goal.structure.args[0];
                const functor_arg = goal.structure.args[1];
                const arity_arg = goal.structure.args[2];

                const resolved_term = resolve(term_arg, current_env);

                if (resolved_term.* == .structure) {
                    // Mode: functor(+Term, ?Functor, ?Arity)
                    const functor_atom = try Term.createAtom(self.alloc, resolved_term.structure.functor);
                    const arity_num = try Term.createNumber(self.alloc, @intCast(resolved_term.structure.args.len));

                    if (unify(self.alloc, functor_arg, functor_atom, current_env) and
                        unify(self.alloc, arity_arg, arity_num, current_env))
                    {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (resolved_term.* == .atom) {
                    // Atom has arity 0
                    const arity_num = try Term.createNumber(self.alloc, 0);
                    if (unify(self.alloc, functor_arg, resolved_term, current_env) and
                        unify(self.alloc, arity_arg, arity_num, current_env))
                    {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (resolved_term.* == .number) {
                    // Number has functor = itself, arity = 0
                    const arity_num = try Term.createNumber(self.alloc, 0);
                    if (unify(self.alloc, functor_arg, resolved_term, current_env) and
                        unify(self.alloc, arity_arg, arity_num, current_env))
                    {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (resolved_term.* == .float) {
                    // Float has functor = itself, arity = 0
                    const arity_num = try Term.createNumber(self.alloc, 0);
                    if (unify(self.alloc, functor_arg, resolved_term, current_env) and
                        unify(self.alloc, arity_arg, arity_num, current_env))
                    {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (resolved_term.* == .variable) {
                    // Mode: functor(?Term, +Functor, +Arity) - construct term
                    const resolved_functor = resolve(functor_arg, current_env);
                    const resolved_arity = resolve(arity_arg, current_env);

                    if (resolved_functor.* == .atom and resolved_arity.* == .number) {
                        const arity = resolved_arity.number;
                        if (arity == 0) {
                            // Create atom
                            if (unify(self.alloc, term_arg, resolved_functor, current_env)) {
                                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                            }
                        } else if (arity > 0) {
                            // Create structure with unbound variables
                            var args = try self.alloc.alloc(*Term, @intCast(arity));
                            for (0..@intCast(arity)) |i| {
                                const var_name = try std.fmt.allocPrint(self.alloc, "_G{d}", .{i});
                                args[i] = try Term.createVariable(self.alloc, var_name);
                            }
                            const new_term = try Term.createStructure(self.alloc, resolved_functor.atom, args);
                            if (unify(self.alloc, term_arg, new_term, current_env)) {
                                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                            }
                        }
                    }
                }
                return .Normal;
            }

            // ISO Prolog arg/3 - arg(N, Term, Arg)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "arg") and goal.structure.args.len == 3) {
                const n_arg = resolve(goal.structure.args[0], current_env);
                const term_arg = resolve(goal.structure.args[1], current_env);
                const arg_arg = goal.structure.args[2];

                if (n_arg.* == .number and term_arg.* == .structure) {
                    const n = n_arg.number;
                    const args = term_arg.structure.args;

                    // Arguments are 1-indexed in Prolog
                    if (n >= 1 and n <= args.len) {
                        const idx: usize = @intCast(n - 1);
                        if (unify(self.alloc, arg_arg, args[idx], current_env)) {
                            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                        }
                    }
                }
                return .Normal;
            }

            // ISO Prolog =../2 (univ) - Term =.. List
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "=..") and goal.structure.args.len == 2) {
                const term_arg = resolve(goal.structure.args[0], current_env);
                const list_arg = resolve(goal.structure.args[1], current_env);

                if (term_arg.* == .structure) {
                    // Mode: +Term =.. ?List - decompose term
                    var list_items = try ArrayListUnmanaged(*Term).initCapacity(self.alloc, term_arg.structure.args.len + 1);
                    defer list_items.deinit(self.alloc);

                    // Add functor as first element
                    try list_items.append(self.alloc, try Term.createAtom(self.alloc, term_arg.structure.functor));
                    // Add arguments
                    for (term_arg.structure.args) |arg| {
                        try list_items.append(self.alloc, arg);
                    }

                    // Convert to Prolog list
                    var result_list = try Term.createAtom(self.alloc, "[]");
                    var i = list_items.items.len;
                    while (i > 0) {
                        i -= 1;
                        result_list = try Term.createStructure(self.alloc, ".", &[_]*Term{ list_items.items[i], result_list });
                    }

                    if (unify(self.alloc, goal.structure.args[1], result_list, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (term_arg.* == .atom or term_arg.* == .number or term_arg.* == .float) {
                    // Atomic terms =.. [Term]
                    const singleton_list = try Term.createStructure(self.alloc, ".", &[_]*Term{ term_arg, try Term.createAtom(self.alloc, "[]") });
                    if (unify(self.alloc, goal.structure.args[1], singleton_list, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (term_arg.* == .variable and list_arg.* == .structure and std.mem.eql(u8, list_arg.structure.functor, ".")) {
                    // Mode: ?Term =.. +List - construct term
                    // Extract list elements
                    var elements = ArrayListUnmanaged(*Term).empty;
                    defer elements.deinit(self.alloc);

                    var current_list = list_arg;
                    while (current_list.* == .structure and std.mem.eql(u8, current_list.structure.functor, ".")) {
                        try elements.append(self.alloc, current_list.structure.args[0]);
                        current_list = resolve(current_list.structure.args[1], current_env);
                    }

                    if (elements.items.len > 0) {
                        const functor_term = resolve(elements.items[0], current_env);
                        if (functor_term.* == .atom) {
                            if (elements.items.len == 1) {
                                // Just an atom
                                if (unify(self.alloc, goal.structure.args[0], functor_term, current_env)) {
                                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                                }
                            } else {
                                // Construct structure
                                const args = elements.items[1..];
                                const new_term = try Term.createStructure(self.alloc, functor_term.atom, args);
                                if (unify(self.alloc, goal.structure.args[0], new_term, current_env)) {
                                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                                }
                            }
                        }
                    }
                }
                return .Normal;
            }

            // ISO Prolog copy_term/2 - copy_term(Term, Copy)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "copy_term") and goal.structure.args.len == 2) {
                const term_arg = goal.structure.args[0];
                const copy_arg = goal.structure.args[1];

                // Create a fresh copy with renamed variables
                var var_map = StringHashMapUnmanaged(*Term){};
                defer var_map.deinit(self.alloc);
                var counter: usize = 0;

                const copied_term = try copyTermWithFreshVars(self.alloc, term_arg, current_env, &var_map, &counter);

                if (unify(self.alloc, copy_arg, copied_term, current_env)) {
                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                }
                return .Normal;
            }

            // ISO Prolog term_variables/2 - term_variables(+Term, -List)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "term_variables") and goal.structure.args.len == 2) {
                const term_arg = goal.structure.args[0];
                const list_arg = goal.structure.args[1];

                // Collect all unique variables from the term
                var var_list = ArrayListUnmanaged(*Term).empty;
                defer var_list.deinit(self.alloc);
                var seen_vars = StringHashMapUnmanaged(void){};
                defer seen_vars.deinit(self.alloc);

                try collectTermVariables(self.alloc, term_arg, current_env, &var_list, &seen_vars);

                // Convert to Prolog list (build in reverse)
                var result_list = try Term.createAtom(self.alloc, "[]");
                var i = var_list.items.len;
                while (i > 0) {
                    i -= 1;
                    result_list = try Term.createStructure(self.alloc, ".", &[_]*Term{ var_list.items[i], result_list });
                }

                if (unify(self.alloc, list_arg, result_list, current_env)) {
                    return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                }
                return .Normal;
            }

            // ISO Prolog atom_length/2 - atom_length(Atom, Length)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "atom_length") and goal.structure.args.len == 2) {
                const atom_arg = resolve(goal.structure.args[0], current_env);
                const length_arg = goal.structure.args[1];

                if (atom_arg.* == .atom) {
                    const len = try Term.createNumber(self.alloc, @intCast(atom_arg.atom.len));
                    if (unify(self.alloc, length_arg, len, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                }
                return .Normal;
            }

            // ISO Prolog atom_concat/3 - atom_concat(Atom1, Atom2, Atom3)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "atom_concat") and goal.structure.args.len == 3) {
                const atom1_arg = resolve(goal.structure.args[0], current_env);
                const atom2_arg = resolve(goal.structure.args[1], current_env);
                const atom3_arg = resolve(goal.structure.args[2], current_env);

                if (atom1_arg.* == .atom and atom2_arg.* == .atom) {
                    // Mode: +Atom1, +Atom2, ?Atom3 - concatenate
                    const concatenated = try std.fmt.allocPrint(self.alloc, "{s}{s}", .{ atom1_arg.atom, atom2_arg.atom });
                    const result = try Term.createAtom(self.alloc, concatenated);
                    if (unify(self.alloc, goal.structure.args[2], result, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (atom1_arg.* == .atom and atom3_arg.* == .atom) {
                    // Mode: +Atom1, ?Atom2, +Atom3 - check if Atom3 starts with Atom1
                    if (std.mem.startsWith(u8, atom3_arg.atom, atom1_arg.atom)) {
                        const rest = atom3_arg.atom[atom1_arg.atom.len..];
                        const atom2 = try Term.createAtom(self.alloc, rest);
                        if (unify(self.alloc, goal.structure.args[1], atom2, current_env)) {
                            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                        }
                    }
                } else if (atom2_arg.* == .atom and atom3_arg.* == .atom) {
                    // Mode: ?Atom1, +Atom2, +Atom3 - check if Atom3 ends with Atom2
                    if (std.mem.endsWith(u8, atom3_arg.atom, atom2_arg.atom)) {
                        const prefix = atom3_arg.atom[0 .. atom3_arg.atom.len - atom2_arg.atom.len];
                        const atom1 = try Term.createAtom(self.alloc, prefix);
                        if (unify(self.alloc, goal.structure.args[0], atom1, current_env)) {
                            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                        }
                    }
                }
                return .Normal;
            }

            // ISO Prolog atom_chars/2 - atom_chars(Atom, Chars)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "atom_chars") and goal.structure.args.len == 2) {
                const atom_arg = resolve(goal.structure.args[0], current_env);
                const chars_arg = resolve(goal.structure.args[1], current_env);

                if (atom_arg.* == .atom) {
                    // Mode: +Atom, ?Chars - convert atom to character list
                    var result_list = try Term.createAtom(self.alloc, "[]");
                    var i = atom_arg.atom.len;
                    while (i > 0) {
                        i -= 1;
                        const char_str = try std.fmt.allocPrint(self.alloc, "{c}", .{atom_arg.atom[i]});
                        const char_atom = try Term.createAtom(self.alloc, char_str);
                        result_list = try Term.createStructure(self.alloc, ".", &[_]*Term{ char_atom, result_list });
                    }
                    if (unify(self.alloc, goal.structure.args[1], result_list, current_env)) {
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                    }
                } else if (chars_arg.* == .structure and std.mem.eql(u8, chars_arg.structure.functor, ".")) {
                    // Mode: ?Atom, +Chars - convert character list to atom
                    var chars = ArrayListUnmanaged(u8).empty;
                    defer chars.deinit(self.alloc);

                    var current_list = chars_arg;
                    while (current_list.* == .structure and std.mem.eql(u8, current_list.structure.functor, ".")) {
                        const char_term = resolve(current_list.structure.args[0], current_env);
                        if (char_term.* == .atom and char_term.atom.len == 1) {
                            try chars.append(self.alloc, char_term.atom[0]);
                        } else {
                            return .Normal; // Invalid character
                        }
                        current_list = resolve(current_list.structure.args[1], current_env);
                    }

                    // Check that we ended with []
                    if (current_list.* == .atom and std.mem.eql(u8, current_list.atom, "[]")) {
                        const atom_str = try chars.toOwnedSlice(self.alloc);
                        const result_atom = try Term.createAtom(self.alloc, atom_str);
                        if (unify(self.alloc, goal.structure.args[0], result_atom, current_env)) {
                            return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
                        }
                    }
                }
                return .Normal;
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

                var neg_goals = ArrayListUnmanaged(*Term).empty;
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
                    var goals_clone = ArrayListUnmanaged(*Term).empty;
                    try goals_clone.appendSlice(self.alloc, current_goals.items);
                    const result = try self.solve(try goals_clone.toOwnedSlice(self.alloc), &env_clone, depth, scope_id, handler, writer);
                    // If cut, stop repeating
                    if (result != .Normal) return result;
                    // Otherwise, keep repeating (backtrack to repeat)
                }
            }

            // assert/1: Add clause to end of database (same as assertz/1)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "assert") and goal.structure.args.len == 1) {
                const clause_term = resolve(goal.structure.args[0], current_env);
                try self.assertClause(clause_term, false); // false = add to end
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }

            // asserta/1: Add clause to beginning of database
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "asserta") and goal.structure.args.len == 1) {
                const clause_term = resolve(goal.structure.args[0], current_env);
                try self.assertClause(clause_term, true); // true = add to beginning
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }

            // assertz/1: Add clause to end of database
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "assertz") and goal.structure.args.len == 1) {
                const clause_term = resolve(goal.structure.args[0], current_env);
                try self.assertClause(clause_term, false); // false = add to end
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }

            // retract/1: Remove first matching clause
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "retract") and goal.structure.args.len == 1) {
                const clause_term = goal.structure.args[0];

                // Try to retract each matching clause, succeeding for each match
                var i: usize = 0;
                while (i < self.db.items.len) {
                    const rule = self.db.items[i];

                    // Convert rule back to clause term for unification
                    const rule_as_term = try self.ruleToTerm(rule);

                    // Try to unify with the pattern
                    var test_env = try current_env.clone(self.alloc);
                    defer test_env.deinit(self.alloc);

                    if (unify(self.alloc, clause_term, rule_as_term, &test_env)) {
                        // Found a match - retract it and succeed with this binding
                        _ = self.db.orderedRemove(i);
                        try self.rebuildIndex();

                        // Continue solving with the unified environment
                        return self.solve(try current_goals.toOwnedSlice(self.alloc), &test_env, depth, scope_id, handler, writer);
                    }
                    i += 1;
                }

                // No match found - fail
                return .Normal;
            }

            // retractall/1: Remove all matching clauses
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "retractall") and goal.structure.args.len == 1) {
                const clause_term = resolve(goal.structure.args[0], current_env);

                // Remove all matching clauses
                var i: usize = 0;
                var removed_any = false;
                while (i < self.db.items.len) {
                    const rule = self.db.items[i];
                    const rule_as_term = try self.ruleToTerm(rule);

                    var test_env = createEnv();
                    defer test_env.deinit(self.alloc);

                    if (unify(self.alloc, clause_term, rule_as_term, &test_env)) {
                        _ = self.db.orderedRemove(i);
                        removed_any = true;
                        // Don't increment i - we removed an element
                    } else {
                        i += 1;
                    }
                }

                if (removed_any) {
                    try self.rebuildIndex();
                }

                // retractall always succeeds, even if nothing was removed
                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }

            // abolish/1: Remove all clauses for a predicate (functor/arity)
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "abolish") and goal.structure.args.len == 1) {
                const pred_indicator = resolve(goal.structure.args[0], current_env);

                // Expect functor/arity format
                if (pred_indicator.* == .structure and std.mem.eql(u8, pred_indicator.structure.functor, "/") and pred_indicator.structure.args.len == 2) {
                    const functor_term = resolve(pred_indicator.structure.args[0], current_env);
                    const arity_term = resolve(pred_indicator.structure.args[1], current_env);

                    if (functor_term.* == .atom and arity_term.* == .number) {
                        const functor = functor_term.atom;
                        const arity = arity_term.number;

                        // Remove all clauses matching this functor/arity
                        var i: usize = 0;
                        var removed_any = false;
                        while (i < self.db.items.len) {
                            const rule = self.db.items[i];
                            const head = rule.head;

                            var matches = false;
                            if (head.* == .atom and arity == 0) {
                                matches = std.mem.eql(u8, head.atom, functor);
                            } else if (head.* == .structure) {
                                matches = std.mem.eql(u8, head.structure.functor, functor) and head.structure.args.len == arity;
                            }

                            if (matches) {
                                _ = self.db.orderedRemove(i);
                                removed_any = true;
                            } else {
                                i += 1;
                            }
                        }

                        if (removed_any) {
                            try self.rebuildIndex();
                        }
                    }
                }

                return self.solve(try current_goals.toOwnedSlice(self.alloc), current_env, depth, scope_id, handler, writer);
            }

            // clause/2: Retrieve clauses from database
            if (goal.* == .structure and std.mem.eql(u8, goal.structure.functor, "clause") and goal.structure.args.len == 2) {
                const head_pattern = goal.structure.args[0];
                const body_pattern = goal.structure.args[1];

                // Try to unify with each clause in the database
                for (self.db.items) |rule| {
                    var test_env = try current_env.clone(self.alloc);
                    defer test_env.deinit(self.alloc);

                    // Unify with head
                    if (unify(self.alloc, head_pattern, rule.head, &test_env)) {
                        // Create body term (true for facts, conjunction for rules)
                        const body_term = try self.bodyToTerm(rule.body);

                        // Unify with body
                        if (unify(self.alloc, body_pattern, body_term, &test_env)) {
                            // Success - continue solving with this binding
                            const result = try self.solve(try current_goals.toOwnedSlice(self.alloc), &test_env, depth, scope_id, handler, writer);

                            // If this branch succeeded normally, continue trying other clauses
                            if (result != .Normal) return result;
                        }
                    }
                }

                return .Normal;
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
                    var next_goals = ArrayListUnmanaged(*Term).empty;

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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Check if X was bound to a in the env (though solve copies env, so we can't check original env easily unless we pass a pointer that persists)
    // Actually solve clones env for each branch.
}

const TestBuffer = struct {
    aw: std.Io.Writer.Allocating,

    pub fn init(allocator: std.mem.Allocator) TestBuffer {
        return .{
            .aw = std.Io.Writer.Allocating.init(allocator),
        };
    }

    pub fn deinit(self: *TestBuffer) void {
        self.aw.deinit();
    }

    pub fn clearRetainingCapacity(self: *TestBuffer) void {
        self.aw.writer.end = 0;
    }

    pub fn writer(self: *TestBuffer, _: std.mem.Allocator) *std.Io.Writer {
        return &self.aw.writer;
    }

    pub fn getItems(self: TestBuffer) []const u8 {
        return self.aw.writer.buffer[0..self.aw.writer.end];
    }
};

const TestHandlerContext = struct {
    buf: *TestBuffer,
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect two "  true.\n" because there are two ways to prove human(victoria)
    try std.testing.expectEqualStrings("  true.\n  true.", buf.getItems());
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect X = nikolay and X = yavor
    const output = buf.getItems();
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

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

    var it = std.mem.splitSequence(u8, buf.getItems(), "\n");
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect only X = 1.
    // X = 2 is pruned by cut (backtracking to p(X) prevented).
    // X = 3 is pruned by cut (next rule for q prevented).

    const output = buf.getItems();
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Expect X = [1, 2, 3]
    const output = buf.getItems();
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

    const output_s = buf.getItems();
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // Query: ?- p.
    var goals_p = [_]*Term{try Term.createAtom(alloc, "p")};
    _ = try eng.solve(&goals_p, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "true") != null);

    // Query: ?- q.
    buf.clearRetainingCapacity();
    has_printed = false;
    var goals_q = [_]*Term{try Term.createAtom(alloc, "q")};
    _ = try eng.solve(&goals_q, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("", buf.getItems()); // Should fail silently (no output)
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // X is 1 + 2.
    const X = try Term.createVariable(alloc, "X");
    const expr = try Term.createStructure(alloc, "+", &[_]*Term{ try Term.createNumber(alloc, 1), try Term.createNumber(alloc, 2) });
    const goal1 = try Term.createStructure(alloc, "is", &[_]*Term{ X, expr });

    var goals1 = [_]*Term{goal1};
    _ = try eng.solve(&goals1, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("X = 3", buf.getItems());

    // 3 > 2.
    buf.clearRetainingCapacity();
    env.clearRetainingCapacity();
    has_printed = false;
    const goal2 = try Term.createStructure(alloc, ">", &[_]*Term{ try Term.createNumber(alloc, 3), try Term.createNumber(alloc, 2) });
    var goals2 = [_]*Term{goal2};
    _ = try eng.solve(&goals2, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("  true.", buf.getItems());
}

test "Engine - missing comparisons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    var env = EnvMap{};
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
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
        try std.testing.expectEqualStrings("  true.", buf.getItems());
    }

    // 2 >= 2
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, ">=", &[_]*Term{ try Term.createNumber(alloc, 2), try Term.createNumber(alloc, 2) });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.getItems());
    }

    // 2 =< 3
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "=<", &[_]*Term{ try Term.createNumber(alloc, 2), try Term.createNumber(alloc, 3) });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.getItems());
    }

    // a \= b
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "\\=", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createAtom(alloc, "b") });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.getItems());
    }

    // a \= a (should fail, so no output)
    {
        buf.clearRetainingCapacity();
        has_printed = false;
        const goal = try Term.createStructure(alloc, "\\=", &[_]*Term{ try Term.createAtom(alloc, "a"), try Term.createAtom(alloc, "a") });
        var goals = [_]*Term{goal};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.getItems());
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Should print true twice (once for a, once for b)
    // Actually, since there are no variables, it prints "true." twice.
    // We can count occurrences of "true."
    var count: usize = 0;
    var it = std.mem.splitSequence(u8, buf.getItems(), "\n");
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "X = 2") != null);
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
            var buf = TestBuffer.init(alloc);
            defer buf.deinit();
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "X = sg") != null);
        }

        // phrase(s(X), [the, cats, sleep]). -> X = pl
        {
            const source = "phrase(s(X), [the, cats, sleep]).";
            var parser = Parser.init(alloc, source);
            const goals = try parser.parseQuery();

            var has_printed = false;
            var buf = TestBuffer.init(alloc);
            defer buf.deinit();
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "X = pl") != null);
        }

        // phrase(s(X), [the, cat, sleep]). -> Fail
        {
            const source = "phrase(s(X), [the, cat, sleep]).";
            var parser = Parser.init(alloc, source);
            const goals = try parser.parseQuery();

            var has_printed = false;
            var buf = TestBuffer.init(alloc);
            defer buf.deinit();
            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };

            const handler = Engine.SolutionHandler{
                .context = &ctx,
                .handle = testHandle,
            };
            var env = EnvMap{};
            defer env.deinit(alloc);
            _ = try engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
            try std.testing.expectEqual(0, buf.getItems().len);
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

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
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

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var env = EnvMap{};
    defer env.deinit(alloc);

    _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
    try std.testing.expectEqualStrings("  true.", buf.getItems());
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

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();
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
    if (std.mem.indexOf(u8, buf.getItems(), "eats") == null) {
        std.debug.print("\nOUTPUT: {s}\n", .{buf.getItems()});
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
        var buf = TestBuffer.init(alloc);
        defer buf.deinit();
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.getItems()); // No output means false
    }

    // ?- \+ p(b). -> true
    {
        var parser_query = Parser.init(alloc, "\\+ p(b).");
        const goals = try parser_query.parseQuery();
        var buf = TestBuffer.init(alloc);
        defer buf.deinit();
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("  true.", buf.getItems());
    }

    // ?- not(p(a)). -> false
    {
        var parser_query = Parser.init(alloc, "not(p(a)).");
        const goals = try parser_query.parseQuery();
        var buf = TestBuffer.init(alloc);
        defer buf.deinit();
        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };
        var env = EnvMap{};
        defer env.deinit(alloc);
        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expectEqualStrings("", buf.getItems());
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
    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{query};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Verify that we found the correct solution
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "X = child_500") != null);

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
    var buf1 = TestBuffer.init(alloc);
    defer buf1.deinit();

    var ctx1 = TestHandlerContext{ .buf = &buf1, .alloc = alloc, .has_printed = &has_printed1 };
    const handler1 = Engine.SolutionHandler{ .context = &ctx1, .handle = testHandle };

    var goals1 = [_]*Term{query_unique};
    _ = try eng.solve(&goals1, &env1, 0, 0, handler1, buf1.writer(alloc));

    // Should succeed with "true"
    try std.testing.expect(std.mem.indexOf(u8, buf1.getItems(), "true") != null);

    // Query non-deterministic predicate
    const query_person = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createVariable(alloc, "X")});

    var env2 = createEnv();
    defer env2.deinit(alloc);

    var has_printed2 = false;
    var buf2 = TestBuffer.init(alloc);
    defer buf2.deinit();

    var ctx2 = TestHandlerContext{ .buf = &buf2, .alloc = alloc, .has_printed = &has_printed2 };
    const handler2 = Engine.SolutionHandler{ .context = &ctx2, .handle = testHandle };

    var goals2 = [_]*Term{query_person};
    _ = try eng.solve(&goals2, &env2, 0, 0, handler2, buf2.writer(alloc));

    // Should have two solutions
    try std.testing.expect(std.mem.indexOf(u8, buf2.getItems(), "X = bob") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf2.getItems(), "X = charlie") != null);

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
    var buf1 = TestBuffer.init(alloc);
    defer buf1.deinit();

    var ctx1 = TestHandlerContext{ .buf = &buf1, .alloc = alloc, .has_printed = &has_printed1 };
    const handler1 = Engine.SolutionHandler{ .context = &ctx1, .handle = testHandle };

    var goals1 = [_]*Term{query1};
    _ = try eng.solve(&goals1, &env1, 0, 0, handler1, buf1.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf1.getItems(), "true") != null);

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
    var buf2 = TestBuffer.init(alloc);
    defer buf2.deinit();

    var ctx2 = TestHandlerContext{ .buf = &buf2, .alloc = alloc, .has_printed = &has_printed2 };
    const handler2 = Engine.SolutionHandler{ .context = &ctx2, .handle = testHandle };

    var goals2 = [_]*Term{query2};
    _ = try eng.solve(&goals2, &env2, 0, 0, handler2, buf2.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf2.getItems(), "true") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Hello, World!\n") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Value: 42\n") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Number: 123\n") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Float: 3.14") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Atom: hello\n") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "String: world\n") != null);
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

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "x = 10, y = 2.5\n") != null);
    }

    // Test format with escaped tilde (~~)
    {
        const query = try Term.createStructure(alloc, "format", &[_]*Term{
            try Term.createAtom(alloc, "Tilde: ~~~n"),
        });

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        var goals = [_]*Term{query};
        _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Tilde: ~\n") != null);
    }
}

test "Engine - assert and retract" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Assert a fact: person(alice)
    const assert_goal = try Term.createStructure(alloc, "assert", &[_]*Term{
        try Term.createStructure(alloc, "person", &[_]*Term{
            try Term.createAtom(alloc, "alice"),
        }),
    });

    var env1 = createEnv();
    defer env1.deinit(alloc);

    var buf1 = TestBuffer.init(alloc);
    defer buf1.deinit();

    var has_printed1 = false;
    var ctx1 = TestHandlerContext{ .buf = &buf1, .alloc = alloc, .has_printed = &has_printed1 };
    const handler1 = Engine.SolutionHandler{ .context = &ctx1, .handle = testHandle };

    var goals1 = [_]*Term{assert_goal};
    _ = try eng.solve(&goals1, &env1, 0, 0, handler1, buf1.writer(alloc));

    // Verify the fact was added
    try std.testing.expectEqual(@as(usize, 1), eng.db.items.len);

    // Query the asserted fact: person(alice)
    const query = try Term.createStructure(alloc, "person", &[_]*Term{
        try Term.createAtom(alloc, "alice"),
    });

    var env2 = createEnv();
    defer env2.deinit(alloc);

    var buf2 = TestBuffer.init(alloc);
    defer buf2.deinit();

    var has_printed2 = false;
    var ctx2 = TestHandlerContext{ .buf = &buf2, .alloc = alloc, .has_printed = &has_printed2 };
    const handler2 = Engine.SolutionHandler{ .context = &ctx2, .handle = testHandle };

    var goals2 = [_]*Term{query};
    _ = try eng.solve(&goals2, &env2, 0, 0, handler2, buf2.writer(alloc));

    try std.testing.expect(std.mem.indexOf(u8, buf2.getItems(), "true") != null);

    // Retract the fact
    const retract_goal = try Term.createStructure(alloc, "retract", &[_]*Term{
        try Term.createStructure(alloc, "person", &[_]*Term{
            try Term.createAtom(alloc, "alice"),
        }),
    });

    var env3 = createEnv();
    defer env3.deinit(alloc);

    var buf3 = TestBuffer.init(alloc);
    defer buf3.deinit();

    var has_printed3 = false;
    var ctx3 = TestHandlerContext{ .buf = &buf3, .alloc = alloc, .has_printed = &has_printed3 };
    const handler3 = Engine.SolutionHandler{ .context = &ctx3, .handle = testHandle };

    var goals3 = [_]*Term{retract_goal};
    _ = try eng.solve(&goals3, &env3, 0, 0, handler3, buf3.writer(alloc));

    // Verify the fact was removed
    try std.testing.expectEqual(@as(usize, 0), eng.db.items.len);
}

test "Engine - asserta vs assertz" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Assert facts in order: assertz(p(1)), asserta(p(2)), assertz(p(3))
    const assertz1 = try Term.createStructure(alloc, "assertz", &[_]*Term{
        try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 1)}),
    });

    const asserta2 = try Term.createStructure(alloc, "asserta", &[_]*Term{
        try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 2)}),
    });

    const assertz3 = try Term.createStructure(alloc, "assertz", &[_]*Term{
        try Term.createStructure(alloc, "p", &[_]*Term{try Term.createNumber(alloc, 3)}),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    // Execute assertions
    var goals1 = [_]*Term{assertz1};
    _ = try eng.solve(&goals1, &env, 0, 0, handler, buf.writer(alloc));

    var goals2 = [_]*Term{asserta2};
    _ = try eng.solve(&goals2, &env, 0, 0, handler, buf.writer(alloc));

    var goals3 = [_]*Term{assertz3};
    _ = try eng.solve(&goals3, &env, 0, 0, handler, buf.writer(alloc));

    // Database should now be: p(2), p(1), p(3)
    try std.testing.expectEqual(@as(usize, 3), eng.db.items.len);

    // Verify order
    const first = eng.db.items[0].head;
    try std.testing.expect(first.* == .structure);
    try std.testing.expectEqual(@as(i64, 2), first.structure.args[0].number);

    const second = eng.db.items[1].head;
    try std.testing.expectEqual(@as(i64, 1), second.structure.args[0].number);

    const third = eng.db.items[2].head;
    try std.testing.expectEqual(@as(i64, 3), third.structure.args[0].number);
}

test "Engine - retractall" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add multiple facts
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "color", &[_]*Term{try Term.createAtom(alloc, "red")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "color", &[_]*Term{try Term.createAtom(alloc, "green")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "color", &[_]*Term{try Term.createAtom(alloc, "blue")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "size", &[_]*Term{try Term.createAtom(alloc, "large")}),
        .body = &[_]*Term{},
    });

    try std.testing.expectEqual(@as(usize, 4), eng.db.items.len);

    // Retract all color facts
    const retractall_goal = try Term.createStructure(alloc, "retractall", &[_]*Term{
        try Term.createStructure(alloc, "color", &[_]*Term{
            try Term.createVariable(alloc, "X"),
        }),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{retractall_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Should have only size(large) left
    try std.testing.expectEqual(@as(usize, 1), eng.db.items.len);
    try std.testing.expect(eng.db.items[0].head.* == .structure);
    try std.testing.expectEqualStrings("size", eng.db.items[0].head.structure.functor);
}

test "Engine - abolish" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add multiple predicates
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createAtom(alloc, "alice")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "person", &[_]*Term{try Term.createAtom(alloc, "bob")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "age", &[_]*Term{
            try Term.createAtom(alloc, "alice"),
            try Term.createNumber(alloc, 30),
        }),
        .body = &[_]*Term{},
    });

    try std.testing.expectEqual(@as(usize, 3), eng.db.items.len);

    // Abolish person/1
    const abolish_goal = try Term.createStructure(alloc, "abolish", &[_]*Term{
        try Term.createStructure(alloc, "/", &[_]*Term{
            try Term.createAtom(alloc, "person"),
            try Term.createNumber(alloc, 1),
        }),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{abolish_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Should have only age/2 left
    try std.testing.expectEqual(@as(usize, 1), eng.db.items.len);
    try std.testing.expectEqualStrings("age", eng.db.items[0].head.structure.functor);
}

test "Engine - clause" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add a fact and a rule
    // Fact: parent(john, mary)
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createAtom(alloc, "john"),
            try Term.createAtom(alloc, "mary"),
        }),
        .body = &[_]*Term{},
    });

    // Rule: grandparent(X, Y) :- parent(X, Z), parent(Z, Y)
    var rule_body = [_]*Term{
        try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createVariable(alloc, "X"),
            try Term.createVariable(alloc, "Z"),
        }),
        try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createVariable(alloc, "Z"),
            try Term.createVariable(alloc, "Y"),
        }),
    };
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "grandparent", &[_]*Term{
            try Term.createVariable(alloc, "X"),
            try Term.createVariable(alloc, "Y"),
        }),
        .body = &rule_body,
    });

    // Query: clause(parent(john, mary), Body)
    const clause_goal = try Term.createStructure(alloc, "clause", &[_]*Term{
        try Term.createStructure(alloc, "parent", &[_]*Term{
            try Term.createAtom(alloc, "john"),
            try Term.createAtom(alloc, "mary"),
        }),
        try Term.createVariable(alloc, "Body"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var solution_count: usize = 0;
    const CounterContext = struct {
        count: *usize,
    };
    var counter_ctx = CounterContext{ .count = &solution_count };

    const counter_handler = struct {
        fn handle(ctx_ptr: ?*anyopaque, _: EnvMap, _: *Engine) SolutionHandlerError!void {
            const ctx: *CounterContext = @ptrCast(@alignCast(ctx_ptr));
            ctx.count.* += 1;
        }
    };

    const handler = Engine.SolutionHandler{
        .context = &counter_ctx,
        .handle = counter_handler.handle,
    };

    var goals = [_]*Term{clause_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // Should find one clause for parent(john, mary)
    try std.testing.expectEqual(@as(usize, 1), solution_count);
}

test "Engine - findall" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add some test data
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "num", &[_]*Term{try Term.createNumber(alloc, 1)}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "num", &[_]*Term{try Term.createNumber(alloc, 2)}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "num", &[_]*Term{try Term.createNumber(alloc, 3)}),
        .body = &[_]*Term{},
    });

    // Query: findall(X, num(X), List)
    const findall_goal = try Term.createStructure(alloc, "findall", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createStructure(alloc, "num", &[_]*Term{try Term.createVariable(alloc, "X")}),
        try Term.createVariable(alloc, "List"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{findall_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // findall should succeed and List should be bound to [1, 2, 3]
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "List = [1, 2, 3]") != null);
}

test "Engine - findall empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Query: findall(X, nonexistent(X), List) should return []
    const findall_goal = try Term.createStructure(alloc, "findall", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createStructure(alloc, "nonexistent", &[_]*Term{try Term.createVariable(alloc, "X")}),
        try Term.createVariable(alloc, "List"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{findall_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // findall should succeed with empty list
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "true") != null or std.mem.indexOf(u8, buf.getItems(), "List") != null);
}

test "Engine - bagof" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add some test data
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "color", &[_]*Term{try Term.createAtom(alloc, "red")}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "color", &[_]*Term{try Term.createAtom(alloc, "green")}),
        .body = &[_]*Term{},
    });

    // Query: bagof(X, color(X), List)
    const bagof_goal = try Term.createStructure(alloc, "bagof", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createStructure(alloc, "color", &[_]*Term{try Term.createVariable(alloc, "X")}),
        try Term.createVariable(alloc, "List"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{bagof_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // bagof should succeed
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "List = [red, green]") != null);
}

test "Engine - setof" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    // Add some test data with duplicates
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "item", &[_]*Term{try Term.createNumber(alloc, 3)}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "item", &[_]*Term{try Term.createNumber(alloc, 1)}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "item", &[_]*Term{try Term.createNumber(alloc, 2)}),
        .body = &[_]*Term{},
    });
    try eng.addRule(Rule{
        .head = try Term.createStructure(alloc, "item", &[_]*Term{try Term.createNumber(alloc, 1)}),
        .body = &[_]*Term{},
    });

    // Query: setof(X, item(X), List)
    const setof_goal = try Term.createStructure(alloc, "setof", &[_]*Term{
        try Term.createVariable(alloc, "X"),
        try Term.createStructure(alloc, "item", &[_]*Term{try Term.createVariable(alloc, "X")}),
        try Term.createVariable(alloc, "List"),
    });

    var env = createEnv();
    defer env.deinit(alloc);

    var buf = TestBuffer.init(alloc);
    defer buf.deinit();

    var has_printed = false;
    var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
    const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

    var goals = [_]*Term{setof_goal};
    _ = try eng.solve(&goals, &env, 0, 0, handler, buf.writer(alloc));

    // setof should return sorted unique values [1, 2, 3]
    try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "List = [1, 2, 3]") != null);
}

test "Engine - unify_with_occurs_check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // Test 1: Normal unification should succeed
    {
        var parser = Parser.init(alloc, "unify_with_occurs_check(X, a).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "X = a") != null);
    }

    // Test 2: Cyclic unification should fail
    {
        var parser = Parser.init(alloc, "unify_with_occurs_check(X, f(X)).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        // Should fail (no output)
        try std.testing.expectEqualStrings("", buf.getItems());
    }

    // Test 3: Deep cyclic structure should fail
    {
        var parser = Parser.init(alloc, "unify_with_occurs_check(X, f(g(X))).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        // Should fail
        try std.testing.expectEqualStrings("", buf.getItems());
    }
}

test "Engine - acyclic_term" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // Test 1: Simple atom is acyclic
    {
        var parser = Parser.init(alloc, "acyclic_term(a).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "true") != null);
    }

    // Test 2: Structure f(a, b) is acyclic
    {
        var parser = Parser.init(alloc, "acyclic_term(f(a, b)).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "true") != null);
    }

    // Test 3: Unbound variable is acyclic
    {
        var parser = Parser.init(alloc, "acyclic_term(X).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "true") != null);
    }
}

test "Engine - term_variables/2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var eng = Engine.init(alloc);
    defer eng.deinit();

    const Parser = @import("parser.zig").Parser;

    // Test 1: No variables in atom
    {
        var parser = Parser.init(alloc, "term_variables(atom, Vars).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Vars = []") != null);
    }

    // Test 2: Single variable
    {
        var parser = Parser.init(alloc, "term_variables(X, Vars).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        try std.testing.expect(std.mem.indexOf(u8, buf.getItems(), "Vars = [X]") != null or
            std.mem.indexOf(u8, buf.getItems(), "Vars = [_") != null);
    }

    // Test 3: Structure with multiple variables
    {
        var parser = Parser.init(alloc, "term_variables(f(X, Y, Z), Vars).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        // Should have all three variables in order
        const output = buf.getItems();
        try std.testing.expect(std.mem.indexOf(u8, output, "X") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Y") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Z") != null);
    }

    // Test 4: Duplicate variables (should only appear once)
    {
        var parser = Parser.init(alloc, "term_variables(f(X, X, Y), Vars).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        // Should have X and Y, but X only once despite appearing twice
        const output = buf.getItems();
        try std.testing.expect(std.mem.indexOf(u8, output, "X") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Y") != null);
    }

    // Test 5: Nested structure
    {
        var parser = Parser.init(alloc, "term_variables(f(g(X, Y), h(Z)), Vars).");
        const goals = try parser.parseQuery();

        var env = createEnv();
        defer env.deinit(alloc);

        var buf = TestBuffer.init(alloc);
        defer buf.deinit();

        var has_printed = false;
        var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
        const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

        _ = try eng.solve(goals, &env, 0, 0, handler, buf.writer(alloc));
        // Should collect variables in depth-first, left-to-right order: X, Y, Z
        const output = buf.getItems();
        try std.testing.expect(std.mem.indexOf(u8, output, "X") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Y") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "Z") != null);
    }
}
