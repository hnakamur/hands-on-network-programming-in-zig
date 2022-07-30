const std = @import("std");
const builtin = @import("builtin");
const Socket = std.x.os.Socket;
const Args = @import("lib").Args;
const parsePort = @import("lib").parsePort;
const SocketAddressExt = @import("lib").SocketAddressExt;
const SocketIpv6Ext = @import("lib").SocketIpv6Ext;
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
    const listen_socket = try Socket.init(socket_domain, std.os.SOCK.STREAM, 0, .{});
    defer listen_socket.deinit();

    try listen_socket.setReuseAddress(true);
    if (builtin.os.tag != .windows) {
        try listen_socket.setReusePort(true);
    }
    try SocketIpv6Ext.setV6OnlyOrNop(listen_socket, false);
    try listen_socket.bind(listen_address);
    try listen_socket.listen(10);

    std.debug.print("Waiting for connections...\n", .{});

    var read_fds = FdSet.init();
    read_fds.set(listen_socket.fd);
    var read_fds_copy = FdSet.init();
    const ConnectionAddressMap = std.AutoArrayHashMap(std.os.socket_t, Socket.Address);
    var connection_addresses = ConnectionAddressMap.init(allocator);
    defer connection_addresses.deinit();
    while (true) {
        read_fds_copy.copyFrom(&read_fds);
        _ = try select(&read_fds_copy, null, null, std.time.ns_per_s);

        var it = read_fds_copy.iterator();
        while (it.next()) |sock_fd| {
            if (sock_fd == listen_socket.fd) {
                const conn = try listen_socket.accept(.{});
                read_fds.set(conn.socket.fd);
                std.debug.print("New connection from {s}\n", .{conn.address});
                try connection_addresses.put(conn.socket.fd, conn.address);
            } else {
                var sock = Socket.from(sock_fd);
                const address = connection_addresses.get(sock_fd).?;
                var read_buf: [1024]u8 = undefined;
                const bytes_received = try sock.read(read_buf[0..], 0);
                std.debug.print("Received {} bytes from {}\n", .{ bytes_received, address });
                if (bytes_received == 0) {
                    read_fds.unset(sock_fd);
                    sock.deinit();
                    if (!connection_addresses.swapRemove(sock_fd)) {
                        std.log.err("address not found in map for sock_fd={}", .{sock_fd});
                    }
                    continue;
                }

                var j: usize = 0;
                while (j < bytes_received) : (j += 1) {
                    read_buf[j] = std.ascii.toUpper(read_buf[j]);
                }
                const bytes_sent = try sock.write(read_buf[0..bytes_received], 0);
                std.debug.print("Sent {} of {} bytes to {}\n", .{ bytes_sent, bytes_received, address });
            }
        }
    }

    std.debug.print("Finished.\n", .{});
}
