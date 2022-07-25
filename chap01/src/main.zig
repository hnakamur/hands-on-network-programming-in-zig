const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;
const ULONG = windows.ULONG;
const DWORD = windows.DWORD;
const PVOID = windows.PVOID;
const ULONG_PTR = windows.ULONG_PTR;
const win32 = @import("win32");
const ip_helper = win32.network_management.ip_helper;
const ADDRESS_FAMILY = ip_helper.ADDRESS_FAMILY;
const GET_ADAPTERS_ADDRESSES_FLAGS = ip_helper.GET_ADAPTERS_ADDRESSES_FLAGS;
const IP_ADAPTER_ADDRESSES_XP = ip_helper.IP_ADAPTER_ADDRESSES_XP;
const AF_UNSPEC = ip_helper.AF_UNSPEC;
const GAA_FLAG_INCLUDE_PREFIX = ip_helper.GAA_FLAG_INCLUDE_PREFIX;
const ERROR_BUFFER_OVERFLOW = win32.everything.ERROR_BUFFER_OVERFLOW;
const ERROR_SUCCESS = win32.everything.ERROR_SUCCESS;
const WIN32_ERROR = win32.everything.WIN32_ERROR;
const AF_INET = win32.everything.AF_INET;
const getnameinfo = win32.everything.getnameinfo;
const NI_NUMERICHOST = win32.everything.NI_NUMERICHOST;

pub extern "IPHLPAPI" fn GetAdaptersAddresses(
    Family: ADDRESS_FAMILY,
    Flags: GET_ADAPTERS_ADDRESSES_FLAGS,
    Reserved: ?*anyopaque,
    // TODO: what to do with BytesParamIndex 4?
    AdapterAddresses: ?*IP_ADAPTER_ADDRESSES_XP,
    SizePointer: ?*u32,
) callconv(WINAPI) WIN32_ERROR;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) @panic("leak");
    var allocator = gpa.allocator();

    var ret_err: ?anyerror = null;
    {
        _ = try windows.WSAStartup(2, 2);
        defer {
            windows.WSACleanup() catch |err| {
                ret_err = err;
            };
        }

        var asize: DWORD = 2000;
        var buf: []u8 = undefined;
        var adapters: ?*IP_ADAPTER_ADDRESSES_XP = null;
        while (true) {
            buf = try allocator.alloc(u8, asize);
            adapters = @intToPtr(*IP_ADAPTER_ADDRESSES_XP, @ptrToInt(buf.ptr));
            const r = GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_PREFIX, null, adapters, &asize);
            switch (r) {
                ERROR_SUCCESS => break,
                ERROR_BUFFER_OVERFLOW => allocator.free(buf),
                else => {
                    allocator.free(buf);
                    return error.GetAdaptersAddresses;
                },
            }
        }
        defer allocator.free(buf);

        var adapter = adapters;
        while (adapter) |adap| {
            if (adap.FriendlyName == null) {
                return error.NullAdapterName;
            }
            const name_u16 = adap.FriendlyName.?;
            const name_len = indexOfSentinel(u16, name_u16, 0);
            const name = name_u16[0..name_len];
            std.debug.print("name={}\n", .{std.unicode.fmtUtf16le(name)});

            var address = adap.FirstUnicastAddress;
            while (address) |addr| {
                const family = if (@as(u32, addr.Address.lpSockaddr.?.sa_family) == @enumToInt(AF_INET))
                    "IPv4"
                else
                    "IPv6";
                std.debug.print("\t{s}", .{family});

                var ap: [100]u8 = undefined;
                var ap_s = ap[0..];
                const r = getnameinfo(
                    addr.Address.lpSockaddr.?,
                    addr.Address.iSockaddrLength,
                    ap_s,
                    @sizeOf(@TypeOf(ap)),
                    null,
                    0,
                    NI_NUMERICHOST,
                );
                if (r != 0) {
                    return error.getnameinfo;
                }
                const ap_len = indexOfSentinel(u8, ap_s, 0);
                std.debug.print("\t{s}\n", .{ap[0..ap_len]});

                address = addr.Next;
            }
            adapter = adap.Next;
        }
    }
}

fn indexOfSentinel(comptime T: type, ptr: [*]const T, value: T) usize {
    var i: usize = 0;
    while (ptr[i] != value) : (i += 1) {}
    return i;
}
