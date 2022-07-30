const std = @import("std");
const builtin = @import("builtin");
const Socket = std.x.os.Socket;
const Args = @import("lib").Args;
const parsePort = @import("lib").parsePort;
const SocketAddressExt = @import("lib").SocketAddressExt;
const SocketIpv6Ext = @import("lib").SocketIpv6Ext;
const SocketUdpExt = @import("lib").SocketUdpExt;
const FdSet = @import("lib").FdSet;
const select = @import("lib").select;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 1) {
        std.debug.print("Usage: tcp_serve_toupper port\n", .{});
        std.os.exit(2);
    }

    const port = try parsePort(args.args[0]);
    const listen_address = try SocketAddressExt.parse("::", port);
    std.debug.print("listen_address={}\n", .{listen_address});
    const socket_domain: u32 = SocketAddressExt.toSocketDomain(listen_address);
    const listen_socket = try Socket.init(socket_domain, std.os.SOCK.DGRAM, 0, .{});
    defer listen_socket.deinit();

    try listen_socket.setReuseAddress(true);
    if (builtin.os.tag != .windows) {
        try listen_socket.setReusePort(true);
    }
    try SocketIpv6Ext.setV6OnlyOrNop(listen_socket, false);
    try listen_socket.bind(listen_address);

    std.debug.print("Waiting for connections...\n", .{});

    while (true) {
        var read_buf: [1024]u8 = undefined;
        var src_address: Socket.Address = undefined;
        const bytes_received = try SocketUdpExt.recvfrom(listen_socket, read_buf[0..], 0, &src_address);
        std.debug.print("Received {} bytes from {}\n", .{ bytes_received, src_address });
        if (bytes_received == 0) {
            std.debug.print("connection closed from {}\n", .{src_address});
            @panic("connection closed should not happend for UDP!");
        }

        var j: usize = 0;
        while (j < bytes_received) : (j += 1) {
            read_buf[j] = std.ascii.toUpper(read_buf[j]);
        }
        const bytes_sent = try SocketUdpExt.sendto(listen_socket, read_buf[0..bytes_received], 0, &src_address);
        std.debug.print("Sent {} of {} bytes to {}\n", .{ bytes_sent, bytes_received, src_address });
    }

    std.debug.print("Finished.\n", .{});
}
