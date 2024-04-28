const std = @import("std");
const c = @import("c.zig");

const global = @import("global.zig");
const input = @import("input.zig");
const game = @import("game.zig");
const asset = @import("asset.zig");
const graphics = @import("graphics.zig");
const net = @import("net.zig");
const server = @import("server.zig");
const event = @import("event.zig");

const Asset = asset.Asset;

pub fn main() void {
    const allocator = std.heap.c_allocator;
    global.init(allocator) catch unreachable;
    defer global.deinit(allocator);

    c.InitWindow(global.window_width, global.window_height, "shoba");
    defer c.CloseWindow();

    c.SetExitKey(c.KEY_NULL);

    c.SetTargetFPS(120);

    graphics.init();
    asset.init();
    defer asset.deinit();

    rng.init();

    // load assets
    {
        std.debug.print("loading assets... ", .{});
        const start = std.time.nanoTimestamp();

        asset.load(.model, "default", .{ .model = asset.Model{ .rl_model = c.LoadModelFromMesh(c.GenMeshPoly(6, 0.1)) } }) catch unreachable;
        asset.load(.model, "dev_ground", .{ .model = asset.Model.init("assets/dev_ground.glb") }) catch unreachable;
        asset.load(.model, "daniel", .{ .model = asset.Model.init("assets/daniel.glb") }) catch unreachable;
        asset.load(.model_animation, "daniel_animation", .{ .model_animation = asset.ModelAnimation.init("assets/daniel.glb") }) catch unreachable;

        const end = std.time.nanoTimestamp();
        std.debug.print("done! {d:.2}s\n", .{@as(f32, @floatFromInt((end - start))) / std.time.ns_per_s});
    }

    std.debug.print("initializing game state... \n", .{});

    const game_state = global.mem.fba_allocator.alloc(game.State, 3) catch unreachable;
    const state_prev = &game_state[0];
    const state_next = &game_state[1];
    const state_server = &game_state[2];
    var input_events = std.ArrayList(event.Event).initCapacity(global.mem.fba_allocator, event.event_max) catch unreachable;
    defer global.mem.fba_allocator.free(game_state);

    state_prev.* = game.State.init();
    state_next.* = game.State.init();

    const ns = std.time.ns_per_s / global.tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;
    var alpha: f32 = 0;

    var socket = net.Socket.socket(.{}) catch unreachable;
    defer socket.close();

    socket.bind(null) catch unreachable;
    std.debug.print("socket: {}\n", .{socket.address});

    var addr = global.local_address;
    addr.setPort(server.port);

    var server_conn = net.Connection{
        .peer_address = addr,
        .socket = socket,
    };

    while (!c.WindowShouldClose()) {
        {
            const now = std.time.nanoTimestamp();
            delta = now - last;
            last = now;

            // FPS.pushDelta(delta);

            accumulator += delta;
            if (accumulator > max_accum) {
                const lost_ns = accumulator - max_accum;
                const lost_ms = lost_ns * 1000 * 1000;
                const lost_frames = @divTrunc(lost_ns, ns);
                accumulator = max_accum;

                std.debug.print("lost {d} frames (~{d:.0}ms)\n", .{ lost_frames, lost_ms });
            }

            while (accumulator >= ns) {
                pollInputEvents(state_next, &input_events);

                sendEventsToServer(&server_conn, input_events);
                recvServerState(&server_conn, state_server);
                reconcileState(state_server, state_prev, state_next);

                state_prev.* = state_next.*;
                game.update(state_next, ns, &input_events);
                accumulator -= ns;
            }
        }

        // TODO frame limiter
        {
            c.BeginTextureMode(graphics.framebuffer_main);
            {
                c.ClearBackground(c.BLUE);
                alpha = @as(f32, @floatFromInt(accumulator)) / ns;
                game.draw(state_prev, state_next, alpha);
                // ui.draw();
            }
            c.EndTextureMode();

            // final draw
            c.BeginDrawing();
            {
                c.ClearBackground(c.BLACK);

                const src = c.Rectangle{
                    .width = @floatFromInt(graphics.framebuffer_main.texture.width),
                    .height = @floatFromInt(-graphics.framebuffer_main.texture.height),
                };
                const dst = c.Rectangle{ .width = global.window_width, .height = global.window_height };
                c.DrawTexturePro(graphics.framebuffer_main.texture, src, dst, .{}, 0, c.WHITE);

                c.DrawFPS(10, 10);
            }
            c.EndDrawing();
        }

        // c.SwapScreenBuffer();
    }
}

fn pollInputEvents(state: *const game.State, events: *event.EventList) void {
    input.poll();
    events.clearRetainingCapacity();
    const ent_self = state.entities.get(state.main_entity_id);
    { // update event queue from user input
        if (input.key(c.KEY_E).isDown())
            events.appendAssumeCapacity(event.Event{ .input_move = .{ .direction = 0.75 } });
        if (input.key(c.KEY_S).isDown())
            events.appendAssumeCapacity(event.Event{ .input_move = .{ .direction = 0.5 } });
        if (input.key(c.KEY_LEFT_ALT).isDown())
            events.appendAssumeCapacity(event.Event{ .input_move = .{ .direction = 0.25 } });
        if (input.key(c.KEY_F).isDown())
            events.appendAssumeCapacity(event.Event{ .input_move = .{ .direction = 0.0 } });

        const dir = c.Vector2Subtract(ent_self.pos, game.getWorldMousePos(state));
        const look_angle_normalized = std.math.atan2(-dir.y, dir.x) / (std.math.pi * 2);
        if (ent_self.angle != look_angle_normalized) {
            events.appendAssumeCapacity(event.Event{ .input_look = .{ .direction = look_angle_normalized } });
        }
    }
}

fn sendEventsToServer(conn: *net.Connection, events: event.EventList) void {
    for (events.items) |evt| {
        const body = net.PacketBody{
            .event = evt,
        };
        if (conn.sendPacket(&body)) |_| {} else |_| {
            std.debug.print("failed to send packet, {s}\n", .{@tagName(body)});
        }
    }
}

fn recvServerState(conn: *net.Connection, state: *game.State) void {
    var peer_addr: std.net.Address = undefined;
    while (net.Connection.recvPacket(conn.socket, &peer_addr)) |pckt| {
        if (peer_addr.eql(conn.peer_address)) {
            conn.acceptPacket(&pckt);
        }
    } else |_| {}
    _ = state;
}

fn reconcileState(
    server_state: *const game.State,
    prev_state: *game.State,
    next_state: *game.State,
) void {
    _ = server_state;
    _ = prev_state;
    _ = next_state;
}

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
