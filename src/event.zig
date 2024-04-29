const std = @import("std");
const global = @import("global.zig");
const ds = @import("ds.zig");

pub const event_max = 64;
pub const EventList = ds.List(Event, event_max, .{ .empty = {} });

pub const EventTag = enum {
    empty,
    input_move,
    input_look,
    input_ability,
};

pub const Event = union(EventTag) {
    empty: void,
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
