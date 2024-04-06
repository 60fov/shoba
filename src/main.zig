const std = @import("std");
const c = @import("c.zig");
const global = @import("global.zig");

const width = 800;
const height = 600;
const tick_rate = 64;

pub fn main() void {
    const allocator = std.heap.c_allocator;
    global.init(allocator) catch unreachable;
    defer global.deinit(allocator);

    c.InitWindow(width, height, "zig-raylib");
    defer c.CloseWindow();

    c.SetExitKey(c.KEY_NULL);

    // c.SetTargetFPS(165);

    Asset.init();
    defer Asset.deinit();
    Asset.load(.framebuffer, "game", .{ .framebuffer = .{ .width = width, .height = height } }) catch unreachable;

    rng.init();
    ui.init();

    const ns = std.time.ns_per_s / tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;
    var alpha: f32 = 0;

    const game = global.allocator().create(Game) catch unreachable;
    defer global.allocator().destroy(game);
    game.* = Game{};

    // temp init game
    {
        const state = &game.state.next;
        state.entity.set(0, Game.Entity.newPlayer());

        for (1..11) |ndx| {
            const e = Game.Entity{
                .tag = .{ .exists = true },
                .position = rng.position(),
                .velocity = .{},
            };
            state.entity.set(ndx, e);
        }
    }

    const fb = Asset.get("game").framebuffer;

    while (!c.WindowShouldClose()) {
        c.PollInputEvents();

        // game time step
        {
            const now = std.time.nanoTimestamp();
            delta = now - last;
            last = now;

            FPS.pushDelta(delta);

            accumulator += delta;
            if (accumulator > max_accum) {
                const lost_ns = accumulator - max_accum;
                const lost_ms = lost_ns * 1000 * 1000;
                const lost_frames = @divTrunc(lost_ns, ns);
                accumulator = max_accum;

                std.debug.print("lost {d} frames (~{d:.0}ms)\n", .{ lost_frames, lost_ms });
            }

            while (accumulator >= ns) {
                game.update(ns);
                accumulator -= ns;
            }
        }

        // TODO frame limiter
        {
            c.BeginTextureMode(fb);
            {
                c.ClearBackground(c.BLUE);
                alpha = @as(f32, @floatFromInt(accumulator)) / ns;
                game.draw(alpha);
                // ui.draw();
            }
            c.EndTextureMode();

            // final draw
            c.BeginDrawing();
            {
                c.ClearBackground(c.BLACK);

                const src = c.Rectangle{ .width = width, .height = -height };
                const dst = c.Rectangle{ .width = width, .height = height };
                c.DrawTexturePro(fb.texture, src, dst, .{}, 0, c.WHITE);

                // c.DrawFPS(10, 10);
                ui.drawDev(game);
                FPS.draw(10, 10);
            }
            c.EndDrawing();
        }

        c.SwapScreenBuffer();
    }
}

