const std = @import("std");
const c = @cImport({
    @cInclude("ifaddrs.h");
    @cInclude("netdb.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/types.h");
});

pub fn main() !void {
    var addresses: ?*c.struct_ifaddrs = undefined;

    if (c.getifaddrs(&addresses) == -1) {
        @panic("getifaddrs call failed");
    }
    defer c.freeifaddrs(addresses);

    var address = addresses;
    while (address) |addr| {
        if (addr.ifa_addr == null) {
            address = addr.ifa_next;
            continue;
        }

        const family = addr.ifa_addr.*.sa_family;
        if (family == c.AF_INET or family == c.AF_INET6) {
            std.debug.print("{s}\t", .{addr.ifa_name});
            const family_str = if (family == c.AF_INET)
                "IPv4"
            else
                "IPv6";
            std.debug.print("{s}\t", .{family_str});

            var ap: [100]u8 = undefined;
            var ap_s = ap[0..];
            const family_size: c_uint = if (family == c.AF_INET)
                @sizeOf(c.struct_sockaddr_in)
            else
                @sizeOf(c.struct_sockaddr_in6);
            const r = c.getnameinfo(
                addr.ifa_addr,
                family_size,
                ap_s,
                @sizeOf(@TypeOf(ap)),
                null,
                0,
                c.NI_NUMERICHOST,
            );
            if (r != 0) {
                @panic("getnameinfo failed");
            }
            std.debug.print("\t{s}\n", .{ap});
        }
        address = addr.ifa_next;
    }
}
