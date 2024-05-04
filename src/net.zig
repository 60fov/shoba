const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const input = @import("input.zig");
const global = @import("global.zig");
const event = @import("event.zig");

pub const server_port = 0xbeef;
pub const proto_id: u32 = 0xbeef;

pub var address_list: *std.net.AddressList = undefined;
pub var local_address: std.net.Address = undefined;
pub var socket: Socket = undefined;

pub const BindOptions = struct {
    address: ?std.net.Address = null,
    socket_options: Socket.SocketOptions = .{},
};

pub fn init(allocator: std.mem.Allocator) void {
    { // for WSAStartup
        const addr_list = std.net.getAddressList(allocator, "localhost", 0) catch unreachable;
        addr_list.deinit();
    }

    const buffer = allocator.alloc(u8, c.HOST_NAME_MAX) catch unreachable;
    const host_name = c.gethostname(buffer[0..c.HOST_NAME_MAX]) catch unreachable;
    address_list = std.net.getAddressList(allocator, host_name, 0) catch unreachable;
    local_address = getaddr: {
        for (address_list.addrs) |addr| {
            // std.debug.print("addr{}: {}\n", .{ i, addr });
            if (addr.any.family == std.posix.AF.INET) {
                break :getaddr addr;
            }
        }
        unreachable;
    };
}

pub fn bind(options: BindOptions) void {
    socket = Socket.socket(options.socket_options) catch unreachable;
    socket.bind(options.address) catch unreachable;
}

pub fn unbind() void {
    socket.close();
}

/// packet header is written by this function
pub fn sendPacketTo(pckt: *Packet, connection: *Connection) PacketSendError!void {
    var buff: [PacketBuffer.mem_size]u8 = undefined;
    var pckt_buffer = PacketBuffer{
        .bytes = buff[0..],
    };

    // write packet header info
    const seq = connection.local_seq;
    const ack = connection.remote_seq;
    const ack_history = 0;

    pckt_buffer.write(u32, proto_id);
    pckt_buffer.write(u32, seq);
    pckt_buffer.write(u32, ack);
    pckt_buffer.write(u32, ack_history);

    // write packet body info
    pckt_buffer.writeSegments(pckt.segments);

    // write crc32 of packet in-place of the protocol id
    const crc = std.hash.Crc32.hash(pckt_buffer.filledSlice());
    @memcpy(pckt_buffer.bytes[0..4], std.mem.asBytes(&crc));

    _ = socket.sendto(connection.peer_address, pckt_buffer.filledSlice()) catch |err| switch (err) {
        std.posix.SendToError.UnreachableAddress => return PacketSendError.UnreachableAddress,
        std.posix.SendToError.SocketNotConnected => unreachable,
        std.posix.SendToError.AddressNotAvailable => unreachable,
        else => return PacketSendError.UnexpectError,
    };

    connection.local_seq += 1;
    connection.last_sent_time = std.time.nanoTimestamp();
}

pub fn recvPacketFrom(peer_address: *std.net.Address) PacketRecvError!Packet {
    var buff: [PacketBuffer.mem_size]u8 = undefined;
    if (socket.recvfrom(&buff, peer_address)) |pckt_size| {
        if (pckt_size == 0) unreachable;

        var pckt_buff = PacketBuffer{
            .bytes = buff[0..pckt_size],
        };

        // read crc from pckt_buff (incoming packet data)
        // replace crc section of pckt_buff (first 4 bytes) with protocol id
        // recalc crc hash of packet then compare
        const pckt_crc = pckt_buff.read(u32);
        @memcpy(pckt_buff.bytes[0..4], std.mem.asBytes(&proto_id));
        const local_crc = std.hash.Crc32.hash(pckt_buff.bytes);
        const is_valid_crc = pckt_crc == local_crc;

        if (is_valid_crc) {
            const header = PacketHeader{
                .crc = pckt_crc,
                .seq = pckt_buff.read(u32),
                .ack = pckt_buff.read(u32),
                .ack_history = pckt_buff.read(u32),
            };

            var segments: [Packet.max_segment_count]PacketSegment = undefined;
            const seg_count = pckt_buff.read(u8);
            for (0..seg_count) |i| {
                segments[i] = pckt_buff.readSegment();
            }

            return Packet{
                .header = header,
                .segments = segments[0..seg_count],
            };
        } else {
            return PacketRecvError.InvalidCrc;
        }
    } else |err| switch (err) {
        // TODO investigate
        std.posix.RecvFromError.ConnectionResetByPeer => return PacketRecvError.EndOfPackets,
        std.posix.RecvFromError.WouldBlock => return PacketRecvError.EndOfPackets,
        else => {
            std.debug.print("unhandled packet error: {}\n", .{err});
            return PacketRecvError.UnexpectError;
        },
    }
}
pub const Connection = struct {
    peer_address: std.net.Address = undefined,

    local_seq: u32 = 0,
    remote_seq: u32 = 0,
    last_sent_time: i128 = 0,
    last_recv_time: i128 = 0,

    /// TODO not sure if i want to do it this way
    pub fn update(self: *Connection, header: *const PacketHeader) void {
        self.last_recv_time = std.time.nanoTimestamp();
        if (header.seq > self.remote_seq) self.remote_seq = header.seq;
    }
};

