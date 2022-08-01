const std = @import("std");
const builtin = @import("builtin");
const mystd = @import("lib").mystd;

pub const log_level: std.log.Level = .info;

const max_request_size = 2048;

const ClientInfo = struct {
    conn: std.x.os.Socket.Connection,
    request: [max_request_size]u8 = undefined,
    received: usize = 0,
    next: ?*ClientInfo = null,
};

const ClientList = struct {
    clients: ?*ClientInfo = null,
    free_list: ?*ClientInfo = null,
};

fn appendClient(
    allocator: std.mem.Allocator,
    client_list: *ClientList,
    conn: std.x.os.Socket.Connection,
) !*ClientInfo {
    var ci = client_list.clients;
    while (ci) |ci2| {
        if (ci2.next == null) {
            break;
        }
        ci = ci2.next;
    }

    var n = if (client_list.free_list) |f| blk: {
        client_list.free_list = f.next;
        break :blk f;
    } else try allocator.create(ClientInfo);
    n.* = .{
        .conn = conn,
        .received = 0,
        .next = null,
    };
    if (ci) |ci2| {
        ci2.next = n;
    } else {
        client_list.clients = n;
    }
    return n;
}

fn dropClient(client_list: *ClientList, client: *ClientInfo) !void {
    client.conn.socket.deinit();

    var p = &client_list.clients;
    while (p.*) |c| {
        if (c == client) {
            p.* = client.next;
            client.next = client_list.free_list;
            client_list.free_list = client;
            std.log.debug("dropClient {*}, clients={*}", .{ client, client_list.clients });
            return;
        }
        p = &c.next;
    }
    return error.DropClientNotFound;
}

fn createSocket(host: []const u8, port_str: []const u8) !std.x.os.Socket {
    const port = try mystd.net.parsePort(port_str);
    const listen_address = try mystd.net.SocketAddressExt.parse(host, port);
    std.log.debug("listen_address={}\n", .{listen_address});
    const socket_domain: u32 = mystd.net.SocketAddressExt.toSocketDomain(listen_address);
    const socket_listen = try std.x.os.Socket.init(socket_domain, std.os.SOCK.STREAM, 0, .{});

    try socket_listen.setReuseAddress(true);
    if (builtin.os.tag != .windows) {
        try socket_listen.setReusePort(true);
    }
    try mystd.net.SocketIpv6Ext.setV6OnlyOrNop(socket_listen, false);
    try socket_listen.bind(listen_address);
    try socket_listen.listen(1024);

    return socket_listen;
}

fn waitOnClients(client_list: *ClientList, server: std.x.os.Socket) !mystd.net.select.FdSet {
    var read_fds = mystd.net.select.FdSet.init();
    read_fds.set(server.fd);

    var ci = client_list.clients;
    while (ci) |ci2| {
        read_fds.set(ci2.conn.socket.fd);
        ci = ci2.next;
    }

    _ = try mystd.net.select.select(&read_fds, null, null, 5 * std.time.ns_per_s);
    return read_fds;
}

