const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();
    _ = allocator;

    var ret_err: ?anyerror = null;
    {
        if (builtin.os.tag == .windows) {
            _ = try windows.WSAStartup(2, 2);
        }
        defer if (builtin.os.tag == .windows) {
            windows.WSACleanup() catch |err| {
                ret_err = err;
            };
        };

    }
    if (ret_err) |err| return err;
}
