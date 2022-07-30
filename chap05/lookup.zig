const std = @import("std");
const Args = @import("lib").Args;
const winsock = @import("lib").winsock;

const log_level = std.log.debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 2) {
        const exe_name = if (args.args.len > 0) std.fs.path.basename(args.args[0]) else "lookup";
        std.debug.print("Usage: {s} hostname\nExample: {s} example.com\n", .{ exe_name, exe_name });
        std.os.exit(2);
    }

    const hostname = args.args[1];
    std.debug.print("hostname={s}\n", .{hostname});

    try winsock.startup();
    defer winsock.cleanup();
}
