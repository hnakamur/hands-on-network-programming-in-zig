const std = @import("std");
const builtin = @import("builtin");
const ws2_32 = std.os.windows.ws2_32;
const ws2_32_or_c = if (builtin.os.tag == .windows) ws2_32 else std.c;
const ws2_32_or_os = if (builtin.os.tag == .windows) ws2_32 else std.os;

pub const os = struct {
    pub const AI = ws2_32_or_c.AI;

    pub const NI = if (builtin.os.tag == .windows)
        struct {
            pub const NUMERICHOST = ws2_32.NI_NUMERICHOST;
            pub const NUMERICSERV = ws2_32.NI_NUMERICSERV;
            pub const NOFQDN = ws2_32.NI_NOFQDN;
            pub const NAMEREQD = ws2_32.NI_NAMEREQD;
            pub const DGRAM = ws2_32.NI_DGRAM;
            pub const NUMERICSCOPE = 0x100;
        }
    else
        std.c.NI;

    pub const freeaddrinfo = ws2_32_or_c.freeaddrinfo;
    pub const sockaddr = ws2_32_or_c.sockaddr;

    pub const addrinfo = ws2_32_or_os.addrinfo;

    pub fn getaddrinfo(
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

    pub fn getaddrinfoZ(
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

    const windowsOrPosix = if (builtin.os.tag == .windows) windows else posix;

    pub fn getnameinfo(
        addr: *const sockaddr,
        addrlen: usize,
        host_buffer: ?*[]u8,
        serv_buffer: ?*[]u8,
        flags: u32,
    ) !void {
        var host = if (host_buffer) |b| @ptrCast([*]u8, b.*) else null;
        const hostlen = if (host_buffer) |b| b.len else 0;
        var serv = if (serv_buffer) |b| @ptrCast([*]u8, b.*) else null;
        const servlen = if (serv_buffer) |b| b.len else 0;
        try windowsOrPosix.getnameinfo(addr, addrlen, host, hostlen, serv, servlen, flags);
        if (host_buffer) |b| {
            b.len = std.mem.indexOfSentinel(u8, 0, @ptrCast([*:0]u8, b.*));
        }
        if (serv_buffer) |b| {
            b.len = std.mem.indexOfSentinel(u8, 0, @ptrCast([*:0]u8, b.*));
        }
    }

    const windows = struct {
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

    const posix = struct {
        fn getnameinfo(
            addr: *const sockaddr,
            addrlen: usize,
            host: ?[*]u8,
            hostlen: usize,
            serv: ?[*]u8,
            servlen: usize,
            flags: u32,
        ) !void {
            const rc = c.getnameinfo(
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
};

pub const c = struct {
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
