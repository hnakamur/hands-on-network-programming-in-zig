const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const IPv6 = std.x.os.IPv6;
const Socket = std.x.os.Socket;
const Args = @import("lib").Args;
const parsePort = @import("lib").parsePort;
const SocketAddressExt = @import("lib").SocketAddressExt;
const FdSet = @import("lib").FdSet;
const select = @import("lib").select;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 2) {
        std.debug.print("Usage: tcp_client hostname port\n", .{});
        std.os.exit(2);
    }

    const host = args.args[0];
    const port = try parsePort(args.args[1]);
    const peer_address = try SocketAddressExt.parse(host, port);
    std.debug.print("peer_address={}\n", .{peer_address});

    const socket_domain: u32 = SocketAddressExt.toSocketDomain(peer_address);
    const socket_peer = try Socket.init(socket_domain, std.os.SOCK.DGRAM, 0, .{});
    defer socket_peer.deinit();

    try socket_peer.connect(peer_address);

    while (true) {
        var read_fds = FdSet.init();
        read_fds.set(socket_peer.fd);
        if (builtin.os.tag != .windows) {
            read_fds.set(std.os.STDIN_FILENO);
        }
        _ = try select(&read_fds, null, null, std.time.ns_per_s);

        if (read_fds.isSet(socket_peer.fd)) {
            var read_buf: [4096]u8 = undefined;
            const bytes_received = try socket_peer.read(read_buf[0..], 0);
            if (bytes_received == 0) {
                std.debug.print("Connection closed by peer.\n", .{});
                break;
            }

            std.debug.print("Received ({} bytes): {s}\n", .{ bytes_received, read_buf[0..bytes_received] });
        }

        if (isStdinReady(&read_fds)) {
            var read_buf: [4096]u8 = undefined;

            const stdin = if (builtin.os.tag == .windows)
                try windows.GetStdHandle(windows.STD_INPUT_HANDLE)
            else
                std.os.STDIN_FILENO;

            const n = try std.os.read(stdin, read_buf[0..]);
            std.debug.print("read {} bytes from stdin.\n", .{n});
            if (n == 0) {
                break;
            }
            const bytes_sent = try socket_peer.write(read_buf[0..n], 0);
            std.debug.print("Sent ({} of {} bytes): {s}\n", .{ bytes_sent, n, read_buf[0..n] });
        }
    }
    std.debug.print("Finished.\n", .{});
}

fn isStdinReady(read_fds: *const FdSet) bool {
    if (builtin.os.tag == .windows) {
        return _kbhit() != 0;
    } else {
        return read_fds.isSet(std.os.STDIN_FILENO);
    }
}

pub extern "msvcrt" fn _kbhit() callconv(windows.WINAPI) i32;
