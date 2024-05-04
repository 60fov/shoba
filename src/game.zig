const std = @import("std");

const c = @import("c.zig");
const asset = @import("asset.zig");
const input = @import("input.zig");
const global = @import("global.zig");
const event = @import("event.zig");
const net = @import("net.zig");
const ds = @import("ds.zig");

const Model = asset.Model;
const ModelAnimation = asset.ModelAnimation;
const AssetId = asset.AssetId;
const ModelAnimationState = asset.ModelAnimationState;

pub const max_player_count = 32;

pub const World = struct {
    ground: Model = undefined,
};

pub const State = struct {
    time: f32 = 0,

    world: World = .{},
    camera: Camera = undefined,

    entities: [Entity.max]Entity = [_]Entity{.{}} ** Entity.max,
    main_entity_id: EntityId = 0,

    pub fn init() State {
        var state = State{
            .camera = Camera{
                .target = 0,
            },
            .world = .{
                .ground = asset.getByName("dev_ground").model,
            },
        };
        const player = &state.entities[0];
        player.tag = .{
            .render_flag = .model,
            .animated = true,
        };
        player.model = asset.getByName("daniel").model;
        player.animation = asset.getByName("idle_anim").model_animation;
        player.anim_state = .{};
        return state;
    }

    pub fn lerp(a: *const State, b: *const State, alpha: f32) State {
        var state = b.*;

        state.time = std.math.lerp(a.time, b.time, alpha);
        state.camera.angle = std.math.lerp(a.camera.angle, b.camera.angle, alpha);
        state.camera.distance = std.math.lerp(a.camera.distance, b.camera.distance, alpha);

        for (0..Entity.max) |i| {
            const ent = &state.entities[i];
            const ent_a = a.entities[i];
            const ent_b = b.entities[i];
            ent.pos.x = std.math.lerp(ent_a.pos.x, ent_b.pos.x, alpha);
            ent.pos.y = std.math.lerp(ent_b.pos.y, ent_b.pos.y, alpha);
        }

        return state;
    }

    pub fn playerEntities(state: *State) []Entity {
        // TODO not surewhere to put this, connected to max connections
        return state.entities[0..max_player_count];
    }
};

pub fn createPlayer() Entity {
    return Entity{
        .tag = .{
            .render_flag = .model,
            .animated = true,
        },
        .model = asset.getByName("daniel").model,
        .animation = asset.getByName("idle_anim").model_animation,
        .anim_state = .{},
    };
}

pub fn applyInputsToEntity(ent: *Entity, input_queue: []event.Event) void {
    var move_dir: c.Vector2 = .{};
    var look_angle = ent.angle;

    for (input_queue) |evt| {
        // std.debug.print("event {}\n", .{evt});
        switch (evt) {
            .input_move => |move| {
                const angle = std.math.pi * 2 * move.direction;
                move_dir = c.Vector2Add(move_dir, c.Vector2{
                    .x = std.math.cos(angle),
                    .y = std.math.sin(angle),
                });
            },
            .input_look => |look| {
                look_angle = look.direction;
            },
            else => {},
        }
    }

    move_dir = c.Vector2Normalize(move_dir);
    const vel = c.Vector2Scale(move_dir, 10);
    ent.vel = vel;
    ent.angle = look_angle;
}

pub fn updateEntityPositions(state: *State, dt: f32) void {
    for (&state.entities) |*ent| {
        const pos = &ent.pos;
        const vel = ent.vel;
        const delta_pos = c.Vector2Scale(vel, dt);
        pos.* = c.Vector2Add(pos.*, delta_pos);
    }
}

pub fn animateModels(state: *State) void {
    for (&state.entities) |*ent| {
        if (ent.tag.animated) {
            ent.anim_state.animateModel(&ent.model, &ent.animation);
        }
    }
}

pub fn draw(state: *const State) void {
    const rl_cam = getRaylibCamera(state);
    c.BeginMode3D(rl_cam);
    {
        // draw world
        // const ground = asset.getById(state.ground).model;
        c.DrawModel(state.world.ground.rl_model, c.Vector3Zero(), 1, c.WHITE);

        // draw entities
        for (state.entities) |ent| {
            const pos3 = c.Vector3{ .x = ent.pos.x, .y = 0.01, .z = ent.pos.y };
            switch (ent.tag.render_flag) {
                .model => {
                    const model = ent.model;
                    const angle = ent.angle;
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

        const wmp = getWorldMousePos(state);
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
    const target_entity = &state.entities[state.camera.target];

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

    exists: bool = false,
    // TODO why???
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
