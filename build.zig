const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // === Library Module ===
    // Primary artifact: the bento layout engine as an importable Zig module
    const bento_mod = b.addModule("bento", .{
        .root_source_file = b.path("src/bento.zig"),
        .target = target,
        .optimize = optimize,
    });

    // === Demo Executable (optional example) ===
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Demo depends on vaxis for TUI rendering
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    demo_mod.addImport("bento", bento_mod);

    const demo = b.addExecutable(.{
        .name = "bento-demo",
        .root_module = demo_mod,
    });
    b.installArtifact(demo);

    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the TUI demo");
    run_step.dependOn(&run_cmd.step);

    // === Tests ===
    const test_step = b.step("test", "Run library tests");
    const lib_tests = b.addTest(.{
        .root_module = bento_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
}
