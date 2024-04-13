const std = @import("std");

const c = @import("c.zig");
const global = @import("global.zig");

const AssetHashMap = std.StringArrayHashMap(Asset);
var asset_table: AssetHashMap = undefined;

/// doesn't free over-written assets
pub fn load(kind: Asset.Kind, name: []const u8, options: Asset.LoadOptions) !void {
    const asset = switch (kind) {
        .model => Asset{
            .model = options.model,
        },
        .framebuffer => Asset{
            .framebuffer = c.LoadRenderTexture(options.framebuffer.width, options.framebuffer.height),
        },
    };
    try asset_table.put(name, asset);
}

/// TODO
pub fn unload() void {}

pub fn get(name: []const u8) Asset {
    return asset_table.get(name).?;
}

pub fn init() void {
    asset_table = AssetHashMap.init(global.allocator());
}

pub fn deinit() void {
    asset_table.deinit();
}

pub const Asset = union(Kind) {
    pub const Kind = enum {
        model,
        framebuffer,
    };

    pub const LoadOptions = union(Kind) {
        model: c.Model,
        framebuffer: struct {
            width: i32,
            height: i32,
        },
    };

    model: c.Model,
    framebuffer: c.RenderTexture,
};
