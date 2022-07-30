const std = @import("std");
const windows = std.os.windows;
const ws2_32 = windows.ws2_32;

const WinSock = struct {
    pub extern "ws2_32" fn select(
        nfds: i32,
        readfds: ?*ws2_32.fd_set,
        writefds: ?*ws2_32.fd_set,
        exceptfds: ?*ws2_32.fd_set,
        timeout: ?*const std.os.timeval,
    ) callconv(windows.WINAPI) i32;
};

pub const FdSet = struct {
    pub const SetSocketIterator = struct {
        fd_set: *const FdSet,
        i: usize,

        pub fn next(self: *SetSocketIterator) ?std.os.socket_t {
            const socket = if (self.i < self.fd_set.fd_count)
                self.fd_set.fd_array[self.i]
            else
                null;
            self.i += 1;
            return socket;
        }
    };

    inner: ws2_32.fd_set,

    pub fn init() FdSet {
        var fdset: ws2_32.fd_set = undefined;
        fdset.fd_count = 0;
        return .{ .inner = fdset };
    }

    pub fn isSet(self: *const FdSet, socket: std.os.socket_t) bool {
        return std.mem.indexOfScalar(
            ws2_32.SOCKET,
            self.inner.fd_array[0..self.inner.fd_count],
            socket,
        ) != null;
    }

    pub fn set(self: *FdSet, socket: std.os.socket_t) void {
        if (std.mem.indexOfScalar(
            ws2_32.SOCKET,
            self.inner.fd_array[0..self.inner.fd_count],
            socket,
        ) != null) {
            return;
        }
        if (self.inner.fd_count == self.inner.fd_array.len) {
            @panic("cannot set new socket since fd_set is full");
        }
        self.inner.fd_array[self.inner.fd_count] = socket;
        self.inner.fd_count += 1;
    }

    pub fn unset(self: *FdSet, socket: std.os.socket_t) void {
        if (std.mem.indexOfScalar(
            ws2_32.SOCKET,
            self.inner.fd_array[0..self.inner.fd_count],
            socket,
        )) |i| {
            std.mem.copy(
                ws2_32.SOCKET,
                self.inner.fd_array[i .. self.inner.fd_count - 1],
                self.inner.fd_array[i + 1 .. self.inner.fd_count],
            );
            self.inner.fd_count -= 1;
        }
    }

    pub fn copyFrom(self: *FdSet, other: *const FdSet) void {
        self.* = other.*;
    }

    pub fn iterator(self: *const FdSet) SetSocketIterator {
        return .{ .fd_set = self, .i = 0 };
    }
};

pub fn select(read_fds: ?*FdSet, write_fds: ?*FdSet, except_fds: ?*FdSet, timeout_nanoseconds: ?u64) !bool {
    var read_inner = if (read_fds) |fds| &fds.inner else null;
    var write_inner = if (write_fds) |fds| &fds.inner else null;
    var except_inner = if (except_fds) |fds| &fds.inner else null;
    var timeout = if (timeout_nanoseconds) |ns|
        &std.os.timeval{
            .tv_sec = @intCast(c_long, ns / std.time.ns_per_s),
            .tv_usec = @intCast(c_long, (ns % std.time.ns_per_s) / std.time.ns_per_us),
        }
    else
        null;

    // We just set nfds to zero, since it is ignored.
    // https://docs.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-select
    const nfds = 0;

    const rc = WinSock.select(nfds, read_inner, write_inner, except_inner, timeout);
    if (rc == ws2_32.SOCKET_ERROR) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSANOTINITIALISED => unreachable,
            .WSAENETDOWN => return error.NetworkSubsystemFailed,
            .WSAEFAULT => unreachable,
            .WSAENOTSOCK => return error.FileDescriptorNotASocket,
            .WSAEINVAL => return error.SocketNotBound,
            else => |err| windows.unexpectedWSAError(err),
        };
    }
    return rc > 0;
}
