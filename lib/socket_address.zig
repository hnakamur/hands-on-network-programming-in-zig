const std = @import("std");

pub fn parsePort(port_str: []const u8) error{InvalidPort}!u16 {
    if (port_str.len == 0 or port_str.len > 5) {
        return error.InvalidPort;
    }
    var port: u32 = 0;
    for (port_str) |c| {
        port *= 10;
        port += std.fmt.charToDigit(c, 10) catch return error.InvalidPort;
    }
    if (port > std.math.maxInt(u16)) {
        return error.InvalidPort;
    }
    return @truncate(u16, port);
}

pub fn parseSocketAddress(host: []const u8, port: u16) !std.x.os.Socket.Address {
    if (std.x.os.IPv4.parse(host)) |ip4| {
        return std.x.os.Socket.Address.initIPv4(ip4, port);
    } else |_| {}

    // NOTE: scope_id must be zero for Windows to connect to ::1.
    if (std.x.os.IPv6.parseWithScopeID(host, 0)) |ip6| {
        return std.x.os.Socket.Address.initIPv6(ip6, port);
    } else |_| {}

    return error.InvalidIPAddressFormat;
}

const testing = std.testing;

test "parsePort" {
    try testing.expectEqual(@as(u16, 0), try parsePort("0"));
    try testing.expectEqual(@as(u16, 65535), try parsePort("65535"));

    try testing.expectError(error.InvalidPort, parsePort(""));
    try testing.expectError(error.InvalidPort, parsePort("65536"));
    try testing.expectError(error.InvalidPort, parsePort("0x01"));
    try testing.expectError(error.InvalidPort, parsePort("-2"));
}

test "parseSocketAddress" {
    const Address = std.x.os.Socket.Address;
    const IPv4 = std.x.os.IPv4;
    const IPv6 = std.x.os.IPv6;
    try testing.expectEqual(Address{
        .ipv4 = .{ .host = IPv4.localhost, .port = 8080 },
    }, try parseSocketAddress("127.0.0.1", 8080));
    try testing.expectEqual(Address{
        .ipv6 = .{ .host = .{ .octets = IPv6.localhost_octets, .scope_id = 0 }, .port = 443 },
    }, try parseSocketAddress("::1", 443));
    try testing.expectEqual(Address{
        .ipv4 = .{ .host = IPv4.unspecified, .port = 8080 },
    }, try parseSocketAddress("0.0.0.0", 8080));
    try testing.expectEqual(Address{
        .ipv6 = .{ .host = .{ .octets = IPv6.unspecified_octets, .scope_id = 0 }, .port = 443 },
    }, try parseSocketAddress("::", 443));

    try testing.expectError(error.InvalidIPAddressFormat, parseSocketAddress("localhost", 8080));
}
