const std = @import("std");
const builtin = @import("builtin");

pub const FdSet = if (builtin.os.tag == .windows)
    @import("select_windows.zig").FdSet
else
    @import("select_posix.zig").FdSet;

pub const select = if (builtin.os.tag == .windows)
    @import("select_windows.zig").select
else
    @import("select_posix.zig").select;
