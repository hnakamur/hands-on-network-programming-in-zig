const std = @import("std");
const builtin = @import("builtin");
const ws2_32 = std.os.windows.ws2_32;
const Args = @import("lib").Args;
const winsock = @import("lib").winsock;

const ws2_32_or_os = if (builtin.os.tag == .windows) ws2_32 else std.os;
const addrinfo = ws2_32_or_os.addrinfo;

const ws2_32_or_c = if (builtin.os.tag == .windows) ws2_32 else std.c;
const AI = ws2_32_or_c.AI;
const freeaddrinfo = ws2_32_or_c.freeaddrinfo;
const sockaddr = ws2_32_or_c.sockaddr;
const NI_NUMERICHOST = if (builtin.os.tag == .windows)
    ws2_32.NI_NUMERICHOST
else
    std.c.NI.NUMERICHOST;

const log_level = std.log.debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var args = try Args.init(allocator);
    defer args.deinit(allocator);

    if (args.args.len != 2) {
        const exe_name = if (args.args.len > 0) std.fs.path.basename(args.args[0]) else "lookup";
        std.debug.print("Usage: {s} hostname\nExample: {s} example.com\n", .{ exe_name, exe_name });
        std.os.exit(2);
    }

    const hostname = args.args[1];
    std.debug.print("hostname={s}\n", .{hostname});

    try winsock.startup();
    defer winsock.cleanup();

    var hints: addrinfo = std.mem.zeroes(addrinfo);
    hints.flags = AI.ALL;
    var peer_address: *addrinfo = undefined;
    try getaddrinfo(allocator, hostname, null, &hints, &peer_address);
    defer freeaddrinfo(peer_address);

    std.debug.print("Remote address is:\n", .{});
    var address: ?*addrinfo = peer_address;
    while (address) |addr| {
        var address_buffer: [100]u8 = undefined;
        try getnameinfo(
            addr.addr.?,
            addr.addrlen,
            address_buffer[0..],
            @sizeOf(@TypeOf(address_buffer)),
            null,
            0,
            NI_NUMERICHOST,
        );
        const len = std.mem.indexOfSentinel(u8, 0, @ptrCast([*:0]u8, address_buffer[0..]));
        std.debug.print("\t{s}\n", .{address_buffer[0..len]});
        address = addr.next;
    }
}

fn getaddrinfo(
    allocator: std.mem.Allocator,
    node: ?[]const u8,
    service: ?[]const u8,
    noalias hints: ?*const addrinfo,
    noalias res: **addrinfo,
) !void {
    var node_z = if (node) |n| try allocator.dupeZ(u8, n) else null;
    defer if (node_z) |n| allocator.free(n);
    var service_z = if (service) |s| try allocator.dupeZ(u8, s) else null;
    defer if (service_z) |s| allocator.free(s);
    try getaddrinfoZ(
        if (node_z) |n| n.ptr else null,
        if (service_z) |s| s.ptr else null,
        hints,
        res,
    );
}

fn getaddrinfoZ(
    noalias node: ?[*:0]const u8,
    noalias service: ?[*:0]const u8,
    noalias hints: ?*const addrinfo,
    noalias res: **addrinfo,
) !void {
    const rc = ws2_32_or_c.getaddrinfo(node, service, hints, res);
    if (builtin.os.tag == .windows) {
        try windowsCheckEaiError(rc);
    } else {
        try posixCheckEaiError(rc);
    }
}

fn windowsCheckEaiError(rc: i32) !void {
    if (rc != 0) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSA_NOT_ENOUGH_MEMORY => error.AddrInfoMemory,
            .WSAEAFNOSUPPORT => error.AddrInfoFamily,
            .WSAEINVAL => error.AddrInfoBadFlags,
            .WSAESOCKTNOSUPPORT => error.AddrInfoSockType,
            .WSAHOST_NOT_FOUND => error.AddrInfoNoName,
            .WSANO_DATA => error.AddrInfoNoData,
            .WSANO_RECOVERY => error.AddrInfoFail,
            .WSANOTINITIALISED => @panic("TODO: handle WSANOTINITIALISED"),
            .WSATRY_AGAIN => error.AddrInfoAgain,
            .WSATYPE_NOT_FOUND => error.AddrInfoService,
            else => error.AddrInfoOther,
        };
    }
}

fn posixCheckEaiError(rc: std.c.EAI) !void {
    if (@enumToInt(rc) != 0) {
        return switch (rc) {
            .BADFLAGS => error.AddrInfoBadFlags,
            .NONAME => error.AddrInfoNoName,
            .AGAIN => error.AddrInfoAgain,
            .FAIL => error.AddrInfoFail,
            .FAMILY => error.AddrInfoFamily,
            .SOCKTYPE => error.AddrInfoSockType,
            .SERVICE => error.AddrInfoService,
            .MEMORY => error.AddrInfoMemory,
            .SYSTEM => error.AddrInfoSystem,
            .OVERFLOW => error.AddrInfoOverflow,
            .NODATA => error.AddrInfoNoData,
            .ADDRFAMILY => error.AddrInfoAddrFamily,
            .INPROGRESS => error.AddrInfoAddrInProgress,
            .CANCELED => error.AddrInfoAddrCanceled,
            .ALLDONE => error.AddrInfoAllDone,
            .INTR => error.AddrInfoIntr,
            .IDN_ENCODE => error.AddrInfoIdnEncode,
            else => error.AddrInfoOther,
        };
    }
}

const MyOsWinOrPosix = if (builtin.os.tag == .windows) MyOsWin else MyOsPosix;
const getnameinfo = MyOsWinOrPosix.getnameinfo;

const MyOsWin = struct {
    fn getnameinfo(
        addr: *const sockaddr,
        addrlen: usize,
        host: ?[*]u8,
        hostlen: usize,
        serv: ?[*]u8,
        servlen: usize,
        flags: u32,
    ) !void {
        const rc = ws2_32.getnameinfo(
            addr,
            @intCast(i32, addrlen),
            host,
            @intCast(u32, hostlen),
            serv,
            @intCast(u32, servlen),
            @intCast(i32, flags),
        );
        try windowsCheckEaiError(rc);
    }
};

const MyOsPosix = struct {
    fn getnameinfo(
        addr: *const sockaddr,
        addrlen: usize,
        host: ?[*]u8,
        hostlen: usize,
        serv: ?[*]u8,
        servlen: usize,
        flags: u32,
    ) !void {
        const rc = MyC.getnameinfo(
            addr,
            @intCast(std.c.socklen_t, addrlen),
            host,
            @intCast(std.c.socklen_t, hostlen),
            serv,
            @intCast(std.c.socklen_t, servlen),
            flags,
        );
        try posixCheckEaiError(rc);
    }
};

const MyC = struct {
    pub extern "c" fn getnameinfo(
        noalias addr: *const std.c.sockaddr,
        addrlen: std.c.socklen_t,
        noalias host: ?[*]u8,
        hostlen: std.c.socklen_t,
        noalias serv: ?[*]u8,
        servlen: std.c.socklen_t,
        flags: u32,
    ) std.c.EAI;
};
