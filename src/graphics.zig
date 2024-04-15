const std = @import("std");

const c = @import("c.zig");
const asset = @import("asset.zig");
const global = @import("global.zig");

pub var framebuffer_main: c.RenderTexture = undefined;

pub fn init() void {
    framebuffer_main = c.LoadRenderTexture(global.window_width, global.window_height);
}

pub fn deinit() void {
    c.UnloadRenderTexture(framebuffer_main);
}
