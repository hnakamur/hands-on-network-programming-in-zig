const std = @import("std");
const builtin = @import("builtin");
const deps = @import("./deps.zig");

const BuildRunStepInfo = struct {
    exe_name: []const u8,
    win_src: []const u8,
    linux_src: []const u8,
    run_step_name: []const u8,
    run_step_description: []const u8,
};

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
        const exe = b.addExecutable(
            "chap01",
            if (builtin.os.tag == .windows)
                "chap01/main_windows.zig"
            else
                "chap01/main_linux.zig",
        );
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

    const infos = [_]BuildRunStepInfo{
        .{
            .exe_name = "chap02_time_server",
            .win_src = "chap02/time_server_windows.zig",
            .linux_src = "chap02/time_server_linux.zig",
            .run_step_name = "run-chap02",
            .run_step_description = "Run the chap02_time_server app",
        },
        .{
            .exe_name = "chap02_time_server_ipv6",
            .win_src = "chap02/time_server_ipv6_windows.zig",
            .linux_src = "chap02/time_server_ipv6_linux.zig",
            .run_step_name = "run-chap02-ipv6",
            .run_step_description = "Run the chap02_time_server_ipv6 app",
        },
        .{
            .exe_name = "chap02_time_server_dual",
            .win_src = "chap02/time_server_dual_windows.zig",
            .linux_src = "chap02/time_server_dual_linux.zig",
            .run_step_name = "run-chap02-dual",
            .run_step_description = "Run the chap02_time_server_dual app",
        },
    };
    for (infos) |info| {
        const exe = b.addExecutable(
            info.exe_name,
            if (builtin.os.tag == .windows)
                info.win_src
            else
                info.linux_src,
        );
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

        const run_step = b.step(info.run_step_name, info.run_step_description);
        run_step.dependOn(&run_cmd.step);
    }
}
