const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Windows exe

    const exe = b.addExecutable("chap01", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    deps.addAllTo(exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Linux exe

    const linux_exe = b.addExecutable("chap01-linux", "src/main_linux.zig");
    linux_exe.setTarget(target);
    linux_exe.setBuildMode(mode);
    linux_exe.linkLibC();
    deps.addAllTo(linux_exe);
    linux_exe.install();

    const linux_run_cmd = linux_exe.run();
    linux_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        linux_run_cmd.addArgs(args);
    }

    const linux_run_step = b.step("run-linux", "Run the app");
    linux_run_step.dependOn(&linux_run_cmd.step);

    // Test

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    deps.addAllTo(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
