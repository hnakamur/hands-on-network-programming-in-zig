const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("netdb.h");
    @cInclude("string.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/types.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();
    _ = allocator;

    std.debug.print("Configuring local address...\n", .{});
    var hints: c.struct_addrinfo = undefined;
    _ = c.memset(&hints, 0, @sizeOf(@TypeOf(hints)));
    hints.ai_family = c.AF_INET;
    hints.ai_socktype = c.SOCK_STREAM;
    hints.ai_flags = c.AI_PASSIVE;

    var bind_address: ?*c.struct_addrinfo = undefined;
    const r = c.getaddrinfo(0, "8080", &hints, &bind_address);
    if (r != 0) {
        @panic("getaddrinfo");
    }
    defer c.freeaddrinfo(bind_address);

    std.debug.print("Creating socket...\n", .{});
    var socket_listen = c.socket(
        bind_address.?.ai_family,
        bind_address.?.ai_socktype,
        bind_address.?.ai_protocol,
    );
    if (socket_listen < 0) {
        std.debug.print("socket() failed. ({})\n", .{std.c._errno().*});
        return error.Socket;
    }

    std.debug.print("Binding socket to local address...\n", .{});
    if (c.bind(socket_listen, bind_address.?.ai_addr, bind_address.?.ai_addrlen) < 0) {
        std.debug.print("bind() failed. ({})\n", .{std.c._errno().*});
        return error.Bind;
    }

    std.debug.print("Listening...\n", .{});
    if (c.listen(socket_listen, 10) < 0) {
        std.debug.print("listen() failed. ({})\n", .{std.c._errno().*});
        return error.Listen;
    }

    std.debug.print("Waiting for connection...\n", .{});
    var client_address: c.struct_sockaddr_storage = undefined;
    var client_len: c.socklen_t = @sizeOf(@TypeOf(client_address));
    var socket_client = c.accept(
        socket_listen,
        @ptrCast(*c.struct_sockaddr, &client_address),
        &client_len,
    );
    if (socket_client < 0) {
        std.debug.print("accept() failed. ({})\n", .{std.c._errno().*});
        return error.Accept;
    }

    std.debug.print("Client is connected... ", .{});
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
    std.debug.print("{s}\n", .{address_buffer});

    std.debug.print("Reading request...\n", .{});
    var request: [1024]u8 = undefined;
    const bytes_received = c.recv(socket_client, request[0..], 1024, 0);
    if (bytes_received < 0) {
        std.debug.print("recv() failed. ({})\n", .{std.c._errno().*});
        return error.Recv;
    }
    std.debug.print("Received {} bytes.\n", .{bytes_received});

    std.debug.print("Sending response...\n", .{});
    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "Local time is: ";
    var bytes_sent = c.send(socket_client, response, response.len, 0);
    if (bytes_sent < 0) {
        std.debug.print("send() failed. ({})\n", .{std.c._errno().*});
        return error.Send;
    }
    std.debug.print("Sent {} of {} bytes.\n", .{ bytes_sent, response.len });

    var timer: c.time_t = undefined;
    if (c.time(&timer) < 0) {
        std.debug.print("time() failed. ({})\n", .{std.c._errno().*});
        return error.Send;
    }
    const time_msg = c.ctime(&timer);
    bytes_sent = c.send(socket_client, time_msg, c.strlen(time_msg), 0);
    if (bytes_sent < 0) {
        std.debug.print("send() time failed. ({})\n", .{std.c._errno().*});
        return error.Send;
    }
    std.debug.print("Sent time {} of {} bytes.\n", .{ bytes_sent, c.strlen(time_msg) });

    std.debug.print("Closing connection...\n", .{});
    _ = c.close(socket_client);

    std.debug.print("Closing listening socket...\n", .{});
    _ = c.close(socket_listen);

    std.debug.print("Finished.\n", .{});
}
