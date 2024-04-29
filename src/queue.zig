const std = @import("std");

pub fn Queue(comptime T: anytype, size: comptime_int) type {
    return struct {
        const Self = @This();

        items: [size]T,
        len: usize,

        pub fn push(self: *Self, item: T) void {
            std.debug.assert(self.len < size);
            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn pop(self: *Self) T {
            std.debug.assert(self.len > 0);
            self.len -= 1;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *Self) []T {
            return self.items[0..self.len];
        }
    };
}
