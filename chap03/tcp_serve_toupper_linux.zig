const std = @import("std");
const c = @cImport({
    @cInclude("netdb.h");
    @cInclude("sys/select.h");
    @cInclude("sys/socket.h");
});

// https://gist.github.com/marler8997/7f2e1b6a3ce938285c620c642c3e581a
const FdSet = std.StaticBitSet(c.FD_SETSIZE);

fn getPortArg(
    allocator: std.mem.Allocator,
    port: *[:0]const u8,
) !bool {
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();

    _ = it.skip();

    var p2: [:0]const u8 = undefined;
    errdefer allocator.free(p2);
    if (it.next()) |p| {
        p2 = try allocator.dupeZ(u8, p);
    } else {
        return false;
    }

    port.* = p2;
    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var port: [:0]const u8 = undefined;
    if (!try getPortArg(allocator, &port)) {
        std.debug.print("Usage: tcp_serve_toupper port\n", .{});
        std.os.exit(2);
    }
    defer allocator.free(port);

    std.debug.print("hello port={s}\n", .{port});

    std.debug.print("Configuring local address...\n", .{});
    var hints: std.c.addrinfo = undefined;
    var hints_bytes: []u8 = undefined;
    hints_bytes.ptr = @ptrCast([*]u8, &hints);
    hints_bytes.len = @sizeOf(@TypeOf(hints));
    std.mem.set(u8, hints_bytes, 0);
    hints.family = std.os.AF.INET;
    hints.socktype = std.os.SOCK.STREAM;
    hints.flags = std.c.AI.PASSIVE;
    var bind_address: *std.c.addrinfo = undefined;
    const r = std.c.getaddrinfo(null, port, &hints, &bind_address);
    if (@enumToInt(r) != 0) {
        @panic("getaddrinfo");
    }
    defer std.c.freeaddrinfo(bind_address);

    std.debug.print("Creating socket...\n", .{});
    const socket_listen = std.c.socket(
        @intCast(c_uint, bind_address.family),
        @intCast(c_uint, bind_address.socktype),
        @intCast(c_uint, bind_address.protocol),
    );
    if (socket_listen < 0) {
        std.debug.print("socket() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    std.debug.print("Binding socket to local address...\n", .{});
    if (std.c.bind(socket_listen, bind_address.addr.?, bind_address.addrlen) < 0) {
        std.debug.print("bind() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    std.debug.print("Listening...\n", .{});
    if (std.c.listen(socket_listen, 10) < 0) {
        std.debug.print("listen() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    var master = FdSet.initEmpty();
    master.set(@intCast(usize, socket_listen));
    var max_socket = socket_listen;

    std.debug.print("Waiting for connections...\n", .{});

    while (true) {
        var reads = master;
        if (c.select(max_socket + 1, @ptrToInt(&reads), null, null, null) < 0) {
            std.debug.print("select() failed. ({})\n", .{std.c._errno().*});
            return error.Socket;
        }

        var s: c_int = 1;
        while (s <= max_socket) : (s += 1) {
            if (reads.isSet(@intCast(usize, s))) {
                if (s == socket_listen) {
                    var client_address: c.sockaddr_storage = undefined;
                    var client_len = @intCast(std.c.socklen_t, @sizeOf(@TypeOf(client_address)));
                    const socket_client = std.c.accept(
                        socket_listen,
                        @ptrCast(*std.c.sockaddr, &client_address),
                        &client_len,
                    );
                    if (socket_client < 0) {
                        std.debug.print("accept() failed. ({})\n", .{std.c._errno().*});
                        return error.Socket;
                    }

                    master.set(@intCast(usize, socket_client));
                    if (socket_client > max_socket) {
                        max_socket = socket_client;
                    }

                    var address_buffer: [100]u8 = undefined;
                    const r2 = c.getnameinfo(
                        @ptrCast(*c.struct_sockaddr, &client_address),
                        client_len,
                        address_buffer[0..],
                        @sizeOf(@TypeOf(address_buffer)),
                        null,
                        0,
                        c.NI_NUMERICHOST,
                    );
                    if (r2 != 0) {
                        std.debug.print("getnameinfo() failed. ({})\n", .{std.c._errno().*});
                        return error.Getnameinfo;
                    }
                    std.debug.print("New connection from {s}\n", .{address_buffer});
                } else {
                    var read_buf: [1024]u8 = undefined;
                    const bytes_received = std.c.recv(
                        s,
                        read_buf[0..],
                        @sizeOf(@TypeOf(read_buf)),
                        0,
                    );
                    if (bytes_received <= 0) {
                        if (bytes_received < 0) {
                            std.debug.print("recv() failed. ({})\n", .{std.c._errno().*});
                        }
                        master.unset(@intCast(usize, s));
                        _ = std.c.close(s);
                        continue;
                    }

                    var j: usize = 0;
                    while (j < bytes_received) : (j += 1) {
                        read_buf[j] = std.ascii.toUpper(read_buf[j]);
                    }
                    if (std.c.send(s, read_buf[0..], @intCast(usize, bytes_received), 0) < 0) {
                        std.debug.print("send() failed. ({})\n", .{std.c._errno().*});
                    }
                }
            }
        }
    }

    std.debug.print("Closing listening socket...\n", .{});

    if (std.c.close(socket_listen) < 0) {
        std.debug.print("close() failed. ({})\n", .{std.c._errno().*});
        return error.Close;
    }

    std.debug.print("Finished.\n", .{});
}
