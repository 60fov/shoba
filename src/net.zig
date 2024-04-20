const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const input = @import("input.zig");
const global = @import("global.zig");

pub const proto_id: u32 = 0xbeef;

pub const Connection = struct {
    socket: Socket,
    peer_address: std.net.Address,

    local_seq: u32 = 0,
    remote_seq: u32 = 0,

    pub fn sendPacket(self: *Connection, pckt_body: *const PacketBody) PacketSendError!void {
        var buff: [PacketBuffer.mem_size]u8 = undefined;
        var pckt_buff = PacketBuffer{
            .buffer = buff[0..],
        };

        // write packet header info
        const seq = self.local_seq;
        const ack = self.remote_seq;
        const ack_history = 0;

        pckt_buff.write(u32, proto_id);
        pckt_buff.write(u32, seq);
        pckt_buff.write(u32, ack);
        pckt_buff.write(u32, ack_history);

        // write packet body info
        const tag = @intFromEnum(pckt_body.*);
        pckt_buff.write(u8, tag);
        switch (pckt_body.*) {
            .ping => {},
        }

        // write crc32 of packet in-place of the protocol id
        const crc = std.hash.Crc32.hash(pckt_buff.buffer);
        @memcpy(pckt_buff.buffer[0..4], std.mem.asBytes(&crc));

        _ = self.socket.sendto(self.peer_address, pckt_buff.filledSlice()) catch |err| switch (err) {
            std.posix.SendToError.UnreachableAddress => return PacketSendError.UnreachableAddress,
            std.posix.SendToError.SocketNotConnected => unreachable,
            std.posix.SendToError.AddressNotAvailable => unreachable,
            else => return PacketSendError.UnexpectError,
        };
        self.local_seq += 1;
    }

    pub fn acceptPacket(self: *Connection, packet: *const Packet) void {
        if (packet.header.seq > self.remote_seq) self.remote_seq = packet.header.seq;
    }

    pub fn recvPacket(socket: Socket, peer_address: *std.net.Address) PacketRecvError!Packet {
        var buff: [PacketBuffer.mem_size]u8 = undefined;
        while (socket.recvfrom(&buff, peer_address)) |pckt_size| {
            if (pckt_size == 0) unreachable;

            var pckt_buff = PacketBuffer{
                .buffer = buff[0..pckt_size],
            };

            const pckt_crc = pckt_buff.read(u32);
            const crc_is_valid = crc_cmp: {
                // read crc from pckt_buff (incoming packet data)
                // replace crc section of pckt_buff (first 4 bytes) with protocol id
                // recalc crc hash of packet then compare
                @memcpy(buff[0..4], std.mem.asBytes(&proto_id));
                const local_crc = std.hash.Crc32.hash(pckt_buff.buffer);
                break :crc_cmp pckt_crc != local_crc;
            };

            if (crc_is_valid) {
                const header = PacketHeader{
                    .crc = pckt_crc,
                    .seq = pckt_buff.read(u32),
                    .ack = pckt_buff.read(u32),
                    .ack_history = pckt_buff.read(u32),
                };

                const tag: PacketBodyTag = @enumFromInt(pckt_buff.read(u8));

                var body: PacketBody = undefined;
                switch (tag) {
                    .ping => {
                        body = .{ .ping = {} };
                    },
                    // else => {
                    //     std.debug.print("unhandled packet body tag\n", .{tag});
                    // },
                }

                return Packet{
                    .header = header,
                    .body = body,
                };
            } else {
                return PacketRecvError.InvalidCrc;
            }
        } else |err| switch (err) {
            // investigate
            std.posix.RecvFromError.ConnectionResetByPeer => return PacketRecvError.EndOfPackets,
            // no data
            std.posix.RecvFromError.WouldBlock => return PacketRecvError.EndOfPackets,
            else => {
                std.debug.print("unhandled packet error: {}\n", .{err});
                return PacketRecvError.UnexpectError;
            },
        }
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

pub const PacketBodyTag = enum(u8) {
    ping,
};

pub const PacketBody = union(PacketBodyTag) {
    ping: void,
};

pub const Packet = struct {
    header: PacketHeader,
    body: PacketBody,

    pub fn deserialize(pckt_buff: PacketBuffer) Packet {
        const pckt = std.mem.bytesToValue(Packet, pckt_buff.buffer);
        return pckt;
    }
};

pub const PacketBuffer = struct {
    const mem_size = @sizeOf(PacketHeader) + 1024;
    buffer: []u8,
    index: usize = 0,

    pub fn write(self: *PacketBuffer, comptime T: type, value: T) void {
        switch (T) {
            u8, u16, u32, i8, i16, i32 => {
                const size = @sizeOf(T);
                std.debug.assert(self.index + size <= self.buffer.len);

                const dest = self.buffer[self.index..][0..size];
                std.mem.writeInt(T, dest, value, .little);
                self.index += size;
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size <= self.buffer.len);

                const dest = self.buffer[self.index..][0..size];
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
                std.debug.assert(self.index + size <= self.buffer.len);

                const src = self.buffer[self.index..][0..size];
                self.index += size;
                return std.mem.readInt(T, src, .little);
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size < self.buffer.len);

                const src = self.buffer[self.index..][0..size];
                self.index += size;
                // TODO consider making readFloat function
                return @bitCast(std.mem.readInt(IntType, src, .little));
            },
            else => @compileError("packet buffer read, unhandled type " ++ @typeName(T)),
        }
    }

    pub fn filledSlice(self: *const PacketBuffer) []const u8 {
        return self.buffer[0..self.index];
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
        const addr = address orelse global.local_address;
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

    // // TODO actual data validation
    // pub fn recvPacket(self: *Socket, packet: *Packet, address: *std.net.Address) !void {
    //     var buff: [@sizeOf(Packet)]u8 = undefined;
    //     const size = try self.recvfrom(&buff, address);

    //     if (size < buff.len) return error.PacketRecievedIncomplete;

    //     // var packet: Packet = undefined;
    //     try packet.read(&buff);

    //     // return packet;
    // }

    // pub fn sendPacket(self: *Socket, packet: *const Packet, address: std.net.Address) !void {
    //     var buff: [@sizeOf(Packet.PacketData)]u8 = undefined;
    //     try packet.write(&buff);
    //     const size = try self.sendto(address, &buff);
    //     if (size < buff.len) return error.PacketSentIncomplete;
    // }
};

test "socket" {
    var sock = Socket{};
    defer sock.close();

    // std.debug.print("empty socket: {}\n", .{socket});

    try sock.socket(.{});

    try std.testing.expect(sock.fd != null);
    try std.testing.expect(sock.address == null);
    // std.debug.print("socket now has fd: {any}\n", .{socket.fd});

    try std.testing.expectError(Socket.SocketError.BindNullAddress, sock.bind());

    const data: []const u8 = &[_]u8{ 10, 20, 30 };
    const dest = try std.net.Address.parseIp4("127.0.0.1", 3000);
    const size = try sock.sendto(dest, data);
    try std.testing.expect(size == data.len);
    // std.debug.print("sent data size: {}\n", .{size});

    try std.testing.expect(sock.address == null);
    const sock_address = try sock.getName();
    // std.debug.print("socket has address but isnt stored: {}\nstored: {}\n", .{ socket, sock_address });

    try sock.name();
    try std.testing.expect(sock_address.eql(sock.address.?));
    // std.debug.print("socket has stored address: {}\n", .{socket});
}