pub const PacketRecvError = error{
    InvalidCrc,
    /// not really an error
    EndOfPackets,
    UnexpectError,
};

pub const PacketSendError = error{
    UnreachableAddress,
    UnexpectError,
};

pub const PacketHeader = struct {
    crc: u32, // crc32(protocol id + packet) (packet not including crc32, ofc)
    seq: u32, // this packet's id
    ack: u32, // id of last packet recv'd
    ack_history: u32, // bitfield of last 32 acks
};

pub const PacketSegmentTag = enum(u8) {
    empty,
    ping,
    event,
    entity,
};

pub const PacketSegment = union(PacketSegmentTag) {
    pub const EntitySegment = struct {
        id: u8,
        x: f32,
        y: f32,
        angle: f32,
    };

    empty: void,
    ping: void,
    event: event.Event,
    entity: EntitySegment,
};

pub const Packet = struct {
    // TODO i chose this number for no good reason
    pub const max_segment_count = 32;

    header: PacketHeader = undefined,
    segments: []PacketSegment,

    pub fn deserialize(pckt_buff: PacketBuffer) Packet {
        const pckt = std.mem.bytesToValue(Packet, pckt_buff.bytes);
        return pckt;
    }

    /// writes crc32 hash of packet in-place of the protocol id
    pub fn writeHash(pckt: *Packet) void {
        const crc = std.hash.Crc32.hash(pckt.buffer.bytes);
        @memcpy(pckt.buffer.bytes[0..4], std.mem.asBytes(&crc));
    }
};

pub const PacketBuffer = struct {
    const mem_size = @sizeOf(PacketHeader) + 1024;
    bytes: []u8,
    index: usize = 0,

    pub fn isValid(self: *PacketBuffer) bool {
        const pckt_crc = self.read(u32);
        // read crc from pckt_buff (incoming packet data)
        // replace crc section of pckt_buff (first 4 bytes) with protocol id
        // recalc crc hash of packet then compare
        @memcpy(self.buff[0..4], std.mem.asBytes(&proto_id));
        const local_crc = std.hash.Crc32.hash(self.pckt_buff.bytes);
        return pckt_crc == local_crc;
    }

    pub fn write(self: *PacketBuffer, comptime T: type, value: T) void {
        switch (T) {
            u8, u16, u32, i8, i16, i32 => {
                const size = @sizeOf(T);
                std.debug.assert(self.index + size <= self.bytes.len);

                const dest = self.bytes[self.index..][0..size];
                std.mem.writeInt(T, dest, value, .little);
                self.index += size;
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size <= self.bytes.len);

                const dest = self.bytes[self.index..][0..size];
                std.mem.writeInt(IntType, dest, @as(IntType, @bitCast(value)), .little);
                self.index += size;
            },
            else => @compileError("packet buffer write, unhandled type " ++ @typeName(T)),
        }
    }

    pub fn read(self: *PacketBuffer, comptime T: type) T {
        switch (T) {
            u8, u16, u32, i8, i16, i32 => {
                const size = @sizeOf(T);
                std.debug.assert(self.index + size <= self.bytes.len);

                const src = self.bytes[self.index..][0..size];
                self.index += size;
                return std.mem.readInt(T, src, .little);
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size <= self.bytes.len);

                const src = self.bytes[self.index..][0..size];
                self.index += size;
                // TODO consider making readFloat function
                return @bitCast(std.mem.readInt(IntType, src, .little));
            },
            else => @compileError("packet buffer read, unhandled type " ++ @typeName(T)),
        }
    }

    // TODO max_segment_count not enforced here
    pub fn writeSegments(self: *PacketBuffer, segments: []const PacketSegment) void {
        self.write(u8, @intCast(segments.len));
        for (segments) |segment| {
            self.writeSegment(segment);
        }
    }

    pub fn readSegments(self: *PacketBuffer, segments: [Packet.max_segment_count]PacketSegment) []PacketSegment {
        const segment_count = self.read(u8);
        for (0..segment_count) |i| {
            segments[i] = self.readSegment();
        }
        return segments[0..segment_count];
    }

    fn writeSegment(self: *PacketBuffer, segment: PacketSegment) void {
        self.write(u8, @intFromEnum(segment));
        switch (segment) {
            .empty => {},
            .ping => {},
            .event => |evt| {
                self.write(u8, @intFromEnum(evt));
                switch (evt) {
                    .input_move => |move| {
                        self.write(f32, move.direction);
                    },
                    .input_look => |look| {
                        self.write(f32, look.direction);
                    },
                    .input_ability => |ability| {
                        self.write(u8, @intFromEnum(ability.slot));
                    },
                    .empty => unreachable,
                }
            },
            .entity => |ent| {
                self.write(u8, ent.id);
                self.write(f32, ent.x);
                self.write(f32, ent.y);
                self.write(f32, ent.angle);
            },
        }
    }

    fn readSegment(self: *PacketBuffer) PacketSegment {
        const segment_tag: PacketSegmentTag = @enumFromInt(self.read(u8));
        switch (segment_tag) {
            .empty => {
                return PacketSegment{ .empty = {} };
            },
            .ping => {
                return PacketSegment{ .ping = {} };
            },
            .event => {
                const event_tag: event.EventTag = @enumFromInt(self.read(u8));
                switch (event_tag) {
                    .input_move => {
                        const dir = self.read(f32);
                        return PacketSegment{ .event = .{ .input_move = .{ .direction = dir } } };
                    },
                    .input_look => {
                        const dir = self.read(f32);
                        return PacketSegment{ .event = .{ .input_look = .{ .direction = dir } } };
                    },
                    .input_ability => {
                        const slot: event.InputAbilityEvent.AbilitySlot = @enumFromInt(self.read(u8));
                        return PacketSegment{ .event = .{ .input_ability = .{ .slot = slot } } };
                    },
                    .empty => unreachable,
                }
            },
            .entity => {
                return PacketSegment{
                    .entity = .{
                        .id = self.read(u8),
                        .x = self.read(f32),
                        .y = self.read(f32),
                        .angle = self.read(f32),
                    },
                };
            },
        }
    }

    pub fn filledSlice(self: *const PacketBuffer) []const u8 {
        return self.bytes[0..self.index];
    }
};

