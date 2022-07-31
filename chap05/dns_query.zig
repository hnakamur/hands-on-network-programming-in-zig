const std = @import("std");
const mystd = @import("lib").mystd;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try mystd.process.Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 3) {
        const exe_name = if (args.args.len > 0) std.fs.path.basename(args.args[0]) else "dns_query";
        std.debug.print("Usage: {s} hostname type\nExample: {s} example.com aaaa\n", .{ exe_name, exe_name });
        std.os.exit(2);
    }

    const hostname = args.args[1];
    const record_type_str = args.args[2];

    if (hostname.len > 255) {
        std.debug.print("hostname too long.\n", .{});
        std.os.exit(1);
    }

    const record_type = if (std.ascii.eqlIgnoreCase(record_type_str, "a"))
        @as(u8, 1)
    else if (std.ascii.eqlIgnoreCase(record_type_str, "mx"))
        @as(u8, 15)
    else if (std.ascii.eqlIgnoreCase(record_type_str, "txt"))
        @as(u8, 16)
    else if (std.ascii.eqlIgnoreCase(record_type_str, "aaaa"))
        @as(u8, 28)
    else if (std.ascii.eqlIgnoreCase(record_type_str, "any"))
        @as(u8, 255)
    else {
        std.debug.print(
            "Unsupported type: {s}. Use a, aaaa, txt, mx, or any.\n",
            .{record_type_str},
        );
        std.os.exit(1);
    };

    std.debug.print("hostname={s}, record_type={}\n", .{ hostname, record_type });

    try mystd.os.windows.winsock.startup();
    defer mystd.os.windows.winsock.cleanup();

    const peer_address = try mystd.net.SocketAddressExt.parse("8.8.8.8", 53);
    const socket_domain: u32 = mystd.net.SocketAddressExt.toSocketDomain(peer_address);
    const socket_peer = try std.x.os.Socket.init(socket_domain, std.os.SOCK.DGRAM, 0, .{});
    defer socket_peer.deinit();

    var query: [1024]u8 = undefined;
    std.mem.copy(u8, query[0..], &[_]u8{
        0xAB, 0xCD, // ID
        0x01, 0x00, // Set recursion
        0x00, 0x01, // QDCOUNT
        0x00, 0x00, // ANCOUNT
        0x00, 0x00, // NSCOUNT
        0x00, 0x00, // ARCOUNT
    });
    var p: [*]u8 = query[12..];
    var hi: usize = 0;
    while (hi < hostname.len) {
        var len: [*]u8 = p;
        p += 1;
        if (hi != 0) hi += 1;
        while (hi < hostname.len and hostname[hi] != '.') {
            p.* = hostname[hi];
            p += 1;
            hi += 1;
        }
        len.* = @intCast(u8, @ptrToInt(p) - @ptrToInt(len) - 1);
    }
    p.* = 0;
    p += 1;
    p.* = 0x00;
    p += 1;
    p.* = record_type; // QTYPE
    p += 1;
    p.* = 0x00;
    p += 1;
    p.* = 0x01; // QCLASS
    p += 1;

    const query_size = @ptrToInt(p) - @ptrToInt(query[0..]);
    std.debug.print(
        "query_size={}, query={}\n",
        .{ query_size, std.fmt.fmtSliceHexLower(query[0..query_size]) },
    );
    try printDnsMessage(query[0..query_size]);

    const bytes_sent = try mystd.net.SocketUdpExt.sendto(
        socket_peer,
        query[0..query_size],
        0,
        &peer_address,
    );
    std.debug.print("Sent {} of {} bytes.\n", .{ bytes_sent, query_size });

    var response_buf: [1024]u8 = undefined;
    const bytes_received = try mystd.net.SocketUdpExt.recvfrom(socket_peer, response_buf[0..], 0, null);
    std.debug.print("Received {} bytes.\n", .{bytes_received});
    try printDnsMessage(response_buf[0..bytes_received]);
}

