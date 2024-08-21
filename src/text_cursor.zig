const std = @import("std");
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;
const Pair = lib.Pair;

// TextCursor
pub const Cursor = struct {
    items: []const u8,
    row: usize = 1,
    col: usize = 1,

    pub fn new(items: []const u8) Cursor {
        return .{
            .items = items,
        };
    }

    pub fn done(self: Cursor) bool {
        return self.len() == 0;
    }

    pub fn next(self: Cursor) ?Pair(Cursor, u8) {
        if (self.done()) return null;
        var row = self.row;
        var col = self.col;

        switch (self.items[0]) {
            '\n' => {
                row += 1;
                col = 1;
            },
            else => col += 1,
        }

        return .{
            .{
                .items = self.items[1..],
                .row = row,
                .col = col,
            },
            self.items[0],
        };
    }

    pub fn peek(self: Cursor) ?u8 {
        if (self.done()) return null;
        return self.items[0];
    }

    pub fn isNext(self: Cursor, comptime T: u8) bool {
        if (self.peek()) |char|
            if (char == T) return true;
        return false;
    }

    pub fn take(self: Cursor, comptime T: u8) ?Cursor {
        if (self.isNext(T)) {
            return self.next().?[0];
        }
        return null;
    }

    pub fn len(self: Cursor) usize {
        return self.items.len;
    }
};
