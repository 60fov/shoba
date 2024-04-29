const std = @import("std");
const builtin = @import("builtin");

pub const dev_build = builtin.mode == .Debug;

pub const window_width = 800;
pub const window_height = 600;
pub const tick_rate = 64;
