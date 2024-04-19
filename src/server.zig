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
                    var peer_addr: std.net.Address = undefined;
                    var buff: [1024]u8 = undefined;
                    while (socket.recvfrom(&buff, &peer_addr)) |pckt_size| {
                        if (pckt_size == 0) break;

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
                        else => {
                            std.debug.print("packet error: {}\n", .{err});
                        },
                        // A remote host refused to allow the network connection, typically because it is not
                        // running the requested service.
                        // .ConnectionRefused => {},

                        // Could not allocate kernel memory.
                        // .SystemResources => {},

                        // .ConnectionResetByPeer => {},
                        // .ConnectionTimedOut => {},

                        // The socket has not been bound.
                        // .SocketNotBound => {},

                        // The UDP message was too big for the buffer and part of it has been discarded
                        // .MessageTooBig => {},

                        // The network subsystem has failed.
                        // .NetworkSubsystemFailed => {},

                        // The socket is not connected (connection-oriented sockets only).
                        // .SocketNotConnected => {},
                    }
                }
            }
        }
    }
}
