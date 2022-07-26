const std = @import("std");
const builtin = @import("builtin");
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

    {
        const exe = b.addExecutable("chap01", if (builtin.os.tag == .windows)
            "chap01/main_windows.zig"
        else
            "chap01/main_linux.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        if (builtin.os.tag != .windows) {
            exe.linkLibC();
        }
        deps.addAllTo(exe);
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-chap01", "Run the chap01 app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const exe = b.addExecutable("chap02_time_server", if (builtin.os.tag == .windows)
            "chap02/time_server_windows.zig"
        else
            "chap02/time_server_linux.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.linkLibC();
        deps.addAllTo(exe);
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-chap02", "Run the chap02 app");
        run_step.dependOn(&run_cmd.step);
    }
}
