const std = @import("std");

const Args = @This();

args: [][]const u8 = .{},

pub fn init(allocator: std.mem.Allocator) !Args {
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();

    _ = it.skip();

    var args_list = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (args_list.items) |arg| allocator.free(arg);
        args_list.deinit(allocator);
    }

    while (it.next()) |arg| {
        const len = std.mem.indexOfSentinel(u8, 0, arg);
        const arg_copy = try allocator.dupe(u8, arg[0..len]);
        errdefer allocator.free(arg_copy);
        try args_list.append(allocator, arg_copy);
    }

    return Args{ .args = args_list.toOwnedSlice(allocator) };
}

pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
    for (self.args) |arg| allocator.free(arg);
    allocator.free(self.args);
}
