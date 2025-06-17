const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const getopt_lib_mod = b.createModule(.{
        .root_source_file = b.path("getopt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const getopt_example_exe_mod = b.createModule(.{
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "getopt",
        .root_module = getopt_lib_mod,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = getopt_example_exe_mod,
    });
    b.installArtifact(exe);

    const getopt_lib_unit_tests = b.addTest(.{ .root_module = getopt_lib_mod });
    const run_tests = b.addRunArtifact(getopt_lib_unit_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
