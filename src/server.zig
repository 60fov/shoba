const std = @import("std");

const global = @import("global.zig");
const net = @import("net.zig");
const game = @import("game.zig");
const event = @import("event.zig");

const ds = @import("ds.zig");

pub const Memory = struct {
    pub const scratch_size = 5 * 1024 * 1024;
    pub const dynamic_size = 5 * 1024 * 1024;
    pub const ClientList = ds.List(Client, game.max_player_count, .{});

    isInitialized: bool,
    scratch: [scratch_size]u8,
    dynamic: [dynamic_size]u8,

    // TODO would a linked list be better?
    client_list: ClientList,

    state: game.State,
};

pub const Client = struct {
    connection: net.Connection = .{},
    entity_id: game.EntityId = undefined,
    input_queue: event.EventList = .{},
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

    std.debug.print("initializing network...\n", .{});

    net.init(dynamic_allocator);
    var address = net.local_address;
    address.setPort(net.server_port);
    net.bind(.{ .address = address });
    std.debug.print("open connection @ {}\n", .{net.socket.address});

    // memory.state = game.State.init();
    memory.client_list = .{};

    const ns = std.time.ns_per_s / global.tick_rate;
    if (ns == 0) unreachable;
    const max_accum = ns * 10;

    var last: i128 = std.time.nanoTimestamp();
    var accumulator: i128 = 0;
    var delta: i128 = 0;

    // var running = true;

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

            recvNetwork(memory);
            while (accumulator >= ns) {
                updateState(memory, ns);
                accumulator -= ns;
            }
            sendNetwork(memory);
        }

        // TODO is there a better way to reduce cpu usage? how does this affect performance?
        std.time.sleep(0);
    }
}

// TODO soooooo messy
pub fn recvNetwork(memory: *Memory) void {
    const clients = &memory.client_list;

    var peer: std.net.Address = undefined;
    recv_pckt_loop: while (net.recvPacketFrom(&peer)) |pckt| {
        std.debug.print("pckt, seq: {}, ack: {}\n", .{ pckt.header.seq, pckt.header.ack });
        var current_client: *Client = find_client: {
            for (clients.slice()) |*client| {
                if (client.connection.peer_address.eql(peer)) {
                    break :find_client client;
                }
            }

            // client not found, handle new client
            if (clients.len < game.max_player_count) {
                // const player = game.createPlayer();
                var ent_id: game.EntityId = 0;
                first_empty_entity: {
                    for (memory.state.playerEntities(), 0..) |*ent, i| {
                        if (!ent.exists) {
                            ent.* = game.Entity{
                                .exists = true,
                            };
                            ent_id = @intCast(i);
                            break :first_empty_entity;
                        }
                    }
                    // failed to find empty player entity slot even though server isn't full
                    unreachable;
                }
                const new_client = Client{
                    .connection = .{
                        .peer_address = peer,
                    },
                    .entity_id = ent_id,
                };
                clients.push(new_client);
                break :find_client &clients.items[clients.len - 1];
            } else {
                std.debug.print("server full, refusing connection from {}\n", .{peer});
                continue :recv_pckt_loop;
            }
        };

        current_client.connection.update(&pckt.header);

        // handle packet
        // TODO maybe conceptualize recving input event packets as polling network input
        // why? would introduce more (potentially helpful) overlap between client and server
        for (pckt.segments) |segment| {
            switch (segment) {
                .empty => {
                    std.debug.print("{}: empty\n", .{peer});
                },
                .ping => {
                    std.debug.print("{}: ping!\n", .{peer});
                },
                .event => |evt| {
                    std.debug.print("{}: event {s}\n", .{ peer, @tagName(evt) });
                    current_client.input_queue.push(evt);
                },
                else => {
                    std.debug.print("{}: sent unhandled packet segment {s}\n", .{ peer, @tagName(segment) });
                },
            }
        }
    } else |err| switch (err) {
        net.PacketRecvError.EndOfPackets => {},
        net.PacketRecvError.InvalidCrc => {
            std.debug.print("recv'd invalid packet (crc)\n", .{});
        },
        else => unreachable,
    }
}

pub fn updateState(memory: *Memory, ns: i128) void {
    const state = &memory.state;
    for (memory.client_list.slice()) |*client| {
        const ent = &state.entities[client.entity_id];
        game.applyInputsToEntity(ent, client.input_queue.slice());
        client.input_queue.clear();
    }

    const dt: f32 = @as(f32, @floatFromInt(ns)) / 1e+9;
    state.time += dt;

    game.updateEntityPositions(state, dt);
}

pub fn sendNetwork(memory: *Memory) void {
    var pckt_seg_list: ds.List(
        net.PacketSegment,
        net.Packet.max_segment_count,
        net.PacketSegment{ .empty = {} },
    ) = .{};

    // collect state changes
    for (memory.state.entities, 0..) |ent, i| {
        if (ent.exists) {
            pckt_seg_list.push(net.PacketSegment{
                .entity = .{
                    .id = @intCast(i),
                    .x = ent.pos.x,
                    .y = ent.pos.y,
                    .angle = ent.angle,
                },
            });
        }
    }

    // construct and send packet to all connected clients
    var pckt: net.Packet = .{
        .segments = pckt_seg_list.slice(),
    };

    for (memory.client_list.slice()) |*client| {
        net.sendPacketTo(&pckt, &client.connection) catch |err| {
            std.debug.print("failed to send packet, err {}\n", .{err});
        };
    }
}
