const std = @import("std");
const builtin = @import("builtin");

pub const scratch_buffer_size = 5 * 1024 * 1024;
pub var scratch_buffer: []u8 = undefined;

const fba_buffer_size = 15 * 1024 * 1024;
var fba_buffer: []u8 = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
var fba_allocator: std.mem.Allocator = undefined;

var asset_dir: std.fs.Dir = undefined;

pub fn init(alloctr: std.mem.Allocator) !void {
    scratch_buffer = try alloctr.alloc(u8, scratch_buffer_size);

    fba_buffer = try alloctr.alloc(u8, fba_buffer_size);
    fba = std.heap.FixedBufferAllocator.init(fba_buffer);
    fba_allocator = fba.allocator();

    if (builtin.mode == .Debug) {
        asset_dir = try std.fs.cwd().openDir("assets", .{});
    } else {
        const exe_path = try std.fs.selfExeDirPathAlloc(fba_allocator);
        defer fba_allocator.free(exe_path);
        const asset_dir_path = try std.fs.path.join(fba_allocator, &.{ exe_path, "assets" });
        defer fba_allocator.free(asset_dir_path);
        asset_dir = try std.fs.openDirAbsolute(asset_dir_path, .{});
    }
}

pub fn deinit(alloctr: std.mem.Allocator) void {
    alloctr.free(fba_buffer);
    fba = undefined;
    fba_allocator = undefined;
}

pub fn allocator() std.mem.Allocator {
    return fba_allocator;
}

pub fn assetDir() std.fs.Dir {
    return asset_dir;
}
