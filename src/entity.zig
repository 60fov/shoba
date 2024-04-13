const std = @import("std");
const c = @import("c.zig");
const global = @import("global.zig");
const ability = @import("ability.zig");

const Ability = ability.Ability;

pub const Entity = struct {
    pub const count = 100;

    pub const Id = u16;

    pub const Tag = packed struct(u16) {
        exists: bool = false,
        controlled: bool = false,
        _padding: u14 = 0,
    };

    pub const Kind = enum {
        empty,
        player,
        projectile,
    };

    pub const Projectile = struct {
        spawn_time: f32,
        duration: f32,
    };

    pub const Player = struct {
        basic: Ability,
        offensive: Ability,
        defensive: Ability,
        mobility: Ability,
        ultra: Ability,
    };

    pub const Data = union(Kind) {
        empty: void,
        player: Player,
        projectile: Projectile,
    };

    pub const SoA = struct {
        tag: [count]Tag = [_]Tag{.{}} ** count,
        position: [count]c.Vector2 = [_]c.Vector2{.{}} ** count,
        velocity: [count]c.Vector2 = [_]c.Vector2{.{}} ** count,
        data: [count]Data = [_]Data{.{ .empty = {} }} ** count,

        pub fn set(soa: *SoA, ndx: usize, entity: Entity) void {
            soa.tag[ndx] = entity.tag;
            soa.position[ndx] = entity.position;
            soa.velocity[ndx] = entity.velocity;
            soa.data[ndx] = entity.data;
        }

        pub fn get(soa: *const SoA, ndx: usize) Entity {
            return Entity{
                .tag = soa.tag[ndx],
                .position = soa.position[ndx],
                .velocity = soa.velocity[ndx],
                .data = soa.data[ndx],
            };
        }

        pub fn push(soa: *SoA, entity: Entity) void {
            for (soa.tag, 0..) |tag, i| {
                if (tag.exists == false) {
                    soa.set(i, entity);
                    return;
                }
            }
            std.debug.print("entity list full cannot push\n", .{});
            unreachable;
        }
    };

    tag: Tag = .{ .exists = true },
    position: c.Vector2 = .{},
    velocity: c.Vector2 = .{},
    data: Entity.Data = .{ .empty = {} },
};

// pub const Ability = struct {
//     const Id = u8;

//     const Info = struct {
//         name: []const u8,
//         desc: []const u8,
//     };

//     const Kind = enum {
//         proj,
//         dash,
//         // leap,
//         // stun,
//         // buff,
//     };

//     const Data = union(Ability.Kind) {
//         proj: Ability.Projectile,
//         dash: Ability.Dash,
//         // leap: Leap,
//         // stun: Stun,
//         // buff: Buff,
//     };

//     const Projectile = struct {
//         speed: f32,
//         power: u32,
//         duration: f32,
//     };

//     const Dash = struct {
//         impulse: f32,
//     };

//     var data_table: std.AutoHashMap(Ability.Id, Ability.Data) = undefined;
//     var info_table: std.AutoHashMap(Ability.Id, Ability.Info) = undefined;

//     // kind: Ability.Kind,
//     owner: Entity.Id,
//     cooldown: f32 = 0,
//     channel_dur: f32 = 0,
//     data: Ability.Data,

//     pub fn init() void {
//         data_table = std.AutoHashMap(Ability.Id, Ability.Data).init(global.allocator());
//         info_table = std.AutoHashMap(Ability.Id, Ability.Info).init(global.allocator());

//         const fireball_id = 1;
//         const fireball_data = .{ .proj = .{
//             .speed = 10,
//             .power = 10,
//             .duration = 1,
//         } };
//         const fireball_info = .{
//             .name = "fireball",
//             .desc = "a flaming ball of fire",
//         };

//         data_table.put(fireball_id, fireball_data) catch unreachable;
//         info_table.put(fireball_id, fireball_info) catch unreachable;

//         const dash_id = 2;
//         const dash_data = .{ .dash = .{
//             .impulse = 10,
//         } };

//         const dash_info = .{
//             .name = "dash",
//             .desc = "move quickly in the direction you're moving",
//         };

//         data_table.put(dash_id, dash_data) catch unreachable;
//         info_table.put(dash_id, dash_info) catch unreachable;
//     }

//     pub fn deinit() void {
//         data_table.deinit();
//         info_table.deinit();
//     }

//     pub fn new(id: Ability.Id, owner: Entity.Id) Ability {
//         const ability_data = data_table.get(id).?;
//         return Ability{
//             .owner = owner,
//             .data = ability_data,
//         };
//     }

//     pub fn getId(name: []const u8) Ability.Id {
//         var iter = info_table.iterator();
//         while (iter.next()) |entry| {
//             const id = entry.key_ptr.*;
//             const ability_name = entry.value_ptr.*.name;
//             if (std.mem.eql(u8, name, ability_name)) return id;
//         }
//         std.debug.print("ability not found, name: {s}\n", .{name});
//         unreachable;
//     }
// };
