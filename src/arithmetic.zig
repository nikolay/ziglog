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
/// - Rounding: floor, ceiling, round, truncate (return integer)
/// - Type conversion: float (returns float)
/// - Math functions: sqrt, exp, log (return float)
/// - Trigonometric: sin, cos, tan, atan (return float)
/// - Binary arithmetic: +, -, *, / (always float), // (int div), div, mod, rem
/// - Power: **, ^ (return float)
/// - Two-argument: atan2 (returns float)
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

                // Rounding functions - always return integer
                if (std.mem.eql(u8, s.functor, "floor")) {
                    const f = arg.toFloat();
                    return .{ .int = @intFromFloat(@floor(f)) };
                }
                if (std.mem.eql(u8, s.functor, "ceiling")) {
                    const f = arg.toFloat();
                    return .{ .int = @intFromFloat(@ceil(f)) };
                }
                if (std.mem.eql(u8, s.functor, "round")) {
                    const f = arg.toFloat();
                    return .{ .int = @intFromFloat(@round(f)) };
                }
                if (std.mem.eql(u8, s.functor, "truncate")) {
                    const f = arg.toFloat();
                    return .{ .int = @intFromFloat(@trunc(f)) };
                }

                // Float conversion - always returns float
                if (std.mem.eql(u8, s.functor, "float")) {
                    return .{ .float = arg.toFloat() };
                }

                // Square root - always returns float
                if (std.mem.eql(u8, s.functor, "sqrt")) {
                    const f = arg.toFloat();
                    return .{ .float = @sqrt(f) };
                }

                // Trigonometric functions - always return float
                if (std.mem.eql(u8, s.functor, "sin")) {
                    const f = arg.toFloat();
                    return .{ .float = @sin(f) };
                }
                if (std.mem.eql(u8, s.functor, "cos")) {
                    const f = arg.toFloat();
                    return .{ .float = @cos(f) };
                }
                if (std.mem.eql(u8, s.functor, "tan")) {
                    const f = arg.toFloat();
                    return .{ .float = @tan(f) };
                }
                if (std.mem.eql(u8, s.functor, "atan")) {
                    const f = arg.toFloat();
                    return .{ .float = std.math.atan(f) };
                }

                // Exponential and logarithm - always return float
                if (std.mem.eql(u8, s.functor, "exp")) {
                    const f = arg.toFloat();
                    return .{ .float = @exp(f) };
                }
                if (std.mem.eql(u8, s.functor, "log")) {
                    const f = arg.toFloat();
                    return .{ .float = @log(f) };
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
                const is_add = std.mem.eql(u8, s.functor, "+");
                const is_sub = std.mem.eql(u8, s.functor, "-");
                const is_mul = std.mem.eql(u8, s.functor, "*");

                if (is_add or is_sub or is_mul) {
                    if (use_float) {
                        const lf = left.toFloat();
                        const rf = right.toFloat();
                        const result = if (is_add) lf + rf else if (is_sub) lf - rf else lf * rf;
                        return .{ .float = result };
                    } else {
                        const result = if (is_add) left.int + right.int else if (is_sub) left.int - right.int else left.int * right.int;
                        return .{ .int = result };
                    }
                }

                // Division: / always returns float in Prolog
                if (std.mem.eql(u8, s.functor, "/")) {
                    return .{ .float = left.toFloat() / right.toFloat() };
                }

                // Integer-only operators: division and modulo/remainder
                const is_int_div = std.mem.eql(u8, s.functor, "//");
                const is_div = std.mem.eql(u8, s.functor, "div");
                const is_mod = std.mem.eql(u8, s.functor, "mod");
                const is_rem = std.mem.eql(u8, s.functor, "rem");

                if (is_int_div or is_div or is_mod or is_rem) {
                    if (!left.isInt() or !right.isInt()) return error.TypeException;

                    if (is_int_div) {
                        return .{ .int = @divTrunc(left.int, right.int) };
                    } else if (is_div) {
                        return .{ .int = @divFloor(left.int, right.int) };
                    } else {
                        // mod or rem: compute via division and subtraction
                        const div_result = if (is_mod) @divFloor(left.int, right.int) else @divTrunc(left.int, right.int);
                        return .{ .int = left.int - (div_result * right.int) };
                    }
                }

                // Min/max - ISO Prolog: preserve type of winning value
                if (std.mem.eql(u8, s.functor, "min") or std.mem.eql(u8, s.functor, "max")) {
                    const is_min = std.mem.eql(u8, s.functor, "min");
                    // Compare numerically (converting to float if needed)
                    const lf = left.toFloat();
                    const rf = right.toFloat();
                    // Return the winning value in its original type
                    const left_wins = if (is_min) lf < rf else lf > rf;
                    const right_wins = if (is_min) rf < lf else rf > lf;

                    if (left_wins) {
                        return left;
                    } else if (right_wins) {
                        return right;
                    } else {
                        // Equal values: if types differ, prefer float (ISO behavior)
                        return if (use_float) (if (left.isInt()) right else left) else left;
                    }
                }

                // Power operator - always returns float
                if (std.mem.eql(u8, s.functor, "**") or std.mem.eql(u8, s.functor, "^")) {
                    const lf = left.toFloat();
                    const rf = right.toFloat();
                    return .{ .float = std.math.pow(f64, lf, rf) };
                }

                // atan2 - two-argument arctangent
                if (std.mem.eql(u8, s.functor, "atan2")) {
                    const lf = left.toFloat();
                    const rf = right.toFloat();
                    return .{ .float = std.math.atan2(lf, rf) };
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

test "arithmetic - rounding functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    // Test floor
    const floor_val = try Term.createFloat(alloc, 3.7);
    const floor_expr = try Term.createStructure(alloc, "floor", &[_]*Term{floor_val});
    const floor_result = try evaluate(floor_expr, empty_env, identity);
    try std.testing.expectEqual(NumericValue{ .int = 3 }, floor_result);

    // Test ceiling
    const ceil_val = try Term.createFloat(alloc, 3.2);
    const ceil_expr = try Term.createStructure(alloc, "ceiling", &[_]*Term{ceil_val});
    const ceil_result = try evaluate(ceil_expr, empty_env, identity);
    try std.testing.expectEqual(NumericValue{ .int = 4 }, ceil_result);

    // Test round
    const round_val = try Term.createFloat(alloc, 3.5);
    const round_expr = try Term.createStructure(alloc, "round", &[_]*Term{round_val});
    const round_result = try evaluate(round_expr, empty_env, identity);
    try std.testing.expectEqual(NumericValue{ .int = 4 }, round_result);

    // Test truncate
    const trunc_val = try Term.createFloat(alloc, -3.7);
    const trunc_expr = try Term.createStructure(alloc, "truncate", &[_]*Term{trunc_val});
    const trunc_result = try evaluate(trunc_expr, empty_env, identity);
    try std.testing.expectEqual(NumericValue{ .int = -3 }, trunc_result);
}

test "arithmetic - math functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    // Test sqrt
    const sqrt_val = try Term.createNumber(alloc, 16);
    const sqrt_expr = try Term.createStructure(alloc, "sqrt", &[_]*Term{sqrt_val});
    const sqrt_result = try evaluate(sqrt_expr, empty_env, identity);
    try std.testing.expect(sqrt_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), sqrt_result.float, 0.0001);

    // Test exp
    const exp_val = try Term.createNumber(alloc, 1);
    const exp_expr = try Term.createStructure(alloc, "exp", &[_]*Term{exp_val});
    const exp_result = try evaluate(exp_expr, empty_env, identity);
    try std.testing.expect(exp_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 2.71828), exp_result.float, 0.0001);

    // Test log (natural logarithm)
    const log_val = try Term.createFloat(alloc, 2.71828);
    const log_expr = try Term.createStructure(alloc, "log", &[_]*Term{log_val});
    const log_result = try evaluate(log_expr, empty_env, identity);
    try std.testing.expect(log_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), log_result.float, 0.0001);
}

