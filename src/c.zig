const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("raymath.h");
    // @cInclude("raygui.h");
});

// TODO consider moving platform specific code to own module

pub const win32 = struct {
    const WINAPI = @import("std").os.windows.WINAPI;

    const HOSTENT = struct {
        h_name: [*]u8,
        h_aliases: [*c]u8,
        h_addrtype: u16,
        h_length: u16,
        h_addr_list: [*c]u8,
    };

    pub extern "ws2_32" fn gethostname(
        name: [*]u8,
        namelen: i32,
    ) callconv(WINAPI) i32;

    pub extern "ws2_32" fn gethostbyname(
        a: [*]const u8,
    ) *HOSTENT;
};

/// [...] this string must be 256 bytes or less. [...]
///
/// https://learn.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-gethostname#remarks
const HOST_NAME_MAX_WINDOWS = 256;
const HOST_NAME_MAX = if (builtin.os.tag == .windows) HOST_NAME_MAX_WINDOWS else std.posix.HOST_NAME_MAX;

pub fn gethostname(name_buffer: *[HOST_NAME_MAX]u8) std.posix.GetHostNameError![]u8 {
    if (builtin.os.tag == .windows) {
        const rc = win32.gethostname(name_buffer, name_buffer.len);
        if (rc == std.os.windows.ws2_32.SOCKET_ERROR) {
            switch (std.os.windows.ws2_32.WSAGetLastError()) {
                // The name parameter is a NULL pointer or is not a valid part of the user address space.
                // This error is also returned if the buffer size specified by namelen parameter is too small to hold the complete host name.
                std.os.windows.ws2_32.WinsockError.WSAEFAULT => unreachable,

                // A successful WSAStartup call must occur before using this function.
                std.os.windows.ws2_32.WinsockError.WSANOTINITIALISED => return std.posix.GetHostNameError.PermissionDenied,

                // The network subsystem has failed.
                std.os.windows.ws2_32.WinsockError.WSAENETDOWN => unreachable,

                //A blocking Windows Sockets 1.1 call is in progress, or the service provider is still processing a callback function.
                std.os.windows.ws2_32.WinsockError.WSAEINPROGRESS => return std.posix.GetHostNameError.PermissionDenied,
                else => |err| return std.os.windows.unexpectedWSAError(err),
            }
        } else {
            return std.mem.sliceTo(name_buffer, 0);
        }
    } else {
        return std.posix.gethostname(name_buffer);
    }
}
