const std = @import("std");

const c = @import("c.zig");
const asset = @import("asset.zig");
const input = @import("input.zig");
const entity = @import("entity.zig");
const ability = @import("ability.zig");

const Asset = asset.Asset;
const Entity = entity.Entity;
const Ability = ability.Ability;

pub const Game = struct {
    pub const World = struct {
        ground: c.Model,

        pub fn load() World {
            return World{
                .ground = asset.get("dev_ground").model,
            };
        }
    };

    pub const State = struct {
        time: f32 = 0,

        cam: c.Camera3D = .{
            .fovy = 45.0,
            .up = .{ .y = 1 },
            .target = .{ .y = 1 },
            .position = .{ .y = 20, .z = 20 },
            .projection = c.CAMERA_PERSPECTIVE,
        },

        world: Game.World = undefined,

        ent_soa: Entity.SoA = .{},
    };

    state: struct {
        prev: State = .{},
        next: State = .{},
    } = .{},

    pub fn update(game: *Game, ns: i128) void {
        const dt: f32 = @as(f32, @floatFromInt(ns)) / 1e+9;

        game.state.prev = game.state.next;
        var state = &game.state.next;

        state.time += dt;

        // user input
        {
            const up = c.Vector2{ .y = -1 };
            const down = c.Vector2{ .y = 1 };
            const left = c.Vector2{ .x = -1 };
            const right = c.Vector2{ .x = 1 };
            for (0..Entity.count) |ndx| {
                const ent = state.ent_soa.get(ndx);
                if (ent.tag.controlled) {
                    var dir: c.Vector2 = .{};
                    if (input.key(c.KEY_E).isDown()) dir = c.Vector2Add(dir, up);
                    if (input.key(c.KEY_S).isDown()) dir = c.Vector2Add(dir, left);
                    if (input.key(c.KEY_LEFT_ALT).isDown()) dir = c.Vector2Add(dir, down);
                    if (input.key(c.KEY_F).isDown()) dir = c.Vector2Add(dir, right);
                    dir = c.Vector2Normalize(dir);
                    const vel = c.Vector2Scale(dir, 10);
                    state.ent_soa.velocity[ndx] = vel;
                }
            }
        }

        // logic
        {
            for (0..Entity.count) |ndx| {
                var ent = state.ent_soa.get(ndx);
                const id: Entity.Id = @intCast(ndx);

                switch (ent.data) {
                    .projectile => {
                        const projectile = ent.data.projectile;

                        for (state.ent_soa.items(.col_mask), 0..) |col_mask, i| {
                            if (col_mask & ent.col_mask) {
                                var ent_other = state.ent_soa.get(i);
                                const col = c.CheckCollisionSpheres(ent_other.position, 1, ent.position, projectile.radius);
                                if (col) {
                                    ent.tag.exists = false;
                                    // Event.applyEffects(i, projectile.effects);
                                    if(@as(Entity.DataTag, ent_other.data) == Entity.DataTag.player) {
                                        ent_other.data.
                                    }
                                }
                            }
                        }

                        const time_alive = state.time - projectile.spawn_time;
                        if (time_alive >= projectile.duration) {
                            ent.tag.exists = false;
                            state.ent_soa.set(ndx, ent);
                        }
                    },
                    .player => {
                        if (input.mbutton(c.MOUSE_BUTTON_LEFT).isJustDown()) {
                            const basic = &state.ent_soa.data[ndx].player.basic;
                            Ability.invoke(basic, id, state);
                        }

                        if (input.key(c.KEY_SPACE).isJustDown()) {
                            const mobility = &state.ent_soa.data[ndx].player.mobility;
                            Ability.invoke(mobility, id, state);
                        }
                    },
                    else => {},
                }
            }
        }

        // move
        {
            for (0..Entity.count) |ndx| {
                var vel = state.ent_soa.velocity[ndx];
                vel = c.Vector2Scale(vel, dt);

                const pos = state.ent_soa.position[ndx];
                state.ent_soa.position[ndx] = c.Vector2Add(pos, vel);
            }
        }
    }

    pub fn draw(game: *const Game, alpha: f32) void {
        var state = game.state.next;

        // interp
        {
            const prev = &game.state.prev;
            const next = &game.state.next;
            for (0..Entity.count) |ndx| {
                const pos = c.Vector2{
                    .x = std.math.lerp(prev.ent_soa.position[ndx].x, next.ent_soa.position[ndx].x, alpha),
                    .y = std.math.lerp(prev.ent_soa.position[ndx].y, next.ent_soa.position[ndx].y, alpha),
                };
                state.ent_soa.position[ndx] = pos;
            }
        }

        c.ClearBackground(c.LIGHTGRAY);

        c.BeginMode3D(state.cam);
        {
            c.DrawGrid(100, 1.0);
            // c.DrawMesh(plane, def_mat, c.MatrixIdentity());

            // unit axis
            c.DrawLine3D(.{}, .{ .x = 1 }, c.RED);
            c.DrawLine3D(.{}, .{ .y = 1 }, c.GREEN);
            c.DrawLine3D(.{}, .{ .z = 1 }, c.BLUE);

            for (0..Entity.count) |ndx| {
                const tag = state.ent_soa.tag[ndx];
                const pos = state.ent_soa.position[ndx];
                if (!tag.exists) continue;
                switch (state.ent_soa.data[ndx]) {
                    .projectile => {
                        // const proj = state.ent_soa.data[ndx].projectile;
                        const color = c.RED;
                        const pos3 = c.Vector3{ .x = pos.x, .y = 1, .z = pos.y };
                        c.DrawSphere(pos3, 0.1, color);
                    },
                    .player => {
                        const pos3 = c.Vector3{ .x = pos.x, .y = 1, .z = pos.y };
                        const pos3_ground = c.Vector3{ .x = pos.x, .y = 0, .z = pos.y };

                        const ray = c.GetScreenToWorldRay(input.mouse.pos, game.state.next.cam);
                        const col = c.GetRayCollisionMesh(ray, state.world.ground.meshes[0], c.MatrixIdentity());
                        c.DrawCircle3D(col.point, 1, c.Vector3{ .x = 1, .y = 0, .z = 0 }, 90, c.DARKGREEN);

                        c.DrawCircle3D(c.Vector3{ .x = pos.x, .y = 0, .z = pos.y }, 1, c.Vector3{ .x = 1, .y = 0, .z = 0 }, 90, c.RED);
                        c.DrawLine3D(pos3_ground, col.point, c.WHITE);
                        c.DrawSphere(pos3, 1, c.BLUE);
                    },
                    else => {
                        const color = c.GRAY;
                        const pos3 = c.Vector3{ .x = pos.x, .y = 1, .z = pos.y };
                        c.DrawCircle3D(c.Vector3{ .x = pos.x, .y = 0, .z = pos.y }, 1, c.Vector3{ .x = 1, .y = 0, .z = 0 }, 90, c.RED);
                        c.DrawSphere(pos3, 1, color);
                    },
                }
            }
        }
        c.EndMode3D();
    }
};
