const std = @import("std");
const c = @import("c.zig");

const global = @import("global.zig");
const input = @import("input.zig");
const game = @import("game.zig");
const asset = @import("asset.zig");
const graphics = @import("graphics.zig");
const net = @import("net.zig");
const server = @import("server.zig");

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

    const game_state = global.mem.fba_allocator.alloc(game.State, 2) catch unreachable;
    const state_prev = &game_state[0];
    const state_next = &game_state[1];
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

    socket.bindAny(global.mem.fba_allocator) catch unreachable;
    std.debug.print("socket: {}\n", .{socket.address});

    // var peer_conn_nano: f32, // the system time (std.time.nano) of the peer
    var last_recv_pckt_nano: i128 = 0;
    // var last_sent_pckt_nano: i128 = 0;
    var last_conn_pckt_nano: i128 = 0;
    var peer_address = global.local_address;
    peer_address.setPort(server.port);

    while (!c.WindowShouldClose()) {
        // network
        {
            // time since last packet
            const now = std.time.nanoTimestamp();
            const pckt_recv_dt = now - last_recv_pckt_nano;
            // const pckt_send_dt = now - last_sent_pckt_nano;
            const pckt_conn_dt = now - last_conn_pckt_nano;

            if (pckt_recv_dt > net.Connection.timeout_duration and pckt_conn_dt > net.Connection.conn_timer) {
                // attempt to establish connection
                var pckt_buff = net.PacketBuffer{
                    .data = global.mem.scratch_buffer[0..1024],
                };

                pckt_buff.write(u8, @intFromEnum(net.Packet.Tag.conn));
                pckt_buff.write(u32, net.proto_id);

                if (socket.sendto(peer_address, pckt_buff.data)) |_| {
                    std.debug.print("connecting to {}\n", .{peer_address});
                } else |err| {
                    std.debug.print("failed to send packet: {}\n", .{err});
                }
                last_conn_pckt_nano = now;
            }

            // send packets
            {
                // send input (action) delta (next_state_actions - prev_state_actions) (probably need map of actions rather than keystates)
                //
            }

            // recv packets
            // collect all game state packets
            // perform "dead reckoning" between server state and client state
            {
                var peer_addr: std.net.Address = undefined;
                var buff: [1024]u8 = undefined;
                while (socket.recvfrom(&buff, &peer_addr)) |pckt_size| {
                    if (pckt_size == 0) break;
                    last_recv_pckt_nano = std.time.nanoTimestamp();

                    var pckt_buff = net.PacketBuffer{
                        .data = buff[0..pckt_size],
                    };

                    const tag: net.Packet.Tag = @enumFromInt(pckt_buff.read(u8));

                    switch (tag) {
                        .ping => {
                            std.debug.print("{}: ping\n", .{peer_addr});
                        },
                        .conn => {
                            const proto_id = pckt_buff.read(u32);
                            std.debug.print("{}: connection, proto_id {x}\n", .{ peer_addr, proto_id });
                        },
                        else => {
                            std.debug.print("{}: unhandled\n", .{peer_addr});
                        },
                    }
                } else |err| switch (err) {
                    std.posix.RecvFromError.ConnectionResetByPeer => {},
                    else => {
                        std.debug.print("packet error: {}\n", .{err});
                    },
                }
            }
        }

        // game time step
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
                input.poll();
                state_prev.* = state_next.*;
                game.update(state_next, ns);
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

        const text = std.fmt.bufPrintZ(global.mem.scratch_buffer, "{d:.0} FPS", .{last_avg_fps}) catch "???";
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
