const std = @import("std");
const os = std.os;
const input = @import("input.zig");

pub const proto_id: u32 = 0xbeef;

pub const Connection = struct {
    pub const timeout_duration = 3 * std.time.ns_per_s;
    pub const conn_timer = 1 * std.time.ns_per_s;
    pub const ping_timer = 1 * std.time.ns_per_s;

    last_pckt_nano: i128 = 0,
    peer_conn_nano: f32, // the system time (std.time.nano) of the peer
    peer_address: std.net.Address,
    // socket: Socket,
};

pub const Packet = struct {
    data: PacketData,

    pub const Tag = enum {
        never,

        ping, // client and server send
        conn,

        // user_input,
    };

    pub const PacketData = union(Tag) {
        never: void,
        ping: PingData,
        conn: ConnectionData,
    };

    pub const PingData = struct {};

    pub const ConnectionData = struct {
        proto_id: u32 = proto_id,
    };

    pub const UserInputData = struct {};

    pub fn read(self: *Packet, buffer: []u8) !void {
        var buff = PacketBuffer{
            .data = buffer,
            .index = 0,
        };
        const tag: Tag = @enumFromInt(buff.read(u8));

        switch (tag) {
            .ping => {
                self.* = Packet{ .data = .{ .ping = .{} } };
            },
            .conn => {
                self.* = Packet{ .data = .{ .conn = .{} } };
            },
            else => return error.PacketReadUnhandledTag,
        }
    }

    pub fn write(self: *const Packet, buffer: []u8) !void {
        var buff = PacketBuffer{
            .data = buffer,
            .index = 0,
        };

        buff.write(u8, @intFromEnum(self.data));
        switch (self.data) {
            .ping => {},
            .conn => {
                buff.write(u32, proto_id);
            },
            else => return error.PacketWriteUnhandledTag,
        }
    }
};

pub const PacketBuffer = struct {
    data: []u8,
    index: usize = 0,

    pub fn write(self: *PacketBuffer, comptime T: type, value: T) void {
        switch (T) {
            u8, u16, u32, i8, i16, i32 => {
                const size = @sizeOf(T);
                std.debug.assert(self.index + size <= self.data.len);

                const dest = self.data[self.index..][0..size];
                std.mem.writeInt(T, dest, value, .little);
                self.index += size;
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size <= self.data.len);

                const dest = self.data[self.index..][0..size];
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
                std.debug.assert(self.index + size <= self.data.len);

                const src = self.data[self.index..][0..size];
                self.index += size;
                return std.mem.readInt(T, src, .little);
            },
            f16, f32 => {
                const size = @sizeOf(T);
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
                std.debug.assert(self.index + size < self.data.len);

                const src = self.data[self.index..][0..size];
                self.index += size;
                // TODO consider making readFloat function
                return @bitCast(std.mem.readInt(IntType, src, .little));
            },
            else => @compileError("packet buffer read, unhandled type " ++ @typeName(T)),
        }
    }
};

pub const Socket = struct {
    fd: os.socket_t,
    address: std.net.Address,

    pub const SocketError = error{
        NoFileDescriptor,
        BindNullAddress,
        NoAddressWithFamily,
    };

    pub const Family = enum(u32) {
        INET = os.AF.INET,
        INET6 = os.AF.INET6,
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
        const sockfd = try os.socket(
            @intFromEnum(options.family),
            os.SOCK.DGRAM | os.SOCK.NONBLOCK,
            0,
        );
        errdefer os.close(sockfd);

        if (options.reuse_address) {
            try os.setsockopt(
                sockfd,
                os.SOL.SOCKET,
                os.SO.REUSEADDR,
                &std.mem.toBytes(@as(c_int, 1)),
            );
        }

        if (@hasDecl(os.SO, "REUSEPORT") and options.reuse_port) {
            try os.setsockopt(
                sockfd,
                os.SOL.SOCKET,
                os.SO.REUSEPORT,
                &std.mem.toBytes(@as(c_int, 1)),
            );
        }

        return Socket{
            .fd = sockfd,
            .address = undefined,
        };
    }

    /// must be called after `socket`
    pub fn bind(self: *Socket, address: std.net.Address) (os.BindError || os.GetSockNameError)!void {
        var sock_len = address.getOsSockLen();
        try os.bind(self.fd, &address.any, sock_len);

        var sock_name: os.sockaddr = undefined;
        try os.getsockname(self.fd, &sock_name, &sock_len);
        self.address = std.net.Address{ .any = sock_name };
    }

    pub fn bindAny(self: *Socket, allocator: std.mem.Allocator) !void {
        const list = try std.net.getAddressList(allocator, "", 0);
        defer list.deinit();

        // get first ipv4 or crash if none found
        const address = ip: {
            for (list.addrs) |addr| {
                if (addr.any.family == os.AF.INET) break :ip addr;
            }
            std.debug.print("no ipv4 address available\n", .{});
            unreachable;
        };

        var sock_len = address.getOsSockLen();
        try os.bind(self.fd, &address.any, sock_len);

        var sock_name: os.sockaddr = undefined;
        try os.getsockname(self.fd, &sock_name, &sock_len);
        self.address = std.net.Address{ .any = sock_name };
    }

    pub fn close(self: *Socket) void {
        os.close(self.fd);
        self.* = undefined;
    }

    pub fn sendto(self: *Socket, dest: std.net.Address, buf: []const u8) os.SendToError!usize {
        return try os.sendto(self.fd, buf, 0, &dest.any, dest.getOsSockLen());
    }

    pub fn recvfrom(self: *Socket, buf: []u8, sender: *std.net.Address) os.RecvFromError!usize {
        var src_addr: os.sockaddr = undefined;
        var len = @as(os.socklen_t, @intCast(@sizeOf(os.sockaddr.in)));
        const size = os.recvfrom(self.fd, buf, 0, &src_addr, &len) catch |err| switch (err) {
            os.RecvFromError.WouldBlock => return 0,
            else => return err,
        };
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
