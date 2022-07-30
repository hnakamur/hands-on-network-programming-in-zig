const std = @import("std");
const c = @cImport({
    @cInclude("sys/select.h");
});

pub const FdSet = struct {
    const FD_SETSIZE = 1024;
    const BitSet = std.StaticBitSet(FD_SETSIZE);

    pub const SetSocketIterator = struct {
        pub const InnerIterator = BitSet.Iterator(.{});

        inner: InnerIterator,

        pub fn next(self: *SetSocketIterator) ?std.os.socket_t {
            return if (self.inner.next()) |i| @intCast(std.os.socket_t, i) else null;
        }
    };

    bitset: BitSet,
    len: usize,

    pub fn init() FdSet {
        return .{ .bitset = BitSet.initEmpty(), .len = 0 };
    }

    pub fn isSet(self: *const FdSet, socket: std.os.socket_t) bool {
        return self.bitset.isSet(@intCast(usize, socket));
    }

    pub fn set(self: *FdSet, socket: std.os.socket_t) void {
        const i = @intCast(usize, socket);
        self.bitset.set(i);
        if (i >= self.len) {
            self.len = i + 1;
        }
    }

    pub fn unset(self: *FdSet, socket: std.os.socket_t) void {
        const i = @intCast(usize, socket);
        self.bitset.unset(i);
        if (i == self.len - 1) {
            if (i == 0) {
                self.len = 0;
            } else {
                var j: usize = i - 1;
                while (true) : (j -= 1) {
                    if (self.bitset.isSet(j)) {
                        self.len = j + 1;
                        break;
                    }
                    if (j == 0) {
                        self.len = 0;
                        break;
                    }
                }
            }
        }
    }

    pub fn clone(self: *const FdSet) FdSet {
        return .{ .bitset = self.bitset, .len = self.len };
    }

    pub fn iterator(self: *const FdSet) SetSocketIterator {
        return .{ .inner = self.bitset.iterator(.{}) };
    }
};

pub fn select(read_fds: ?*FdSet, write_fds: ?*FdSet, except_fds: ?*FdSet, timeout_nanoseconds: ?u64) !bool {
    var read_bitset = if (read_fds) |fds| &fds.bitset else null;
    var write_bitset = if (write_fds) |fds| &fds.bitset else null;
    var except_bitset = if (except_fds) |fds| &fds.bitset else null;
    var timeout = if (timeout_nanoseconds) |ns|
        &c.struct_timeval{
            .tv_sec = @intCast(c_long, ns / std.time.ns_per_s),
            .tv_usec = @intCast(c_int, (ns % std.time.ns_per_s) / std.time.ns_per_us),
        }
    else
        null;

    var nfds: c_int = 0;
    if (read_fds) |fds| {
        if (fds.len > nfds) nfds = @intCast(c_int, fds.len);
    }
    if (write_fds) |fds| {
        if (fds.len > nfds) nfds = @intCast(c_int, fds.len);
    }
    if (except_fds) |fds| {
        if (fds.len > nfds) nfds = @intCast(c_int, fds.len);
    }
    const n = c.select(nfds, @ptrToInt(read_bitset), @ptrToInt(write_bitset), @ptrToInt(except_bitset), timeout);
    if (n < 0) {
        return error.Select;
    }
    return n > 0;
}

const testing = std.testing;

test "FdSet posix" {
    var fd_set = FdSet.init();

    fd_set.set(3);
    try testing.expectEqual(@as(usize, 4), fd_set.len);
    fd_set.set(4);
    try testing.expectEqual(@as(usize, 5), fd_set.len);
    fd_set.set(7);
    try testing.expectEqual(@as(usize, 8), fd_set.len);

    var it = fd_set.iterator();
    try testing.expectEqual(@as(?std.os.socket_t, 3), it.next());
    try testing.expectEqual(@as(?std.os.socket_t, 4), it.next());
    try testing.expectEqual(@as(?std.os.socket_t, 7), it.next());
    try testing.expectEqual(@as(?std.os.socket_t, null), it.next());

    var fd_set2 = fd_set.clone();
    var it2 = fd_set2.iterator();
    try testing.expectEqual(@as(?std.os.socket_t, 3), it2.next());
    try testing.expectEqual(@as(?std.os.socket_t, 4), it2.next());
    try testing.expectEqual(@as(?std.os.socket_t, 7), it2.next());
    try testing.expectEqual(@as(?std.os.socket_t, null), it2.next());

    fd_set.unset(7);
    try testing.expectEqual(@as(usize, 5), fd_set.len);
    fd_set.unset(3);
    try testing.expectEqual(@as(usize, 5), fd_set.len);
    fd_set.unset(4);
    try testing.expectEqual(@as(usize, 0), fd_set.len);
}