fn printDnsMessage(msg: []const u8) !void {
    if (msg.len < 12) {
        return error.MessageTooShort;
    }

    std.debug.print("ID = 0x{X:02}, 0x{X:02}\n", .{ msg[0], msg[1] });

    const qr = (msg[2] & 0x80) >> 7;
    const qr_str = if (qr != 0) @as([]const u8, "response") else @as([]const u8, "query");
    std.debug.print("QR = {} {s}\n", .{ qr, qr_str });

    const opcode = (msg[2] & 0x78) >> 3;
    const opcode_str = switch (opcode) {
        0 => "standard",
        1 => "reverse",
        2 => "status",
        else => "?",
    };
    std.debug.print("OPCODE = {} {s}\n", .{ opcode, opcode_str });

    const aa = (msg[2] & 0x04) >> 2;
    const aa_str = if (aa != 0) "authoritative" else "";
    std.debug.print("AA = {} {s}\n", .{ aa, aa_str });

    const tc = (msg[2] & 0x02) >> 1;
    const tc_str = if (tc != 0) "message truncated" else "";
    std.debug.print("TC = {} {s}\n", .{ tc, tc_str });

    const rd = (msg[2] & 0x02) >> 1;
    const rd_str = if (rd != 0) "recursion desired" else "";
    std.debug.print("RD = {} {s}\n", .{ rd, rd_str });

    if (qr != 0) {
        const rcode = msg[3] & 0x0F;
        const rcode_str = switch (opcode) {
            0 => "success",
            1 => "format error",
            2 => "server failure",
            3 => "name error",
            4 => "not implemented",
            5 => "refused",
            else => "?",
        };
        std.debug.print("RCODE = {} {s}\n", .{ rcode, rcode_str });
        if (rcode != 0) return;
    }

    const qdcount = std.mem.readIntBig(u16, msg[4..6]);
    const ancount = std.mem.readIntBig(u16, msg[6..8]);
    const nscount = std.mem.readIntBig(u16, msg[8..10]);
    const arcount = std.mem.readIntBig(u16, msg[10..12]);
    std.debug.print("QDCOUNT = {}\n", .{qdcount});
    std.debug.print("ANCOUNT = {}\n", .{ancount});
    std.debug.print("NSCOUNT = {}\n", .{nscount});
    std.debug.print("ARCOUNT = {}\n", .{arcount});

    var off: usize = 12;
    if (qdcount > 0) {
        var i: usize = 0;
        while (i < qdcount) : (i += 1) {
            if (off >= msg.len) {
                return error.UnexpectedEof;
            }

            std.debug.print("Qeury {d: >2}\n", .{i + 1});
            std.debug.print("  name: ", .{});
            off = try printName(msg, off);
            std.debug.print("\n", .{});

            if (off + 4 > msg.len) {
                return error.UnexpectedEof;
            }

            const @"type" = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
            std.debug.print("  type: {}\n", .{@"type"});
            off += 2;

            const qclass = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
            std.debug.print("  class: {}\n", .{qclass});
            off += 2;
        }
    }

    if (ancount > 0 or nscount > 0 or arcount > 0) {
        var i: usize = 0;
        while (i < ancount + nscount + arcount) : (i += 1) {
            if (off >= msg.len) {
                return error.UnexpectedEof;
            }

            std.debug.print("Answer {d: >2}\n", .{i + 1});
            std.debug.print("  name: ", .{});
            off = try printName(msg, off);
            std.debug.print("\n", .{});

            if (off + 10 > msg.len) {
                return error.UnexpectedEof;
            }

            const @"type" = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
            std.debug.print("  type: {}\n", .{@"type"});
            off += 2;

            const qclass = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
            std.debug.print(" class: {}\n", .{qclass});
            off += 2;

            const ttl = std.mem.readIntBig(u32, msg[off .. off + 4][0..4]);
            std.debug.print("   ttl: {}\n", .{ttl});
            off += 4;

            const rdlen = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
            std.debug.print("  rdlen: {}\n", .{rdlen});
            off += 2;

            if (off + rdlen > msg.len) {
                return error.UnexpectedEof;
            }

            if (rdlen == 4 and @"type" == 1) {
                // A Record
                std.debug.print("Address {}.{}.{}.{}\n", .{
                    msg[off], msg[off + 1], msg[off + 2], msg[off + 3],
                });
            } else if (rdlen == 16 and @"type" == 28) {
                // AAAA Record
                var j: usize = 0;
                while (j < rdlen) : (j += 2) {
                    std.debug.print("{x:0<2}{x:0<2}", .{ msg[off + j], msg[off + j + 1] });
                    if (j + 2 < rdlen) std.debug.print(":", .{});
                }
                std.debug.print("\n", .{});
            } else if (@"type" == 15 and rdlen > 3) {
                // MX Record
                const preference = std.mem.readIntBig(u16, msg[off .. off + 2][0..2]);
                std.debug.print("  pref: {}\n", .{preference});
                std.debug.print("MX: ", .{});
                _ = try printName(msg, off + 2);
                std.debug.print("\n", .{});
            } else if (@"type" == 16) {
                // TXT Record
                std.debug.print("TXT: \"{s}\"\n", .{msg[off + 1 .. off + 1 + (rdlen - 1)]});
            } else if (@"type" == 5) {
                // CNAME Record
                std.debug.print("CNAME: ", .{});
                _ = try printName(msg, off);
                std.debug.print("\n", .{});
            }

            off += rdlen;
        }
    }

    if (off != msg.len) {
        return error.UnreadDataLeftOver;
    }

    std.debug.print("\n", .{});
}

fn printName(msg: []const u8, pos: usize) error{UnexpectedEof}!usize {
    var off = pos;
    if (off + 2 > msg.len) {
        return error.UnexpectedEof;
    }

    if (msg[off] & 0xC0 == 0xC0) {
        const k = std.mem.readIntBig(u16, &[_]u8{ msg[off] & 0x3F, msg[off + 1] });
        off += 2;
        std.debug.print(" (pointer {}) ", .{k});
        _ = try printName(msg, k);
        return off;
    } else {
        const len = msg[off];
        off += 1;
        if (off + len + 1 > msg.len) {
            return error.UnexpectedEof;
        }
        std.debug.print("{s}", .{msg[off .. off + len]});
        off += len;
        if (msg[off] != '\x00') {
            std.debug.print(".", .{});
            return try printName(msg, off);
        } else {
            return off + 1;
        }
    }
}
