const std = @import("std");
const global = @import("global.zig");

const event_max = 100;
pub var queue: [event_max]Event = undefined;

pub fn init() void {
    std.debug.print("event size {}\n", @sizeOf(Event));
    std.debug.print("event queue size {}\n", @sizeOf(@TypeOf(queue)));
    queue = global.mem.fba_allocator.alloc(Event, event_max) catch unreachable;
}

pub fn deinit() void {
    global.mem.fba_allocator.free(queue);
}

pub fn push(evt: Event) void {
    _ = evt;
}

pub const EventTag = enum {
    input_move,
    input_look,
    input_ability,
};

pub const Event = union(EventTag) {
    input_move: InputMoveEvent,
    input_look: InputLookEvent,
    input_ability: InputAbilityEvent,
};

pub const InputMoveEvent = struct {
    direction: f32, // [0-1)
};

pub const InputLookEvent = struct {
    direction: f32, // [0-1)
};

pub const InputAbilityEvent = struct {
    pub const AbilitySlot = enum {
        basic,
        offsensive,
        defensive,
        mobility,
    };
    slot: AbilitySlot, // [0-1)
};