test "arithmetic - trigonometric functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    const pi = std.math.pi;

    // Test sin
    const sin_val = try Term.createFloat(alloc, pi / 2.0);
    const sin_expr = try Term.createStructure(alloc, "sin", &[_]*Term{sin_val});
    const sin_result = try evaluate(sin_expr, empty_env, identity);
    try std.testing.expect(sin_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sin_result.float, 0.0001);

    // Test cos
    const cos_val = try Term.createFloat(alloc, 0.0);
    const cos_expr = try Term.createStructure(alloc, "cos", &[_]*Term{cos_val});
    const cos_result = try evaluate(cos_expr, empty_env, identity);
    try std.testing.expect(cos_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), cos_result.float, 0.0001);

    // Test tan
    const tan_val = try Term.createFloat(alloc, pi / 4.0);
    const tan_expr = try Term.createStructure(alloc, "tan", &[_]*Term{tan_val});
    const tan_result = try evaluate(tan_expr, empty_env, identity);
    try std.testing.expect(tan_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), tan_result.float, 0.0001);

    // Test atan
    const atan_val = try Term.createNumber(alloc, 1);
    const atan_expr = try Term.createStructure(alloc, "atan", &[_]*Term{atan_val});
    const atan_result = try evaluate(atan_expr, empty_env, identity);
    try std.testing.expect(atan_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, pi / 4.0), atan_result.float, 0.0001);
}

test "arithmetic - power and atan2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    // Test power operator **
    const base = try Term.createNumber(alloc, 2);
    const exp = try Term.createNumber(alloc, 3);
    const pow_expr = try Term.createStructure(alloc, "**", &[_]*Term{ base, exp });
    const pow_result = try evaluate(pow_expr, empty_env, identity);
    try std.testing.expect(pow_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), pow_result.float, 0.0001);

    // Test atan2
    const y = try Term.createNumber(alloc, 1);
    const x = try Term.createNumber(alloc, 1);
    const atan2_expr = try Term.createStructure(alloc, "atan2", &[_]*Term{ y, x });
    const atan2_result = try evaluate(atan2_expr, empty_env, identity);
    try std.testing.expect(atan2_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, std.math.pi / 4.0), atan2_result.float, 0.0001);
}

test "arithmetic - float conversion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const EmptyEnv = struct {};
    const empty_env = EmptyEnv{};
    const identity = struct {
        fn resolve(t: *Term, _: EmptyEnv) *Term {
            return t;
        }
    }.resolve;

    // Test float conversion from integer
    const int_val = try Term.createNumber(alloc, 42);
    const float_expr = try Term.createStructure(alloc, "float", &[_]*Term{int_val});
    const float_result = try evaluate(float_expr, empty_env, identity);
    try std.testing.expect(float_result == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), float_result.float, 0.0001);
}
