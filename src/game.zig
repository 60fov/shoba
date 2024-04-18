const std = @import("std");

const c = @import("c.zig");
const asset = @import("asset.zig");
const input = @import("input.zig");
const global = @import("global.zig");

const Model = asset.Model;
const ModelAnimation = asset.ModelAnimation;
const AssetId = asset.AssetId;
const ModelAnimationState = asset.ModelAnimationState;

pub const State = struct {
    ground: AssetId = undefined,
    camera: Camera = undefined,

    time: f32 = 0,
    entities: EntitySoA = undefined,
    main_entity_id: EntityId = 0,

    pub fn init() State {
        var entities = EntitySoA{};
        entities.setCapacity(global.mem.fba_allocator, Entity.max) catch unreachable;
        entities.appendAssumeCapacity(Entity{ .tag = .{ .render_flag = .ball } }); // 0
        entities.appendAssumeCapacity(Entity{
            .tag = .{
                .render_flag = .model,
                .animated = true,
            },
            .model = asset.getByName("daniel").model,
            .animation = asset.getByName("daniel_animation").model_animation,
        }); // 1

        return State{
            .ground = asset.getId("dev_ground"),
            .camera = Camera{ .target = 1 },
            .entities = entities,
            .main_entity_id = 1,
        };
    }

    pub fn lerp(a: *const State, b: *const State, alpha: f32) State {
        var state = b.*;

        state.time = std.math.lerp(a.time, b.time, alpha);
        state.camera.angle = std.math.lerp(a.camera.angle, b.camera.angle, alpha);
        state.camera.distance = std.math.lerp(a.camera.distance, b.camera.distance, alpha);

        const pos = state.entities.items(.pos);
        for (a.entities.items(.pos), b.entities.items(.pos), 0..) |a_pos, b_pos, i| {
            pos[i].x = std.math.lerp(a_pos.x, b_pos.x, alpha);
            pos[i].y = std.math.lerp(a_pos.y, b_pos.y, alpha);
        }

        return state;
    }
};

pub fn update(state: *State, ns: i128) void {
    const dt: f32 = @as(f32, @floatFromInt(ns)) / 1e+9;
    state.time += dt;

    // logic
    {
        const up = c.Vector2{ .y = -1 };
        const down = c.Vector2{ .y = 1 };
        const left = c.Vector2{ .x = -1 };
        const right = c.Vector2{ .x = 1 };
        var ent = state.entities.get(state.main_entity_id);
        var dir: c.Vector2 = .{};
        if (input.key(c.KEY_E).isDown()) dir = c.Vector2Add(dir, up);
        if (input.key(c.KEY_S).isDown()) dir = c.Vector2Add(dir, left);
        if (input.key(c.KEY_LEFT_ALT).isDown()) dir = c.Vector2Add(dir, down);
        if (input.key(c.KEY_F).isDown()) dir = c.Vector2Add(dir, right);
        dir = c.Vector2Normalize(dir);
        const vel = c.Vector2Scale(dir, 10);
        ent.vel = vel;
        state.entities.set(state.main_entity_id, ent);
    }

    // move
    {
        for (state.entities.items(.pos), state.entities.items(.vel)) |*pos, vel| {
            const delta_pos = c.Vector2Scale(vel, dt);
            pos.* = c.Vector2Add(pos.*, delta_pos);
        }
    }

    // animate models
    {
        var slice = state.entities.slice();
        for (0..slice.len) |ent_id| {
            var ent = slice.get(ent_id);
            if (ent.tag.animated) {
                ent.anim_state.animateModel(&ent.model, &ent.animation);
            }

            const dir = c.Vector2Subtract(ent.pos, getWorldMousePos(state));
            ent.angle = std.math.atan2(-dir.y, dir.x) / (std.math.pi * 2);

            slice.set(ent_id, ent);
        }
    }
}

