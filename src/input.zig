const c = @import("c.zig");

// consider moving out of keyboard and switching to InputState
pub const KeyState = packed struct(u2) {
    down: bool = false,
    just: bool = false,

    pub fn isJustDown(self: *const KeyState) bool {
        return self.just and self.down;
    }

    pub fn isJustUp(self: *const KeyState) bool {
        return self.just and self.down;
    }

    pub fn isUp(self: *const KeyState) bool {
        return !self.down;
    }

    pub fn isDown(self: *const KeyState) bool {
        return self.down;
    }
};

pub const mouse = struct {
    const btn_count = 7;
    pub var pos: c.Vector2 = .{};
    var btn = [_]KeyState{.{}} ** btn_count;
};

const key_count = 349;
var keys = [_]KeyState{.{}} ** key_count;

pub fn key(keycode: c.KeyboardKey) KeyState {
    return keys[@intCast(keycode)];
}

pub fn mbutton(btncode: c.MouseButton) KeyState {
    return mouse.btn[@intCast(btncode)];
}

pub fn poll() void {
    // TODO consider moving to main loop
    c.PollInputEvents();

    mouse.pos = c.GetMousePosition();

    for (&keys, 0..) |*key_state, i| {
        const key_down = c.IsKeyDown(@intCast(i));
        key_state.just = key_down != key_state.down;
        key_state.down = key_down;
    }

    for (&mouse.btn, 0..) |*btn_state, i| {
        const btn_down = c.IsMouseButtonDown(@intCast(i));
        btn_state.just = btn_down != btn_state.down;
        btn_state.down = btn_down;
    }
}
