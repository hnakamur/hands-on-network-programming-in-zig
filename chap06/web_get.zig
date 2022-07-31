const std = @import("std");
const mystd = @import("lib").mystd;

pub const log_level: std.log.Level = .info;

const timeout_ns = 5 * std.time.ns_per_s; // 5 seconds

fn parseUrl(url: []const u8, hostname: *[]const u8, port: *[]const u8, path: *[]const u8) !void {
    std.debug.print("URL: {s}\n", .{url});

    var off = if (std.mem.indexOf(u8, url, "://")) |o| o else return error.InvalidUrl;
    const protocol = url[0..off];
    if (!std.mem.eql(u8, protocol, "http")) {
        return error.UnsupportedProtocol;
    }

    off += "://".len;
    var start = off;
    while (off < url.len and url[off] != ':' and url[off] != '/' and url[off] != '#') : (off += 1) {}
    hostname.* = url[start..off];

    port.* = if (url[off] == ':') blk: {
        start = off;
        while (off < url.len and url[off] != '/' and url[off] != '#') : (off += 1) {}
        break :blk url[start..off];
    } else "80";

    start = off;
    if (off < url.len and url[off] == '/') {
        start += 1;
    }
    while (off < url.len and url[off] != '#') : (off += 1) {}
    path.* = url[start..off];

    std.debug.print("hostname: {s}\n", .{hostname.*});
    std.debug.print("port: {s}\n", .{port.*});
    std.debug.print("path: {s}\n", .{path.*});
}

fn connectToHost(
    allocator: std.mem.Allocator,
    hostname: []const u8,
    port_str: []const u8,
) !std.x.os.Socket {
    var hints: mystd.os.addrinfo = std.mem.zeroes(mystd.os.addrinfo);
    hints.flags = mystd.os.AI.ALL;
    var native_peer_address: *mystd.os.addrinfo = undefined;
    try mystd.os.getaddrinfo(allocator, hostname, port_str, &hints, &native_peer_address);
    defer mystd.os.freeaddrinfo(native_peer_address);

    const peer_address = std.x.os.Socket.Address.fromNative(
        @intToPtr(*align(4) const std.os.sockaddr, @ptrToInt(native_peer_address.addr.?)),
    );
    std.debug.print("peer_address={}\n", .{peer_address});
    const socket_domain = mystd.net.SocketAddressExt.toSocketDomain(peer_address);
    const socket_peer = try std.x.os.Socket.init(socket_domain, std.os.SOCK.STREAM, 0, .{});
    std.debug.print("Connecting...\n", .{});
    try socket_peer.connect(peer_address);
    std.debug.print("Connected.\n", .{});
    return socket_peer;
}

fn sendRequest(
    socket: std.x.os.Socket,
    hostname: []const u8,
    port: []const u8,
    path: []const u8,
) !void {
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(buffer[0..]);
    var writer = fbs.writer();

    try std.fmt.format(writer, "GET /{s} HTTP/1.1\r\n", .{path});
    try std.fmt.format(writer, "Host: {s}:{s}\r\n", .{ hostname, port });
    try writer.writeAll("Connection: close\r\n");
    try writer.writeAll("User-Agent: honpwc web_get 1.0\r\n");
    try writer.writeAll("\r\n");

    const header = fbs.getWritten();
    const bytes_sent = try socket.write(header, 0);
    std.debug.print("Sent {} of {} bytes: {s}\n", .{ bytes_sent, header.len, header });
}