pub fn draw(prev_state: *const State, next_state: *const State, alpha: f32) void {
    const state = State.lerp(prev_state, next_state, alpha);

    const rl_cam = getRaylibCamera(&state);
    c.BeginMode3D(rl_cam);
    {
        const ground = asset.getById(state.ground).model;
        c.DrawModel(ground.rl_model, c.Vector3Zero(), 1, c.WHITE);
        const entity_slice = state.entities.slice();
        for (0..entity_slice.len) |ent_id| {
            const entity = entity_slice.get(ent_id);
            const pos3 = c.Vector3{ .x = entity.pos.x, .y = 0.01, .z = entity.pos.y };
            switch (entity.tag.render_flag) {
                .model => {
                    const model = entity.model;
                    const angle = entity.angle;
                    const rot_axis = c.Vector3{ .y = 1 };
                    const scale = c.Vector3Scale(c.Vector3One(), 0.04);
                    c.DrawCircle3D(pos3, 1, c.Vector3{ .x = 1 }, 90, c.BLUE);
                    c.DrawModelEx(model.rl_model, pos3, rot_axis, (angle - 0.25) * 360, scale, c.WHITE);
                },
                .ball => {
                    c.DrawSphere(pos3, 0.1, c.GRAY);
                },
                else => {},
            }
        }

        const wmp = getWorldMousePos(&state);
        const cursor_pos = c.Vector3{ .x = wmp.x, .y = 0.01, .z = wmp.y };
        c.DrawCircle3D(cursor_pos, 1, c.Vector3{ .x = 1 }, 90, c.GOLD);
    }
    c.EndMode3D();
}

pub const Camera = struct {
    const min_angle = std.math.pi / 4.0;
    const max_angle = std.math.pi / 2.0 - 0.01;
    const min_dist = 10;
    const max_dist = 100;

    target: EntityId = 0,
    angle: f32 = 0.25, // [0, 1]
    distance: f32 = 0.2, // [0, 1]
};

pub fn getRaylibCamera(state: *const State) c.Camera3D {
    const target_entity = state.entities.get(state.camera.target);

    const theta = std.math.lerp(Camera.min_angle, Camera.max_angle, state.camera.angle);
    const hyp = std.math.lerp(Camera.min_dist, Camera.max_dist, state.camera.distance);
    const z_off = std.math.cos(theta) * hyp;
    const height = std.math.sin(theta) * hyp;
    const x = target_entity.pos.x;
    const y = height;
    const z = target_entity.pos.y + z_off;

    return c.Camera3D{
        .fovy = 45,
        .position = .{ .x = x, .y = y, .z = z },
        .target = .{
            .x = x,
            .y = 0,
            .z = target_entity.pos.y,
        },
        .up = .{ .y = 1 },
        .projection = c.CAMERA_PERSPECTIVE,
    };
}

pub fn getWorldMousePos(state: *const State) c.Vector2 {
    const ray = c.GetScreenToWorldRay(input.mouse.pos, getRaylibCamera(state));
    const col = c.GetRayCollisionBox(ray, c.BoundingBox{ .min = .{ .x = -1000, .y = 0, .z = -1000 }, .max = .{ .x = 1000, .y = 0, .z = 1000 } });
    return c.Vector2{ .x = col.point.x, .y = col.point.z };
}

pub const Entity = struct {
    const max = 1000;

    tag: EntityTag = .{},

    pos: c.Vector2 = .{},
    vel: c.Vector2 = .{},

    model: Model = .{},
    animation: ModelAnimation = .{},
    anim_state: ModelAnimationState = .{},
    angle: f32 = 0, // [0, 1]
};

pub const EntityId = u32;
pub const EntitySoA = std.MultiArrayList(Entity);
pub const EntityTag = struct {
    render_flag: RenderFlag = .none,
    animated: bool = false,
};

pub const RenderFlag = enum(u4) {
    none,
    ball,
    model,
};

// pub const RenderFlag = packed struct(u4) {
//     none: bool = true,
//     model: bool = false,
//     animated_model: bool = false,
//     shape: bool = false,
// };
