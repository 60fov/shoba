const std = @import("std");
const global = @import("global.zig");

pub const event_max = 100;
pub const EventList = std.ArrayList(Event);

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
