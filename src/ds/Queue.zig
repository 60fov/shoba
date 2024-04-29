const std = @import("std");

fn Queue(comptime T: anytype, size: comptime_int) type {
    _ = T;
    _ = size;
    return struct {};
}
