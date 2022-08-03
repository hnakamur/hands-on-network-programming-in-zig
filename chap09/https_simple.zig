const std = @import("std");
const builtin = @import("builtin");
const mystd = @import("lib").mystd;
const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cDefine("__FILE__", "\"\"");
    @cDefine("__LINE__", "0");
});

pub const log_level: std.log.Level = .info;

fn connectToHost(
    allocator: std.mem.Allocator,
    hostname: []const u8,
    port_str: []const u8,
) !std.x.os.Socket {
    var hints: mystd.os.addrinfo = std.mem.zeroes(mystd.os.addrinfo);
    hints.socktype = std.os.SOCK.STREAM;
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

pub fn main() !void {
    try mystd.os.windows.winsock.startup();
    defer mystd.os.windows.winsock.cleanup();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try mystd.process.Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 3) {
        const exe_name = if (args.args.len > 0)
            std.fs.path.basename(args.args[0])
        else
            "https_simple";
        std.debug.print("Usage: {s} hostname port\n", .{exe_name});
        std.os.exit(2);
    }

    const hostname = args.args[1];
    const port = args.args[2];
    const server = try connectToHost(allocator, hostname, port);
    defer server.deinit();

    var ctx = c.SSL_CTX_new(c.TLS_client_method());
    if (ctx == null) {
        std.log.err("SSL_CTX_new failed.", .{});
        std.os.exit(1);
    }
    defer c.SSL_CTX_free(ctx);

    var ssl = c.SSL_new(ctx);
    if (ssl == null) {
        std.log.err("SSL_new failed.", .{});
        std.os.exit(1);
    }
    defer c.SSL_free(ssl);
    defer if (c.SSL_shutdown(ssl.?) < 0) {
        std.log.err("SSL_shutdown() failed.", .{});
        std.os.exit(1);
    };

    const hostname_z = try allocator.dupeZ(u8, hostname);
    defer allocator.free(hostname_z);
    // if (SSL_set_tlsext_host_name(ssl.?, hostname_z) == 0) {
    if (SSL_set_tlsext_host_name(ssl.?, hostname_z) == 0) {
        std.log.err("SSL_set_tlsext_host_name() failed.", .{});
        ERR_print_errors_stderr();
        std.os.exit(1);
    }

    if (c.SSL_set_fd(ssl.?, sockFdToCInt(server.fd)) == 0) {
        std.log.err("SSL_set_fd() failed.", .{});
        std.os.exit(1);
    }
    if (c.SSL_connect(ssl.?) == -1) {
        std.log.err("SSL_connect() failed.", .{});
        ERR_print_errors_stderr();
        std.os.exit(1);
    }

    std.log.info("SSL/TLS using {s}.", .{c.SSL_get_cipher(ssl.?)});

    const cert = c.SSL_get_peer_certificate(ssl.?);
    if (cert == null) {
        std.log.err("SSL_get_peer_certificate() failed.", .{});
        std.os.exit(1);
    }
    defer c.X509_free(cert.?);

    var tmp = c.X509_NAME_oneline(c.X509_get_subject_name(cert.?), null, 0);
    if (tmp != null) {
        std.log.info("subject: {s}.", .{tmp.?});
        c.OPENSSL_free(tmp.?);
    }

    tmp = c.X509_NAME_oneline(c.X509_get_issuer_name(cert.?), null, 0);
    if (tmp != null) {
        std.log.info("issuer: {s}.", .{tmp.?});
        c.OPENSSL_free(tmp.?);
    }

    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(buffer[0..]);
    var writer = fbs.writer();
    try std.fmt.format(writer, "GET / HTTP/1.1\r\n", .{});
    try std.fmt.format(writer, "Host: {s}:{s}\r\n", .{ hostname, port });
    try std.fmt.format(writer, "Connection: close\r\n", .{});
    try std.fmt.format(writer, "User-Agent: https_simple\r\n", .{});
    try std.fmt.format(writer, "\r\n", .{});
    const headers = fbs.getWritten();

    const bytes_written = c.SSL_write(
        ssl.?,
        @ptrCast(*anyopaque, headers),
        @intCast(c_int, headers.len),
    );
    if (bytes_written != headers.len) {
        std.log.err("SSL_write() failed, ret={}, want={}", .{ bytes_written, headers.len });
        std.os.exit(1);
    }

    while (true) {
        const bytes_received = c.SSL_read(ssl.?, buffer[0..], buffer.len);
        if (bytes_received < 1) {
            std.log.info("Connection closed by peer.", .{});
            break;
        }

        std.log.info("Received ({} bytes): '{s}'", .{
            bytes_received,
            buffer[0..@intCast(usize, bytes_received)],
        });
    }
}

fn SSL_set_tlsext_host_name(ssl: *c.SSL, hostname: [:0]u8) c_long {
    return c.SSL_ctrl(
        ssl,
        c.SSL_CTRL_SET_TLSEXT_HOSTNAME,
        c.TLSEXT_NAMETYPE_host_name,
        @ptrCast(*anyopaque, hostname),
    );
}

fn ERR_print_errors_stderr() void {
    if (builtin.os.tag != .windows) {
        c.ERR_print_errors_fp(c.stderr);
    }
}

fn sockFdToCInt(sockfd: std.os.socket_t) c_int {
    return if (builtin.os.tag == .windows)
        @intCast(c_int, @ptrToInt(sockfd))
    else
        @intCast(c_int, sockfd);
}
