const std = @import("std");
const builtin = @import("builtin");
const Args = @import("lib").Args;
const mystd = @import("lib").mystd;
const winsock = @import("lib").winsock;

pub const log_level: std.log.Level = .debug;

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

    var hints: mystd.os.addrinfo = std.mem.zeroes(mystd.os.addrinfo);
    hints.flags = mystd.os.AI.ALL;
    var peer_address: *mystd.os.addrinfo = undefined;
    try mystd.os.getaddrinfo(allocator, hostname, null, &hints, &peer_address);
    defer mystd.os.freeaddrinfo(peer_address);

    std.debug.print("Remote address is:\n", .{});
    var address: ?*mystd.os.addrinfo = peer_address;
    while (address) |addr| {
        var address_buffer: [100]u8 = undefined;
        var address_slice: []u8 = address_buffer[0..];
        try mystd.os.getnameinfo(
            addr.addr.?,
            addr.addrlen,
            &address_slice,
            null,
            mystd.os.NI.NUMERICHOST,
        );
        std.debug.print("\t{s}\n", .{address_slice});
        address = addr.next;
    }
}
