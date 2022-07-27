const std = @import("std");
const c = @cImport({
    @cInclude("sys/select.h");
});

// https://gist.github.com/marler8997/7f2e1b6a3ce938285c620c642c3e581a
const FdSet = std.StaticBitSet(c.FD_SETSIZE);

fn getHostnamePortArgs(
    allocator: std.mem.Allocator,
    hostname: *[:0]const u8,
    port: *[:0]const u8,
) !bool {
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();

    _ = it.skip();

    var h2: [:0]const u8 = undefined;
    errdefer allocator.free(h2);
    if (it.next()) |h| {
        h2 = try allocator.dupeZ(u8, h);
    } else {
        return false;
    }

    var p2: [:0]const u8 = undefined;
    errdefer allocator.free(p2);
    if (it.next()) |p| {
        p2 = try allocator.dupeZ(u8, p);
    } else {
        return false;
    }

    hostname.* = h2;
    port.* = p2;
    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var hostname: [:0]const u8 = undefined;
    var port: [:0]const u8 = undefined;
    if (!try getHostnamePortArgs(allocator, &hostname, &port)) {
        std.debug.print("Usage: tcp_client hostname port\n", .{});
        std.os.exit(2);
    }
    defer allocator.free(hostname);
    defer allocator.free(port);

    std.debug.print("hello hostname={s}, port={s}\n", .{ hostname, port });

    std.debug.print("Configuring remote address...\n", .{});
    var hints: std.c.addrinfo = undefined;
    var hints_bytes: []u8 = undefined;
    hints_bytes.ptr = @ptrCast([*]u8, &hints);
    hints_bytes.len = @sizeOf(@TypeOf(hints));
    std.mem.set(u8, hints_bytes, 0);
    hints.socktype = std.os.SOCK.STREAM;
    var peer_address: *std.c.addrinfo = undefined;
    const r = std.c.getaddrinfo(hostname, port, &hints, &peer_address);
    if (@enumToInt(r) != 0) {
        @panic("getaddrinfo");
    }
    defer std.c.freeaddrinfo(peer_address);

    std.debug.print("Remote address is: ", .{});
    var address_buffer: [100]u8 = undefined;
    var service_buffer: [100]u8 = undefined;
    const r2 = std.c.getnameinfo(@ptrCast(*std.c.sockaddr, peer_address.addr), peer_address.addrlen, address_buffer[0..], @sizeOf(@TypeOf(address_buffer)), service_buffer[0..], @sizeOf(@TypeOf(service_buffer)), std.c.NI.NUMERICHOST);
    std.debug.print("r2={}\n", .{@enumToInt(r2)});
    if (@enumToInt(r2) != 0) {
        std.debug.print("getnameinfo() failed. ({})\n", .{std.c._errno().*});
        return error.Getnameinfo;
    }
    std.debug.print("{s} {s}\n", .{ address_buffer, service_buffer });

    std.debug.print("Creating socket...\n", .{});
    const socket_peer = std.c.socket(
        @intCast(c_uint, peer_address.family),
        @intCast(c_uint, peer_address.socktype),
        @intCast(c_uint, peer_address.protocol),
    );
    if (socket_peer < 0) {
        std.debug.print("socket() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    std.debug.print("Connecting...\n", .{});
    if (std.c.connect(socket_peer, peer_address.addr.?, peer_address.addrlen) != 0) {
        std.debug.print("connect() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    std.debug.print("Connected.\n", .{});
    std.debug.print("To send data, enter text followed by enter.\n", .{});

    const stdin_fd = std.os.STDIN_FILENO;

    while (true) {
        var reads = FdSet.initEmpty();
        reads.setValue(@intCast(usize, socket_peer), true);
        reads.setValue(stdin_fd, true);
        var timeout = c.struct_timeval{
            .tv_sec = 0,
            .tv_usec = 100000,
        };
        if (c.select(
            socket_peer + 1,
            @ptrToInt(&reads),
            null,
            null,
            &timeout,
        ) < 0) {
            std.debug.print("select() failed. ({})\n", .{std.c._errno().*});
            return error.Socket;
        }

        if (reads.isSet(@intCast(usize, socket_peer))) {
            var read_buf: [4096]u8 = undefined;
            const bytes_received = std.c.recv(
                socket_peer,
                read_buf[0..],
                @sizeOf(@TypeOf(read_buf)),
                0,
            );
            if (bytes_received < 0) {
                std.debug.print("recv() failed. ({})\n", .{std.c._errno().*});
                return error.Send;
            }
            if (bytes_received == 0) {
                std.debug.print("Connection closed by peer.\n", .{});
                break;
            }

            std.debug.print(
                "Received ({} bytes): {s}\n",
                .{ bytes_received, read_buf[0..@intCast(usize, bytes_received)] },
            );
        }
        
        if (reads.isSet(stdin_fd)) {
            var read_buf: [4096]u8 = undefined;
            const n = try std.os.read(stdin_fd, read_buf[0..]);
            if (n == 0) {
                break;
            }
            std.debug.print("Sendings: {s}\n", .{read_buf[0..n]});
            const bytes_sent = std.c.send(socket_peer, read_buf[0..], n, 0);
            if (bytes_sent < 0) {
                std.debug.print("send() failed. ({})\n", .{std.c._errno().*});
                return error.Send;
            }
        }
    }

    std.debug.print("Closing socket...\n", .{});

    if (std.c.close(socket_peer) < 0) {
        std.debug.print("close() failed. ({})\n", .{std.c._errno().*});
        return error.Close;
    }

    std.debug.print("Finished.\n", .{});
}
