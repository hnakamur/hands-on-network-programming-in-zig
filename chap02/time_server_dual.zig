const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const IPv6 = std.x.os.IPv6;
const Socket = std.x.os.Socket;
const c = @cImport({
    @cInclude("time.h");
});

pub fn main() !void {
    const bind_address = Socket.Address.initIPv6(IPv6{
        .octets = IPv6.unspecified_octets,
        .scope_id = 0, // bind failed on Windows if this is IPv6.no_scope_id
    }, 8080);
    std.debug.print("bind_address={}\n", .{bind_address});
    std.debug.print("bind_address.ipv6.port={}, addr={}, scope_id={}\n", .{
        bind_address.ipv6.port,
        std.fmt.fmtSliceHexLower(bind_address.ipv6.host.octets[0..]),
        bind_address.ipv6.host.scope_id,
    });
    const native_address = bind_address.toNative();
    std.debug.print("native_address.port={}, flowinfo={}, addr={}, scope_id={}\n", .{
        std.mem.bigToNative(u16, native_address.ipv6.port),
        native_address.ipv6.flowinfo,
        std.fmt.fmtSliceHexLower(native_address.ipv6.addr[0..]),
        native_address.ipv6.scope_id,
    });

    std.debug.print("family={}, socktype={}, protocol={}\n", .{
        std.os.AF.INET6,
        std.os.SOCK.STREAM,
        0,
    });
    var socket_listen = try Socket.init(
        std.os.AF.INET6,
        std.os.SOCK.STREAM,
        0,
        .{},
    );
    defer socket_listen.deinit();

    // V6Only is need to set to be false explicitly on Windows for dual bind in IPv4 and IPv6.
    try setV6Only(socket_listen, false);
    try socket_listen.bind(bind_address);
    try socket_listen.listen(10);
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

fn setV6Only(socket: Socket, enabled: bool) !void {
    const level = if (is_windows)
        41 // should be defined as std.os.windows.ws2_32.IPPROTO.IPV6
    else
        std.os.IPPROTO.IPV6;
    const code = switch (builtin.os.tag) {
        .windows => std.os.windows.ws2_32.IPV6_V6ONLY,
        .linux => std.os.linux.IPV6.V6ONLY,
        else => @panic("IPV6_ONLY is not supported for this OS"),
    };
    std.debug.print("setV6Only, level={}, code={}\n", .{ level, code });
    return socket.setOption(level, code, std.mem.asBytes(&@as(u32, @boolToInt(enabled))));
}
