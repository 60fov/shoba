const std = @import("std");
const asset = @import("asset.zig");
const net = @import("net.zig");
const input = @import("input.zig");
const game = @import("game.zig");

pub const Memory = struct {
    pub const asset_count = asset.getAssetCount();
    pub const pckt_queue_max = 256;
    pub const input_queue_max = 64;
    pub const scratch_size = 5 * 1024 * 1024;

    initialized: bool,
    scratch: [scratch_size]u8,
    scratch_allocator: std.heap.FixedBufferAllocator,

    asset_list: [asset_count]asset.Asset,

    pckt_queue: [pckt_queue_max]net.Packet,
    input_queue: [input_queue_max]input.Entry,

    state: struct {
        prev: game.State,
        next: game.State,
    },
};

pub fn init(memory: *Memory) void {
    memory.scratch_allocator = std.heap.FixedBufferAllocator.init(memory.scratch);
}
