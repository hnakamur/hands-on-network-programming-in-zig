const std = @import("std");
const builtin = @import("builtin");
const IPv6 = std.x.os.IPv6;
const Socket = std.x.os.Socket;
const SocketAddressExt = @import("lib").SocketAddressExt;
const SocketIpv6Ext = @import("lib").SocketIpv6Ext;
const c = @cImport({
    @cInclude("time.h");
});

pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    const bind_address = try SocketAddressExt.parse("::", 8080);
    var socket_listen = try Socket.init(
        std.os.AF.INET6,
        std.os.SOCK.STREAM,
        0,
        .{},
    );
    defer socket_listen.deinit();

    try socket_listen.setReuseAddress(true);
    if (builtin.os.tag != .windows) {
        try socket_listen.setReusePort(true);
    }
    try SocketIpv6Ext.setV6OnlyOrNop(socket_listen, false);
    try socket_listen.bind(bind_address);
    try socket_listen.listen(10);
    std.debug.print("Waiting for a client connection.\n", .{});
    var conn = try socket_listen.accept(.{});
    defer conn.socket.deinit();
    std.debug.print("Client is connected from {}\n", .{conn.address});

    var request: [1024]u8 = undefined;
    const bytes_received = try conn.socket.read(request[0..], 0);
    std.debug.print("Received {} bytes.\n", .{bytes_received});

    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "Local time is: ";
    const bytes_sent = try conn.socket.write(response, 0);
    std.debug.print("Sent #1 {} of {} bytes.\n", .{ bytes_sent, response.len });

    var timer: c.time_t = undefined;
    if (c.time(&timer) < 0) {
        std.debug.print("time() failed. ({})\n", .{std.c._errno().*});
        return error.Time;
    }
    const time_msg = c.ctime(&timer);
    const time_msg_len = std.mem.indexOfSentinel(u8, 0, time_msg);
    const bytes_sent2 = try conn.socket.write(time_msg[0..time_msg_len], 0);
    std.debug.print("Sent #2 {} of {} bytes.\n", .{ bytes_sent2, time_msg_len });
}
