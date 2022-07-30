const std = @import("std");
const c = @cImport({
    @cInclude("sys/select.h");
});

pub const FdSet = struct {
};

pub fn select(read_fds: ?*FdSet, write_fds: ?*FdSet, except_fds: ?*FdSet, timeout_nanoseconds: ?u64) !bool {
    _ = read_fds;
    _ = write_fds;
    _ = except_fds;
    _ = timeout_nanoseconds;
    @panic("not implemented yet");
}
