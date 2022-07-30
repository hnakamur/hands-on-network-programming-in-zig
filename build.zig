const std = @import("std");
const builtin = @import("builtin");
const deps = @import("./deps.zig");

const BuildExeInfo = struct {
    exe_name: []const u8,
    src: []const u8,
};

const BuildRunStepInfo = struct {
    exe_name: []const u8,
    win_src: []const u8,
    linux_src: []const u8,
    run_step_name: []const u8,
    run_step_description: []const u8,
};

const pkgs = struct {
    const lib = std.build.Pkg{
        .name = "lib",
        .source = .{ .path = "./lib/main.zig" },
    };
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

        const run_step = b.step("run_chap01", "Run the chap01 app");
        run_step.dependOn(&run_cmd.step);
    }

    const lib = b.addStaticLibrary(pkgs.lib.name, pkgs.lib.source.path);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.install();

    const exe_infos = [_]BuildExeInfo{
        .{ .exe_name = "time_server_dual", .src = "chap02/time_server_dual.zig" },
        .{ .exe_name = "tcp_client", .src = "chap03/tcp_client.zig" },
        .{ .exe_name = "tcp_serve_toupper", .src = "chap03/tcp_serve_toupper.zig" },
        .{ .exe_name = "udp_client", .src = "chap04/udp_client.zig" },
        .{ .exe_name = "udp_serve_toupper_simple", .src = "chap04/udp_serve_toupper_simple.zig" },
        .{ .exe_name = "udp_serve_toupper", .src = "chap04/udp_serve_toupper.zig" },
    };
    for (exe_infos) |info| {
        const exe = b.addExecutable(info.exe_name, info.src);
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.linkLibC();
        exe.addPackage(pkgs.lib);
        exe.install();
    }

    const infos = [_]BuildRunStepInfo{
        .{
            .exe_name = "chap02_time_server",
            .win_src = "chap02/time_server_windows.zig",
            .linux_src = "chap02/time_server_linux.zig",
            .run_step_name = "run_chap02_time_server",
            .run_step_description = "Run the chap02_time_server app",
        },
        .{
            .exe_name = "chap02_time_server_ipv6",
            .win_src = "chap02/time_server_ipv6_windows.zig",
            .linux_src = "chap02/time_server_ipv6_linux.zig",
            .run_step_name = "run_chap02_time_server_ipv6",
            .run_step_description = "Run the chap02_time_server_ipv6 app",
        },
        .{
            .exe_name = "chap02_time_server_dual",
            .win_src = "chap02/time_server_dual_windows.zig",
            .linux_src = "chap02/time_server_dual_linux.zig",
            .run_step_name = "run_chap02_time_server_dual",
            .run_step_description = "Run the chap02_time_server_dual app",
        },
        .{
            .exe_name = "chap03_tcp_client",
            .win_src = "chap03/tcp_client_windows.zig",
            .linux_src = "chap03/tcp_client_linux.zig",
            .run_step_name = "run_chap03_tcp_client",
            .run_step_description = "Run the chap03_tcp_client app",
        },
        .{
            .exe_name = "chap03_tcp_serve_toupper",
            .win_src = "chap03/tcp_serve_toupper_windows.zig",
            .linux_src = "chap03/tcp_serve_toupper_linux.zig",
            .run_step_name = "run_chap03_tcp_serve_toupper",
            .run_step_description = "Run the chap03_tcp_serve_toupper app",
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

    const lib_tests = b.addTest("lib/test_main.zig");
    lib_tests.setTarget(target);
    lib_tests.setBuildMode(mode);
    lib_tests.addPackage(pkgs.lib);

    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    lib_tests.filter = test_filter;

    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    if (coverage) {
        lib_tests.setExecCmd(&[_]?[]const u8{
            "kcov",
            "--include-path=./src",
            "kcov-output", // output dir for kcov
            null, // to get zig to use the --test-cmd-bin flag
        });
    }

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&lib_tests.step);
}
