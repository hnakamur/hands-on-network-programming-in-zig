const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const ws2_32 = windows.ws2_32;
const WSAGetLastError = ws2_32.WSAGetLastError;

pub extern "ws2_32" fn select(
    nfds: i32,
    readfds: ?*ws2_32.fd_set,
    writefds: ?*ws2_32.fd_set,
    exceptfds: ?*ws2_32.fd_set,
    timeout: ?*const std.os.timeval,
) callconv(windows.WINAPI) i32;

pub extern "ws2_32" fn __WSAFDIsSet(
    fd: ws2_32.SOCKET,
    fds: ?*ws2_32.fd_set,
) callconv(windows.WINAPI) i32;

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

    var ret_err: ?anyerror = null;
    {
        if (builtin.os.tag == .windows) {
            _ = try windows.WSAStartup(2, 2);
        }
        defer if (builtin.os.tag == .windows) {
            windows.WSACleanup() catch |err| {
                ret_err = err;
            };
        };
        var port: [:0]const u8 = undefined;
        if (!try getPortArg(allocator, &port)) {
            std.debug.print("Usage: tcp_serve_toupper port\n", .{});
            std.os.exit(2);
        }
        defer allocator.free(port);

        std.debug.print("hello port={s}\n", .{port});

        std.debug.print("Configuring local address...\n", .{});
        var hints: ws2_32.addrinfoa = undefined;
        var hints_bytes: []u8 = undefined;
        hints_bytes.ptr = @ptrCast([*]u8, &hints);
        hints_bytes.len = @sizeOf(@TypeOf(hints));
        std.mem.set(u8, hints_bytes, 0);
        hints.family = ws2_32.AF.INET;
        hints.socktype = ws2_32.SOCK.STREAM;
        hints.flags = ws2_32.AI.PASSIVE;
        var bind_address: *ws2_32.addrinfo = undefined;
        const r = ws2_32.getaddrinfo(null, port, &hints, &bind_address);
        if (r != 0) {
            @panic("getaddrinfo");
        }
        defer ws2_32.freeaddrinfo(bind_address);

        std.debug.print("Creating socket...\n", .{});
        const socket_listen = ws2_32.socket(
            bind_address.family,
            bind_address.socktype,
            bind_address.protocol,
        );
        if (socket_listen == ws2_32.INVALID_SOCKET) {
            std.debug.print("socket() failed. ({})\n", .{WSAGetLastError()});
            return error.Socket;
        }

        std.debug.print("Binding socket to local address...\n", .{});
        if (ws2_32.bind(
            socket_listen,
            bind_address.addr.?,
            @intCast(i32, bind_address.addrlen),
        ) != 0) {
            std.debug.print("bind() failed. ({})\n", .{WSAGetLastError()});
            return error.Bind;
        }

        std.debug.print("Listening...\n", .{});
        if (ws2_32.listen(socket_listen, 10) < 0) {
            std.debug.print("listen() failed. ({})\n", .{WSAGetLastError()});
            return error.Listen;
        }

        var master: ws2_32.fd_set = undefined;
        master.fd_count = 1;
        master.fd_array[0] = socket_listen;

        while (true) {
            var reads = cloneFdSet(master);
            if (select(
                0, // Windows ignores nfds so we just pass zero here. https://github.com/MasterQ32/zig-network/blob/16f7e71a09e35861f634b2bffd235ef0db04467f/network.zig#L1465
                &reads,
                null,
                null,
                null,
            ) < 0) {
                std.debug.print("select() failed. ({})\n", .{WSAGetLastError()});
                return error.Socket;
            }

            var i: usize = 0;
            while (i < reads.fd_count) : (i += 1) {
                const s = reads.fd_array[i];
                if (s != ws2_32.INVALID_SOCKET) {
                    if (s == socket_listen) {
                        var client_address: ws2_32.sockaddr = undefined;
                        var client_len: i32 = @sizeOf(@TypeOf(client_address));
                        const socket_client = ws2_32.accept(
                            socket_listen,
                            @ptrCast(*ws2_32.sockaddr, &client_address),
                            &client_len,
                        );
                        if (socket_client == ws2_32.INVALID_SOCKET) {
                            std.debug.print("accept() failed. ({})\n", .{WSAGetLastError()});
                            return error.Accept;
                        }

                        try setFdSet(&master, socket_client);

                        var address_buffer: [100]u8 = undefined;
                        var service_buffer: [100]u8 = undefined;
                        const r2 = ws2_32.getnameinfo(
                            &client_address,
                            client_len,
                            address_buffer[0..],
                            @sizeOf(@TypeOf(address_buffer)),
                            service_buffer[0..],
                            @sizeOf(@TypeOf(service_buffer)),
                            ws2_32.NI_NUMERICHOST,
                        );
                        if (r2 != 0) {
                            std.debug.print("getnameinfo() failed. ({})\n", .{WSAGetLastError()});
                            return error.Getnameinfo;
                        }
                        std.debug.print("New connection from {s}:{s}\n", .{
                            address_buffer[0..indexOfSentinel(u8, address_buffer[0..], 0)],
                            service_buffer[0..indexOfSentinel(u8, service_buffer[0..], 0)],
                        });
                    } else {
                        var read_buf: [1024]u8 = undefined;
                        const bytes_received = ws2_32.recv(
                            s,
                            read_buf[0..],
                            @sizeOf(@TypeOf(read_buf)),
                            0,
                        );
                        if (bytes_received <= 0) {
                            if (bytes_received < 0) {
                                std.debug.print("recv() failed. ({})\n", .{WSAGetLastError()});
                            }
                            clearFdSet(&master, s);
                            _ = ws2_32.closesocket(s);
                            continue;
                        }

                        var j: usize = 0;
                        while (j < bytes_received) : (j += 1) {
                            read_buf[j] = std.ascii.toUpper(read_buf[j]);
                        }
                        if (ws2_32.send(s, read_buf[0..], @intCast(i32, bytes_received), 0) < 0) {
                            std.debug.print("send() failed. ({})\n", .{WSAGetLastError()});
                        }
                    }
                }
            }
        }

        std.debug.print("Closing socket...\n", .{});

        if (ws2_32.closesocket(socket_listen) < 0) {
            std.debug.print("close() failed. ({})\n", .{WSAGetLastError()});
            return error.Close;
        }

        std.debug.print("Finished.\n", .{});
    }
    if (ret_err) |err| return err;
}

