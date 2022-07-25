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
            std.debug.print("iftype={}", .{adap.IfType});
            if (adap.FriendlyName) |name_u16| {
                const name_len = indexOfSentinel(u16, name_u16, 0);
                const name = name_u16[0..name_len];
                std.debug.print(", name={}", .{std.unicode.fmtUtf16le(name)});
            }
            std.debug.print("\n", .{});
            adapter = adap.Next;
        }
    }
}

fn indexOfSentinel(comptime T: type, ptr: [*]const T, value: T) usize {
    var i: usize = 0;
    while (ptr[i] != value) : (i += 1) {}
    return i;
}
