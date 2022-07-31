const std = @import("std");

pub fn parseIntDigits(comptime T: type, s: []const u8) !T {
    return try parseIntDigitsWithMax(T, s, std.math.maxInt(T));
}

pub fn parseIntDigitsWithMax(comptime T: type, s: []const u8, max: T) !T {
    if (s.len == 0) {
        return error.Empty;
    }

    var ret: T = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (ret > max / 10) {
            return error.Overflow;
        }
        ret *= 10;
        const d = std.fmt.charToDigit(s[i], 10) catch return error.NotDigit;
        if (ret > max - d) {
            return error.Overflow;
        }
        ret += d;
    }
    return ret;
}

pub fn getDigitsSpan(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and '0' <= s[i] and s[i] <= '9') : (i += 1) {}
    return s[0..i];
}

const testing = std.testing;

test "parseIntDigits" {
    try testing.expectEqual(@as(u16, 65535), try parseIntDigits(u16, "65535"));

    try testing.expectError(error.Empty, parseIntDigits(u16, ""));
    try testing.expectError(error.Overflow, parseIntDigits(u16, "65536"));
    try testing.expectError(error.Overflow, parseIntDigits(u16, "70000"));
    try testing.expectError(error.NotDigit, parseIntDigits(u16, "0x24"));
}

test "parseIntDigitsWithMax" {
    try testing.expectEqual(@as(u32, 60000), try parseIntDigitsWithMax(u32, "60000", 60000));
    try testing.expectEqual(@as(u32, 65535), try parseIntDigitsWithMax(u32, "65535", std.math.maxInt(u16)));
    try testing.expectError(error.Overflow, parseIntDigitsWithMax(u32, "65536", std.math.maxInt(u16)));
}
