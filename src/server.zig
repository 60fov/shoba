const std = @import("std");

const global = @import("global.zig");
const net = @import("net.zig");
const game = @import("game.zig");

// TODO get tickrate from command line

pub const port = 0xbeef;

pub fn main() void {
    global.init(std.heap.page_allocator) catch unreachable;
    defer global.deinit(std.heap.page_allocator) catch unreachable;

    var address = global.local_address;
    address.setPort(port);

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
    const state = global.mem.fba_allocator.create(game.State) catch unreachable;
    state.* = game.State{};

    var clients = std.ArrayList(net.Connection).initCapacity(global.mem.fba_allocator, 3) catch unreachable;

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
                {}

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
    }
}