fn getContentType(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |pos| {
        const ext = path[pos..];
        if (std.mem.eql(u8, ext, ".css")) return "text/css";
        if (std.mem.eql(u8, ext, ".csv")) return "text/csv";
        if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
        if (std.mem.eql(u8, ext, ".htm")) return "text/html";
        if (std.mem.eql(u8, ext, ".html")) return "text/html";
        if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
        if (std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
        if (std.mem.eql(u8, ext, ".jpg")) return "image/jpeg";
        if (std.mem.eql(u8, ext, ".js")) return "text/javascript";
        if (std.mem.eql(u8, ext, ".json")) return "application/json";
        if (std.mem.eql(u8, ext, ".pdf")) return "application/pdf";
        if (std.mem.eql(u8, ext, ".png")) return "image/png";
        if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
        if (std.mem.eql(u8, ext, ".txt")) return "text/plain";
    }
    return "application/octet-stream";
}

fn send400(client_list: *ClientList, client: *ClientInfo) !void {
    const msg = "HTTP/1.1 400 Bad Request\r\n" ++
        "Connection: close\r\n" ++
        "Content-Length: 11\r\n\r\nBad Request";
    const bytes_sent = try client.conn.socket.write(msg, 0);
    std.log.debug("send400 sent {} of {} bytes.", .{ bytes_sent, msg.len });
    try dropClient(client_list, client);
}

fn send404(client_list: *ClientList, client: *ClientInfo) !void {
    const msg = "HTTP/1.1 404 Not Found\r\n" ++
        "Connection: close\r\n" ++
        "Content-Length: 9\r\n\r\nNot Found";
    const bytes_sent = try client.conn.socket.write(msg, 0);
    std.log.debug("send400 sent {} of {} bytes.", .{ bytes_sent, msg.len });
    try dropClient(client_list, client);
}

fn serveResource(
    client_list: *ClientList,
    client: *ClientInfo,
    path: []const u8,
) !void {
    std.log.debug("serveResource {} {s}", .{ client.conn.address, path });

    const path2 = if (std.mem.eql(u8, path, "/")) "/index.html" else path;
    std.log.debug("path2={s}", .{path2});
    if (path2.len > 100) {
        try send400(client_list, client);
        return;
    }

    if (std.mem.indexOf(u8, path2, "..")) |_| {
        try send404(client_list, client);
        return;
    }

    var rel_path_buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(rel_path_buf[0..]);
    var writer = fbs.writer();
    try std.fmt.format(writer, "public{s}", .{path2});
    var rel_path = fbs.getWritten();
    if (builtin.os.tag == .windows) {
        std.mem.replaceScalar(u8, rel_path, std.fs.path.sep_posix, std.fs.path.sep_windows);
    }
    std.log.debug("rel_path={s}", .{rel_path});

    var file = std.fs.cwd().openFile(rel_path, .{}) catch {
        try send404(client_list, client);
        return;
    };
    defer file.close();

    const content_length = try file.getEndPos();
    const content_type = getContentType(rel_path);

    var buffer: [1024]u8 = undefined;
    fbs = std.io.fixedBufferStream(buffer[0..]);
    writer = fbs.writer();
    try std.fmt.format(writer, "HTTP/1.1 200 OK\r\n", .{});
    try std.fmt.format(writer, "Connection: close\r\n", .{});
    try std.fmt.format(writer, "Content-Length: {}\r\n", .{content_length});
    try std.fmt.format(writer, "Content-Type: {s}\r\n", .{content_type});
    try std.fmt.format(writer, "\r\n", .{});
    const header = fbs.getWritten();
    var bytes_sent = try client.conn.socket.write(header, 0);
    std.log.debug("Sent header {} of {} bytes", .{ bytes_sent, header.len });

    while (true) {
        const r = try file.read(buffer[0..]);
        if (r == 0) {
            break;
        }
        bytes_sent = try client.conn.socket.write(buffer[0..r], 0);
        std.log.debug("Sent body chunk {} of {} bytes", .{ bytes_sent, r });
    }

    try dropClient(client_list, client);
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
        const exe_name = if (args.args.len > 0) std.fs.path.basename(args.args[0]) else "web_server";
        std.debug.print("Usage: {s} port\n", .{exe_name});
        std.os.exit(2);
    }

    const socket_server = try createSocket("::", args.args[1]);
    defer socket_server.deinit();

    var client_list = ClientList{};

    while (true) {
        var read_fds = try waitOnClients(&client_list, socket_server);
        if (read_fds.isSet(socket_server.fd)) {
            const conn = try socket_server.accept(.{});
            std.log.debug("New connection from {}.", .{conn.address});
            const client = try appendClient(allocator, &client_list, conn);
            std.log.debug("Client appended {*}.", .{client});
        }

        var client = client_list.clients;
        std.log.debug("start loop clients {*}", .{client});
        while (client) |cli| {
            std.log.debug("loop cli {*}", .{cli});
            const next = cli.next;
            if (read_fds.isSet(cli.conn.socket.fd)) {
                if (cli.received == max_request_size) {
                    try send400(&client_list, cli);
                    client = next;
                    continue;
                }

                const r = try cli.conn.socket.read(cli.request[cli.received..], 0);
                if (r == 0) {
                    std.debug.print("Unexpected disconnect from {}.\n", .{cli.conn.address});
                    try dropClient(&client_list, cli);
                } else {
                    cli.received += r;
                    if (std.mem.indexOf(u8, cli.request[0..], "\r\n\r\n")) |_| {
                        if (std.mem.startsWith(u8, cli.request[0..], "GET /")) {
                            const path_start = "GET ".len;
                            if (std.mem.indexOfScalarPos(
                                u8,
                                cli.request[0..],
                                path_start,
                                ' ',
                            )) |path_end| {
                                try serveResource(
                                    &client_list,
                                    cli,
                                    cli.request[path_start..path_end],
                                );
                            } else {
                                try send400(&client_list, cli);
                            }
                        } else {
                            try send400(&client_list, cli);
                        }
                    }
                }
            }
            client = next;
        }
    }
}
