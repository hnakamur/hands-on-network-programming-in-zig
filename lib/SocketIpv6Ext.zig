const std = @import("std");
const builtin = @import("builtin");

pub const SocketIpv6Ext = @This();

pub fn setV6OnlyOrNop(self: std.x.os.Socket, enabled: bool) !void {
    const level = switch (builtin.os.tag) {
        .windows => 41, // should be defined as std.os.windows.ws2_32.IPPROTO.IPV6
        .linux => std.os.IPPROTO.IPV6,
        else => return, // No-op for other OSes such as macOS and FreeBSD.
    };

    const code = switch (builtin.os.tag) {
        .windows => std.os.windows.ws2_32.IPV6_V6ONLY,
        .linux => std.os.linux.IPV6.V6ONLY,
        else => unreachable,
    };

    std.log.debug(
        "SocketIpv6Ext.setV6OnlyOrNop level={}, code={}, enabled={}",
        .{ level, code, enabled },
    );
    return self.setOption(level, code, std.mem.asBytes(&@as(u32, @boolToInt(enabled))));
}
