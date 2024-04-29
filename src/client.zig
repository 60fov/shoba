const std = @import("std");
const c = @import("c.zig");

const global = @import("global.zig");
const input = @import("input.zig");
const game = @import("game.zig");
const asset = @import("asset.zig");
const net = @import("net.zig");
const server = @import("server.zig");
const event = @import("event.zig");

const Asset = asset.Asset;

pub const Memory = struct {
    pub const asset_count = asset.asset_file_list.len;
    pub const pckt_queue_max = 256;
    pub const input_queue_max = 64;
    pub const scratch_size = 5 * 1024 * 1024;
    pub const dynamic_size = 15 * 1024 * 1024;

    isInitialized: bool,
    scratch: [scratch_size]u8,
    dynamic: [dynamic_size]u8,

    pckt_queue: [pckt_queue_max]net.Packet,
    server_connection: net.Connection,

    input_queue: event.EventList,

    framebuffer: c.RenderTexture,

    state: struct {
        prev: game.State,
        next: game.State,
    },
};

pub fn main() void {
    const allocator = std.heap.c_allocator;
    const memory: *Memory = allocator.create(Memory) catch unreachable;
    defer allocator.destroy(memory);
    // memory.* = std.mem.zeroInit(Memory, .{});

    var scratch_fba = std.heap.FixedBufferAllocator.init(&memory.scratch);
    const scratch_allocator = scratch_fba.allocator();
    _ = scratch_allocator;
    var dynamic_fba = std.heap.FixedBufferAllocator.init(&memory.dynamic);
    const dynamic_allocator = dynamic_fba.allocator();

    std.debug.print("init platform...\n", .{});
    // raylib init
    c.InitWindow(global.window_width, global.window_height, "shoba");
    defer c.CloseWindow();

    c.SetExitKey(c.KEY_NULL);
    c.SetTargetFPS(120);

    std.debug.print("init network...\n", .{});
    net.init(dynamic_allocator);
    net.bind(.{});
    defer net.unbind();

    std.debug.print("loading...\n", .{});
    { // memory init

        asset.init(dynamic_allocator);
        asset.loadAssets() catch unreachable;

        memory.framebuffer = c.LoadRenderTexture(global.window_width, global.window_height);

        var server_address = net.local_address;
        server_address.setPort(net.server_port);
        memory.server_connection = net.Connection{
            .peer_address = server_address,
        };

        memory.state.prev = game.State.init();
        memory.state.next = game.State.init();
    }
    defer c.UnloadRenderTexture(memory.framebuffer);

    const ns = std.time.ns_per_s / global.tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;
    var alpha: f32 = 0;

    while (!c.WindowShouldClose()) {
        {
            const now = std.time.nanoTimestamp();
            delta = now - last;
            last = now;

            accumulator += delta;
            if (accumulator > max_accum) {
                const lost_ns = accumulator - max_accum;
                const lost_ms = lost_ns * 1000 * 1000;
                const lost_frames = @divTrunc(lost_ns, ns);
                accumulator = max_accum;

                std.debug.print("lost {d} frames (~{d:.0}ms)\n", .{ lost_frames, lost_ms });
            }

            while (accumulator >= ns) {
                pollInputEvents(memory);
                updateNetwork(memory);
                updateState(memory, ns);
                accumulator -= ns;
            }
        }

        // TODO frame limiter
        alpha = @as(f32, @floatFromInt(accumulator)) / ns;
        drawState(memory, alpha);
    }
}

fn pollInputEvents(memory: *Memory) void {
    input.poll();
    memory.input_queue.clear();
    const state = &memory.state.next;
    const player = state.entities[0];
    { // update event queue from user input
        if (input.key(c.KEY_E).isDown()) {
            memory.input_queue.push(event.Event{ .input_move = .{ .direction = 0.75 } });
        }
        if (input.key(c.KEY_S).isDown()) {
            memory.input_queue.push(event.Event{ .input_move = .{ .direction = 0.5 } });
        }
        if (input.key(c.KEY_LEFT_ALT).isDown()) {
            memory.input_queue.push(event.Event{ .input_move = .{ .direction = 0.25 } });
        }
        if (input.key(c.KEY_F).isDown()) {
            memory.input_queue.push(event.Event{ .input_move = .{ .direction = 0.0 } });
        }

        const dir = c.Vector2Subtract(player.pos, game.getWorldMousePos(state));
        const look_angle_normalized = std.math.atan2(-dir.y, dir.x) / (std.math.pi * 2);
        if (player.angle != look_angle_normalized) {
            memory.input_queue.push(
                event.Event{ .input_look = .{ .direction = look_angle_normalized } },
            );
        }
    }
}

fn updateNetwork(memory: *Memory) void {
    // send events to server
    for (memory.input_queue.slice()) |evt| {
        const body = net.PacketBody{
            .event = evt,
        };
        if (memory.server_connection.sendPacket(&body)) |_| {} else |_| {
            std.debug.print("failed to send packet, {s}\n", .{@tagName(body)});
        }
    }

    // recv server state
    var peer_addr: std.net.Address = undefined;
    const conn = &memory.server_connection;
    while (net.Connection.recvPacket(net.socket, &peer_addr)) |pckt| {
        if (peer_addr.eql(conn.peer_address)) {
            conn.update(&pckt.header);
        }
    } else |_| {}
}

fn updateState(memory: *Memory, ns: i128) void {
    // TODO network reconciliation
    memory.state.prev = memory.state.next;

    const state = &memory.state.next;
    const input_queue = &memory.input_queue;

    const dt: f32 = @as(f32, @floatFromInt(ns)) / 1e+9;
    state.time += dt;

    const player = &state.entities[0];
    game.applyInputsToEntity(player, input_queue.slice());
    game.updateEntityPositions(state, dt);
    game.animateModels(state);
}

fn drawState(memory: *Memory, alpha: f32) void {
    const framebuffer = memory.framebuffer;

    c.BeginTextureMode(framebuffer);
    {
        c.ClearBackground(c.BLUE);
        const draw_state = game.State.lerp(&memory.state.prev, &memory.state.next, alpha);
        game.draw(&draw_state);
    }
    c.EndTextureMode();

    // final draw
    c.BeginDrawing();
    {
        c.ClearBackground(c.BLACK);

        const src = c.Rectangle{
            .width = @floatFromInt(framebuffer.texture.width),
            .height = @floatFromInt(-framebuffer.texture.height),
        };
        const dst = c.Rectangle{ .width = global.window_width, .height = global.window_height };
        c.DrawTexturePro(framebuffer.texture, src, dst, .{}, 0, c.WHITE);

        c.DrawFPS(10, 10);
    }
    c.EndDrawing();
}
