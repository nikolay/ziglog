const std = @import("std");
const test_runner = @import("test_runner.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_files = [_][]const u8{
        "tests/integration/basic.pl",
        "tests/integration/family.pl",
        "tests/integration/lists.pl",
        "tests/integration/dcg.pl",
        "tests/integration/comments_test.pl",
        "tests/integration/block_comments.pl",
        "tests/integration/choice_point_elimination.pl",
        "tests/integration/tail_call_optimization.pl",
        "tests/integration/arithmetic.pl",
        "tests/integration/floats.pl",
        "tests/integration/format.pl",
        "tests/integration/unicode_escapes.pl",
        "tests/integration/nondecimal.pl",
        "tests/integration/digit_grouping.pl",
        "tests/integration/infinity_nan.pl",
        "tests/integration/control.pl",
    };

    var failed = false;
    var total_passed: usize = 0;
    var total_failed: usize = 0;

    std.debug.print("\n========================================\n", .{});
    std.debug.print("Running Integration Tests\n", .{});
    std.debug.print("========================================\n\n", .{});

    for (test_files) |file| {
        std.debug.print("Running {s}...\n", .{file});
        test_runner.runTestFile(allocator, file) catch |err| {
            if (err == error.TestsFailed) {
                failed = true;
                total_failed += 1;
            } else {
                std.debug.print("Error running {s}: {}\n", .{ file, err });
                failed = true;
                total_failed += 1;
            }
            continue;
        };
        total_passed += 1;
        std.debug.print("\n", .{});
    }

    std.debug.print("========================================\n", .{});
    std.debug.print("Integration Test Summary\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("Passed: {d}/{d} test files\n", .{ total_passed, test_files.len });

    if (failed) {
        std.debug.print("\n❌ Some tests failed!\n", .{});
        std.process.exit(1);
    } else {
        std.debug.print("\n✅ All tests passed!\n", .{});
    }
}
