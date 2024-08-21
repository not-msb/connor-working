const std = @import("std");
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;

pub fn Cursor(comptime T: type) type {
    return struct {
        items: []const T,
        pos: usize = 0,

        const Self = Cursor(T);

        pub fn from(slice: []const T) Self {
            return .{
                .items = slice,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn done(self: Self) bool {
            return self.pos >= self.items.len;
        }

        pub fn next(self: *Self) ?T {
            if (self.done()) return null;
            self.pos += 1;
            return self.items[self.pos - 1];
        }

        pub fn peek(self: *Self) ?T {
            if (self.done()) return null;
            return self.items[self.pos];
        }
    };
}
