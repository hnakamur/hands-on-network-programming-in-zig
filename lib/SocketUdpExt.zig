const std = @import("std");
const builtin = @import("builtin");
const Socket = std.x.os.Socket;

pub const SocketUdpExt = @This();

pub fn recvfrom(
    socket: Socket,
    buf: []u8,
    flags: u32,
    src_address: ?*Socket.Address,
) std.os.RecvFromError!usize {
    var src_addr: std.os.sockaddr.storage = undefined;
    var addrlen: std.os.socklen_t = @sizeOf(@TypeOf(src_addr));
    const n = std.os.recvfrom(
        socket.fd,
        buf,
        flags,
        @ptrCast(*std.os.sockaddr, &src_addr),
        &addrlen,
    );
    if (src_address) |addr| {
        addr.* = Socket.Address.fromNative(@ptrCast(*align(4) const std.os.sockaddr, &src_addr));
    }
    return n;
}

pub fn sendto(
    socket: Socket,
    buf: []u8,
    flags: u32,
    dest_address: *const Socket.Address,
) std.os.SendToError!usize {
    return try std.os.sendto(
        socket.fd,
        buf,
        flags,
        @ptrCast(*std.os.sockaddr, &dest_address.toNative()),
        @as(std.os.socklen_t, dest_address.getNativeSize()),
    );
}