pub const Game = struct {
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
            ability,
            player,
        };

        pub const Data = union(Kind) {
            pub const Ability = enum {
                fireball,
                dash,
                portal,
            };

            pub const Player = struct {
                basic1: Ability,
                basic2: Ability,
                attack: Ability,
                defensive: Ability,
                ultra: Ability,
            };

            empty: void,
            ability: Ability,
            player: Player,
        };

        pub const SoA = struct {
            tag: [count]Tag = [_]Tag{.{}} ** count,
            position: [count]c.Vector2 = [_]c.Vector2{.{}} ** count,
            velocity: [count]c.Vector2 = [_]c.Vector2{.{}} ** count,
            data: [count]Data = [_]Data{.{ .empty = {} }} ** count,

            fn set(soa: *SoA, ndx: usize, entity: Entity) void {
                soa.tag[ndx] = entity.tag;
                soa.position[ndx] = entity.position;
                soa.velocity[ndx] = entity.velocity;
                soa.data[ndx] = entity.data;
            }

            fn get(soa: *const SoA, ndx: usize) Entity {
                return Entity{
                    .tag = soa.tag[ndx],
                    .position = soa.position[ndx],
                    .velocity = soa.velocity[ndx],
                    .data = soa.data[ndx],
                };
            }
        };

        tag: Tag = .{ .exists = true },
        position: c.Vector2 = .{},
        velocity: c.Vector2 = .{},
        data: Entity.Data = .{ .empty = {} },

        fn newDevBall(pos: c.Vector2) Entity {
            return Entity{
                .tag = .{
                    .exists = true,
                },
                .position = pos,
                .velocity = .{},
            };
        }

        fn newPlayer() Entity {
            return Entity{
                .tag = .{
                    .exists = true,
                    .controlled = true,
                },
                .position = .{},
                .data = .{ .player = .{
                    .basic1 = .fireball,
                    .basic2 = .fireball,
                    .attack = .fireball,
                    .defensive = .fireball,
                    .ultra = .fireball,
                } },
            };
        }

        fn newAbility(ability: Game.Entity.Data.Ability, owner: Entity) Entity {
            switch (ability) {
                .fireball => {
                    // TODO mouse direction for projectile
                    const dir = c.Vector2{ .x = 1, .y = 0 };
                    const speed = 1;
                    return Entity{
                        .tag = .{ .exists = true },
                        .position = owner.position,
                        .velocity = c.Vector2Scale(dir, speed),
                        .data = .{ .ability = .fireball },
                    };
                },
                else => unreachable,
            }
        }
    };

    pub const State = struct {
        cam: c.Camera3D = .{
            .fovy = 45.0,
            .up = .{ .y = 1 },
            .target = .{ .y = 1 },
            .position = .{ .y = 20, .z = 20 },
            .projection = c.CAMERA_PERSPECTIVE,
        },

        entity: Entity.SoA = .{},
    };

    state: struct {
        prev: State = .{},
        next: State = .{},
    } = .{},

    fn update(game: *Game, ns: i128) void {
        const dt: f32 = @as(f32, @floatFromInt(ns)) / 1e+9;

        game.state.prev = game.state.next;
        var state = &game.state.next;

        // simulate
        {
            const up = c.Vector2{ .y = -1 };
            const down = c.Vector2{ .y = 1 };
            const left = c.Vector2{ .x = -1 };
            const right = c.Vector2{ .x = 1 };
            for (0..Entity.count) |ndx| {
                const entity = state.entity.get(ndx);
                if (entity.tag.controlled) {
                    var dir: c.Vector2 = .{};
                    if (c.IsKeyDown(c.KEY_E)) dir = c.Vector2Add(dir, up);
                    if (c.IsKeyDown(c.KEY_S)) dir = c.Vector2Add(dir, left);
                    if (c.IsKeyDown(c.KEY_D)) dir = c.Vector2Add(dir, down);
                    if (c.IsKeyDown(c.KEY_F)) dir = c.Vector2Add(dir, right);
                    dir = c.Vector2Normalize(dir);
                    const vel = c.Vector2Scale(dir, 10);
                    state.entity.velocity[ndx] = vel;
                }

                switch (state.entity.data[ndx]) {
                    .ability => {
                        switch (entity.data.ability) {
                            .fireball => {},
                            else => {},
                        }
                    },
                    .player => {
                        if (c.IsKeyPressed(c.KEY_SPACE)) {
                            state.entity.set(20, Game.Entity.newAbility(entity.data.player.basic1, entity));
                        }
                    },
                    else => {},
                }
            }
        }

        // move
        {
            for (0..Entity.count) |ndx| {
                var vel = state.entity.velocity[ndx];
                vel = c.Vector2Scale(vel, dt);

                const pos = state.entity.position[ndx];
                state.entity.position[ndx] = c.Vector2Add(pos, vel);
            }
        }
    }

    fn draw(game: *const Game, alpha: f32) void {
        var state = game.state.next;

        // interp
        {
            const prev = &game.state.prev;
            const next = &game.state.next;
            for (0..Entity.count) |ndx| {
                const pos = c.Vector2{
                    .x = std.math.lerp(prev.entity.position[ndx].x, next.entity.position[ndx].x, alpha),
                    .y = std.math.lerp(prev.entity.position[ndx].y, next.entity.position[ndx].y, alpha),
                };
                state.entity.position[ndx] = pos;
            }
        }

        c.ClearBackground(c.LIGHTGRAY);

        c.BeginMode3D(state.cam);
        {
            c.DrawGrid(100, 1.0);

            // unit axis
            c.DrawLine3D(.{}, .{ .x = 1 }, c.RED);
            c.DrawLine3D(.{}, .{ .y = 1 }, c.GREEN);
            c.DrawLine3D(.{}, .{ .z = 1 }, c.BLUE);

            const cube_pos: c.Vector3 = .{ .x = 1, .y = 1, .z = 0 };
            if (c.IsKeyPressed(c.KEY_SPACE)) {
                c.DrawCubeV(cube_pos, .{ .x = 1, .y = 1, .z = 1 }, c.RED);
                c.DrawCubeWiresV(cube_pos, .{ .x = 1, .y = 1, .z = 1 }, c.MAROON);
            }

            for (0..Entity.count) |ndx| {
                const tag = state.entity.tag[ndx];
                const pos = state.entity.position[ndx];
                if (!tag.exists) continue;
                switch (state.entity.data[ndx]) {
                    .ability => {
                        switch (state.entity.data[ndx].ability) {
                            .fireball => {
                                const color = c.RED;
                                const pos3 = c.Vector3{ .x = pos.x, .y = 1, .z = pos.y };
                                c.DrawSphere(pos3, 0.1, color);
                            },
                            else => {},
                        }
                    },
                    .player => {
                        const color = c.BLUE;
                        const pos3 = c.Vector3{ .x = pos.x, .y = 1, .z = pos.y };
                        c.DrawCircle3D(c.Vector3{ .x = pos.x, .y = 0, .z = pos.y }, 1, c.Vector3{ .x = 1, .y = 0, .z = 0 }, 90, c.RED);
                        c.DrawSphere(pos3, 1, color);
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

const Asset = union(Kind) {
    pub const Kind = enum {
        model,
        framebuffer,
    };

    pub const LoadOptions = union(Kind) {
        model: struct {
            path: []const u8,
        },
        framebuffer: struct {
            width: i32,
            height: i32,
        },
    };

    pub const AssetHashMap = std.StringArrayHashMap(Asset);
    var asset_table: AssetHashMap = undefined;

    model: c.Model,
    framebuffer: c.RenderTexture,

    /// doesn't free over-written assets
    pub fn load(kind: Kind, name: []const u8, options: LoadOptions) !void {
        const asset = switch (kind) {
            .model => Asset{
                .model = c.LoadModel(@ptrCast(options.model.path)),
            },
            .framebuffer => Asset{
                .framebuffer = c.LoadRenderTexture(options.framebuffer.width, options.framebuffer.height),
            },
        };
        try asset_table.put(name, asset);
    }

    /// TODO
    pub fn unload() void {}

    pub fn get(name: []const u8) Asset {
        return asset_table.get(name).?;
    }

    pub fn init() void {
        asset_table = AssetHashMap.init(global.allocator());
    }

    pub fn deinit() void {
        asset_table.deinit();
    }
};

const FPS = struct {
    const history_size = 30;
    const update_freq = 0.1 * std.time.ns_per_s;
    var history: [history_size]i128 = [_]i128{0} ** history_size;
    var h_idx: usize = 0;
    var accum: f64 = 0;
    var last_avg_fps: f64 = 0;

    fn pushDelta(dt: i128) void {
        h_idx = (h_idx + 1) % history_size;
        history[h_idx] = dt;
        accum += @floatFromInt(dt);
    }

    fn draw(x: i32, y: i32) void {
        _ = x;
        _ = y;

        if (accum >= update_freq) {
            accum -= update_freq;
            last_avg_fps = avgFps();
        }

        const text = std.fmt.bufPrintZ(global.scratch_buffer, "{d:.0} FPS", .{last_avg_fps}) catch "???";
        c.DrawText(text, 10, 10, 20, c.GREEN);
    }

    fn avgDelta() f64 {
        var result: f64 = 0;
        for (history) |dt| {
            result += @floatFromInt(dt);
        }
        result /= history_size;
        return result;
    }

    fn avgFps() f64 {
        const ad = avgDelta();
        return @as(f64, std.time.ns_per_s) / ad;
    }
};

const rng = struct {
    var random: std.rand.Random = undefined;

    pub fn init() void {
        var prng = std.rand.Xoroshiro128.init(0xbeef);
        random = prng.random();
    }

    pub fn position() c.Vector2 {
        var bytes: [2]u8 = undefined;
        std.os.getrandom(&bytes) catch unreachable;
        const x: f32 = @mod(@as(f32, @floatFromInt(bytes[0])), 20) - 10;
        const y: f32 = @mod(@as(f32, @floatFromInt(bytes[1])), 20) - 10;
        return .{
            .x = x,
            .y = y,
        };
    }
};

const ui = struct {
    const Item = union(Item.Kind) {
        pub const Kind = enum {
            button,
            number,
        };
        button: []const u8,
        number: i32,
    };
    const Menu = struct {
        items: [12]?Item = [_]?Item{null} ** 12,
    };

    var stack: [4]?Menu = [_]?Menu{null} ** 4;
    var bg_color: c.Color = undefined;

    pub fn init() void {
        bg_color = c.DARKGRAY;
        // push(menu1());
    }

    pub fn push(new_menu: Menu) void {
        for (stack, 0..) |menu, i| {
            if (menu) |_| continue;
            stack[i] = new_menu;
        }
    }

    pub fn pop() void {
        for (stack, 0..) |menu, i| {
            if (menu) |_| stack[i] = null;
        }
    }

    pub fn menu1() Menu {
        var menu = Menu{};
        menu.items[2] = Item{ .button = "play" };
        menu.items[1] = Item{ .button = "online" };
        menu.items[0] = Item{ .button = "settings" };
        return menu;
    }

    pub fn draw() void {
        // handle input
        {
            if (c.IsKeyPressed(c.KEY_ESCAPE)) {
                if (stack[0] == null) {
                    push(menu1());
                } else {
                    pop();
                }
            }
        }

        for (stack) |menu| {
            if (menu) |m| {
                c.DrawRectangle(0, 0, width, height, bg_color);
                for (m.items, 0..) |item_opt, i| {
                    const size = 40;
                    const x = 10;
                    const y = height - (10 + @as(i32, @intCast(i + 1)) * size);
                    if (item_opt) |item| {
                        switch (item) {
                            .button => {
                                // if (ui.button()) {
                                //     // play event
                                // }
                                c.DrawText(@ptrCast(item.button.ptr), x, y, size, c.LIGHTGRAY);
                            },
                            .number => {
                                c.DrawText("number item...", x, y, size, c.LIGHTGRAY);
                            },
                        }
                    }
                }
            }
        }
    }

    var show_dev: bool = true;
    pub fn drawDev(game: *Game) void {
        if (c.IsKeyPressed(c.KEY_ESCAPE)) show_dev = !show_dev;

        if (show_dev) {
            var index: f32 = 0;
            const padding = 4;
            const row_height = 23;
            const y_offset = row_height + padding;
            const wbox = c.Rectangle{
                .x = 10,
                .y = 10,
                .width = 200,
                .height = 400,
            };
            const inner = c.Rectangle{
                .x = wbox.x + padding,
                .y = wbox.y + padding + row_height,
                .width = wbox.width - padding * 2,
                .height = 20,
            };
            show_dev = c.GuiWindowBox(wbox, "dev") != 1;
            if (c.GuiButton(c.Rectangle{
                .x = inner.x,
                .y = inner.y + index * y_offset,
                .width = inner.width,
                .height = row_height,
            }, "button1") == 1) {}
            index += 1;

            const label_width = 30;
            const cam = &game.state.next.cam;

            _ = c.GuiSlider(c.Rectangle{
                .x = inner.x + label_width,
                .y = inner.y + index * y_offset,
                .width = inner.width - label_width,
                .height = row_height,
            }, "fovy", "", @ptrCast(&cam.fovy), 40, 120);
            index += 1;

            var cam_angle: f32 = std.math.atan2(cam.position.z, cam.position.y);
            var cam_dist: f32 = c.Vector2Length(c.Vector2{ .x = cam.position.z, .y = cam.position.y });
            // const cam_h = cam_dist * std.math.sin(cam_angle);
            // var cam_yoff: f32 = cam.position.y - cam_h;

            if (c.GuiSlider(c.Rectangle{
                .x = inner.x + label_width,
                .y = inner.y + index * y_offset,
                .width = inner.width - label_width,
                .height = row_height,
            }, "angle", "", @ptrCast(&cam_angle), 0, std.math.pi / 2.0 - 0.01) == 1) {
                cam.position.z = cam_dist * std.math.cos(cam_angle);
                cam.position.y = cam_dist * std.math.sin(cam_angle);
            }
            index += 1;

            if (c.GuiSlider(c.Rectangle{
                .x = inner.x + label_width,
                .y = inner.y + index * y_offset,
                .width = inner.width - label_width,
                .height = row_height,
            }, "dist", "", @ptrCast(&cam_dist), 1, 100) == 1) {
                cam.position.z = cam_dist * std.math.cos(cam_angle);
                cam.position.y = cam_dist * std.math.sin(cam_angle);
            }
            index += 1;

            // if (c.GuiSlider(c.Rectangle{
            //     .x = inner.x + label_width,
            //     .y = inner.y + index * y_offset,
            //     .width = inner.width - label_width,
            //     .height = row_height,
            // }, "y-off", "", @ptrCast(&cam_yoff), 1, 10) == 1) {
            //     cam.position.y = cam_dist * std.math.sin(cam_angle) - cam_yoff;
            //     cam.target.y = cam_yoff;
            // }
            // index += 1;
        }
    }
};

// TODO
// update zig
// event system
// menu
// camera controls
// game logic structure
