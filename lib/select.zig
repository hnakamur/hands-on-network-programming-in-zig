const std = @import("std");
const builtin = @import("builtin");
const posix = @import("select_posix.zig");
const windows = @import("select_windows.zig");

pub const FdSet = if (builtin.os.tag == .windows) windows.FdSet else posix.FdSet;
pub const select = if (builtin.os.tag == .windows) windows.select else posix.select;