pub const Socket = struct {
    fd: std.posix.socket_t,
    address: std.net.Address,

    pub const SocketError = error{
        NoFileDescriptor,
        BindNullAddress,
        NoAddressWithFamily,
    };

    pub const Family = enum(u32) {
        INET = std.posix.AF.INET,
        INET6 = std.posix.AF.INET6,
    };

    pub const SocketOptions = struct {
        family: Family = .INET,
        reuse_address: bool = true,
        reuse_port: bool = true,
    };

    pub const MsgInfo = struct {
        from: std.net.Address,
        size: usize,
    };

    /// only creates the socket's file descriptor,
    /// call `bind` to set the socket's address
    pub fn socket(options: SocketOptions) !Socket {
        const sockfd = try std.posix.socket(
            @intFromEnum(options.family),
            std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK,
            0,
        );
        errdefer std.posix.close(sockfd);

        if (options.reuse_address) {
            try std.posix.setsockopt(
                sockfd,
                std.posix.SOL.SOCKET,
                std.posix.SO.REUSEADDR,
                &std.mem.toBytes(@as(c_int, 1)),
            );
        }

        if (@hasDecl(std.posix.SO, "REUSEPORT") and options.reuse_port) {
            try std.posix.setsockopt(
                sockfd,
                std.posix.SOL.SOCKET,
                std.posix.SO.REUSEPORT,
                &std.mem.toBytes(@as(c_int, 1)),
            );
        }

        return Socket{
            .fd = sockfd,
            .address = undefined,
        };
    }

    /// must be called after `socket`
    pub fn bind(self: *Socket, address: ?std.net.Address) (std.posix.BindError || std.posix.GetSockNameError)!void {
        const addr = address orelse local_address;
        var sock_len = addr.getOsSockLen();
        try std.posix.bind(self.fd, &addr.any, sock_len);

        var sock_name: std.posix.sockaddr = undefined;
        try std.posix.getsockname(self.fd, &sock_name, &sock_len);
        self.address = std.net.Address{ .any = sock_name };
    }

    pub fn close(self: *Socket) void {
        std.posix.close(self.fd);
        self.* = undefined;
    }

    pub fn sendto(self: *const Socket, dest: std.net.Address, buf: []const u8) std.posix.SendToError!usize {
        return try std.posix.sendto(self.fd, buf, 0, &dest.any, dest.getOsSockLen());
    }

    pub fn recvfrom(self: *const Socket, buf: []u8, sender: *std.net.Address) std.posix.RecvFromError!usize {
        var src_addr: std.posix.sockaddr = undefined;
        var len = @as(std.posix.socklen_t, @intCast(@sizeOf(std.posix.sockaddr.in)));
        const size = try std.posix.recvfrom(self.fd, buf, 0, &src_addr, &len);
        sender.* = .{ .any = src_addr };
        return size;
    }
};
