const std = @import("std");
const ast = @import("ast.zig");
const Term = ast.Term;

/// Represents a numeric value that can be either an integer or float
pub const NumericValue = union(enum) {
    int: i64,
    float: f64,

    /// Convert to float, promoting integers if necessary
    pub fn toFloat(self: NumericValue) f64 {
        return switch (self) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
        };
    }

    /// Check if value is an integer (not a float)
    pub fn isInt(self: NumericValue) bool {
        return self == .int;
    }
};

/// Evaluates a nullary (0-argument) arithmetic function.
/// Currently supports: nan, inf
/// Returns error.UnknownOperator if the function name is not recognized.
fn evaluateNullaryFunction(name: []const u8) !NumericValue {
    if (std.mem.eql(u8, name, "nan")) {
        return .{ .float = std.math.nan(f64) };
    }
    if (std.mem.eql(u8, name, "inf")) {
        return .{ .float = std.math.inf(f64) };
    }
    return error.UnknownOperator;
}

/// Evaluate an arithmetic expression term to a numeric value.
/// Supports both integer and floating-point arithmetic with automatic type promotion.
///
/// Operators:
/// - Unary: abs, sign, -
/// - Binary arithmetic: +, -, *, / (always float), // (int div), div, mod, rem
/// - Min/max: min, max
/// - Nullary functions: nan, inf
///
/// Returns error if:
/// - Variable is uninstantiated
/// - Term is not a number or arithmetic expression
/// - Operator is unknown
/// - Type mismatch (e.g., integer-only operator on float)
pub fn evaluate(term: *Term, env: anytype, resolveFn: anytype) !NumericValue {
    const t = resolveFn(term, env);
    switch (t.*) {
        .number => |n| return .{ .int = n },
        .float => |f| return .{ .float = f },
        .variable => return error.InstantiationError,
        .atom => |a| return evaluateNullaryFunction(a),
        .structure => |s| {
            // Nullary functions (0 arguments)
            if (s.args.len == 0) {
                return evaluateNullaryFunction(s.functor);
            }

            // Unary operators
            if (s.args.len == 1) {
                const arg = try evaluate(s.args[0], env, resolveFn);
                if (std.mem.eql(u8, s.functor, "abs")) {
                    return switch (arg) {
                        .int => |i| .{ .int = if (i < 0) -i else i },
                        .float => |f| .{ .float = if (f < 0.0) -f else f },
                    };
                }
                if (std.mem.eql(u8, s.functor, "sign")) {
                    return switch (arg) {
                        .int => |i| .{ .int = if (i < 0) @as(i64, -1) else if (i > 0) @as(i64, 1) else @as(i64, 0) },
                        .float => |f| .{ .float = if (f < 0.0) @as(f64, -1.0) else if (f > 0.0) @as(f64, 1.0) else @as(f64, 0.0) },
                    };
                }
                if (std.mem.eql(u8, s.functor, "-")) {
                    return switch (arg) {
                        .int => |i| .{ .int = -i },
                        .float => |f| .{ .float = -f },
                    };
                }
                return error.UnknownOperator;
            }

            // Binary operators
            if (s.args.len == 2) {
                const left = try evaluate(s.args[0], env, resolveFn);
                const right = try evaluate(s.args[1], env, resolveFn);

                // Determine if we need float arithmetic
                const use_float = !left.isInt() or !right.isInt();

                // Basic arithmetic - if either is float, result is float
                if (std.mem.eql(u8, s.functor, "+")) {
                    if (use_float) {
                        return .{ .float = left.toFloat() + right.toFloat() };
                    } else {
                        return .{ .int = left.int + right.int };
                    }
                }
                if (std.mem.eql(u8, s.functor, "-")) {
                    if (use_float) {
                        return .{ .float = left.toFloat() - right.toFloat() };
                    } else {
                        return .{ .int = left.int - right.int };
                    }
                }
                if (std.mem.eql(u8, s.functor, "*")) {
                    if (use_float) {
                        return .{ .float = left.toFloat() * right.toFloat() };
                    } else {
                        return .{ .int = left.int * right.int };
                    }
                }

                // Division: / always returns float in Prolog
                if (std.mem.eql(u8, s.functor, "/")) {
                    return .{ .float = left.toFloat() / right.toFloat() };
                }

                // Integer division operators - only work on integers
                if (std.mem.eql(u8, s.functor, "//")) {
                    if (!left.isInt() or !right.isInt()) return error.TypeException;
                    return .{ .int = @divTrunc(left.int, right.int) };
                }
                if (std.mem.eql(u8, s.functor, "div")) {
                    if (!left.isInt() or !right.isInt()) return error.TypeException;
                    return .{ .int = @divFloor(left.int, right.int) };
                }

                // Modulo and remainder - integer only
                if (std.mem.eql(u8, s.functor, "mod")) {
                    if (!left.isInt() or !right.isInt()) return error.TypeException;
                    const div_result = @divFloor(left.int, right.int);
                    return .{ .int = left.int - (div_result * right.int) };
                }
                if (std.mem.eql(u8, s.functor, "rem")) {
                    if (!left.isInt() or !right.isInt()) return error.TypeException;
                    const div_result = @divTrunc(left.int, right.int);
                    return .{ .int = left.int - (div_result * right.int) };
                }

                // Min/max
                if (std.mem.eql(u8, s.functor, "min")) {
                    if (use_float) {
                        const lf = left.toFloat();
                        const rf = right.toFloat();
                        return .{ .float = if (lf < rf) lf else rf };
                    } else {
                        return .{ .int = if (left.int < right.int) left.int else right.int };
                    }
                }
                if (std.mem.eql(u8, s.functor, "max")) {
                    if (use_float) {
                        const lf = left.toFloat();
                        const rf = right.toFloat();
                        return .{ .float = if (lf > rf) lf else rf };
                    } else {
                        return .{ .int = if (left.int > right.int) left.int else right.int };
                    }
                }
            }
            return error.UnknownOperator;
        },
        .string => return error.TypeException,
    }
}

test "arithmetic - basic operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test integer arithmetic
    const two = try Term.createNumber(alloc, 2);
    const three = try Term.createNumber(alloc, 3);
    const add = try Term.createStructure(alloc, "+", &[_]*Term{ two, three });

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    const result = try evaluate(add, empty_env, identity);
    try std.testing.expectEqual(NumericValue{ .int = 5 }, result);
}

test "arithmetic - type promotion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const int_val = try Term.createNumber(alloc, 10);
    const float_val = try Term.createFloat(alloc, 2.5);
    const expr = try Term.createStructure(alloc, "*", &[_]*Term{ int_val, float_val });

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    const result = try evaluate(expr, empty_env, identity);
    try std.testing.expect(result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), result.float, 0.001);
}
