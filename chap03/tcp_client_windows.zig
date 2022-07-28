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

pub extern "msvcrt" fn _kbhit() callconv(windows.WINAPI) i32;

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
        var hints: ws2_32.addrinfoa = undefined;
        var hints_bytes: []u8 = undefined;
        hints_bytes.ptr = @ptrCast([*]u8, &hints);
        hints_bytes.len = @sizeOf(@TypeOf(hints));
        std.mem.set(u8, hints_bytes, 0);
        hints.socktype = ws2_32.SOCK.STREAM;
        var peer_address: *ws2_32.addrinfo = undefined;
        const r = ws2_32.getaddrinfo(hostname, port, &hints, &peer_address);
        if (r != 0) {
            @panic("getaddrinfo");
        }
        defer ws2_32.freeaddrinfo(peer_address);

        std.debug.print("Remote address is: ", .{});
        var address_buffer: [100]u8 = undefined;
        var service_buffer: [100]u8 = undefined;
        const r2 = ws2_32.getnameinfo(
            @ptrCast(*ws2_32.sockaddr, peer_address.addr),
            @intCast(i32, peer_address.addrlen),
            address_buffer[0..],
            @sizeOf(@TypeOf(address_buffer)),
            service_buffer[0..],
            @sizeOf(@TypeOf(service_buffer)),
            ws2_32.NI_NUMERICHOST,
        );
        std.debug.print("r2={}\n", .{r2});
        if (r2 != 0) {
            std.debug.print("getnameinfo() failed. ({})\n", .{std.c._errno().*});
            return error.Getnameinfo;
        }
        std.debug.print("{s} {s}\n", .{
            address_buffer[0..indexOfSentinel(u8, address_buffer[0..], 0)],
            service_buffer[0..indexOfSentinel(u8, service_buffer[0..], 0)],
        });

        std.debug.print("Creating socket...\n", .{});
        const socket_peer = ws2_32.socket(
            peer_address.family,
            peer_address.socktype,
            peer_address.protocol,
        );
        if (socket_peer == ws2_32.INVALID_SOCKET) {
            std.debug.print("socket() failed. ({})\n", .{WSAGetLastError()});
            return error.Socket;
        }

        std.debug.print("Connecting...\n", .{});
        if (ws2_32.connect(
            socket_peer,
            peer_address.addr.?,
            @intCast(i32, peer_address.addrlen),
        ) != 0) {
            std.debug.print("connect() failed. ({})\n", .{WSAGetLastError()});
            return error.Socket;
        }

        std.debug.print("Connected.\n", .{});
        std.debug.print("To send data, enter text followed by enter.\n", .{});

        const stdin = try windows.GetStdHandle(windows.STD_INPUT_HANDLE);

        while (true) {
            var reads: ws2_32.fd_set = undefined;
            reads.fd_count = 1;
            reads.fd_array[0] = socket_peer;

            var timeout = std.os.timeval{
                .tv_sec = 0,
                .tv_usec = 100000,
            };
            if (select(
                0, // Windows ignores nfds so we just pass zero here. https://github.com/MasterQ32/zig-network/blob/16f7e71a09e35861f634b2bffd235ef0db04467f/network.zig#L1465
                &reads,
                null,
                null,
                &timeout,
            ) < 0) {
                std.debug.print("select() failed. ({})\n", .{WSAGetLastError()});
                return error.Socket;
            }

            if (__WSAFDIsSet(socket_peer, &reads) != 0) {
                std.debug.print("socket_peer read ready.\n", .{});
                var read_buf: [4096]u8 = undefined;
                const bytes_received = ws2_32.recv(
                    socket_peer,
                    read_buf[0..],
                    @sizeOf(@TypeOf(read_buf)),
                    0,
                );
                if (bytes_received < 0) {
                    std.debug.print("recv() failed. ({})\n", .{WSAGetLastError()});
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

            if (_kbhit() != 0) {
                std.debug.print("stdin read ready.\n", .{});

                var read_buf: [4096]u8 = undefined;
                const n = try std.os.read(stdin, read_buf[0..]);
                if (n == 0) {
                    break;
                }
                std.debug.print("Sendings: {s}\n", .{read_buf[0..n]});
                const bytes_sent = ws2_32.send(socket_peer, read_buf[0..], @intCast(i32, n), 0);
                if (bytes_sent < 0) {
                    std.debug.print("send() failed. ({})\n", .{WSAGetLastError()});
                    return error.Send;
                }
            }
        }

        std.debug.print("Closing socket...\n", .{});

        if (ws2_32.closesocket(socket_peer) < 0) {
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
