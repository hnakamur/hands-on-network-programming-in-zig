const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

/// startup WinSock on Windows, no-op on other OSes.
pub fn startup() !void {
    if (builtin.os.tag == .windows) {
        _ = try windows.WSAStartup(2, 2);
    }
}

/// cleanup WinSock on Windows, no-op on other OSes.
pub fn cleanup() void {
    if (builtin.os.tag == .windows) {
        windows.WSACleanup() catch |err| {
            // Generally speaking, log should not be written from a library,
            // but here I break the rule in favor of calling winsock.cleanup
            // simply like below:
            //    try winsock.startup();
            //    defer winsock.cleanup();
            std.log.err("error in WSACleanup: {s}", .{@errorName(err)});
        };
    }
}
