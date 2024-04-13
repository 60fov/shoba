const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const global = @import("global.zig");
const entity = @import("entity.zig");
const game = @import("game.zig");
const input = @import("input.zig");

const Game = game.Game;
const Entity = entity.Entity;

var info_table: std.AutoHashMap(Ability.Id, Ability.Info) = undefined;

const a = [_]struct { a: Ability }{ 1, .{ .a = 1 } };

pub fn init() void {
    if (global.dev_build) {
        info_table = std.AutoHashMap(Ability.Id, Ability.Info).init(global.allocator());
    }

    // TODO dynamic loading of abilities
    // const libname = switch (builtin.os.tag) {
    //     .linux, .freebsd, .openbsd => "ability_so.so",
    //     .windows => "ability_dll.dll",
    //     .macos => "ability_dylib.dylib",
    //     else => return error.UnsupportedPlatform,
    // };
    // const lib = try std.DynLib.open(libname);
    // defer lib.close();

    for (abilities, 0..) |ability, id| {
        register(@intCast(id), ability) catch unreachable;
    }
}

pub fn deinit() void {
    for (abilities, 0..) |_, id| {
        unregister(@intCast(id));
    }

    info_table.deinit();
}

pub fn register(id: Ability.Id, info: Ability.Info) !void {
    try info_table.put(id, info);
}

pub fn unregister(id: Ability.Id) void {
    info_table.remove(id);
}

pub fn getId(name: []const u8) Ability.Id {
    var iter = info_table.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, name, entry.value_ptr.*.name)) return entry.key_ptr.*;
    }
    std.debug.print("unable to find ability named: {s}\n", .{name});
    unreachable;
}

pub const Ability = struct {
    pub const Id = u32;

    pub const Info = struct {
        name: []const u8,
        desc: []const u8,
        timings: Ability.Timings,
        invoke_fn: Ability.InvokeFn,
    };

    pub const Timings = struct {
        cast: f32 = 0,
        channel: f32 = 0,
        cooldown: f32 = 0,
    };

    pub const InvokeFn = *const fn (ability: *Ability, caster: Entity.Id, state: *Game.State) void;

    id: Ability.Id,
    info: Ability.Info,
    timer: Ability.Timings,
    invoke_fn: InvokeFn = undefined,
    // state: *opaque = {},

    pub fn create(id: Ability.Id) Ability {
        const info = info_table.get(id).?;
        return Ability{
            .id = id,
            .info = info,
            .timer = Ability.Timings{},
            .invoke_fn = if (global.dev_build) undefined else info.get(id).?.invoke_fn,
        };
    }

    pub fn createFromName(name: []const u8) Ability {
        return create(getId(name));
    }

    pub fn invoke(self: *Ability, caster: Entity.Id, state: *Game.State) void {
        if (global.dev_build) {
            const invoke_fn = info_table.get(self.id).?.invoke_fn;
            invoke_fn(self, caster, state);
        } else {
            self.invoke_fn(caster, state);
        }
    }
};

pub const Effect = union(Effect.Kind) {
    pub const Kind = enum {
        dot,
        buff,
    };

    dot: DoT,

    pub const DoT = struct {
        count: u32,
        freq: f32,
    };
};

const abilities = [_]Ability.Info{
    .{
        .name = "fireball",
        .desc = "a flaming projectile",
        .timings = .{
            .cast = 1,
            .channel = 0.5,
            .cooldown = 2,
        },
        .invoke_fn = invoke_fireball,
    },
    .{
        .name = "dash",
        .desc = "move in a direction quickly",
        .timings = .{
            .cast = 0,
            .channel = 0,
            .cooldown = 5,
        },
        .invoke_fn = invoke_dash,
    },
};

fn invoke_fireball(ability: *Ability, caster_id: Entity.Id, state: *Game.State) void {
    const duration = 1;
    const speed = 10;

    const dot = .DoT{
        .freq = 3,
        .count = 3,
    };

    ability.timer.cooldown = ability.info.timings.cooldown;

    const caster = state.ent_soa.get(caster_id);
    const ray = c.GetScreenToWorldRay(input.mouse.pos, state.cam);
    const col = c.GetRayCollisionMesh(ray, state.world.ground.meshes[0], c.MatrixIdentity());
    const dir = c.Vector2Subtract(c.Vector2{ .x = col.point.x, .y = col.point.z }, caster.position);
    const dir_n = c.Vector2Normalize(dir);

    const e = Entity{
        .position = c.Vector2Add(caster.position, dir_n),
        .velocity = c.Vector2Scale(dir_n, speed),
        .tag = .{
            .exists = true,
        },
        .data = .{ .projectile = .{
            .spawn_time = state.time,
            .duration = duration,
            .effects = .{
                .{ .dot = dot },
            },
        } },
    };
    // std.debug.print("spawn fireball {}\n", .{ability});
    state.ent_soa.push(e);
}

fn invoke_dash(ability: *Ability, caster_id: Entity.Id, state: *Game.State) void {
    _ = ability;
    _ = caster_id;
    _ = state;

    // apply dash effect on caster
}
