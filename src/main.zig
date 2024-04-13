const std = @import("std");
const c = @import("c.zig");

const global = @import("global.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");
const game = @import("game.zig");
const entity = @import("entity.zig");
const ability = @import("ability.zig");
const asset = @import("asset.zig");

const Asset = asset.Asset;
const Game = game.Game;
const Entity = entity.Entity;
const Ability = ability.Ability;

const width = global.width;
const height = global.height;
const tick_rate = global.tick_rate;

pub fn main() void {
    const allocator = std.heap.c_allocator;
    global.init(allocator) catch unreachable;
    defer global.deinit(allocator);

    c.InitWindow(width, height, "shoba");
    defer c.CloseWindow();

    c.SetExitKey(c.KEY_NULL);

    // c.SetTargetFPS(165);

    asset.init();
    defer asset.deinit();
    asset.load(.framebuffer, "game", .{ .framebuffer = .{ .width = width, .height = height } }) catch unreachable;
    asset.load(.model, "dev_ground", .{ .model = c.LoadModelFromMesh(c.GenMeshPlane(100, 100, 10, 10)) }) catch unreachable;

    rng.init();
    ui.init();
    ability.init();

    const ns = std.time.ns_per_s / tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;
    var alpha: f32 = 0;

    const shoba = global.allocator().create(Game) catch unreachable;
    defer global.allocator().destroy(shoba);
    shoba.* = Game{};

    // temp init game
    {
        const state = &shoba.state.next;
        state.world = Game.World.load();
        state.ent_soa.set(0, Entity{
            .tag = .{
                .exists = true,
                .controlled = true,
            },
            .position = .{},
            .data = .{ .player = .{
                .mobility = Ability.createFromName("fireball"),
                .basic = Ability.createFromName("fireball"),
                .offensive = Ability.createFromName("fireball"),
                .defensive = Ability.createFromName("fireball"),
                .ultra = Ability.createFromName("fireball"),
            } },
        });

        for (1..11) |ndx| {
            const e = Entity{
                .tag = .{ .exists = true },
                .position = rng.position(),
                .velocity = .{},
            };
            state.ent_soa.set(ndx, e);
        }
    }

    const fb = asset.get("game").framebuffer;

    while (!c.WindowShouldClose()) {
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
                input.poll();
                shoba.update(ns);
                accumulator -= ns;
            }
        }

        // TODO frame limiter
        {
            c.BeginTextureMode(fb);
            {
                c.ClearBackground(c.BLUE);
                alpha = @as(f32, @floatFromInt(accumulator)) / ns;
                shoba.draw(alpha);
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
                ui.drawDev(shoba);
                FPS.draw(10, 10);
            }
            c.EndDrawing();
        }

        c.SwapScreenBuffer();
    }
}

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

// TODO
// update zig
// event system
// menu
// camera controls
// game logic structure