pub fn main() !void {
    try mystd.os.windows.winsock.startup();
    defer mystd.os.windows.winsock.cleanup();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try mystd.process.Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 2) {
        const exe_name = if (args.args.len > 0) std.fs.path.basename(args.args[0]) else "web_get";
        std.debug.print("Usage: {s} url\n", .{exe_name});
        std.os.exit(2);
    }

    const url = args.args[1];
    std.debug.print("url={s}\n", .{url});
    var hostname: []const u8 = undefined;
    var port: []const u8 = undefined;
    var path: []const u8 = undefined;
    try parseUrl(url, &hostname, &port, &path);

    const socket_server = try connectToHost(allocator, hostname, port);
    defer socket_server.deinit();

    try sendRequest(socket_server, hostname, port, path);

    const start_time_ns = std.time.nanoTimestamp();

    const response_buf_len = 32768;
    var response: [response_buf_len]u8 = undefined;
    var seen_header_end = false;
    var header: []const u8 = "";
    var body: ?[]const u8 = null;
    var off: usize = 0;
    var chunk_off: usize = 0;
    var content_length: ?usize = null;
    var remaining: usize = 0;

    const Encoding = enum {
        length,
        chunked,
        connection,
    };
    var encoding: Encoding = undefined;

    read_loop: while (true) {
        const current_time_ns = std.time.nanoTimestamp();
        if (current_time_ns - start_time_ns > timeout_ns) {
            std.debug.print("timeout after {d:.2} seconds\n", .{@as(f64, timeout_ns) / std.time.ns_per_s});
            std.os.exit(1);
        }

        if (off == response_buf_len) {
            std.debug.print("out of buffer space.\n", .{});
            std.os.exit(1);
        }

        var read_fds = mystd.net.select.FdSet.init();
        read_fds.set(socket_server.fd);
        _ = try mystd.net.select.select(&read_fds, null, null, 2 * std.time.ns_per_s);
        if (read_fds.isSet(socket_server.fd)) {
            const bytes_received = try socket_server.read(response[off..], 0);
            if (bytes_received == 0) {
                if (encoding == .connection and body != null) {
                    std.debug.print("{s}", .{body.?});
                }
                std.debug.print("\nConnection closed by peer.\n", .{});
                break;
            }
            std.log.debug("Received {} bytes.\n", .{bytes_received});
            off += bytes_received;

            if (!seen_header_end) {
                if (std.mem.indexOf(u8, response[0..], "\r\n\r\n")) |off2| {
                    const body_start = off2 + "\r\n\r\n".len;
                    header = response[0..body_start];
                    seen_header_end = true;
                    std.debug.print("Received Headers:\n{s}\n", .{header});
                    if (std.ascii.indexOfIgnoreCase(header, "\r\ncontent-length: ")) |off3| {
                        encoding = .length;
                        const length_start = off3 + "\r\ncontent-length: ".len;
                        if (std.mem.indexOfPos(u8, header, length_start, "\r\n")) |length_end| {
                            content_length = try mystd.fmt.parseIntDigits(
                                usize,
                                header[length_start..length_end],
                                10,
                            );
                        } else {
                            std.debug.print("content-length header does not end with CRLF.", .{});
                            std.os.exit(1);
                        }
                    } else if (std.ascii.indexOfIgnoreCase(
                        header,
                        "\r\ntransfer-encoding: chunked\r\n",
                    )) |_| {
                        encoding = .chunked;
                        remaining = 0;
                        chunk_off = body_start;
                    } else {
                        encoding = .connection;
                    }
                    std.debug.print("Received body:\n", .{});
                }
            }

            if (seen_header_end) {
                switch (encoding) {
                    .length => {
                        if (off >= remaining) {
                            std.debug.print("{s}", .{response[header.len..off]});
                            break;
                        }
                    },
                    .chunked => {
                        while (true) {
                            if (remaining == 0) {
                                if (std.mem.indexOfPos(u8, response[0..], off, "\r\n")) |off2| {
                                    remaining = try mystd.fmt.parseIntDigits(usize, response[chunk_off..off2], 16);
                                    if (remaining == 0) {
                                        break :read_loop;
                                    }
                                    chunk_off = off2 + "\r\n".len;
                                } else {
                                    break;
                                }
                            }
                            if (remaining > 0 and off - chunk_off >= remaining) {
                                std.debug.print("{s}", .{response[chunk_off .. chunk_off + remaining]});
                                chunk_off += remaining + "\r\n".len;
                                remaining = 0;
                            }

                            if (remaining != 0) {
                                break;
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }

    std.log.debug("Finished.\n", .{});
}
