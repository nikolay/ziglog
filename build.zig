const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ziglog",
        .root_module = exe_mod,
    });

    // Add isocline C library (pure C, much simpler than replxx!)
    // Note: isocline.c includes all other files, so we only compile that one!
    // isocline.c already defines _XOPEN_SOURCE internally, so we don't need to add it
    const isocline_sources = [_][]const u8{
        "src/isocline/isocline.c",
    };

    for (isocline_sources) |src| {
        exe.addCSourceFile(.{
            .file = b.path(src),
            .flags = &[_][]const u8{"-std=c99"},
        });
    }

    exe.addIncludePath(b.path("src/isocline"));
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Integration tests using .pl files
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("src/integration_test_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const integration_tests = b.addExecutable(.{
        .name = "integration-tests",
        .root_module = integration_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.step.dependOn(b.getInstallStep());

    const integration_step = b.step("test-integration", "Run integration tests from .pl files");
    integration_step.dependOn(&run_integration_tests.step);

    // Run both unit and integration tests
    const all_tests_step = b.step("test-all", "Run all tests (unit + integration)");
    all_tests_step.dependOn(&run_exe_unit_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
}
