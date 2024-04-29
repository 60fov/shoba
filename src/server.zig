const std = @import("std");

const global = @import("global.zig");
const net = @import("net.zig");
const game = @import("game.zig");
const event = @import("event.zig");

pub const Memory = struct {
    pub const pckt_queue_max = 2048;
    pub const input_queue_max = 512;
    pub const scratch_size = 5 * 1024 * 1024;
    pub const dynamic_size = 5 * 1024 * 1024;

    isInitialized: bool,
    scratch: [scratch_size]u8,
    dynamic: [dynamic_size]u8,

    pckt_queue: [pckt_queue_max]net.Packet,

    input_queue: event.EventQueue,

    state: game.State,
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

    std.debug.print("loading...\n", .{});

    // memory.state = game.State.init();

    net.init(dynamic_allocator);
    var address = net.local_address;
    address.setPort(net.server_port);

    var socket = net.Socket.socket(.{}) catch unreachable;
    socket.bind(address) catch unreachable;
    std.debug.print("open connection @ {}\n", .{socket.address});

    const ns = std.time.ns_per_s / global.tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;

    // var running = true;

    var clients = std.ArrayList(net.Connection).initCapacity(dynamic_allocator, 3) catch unreachable;

    while (true) {
        // game time step
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

            var updated = false;
            while (accumulator >= ns) {
                updated = true;
                // game.update(state, ns);
                accumulator -= ns;
            }

            if (updated) {
                // find state delta
                // send over network

                // send packets
                {
                    for (clients.items) |*conn| {
                        if (now - conn.last_sent_time > 1 * std.time.ns_per_s) {
                            std.debug.print("sending ping packet to client: {}...\n", .{conn.peer_address});
                            const body = net.PacketBody{
                                .ping = {},
                            };
                            conn.sendPacket(&body) catch {
                                std.debug.print("failed\n", .{});
                            };
                        }
                    }
                }

                // recv packets
                {
                    var peer: std.net.Address = undefined;
                    while (net.Connection.recvPacket(socket, &peer)) |pckt| {
                        std.debug.print("pckt, seq: {}, ack: {}\n", .{ pckt.header.seq, pckt.header.ack });
                        update_clients: {
                            for (clients.items) |*conn| {
                                if (conn.peer_address.eql(peer)) {
                                    conn.acceptPacket(&pckt);
                                    break :update_clients;
                                }
                            }
                            // client not found
                            if (clients.items.len < clients.capacity) {
                                clients.appendAssumeCapacity(net.Connection{
                                    .peer_address = peer,
                                    .socket = socket,
                                });
                            } else {
                                std.debug.print("server full\n", .{});
                            }
                        }

                        switch (pckt.body) {
                            .ping => {
                                std.debug.print("{}: ping!\n", .{peer});
                            },
                            .event => |evt| {
                                std.debug.print("{}: event {s}\n", .{ peer, @tagName(evt) });
                            },
                        }
                    } else |err| switch (err) {
                        net.PacketRecvError.EndOfPackets => {},
                        net.PacketRecvError.InvalidCrc => {
                            std.debug.print("recv'd invalid packet (crc)\n", .{});
                        },
                        else => unreachable,
                    }
                }
            }
        }
        // TODO is there a better way to reduce cpu usage? does this affect performance in anyway?
        std.time.sleep(0);
    }
}
