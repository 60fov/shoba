const std = @import("std");

pub fn List(comptime T: type, cap: usize, init: anytype) type {
    return struct {
        const Self = @This();
        pub const capacity = cap;

        items: [capacity]T = [_]T{init} ** capacity,
        len: usize = 0,

        /// swap remove O(1)
        ///
        /// assert(len > 0) and assert(i < len)
        pub fn remove(self: *Self, i: usize) void {
            std.debug.assert(self.len > 0);
            std.debug.assert(i < self.len);
            // TODO check if this operation gets compiled away when attempting to remove last item
            // since they would be the same pointer the compiler should realize, right?
            std.mem.swap(T, &self.items[i], &self.items[self.len - 1]);
            self.len -= 1;
        }

        /// append to end of list
        ///
        /// assert(len < capacity)
        pub fn push(self: *Self, item: T) void {
            std.debug.assert(self.len < capacity);
            self.items[self.len] = item;
            self.len += 1;
        }

        /// return last element of the list and reduce the size by 1
        ///
        /// assert(len > 0)
        pub fn pop(self: *Self) T {
            std.debug.assert(self.len > 0);
            self.len -= 1;
            return self.items[self.len];
        }

        /// sets len to 0
        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *Self) []T {
            return self.items[0..self.len];
        }
    };
}
