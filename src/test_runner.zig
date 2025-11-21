const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("parser.zig").Parser;
const Engine = @import("engine.zig").Engine;
const EnvMap = @import("engine.zig").EnvMap;
const copyTerm = @import("engine.zig").copyTerm;

/// Test file format:
/// % EXPECT: <expected output>
/// ?- query.
///
/// Lines starting with % EXPECT: specify expected output for the next query
/// Multiple EXPECT lines can be used for multiple solutions

const TestCase = struct {
    query: []const u8,
    expected: []const []const u8,
    line_num: usize,
};

pub fn runTestFile(allocator: Allocator, file_path: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var engine = Engine.init(alloc);
    defer engine.deinit();

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;

    var current_expects = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (current_expects.items) |item| {
            allocator.free(item);
        }
        current_expects.deinit(allocator);
    }

    var failed = false;
    var total_queries: usize = 0;
    var passed_queries: usize = 0;

    while (line_iter.next()) |line| {
        line_num += 1;
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0) continue;

        // Check for EXPECT directive
        if (std.mem.startsWith(u8, trimmed, "% EXPECT:")) {
            const expect = std.mem.trim(u8, trimmed[9..], " \t");
            try current_expects.append(allocator, try allocator.dupe(u8, expect));
            continue;
        }

        // Skip comments
        if (std.mem.startsWith(u8, trimmed, "%")) continue;
        if (std.mem.startsWith(u8, trimmed, "/*")) continue;
        if (std.mem.startsWith(u8, trimmed, "*/")) continue;

        // Query
        if (std.mem.startsWith(u8, trimmed, "?-")) {
            total_queries += 1;
            const query_text = std.mem.trim(u8, trimmed[2..], " \t"); // Strip "?-" prefix

            // Parse and execute query
            var parser = Parser.init(alloc, query_text);
            const goals = parser.parseQuery() catch |err| {
                std.debug.print("❌ {s}:{d}: Parse error: {}\n", .{ file_path, line_num, err });
                failed = true;
                for (current_expects.items) |item| allocator.free(item);
                current_expects.clearRetainingCapacity();
                continue;
            };

            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(alloc);

            var has_printed = false;
            const TestHandlerContext = struct {
                buf: *std.ArrayListUnmanaged(u8),
                alloc: Allocator,
                has_printed: *bool,
            };

            const testHandle = struct {
                fn handle(ctx_ptr: ?*anyopaque, env: EnvMap, _: *Engine) !void {
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
                        try out_writer.print("true", .{});
                    }
                    ctx.has_printed.* = true;
                }
            }.handle;

            var ctx = TestHandlerContext{ .buf = &buf, .alloc = alloc, .has_printed = &has_printed };
            const handler = Engine.SolutionHandler{ .context = &ctx, .handle = testHandle };

            var env = EnvMap{};
            defer env.deinit(alloc);

            _ = engine.solve(goals, &env, 0, 0, handler, buf.writer(alloc)) catch |err| {
                std.debug.print("❌ {s}:{d}: Runtime error: {}\n", .{ file_path, line_num, err });
                failed = true;
                for (current_expects.items) |item| allocator.free(item);
                current_expects.clearRetainingCapacity();
                continue;
            };

            const output = buf.items;

            // Check expectations
            if (current_expects.items.len > 0) {
                var all_matched = true;

                if (current_expects.items.len == 1 and std.mem.eql(u8, current_expects.items[0], "false")) {
                    // Expect failure
                    if (output.len != 0) {
                        std.debug.print("❌ {s}:{d}: Expected false, got: {s}\n", .{ file_path, line_num, output });
                        all_matched = false;
                    }
                } else {
                    // Expect specific output(s)
                    for (current_expects.items) |expect| {
                        if (std.mem.indexOf(u8, output, expect) == null) {
                            std.debug.print("❌ {s}:{d}: Expected '{s}' in output, got: {s}\n", .{ file_path, line_num, expect, output });
                            all_matched = false;
                        }
                    }
                }

                if (all_matched) {
                    passed_queries += 1;
                    std.debug.print("✓ {s}:{d}\n", .{ file_path, line_num });
                } else {
                    failed = true;
                }
            } else {
                // No expectation, just print output
                std.debug.print("  {s}:{d}: {s}\n", .{ file_path, line_num, output });
                passed_queries += 1;
            }

            for (current_expects.items) |item| allocator.free(item);
            current_expects.clearRetainingCapacity();
        } else {
            // Rule or fact
            var parser = Parser.init(alloc, trimmed);
            const rule = parser.parseRule() catch |err| {
                std.debug.print("❌ {s}:{d}: Parse error: {}\n", .{ file_path, line_num, err });
                failed = true;
                continue;
            };
            try engine.addRule(rule);
        }
    }

    std.debug.print("\n{s}: {d}/{d} queries passed\n", .{ file_path, passed_queries, total_queries });

    if (failed) {
        return error.TestsFailed;
    }
}

test "test runner" {
    // This will be called by build.zig
}
