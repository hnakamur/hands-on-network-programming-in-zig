const std = @import("std");
const c = @cImport({
    @cInclude("openssl/crypto.h");
});

pub fn main() !void {
    const version = c.OpenSSL_version(c.SSLEAY_VERSION);
    const off = std.mem.indexOfSentinel(u8, 0, version);
    std.debug.print("OpenSSL version: {s}\n", .{version[0..off]});
}
