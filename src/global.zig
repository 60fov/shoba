const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");

pub const dev_build = builtin.mode == .Debug;

pub const window_width = 800;
pub const window_height = 600;
pub const tick_rate = 64;

var asset_dir: std.fs.Dir = undefined;
var address_list: *std.net.AddressList = undefined;
pub var local_address: std.net.Address = undefined;

pub const mem = struct {
    pub const scratch_buffer_size = 5 * 1024 * 1024;
    pub var scratch_buffer: []u8 = undefined;

    const fba_buffer_size = 15 * 1024 * 1024;
    var fba_buffer: []u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = undefined;
    pub var fba_allocator: std.mem.Allocator = undefined;
};

pub fn init(alloctr: std.mem.Allocator) !void {
    mem.scratch_buffer = try alloctr.alloc(u8, mem.scratch_buffer_size);

    mem.fba_buffer = try alloctr.alloc(u8, mem.fba_buffer_size);
    mem.fba = std.heap.FixedBufferAllocator.init(mem.fba_buffer);
    mem.fba_allocator = mem.fba.allocator();

    if (builtin.mode == .Debug) {
        asset_dir = try std.fs.cwd().openDir("assets", .{});
    } else {
        const exe_path = try std.fs.selfExeDirPathAlloc(mem.fba_allocator);
        defer mem.fba_allocator.free(exe_path);
        const asset_dir_path = try std.fs.path.join(mem.fba_allocator, &.{ exe_path, "assets" });
        defer mem.fba_allocator.free(asset_dir_path);
        asset_dir = try std.fs.openDirAbsolute(asset_dir_path, .{});
    }

    // (WSAStartup)
    address_list = std.net.getAddressList(mem.fba_allocator, "localhost", 0) catch unreachable;
    address_list.deinit();

    const host_name = c.gethostname(mem.scratch_buffer[0..c.HOST_NAME_MAX]) catch unreachable;
    address_list = std.net.getAddressList(mem.fba_allocator, host_name, 0) catch unreachable;

    local_address = getaddr: {
        for (address_list.addrs) |addr| {
            // std.debug.print("addr{}: {}\n", .{ i, addr });
            if (addr.any.family == std.posix.AF.INET) {
                break :getaddr addr;
            }
        }
        unreachable;
    };
}

pub fn deinit(alloctr: std.mem.Allocator) void {
    address_list.deinit();
    alloctr.free(mem.fba_buffer);
    mem.fba = undefined;
    mem.fba_allocator = undefined;
}

pub fn assetDir() std.fs.Dir {
    return asset_dir;
}