fn indexOfSentinel(comptime T: type, ptr: [*]const T, value: T) usize {
    var i: usize = 0;
    while (ptr[i] != value) : (i += 1) {}
    return i;
}

fn cloneFdSet(src: ws2_32.fd_set) ws2_32.fd_set {
    var dest: ws2_32.fd_set = undefined;
    dest.fd_count = src.fd_count;
    std.mem.copy(ws2_32.SOCKET, dest.fd_array[0..], src.fd_array[0..]);
    return dest;
}

fn setFdSet(set: *ws2_32.fd_set, s: ws2_32.SOCKET) !void {
    var i: usize = 0;
    while (i < set.fd_count) : (i += 1) {
        if (set.fd_array[i] == s) {
            return;
        }
    }
    if (i >= set.fd_array.len) {
        return error.FdSetFull;
    }
    set.fd_count += 1;
    set.fd_array[i] = s;
}

fn clearFdSet(set: *ws2_32.fd_set, s: ws2_32.SOCKET) void {
    if (std.mem.indexOfScalar(ws2_32.SOCKET, set.fd_array[0..set.fd_count], s)) |i| {
        std.mem.copy(
            ws2_32.SOCKET,
            set.fd_array[i .. set.fd_count - 1],
            set.fd_array[i + 1 .. set.fd_count],
        );
        set.fd_count -= 1;
    }
}
