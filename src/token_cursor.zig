const std = @import("std");
const lib = @import("lib.zig");
const ParseError = lib.Error;
const Pair = lib.Pair;
const Token = lib.token.Token;
const TokenTag = @typeInfo(Token.Node).Union.tag_type.?;
const Location = lib.Location;

fn tokenField(comptime T: TokenTag) type {
    const fields = @typeInfo(Token.Node).Union.fields;
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, @tagName(T))) return field.type;
    }
    unreachable;
}

pub const Cursor = struct {
    items: []const Token,
    loc: Location,

    pub fn new(items: []const Token) Cursor {
        return .{
            .items = items,
            .loc = undefined,
        };
    }

    pub fn next(self: Cursor) ?Pair(Cursor, Token) {
        if (self.items.len == 0)
            return null;
        return .{
            .{
                .items = self.items[1..],
                .loc = self.items[0].loc,
            },
            self.items[0],
        };
    }

    pub fn peek(self: Cursor) ?Token {
        if (self.items.len == 0)
            return null;
        return self.items[0];
    }

    pub fn isNext(self: Cursor, comptime T: TokenTag) bool {
        if (self.peek()) |token|
            if (token.node == T) return true;
        return false;
    }

    pub fn take(self: Cursor, comptime T: TokenTag) ?Pair(Cursor, tokenField(T)) {
        if (self.isNext(T)) {
            const in, const token = self.next().?;
            lib.global_error = in.loc;
            return .{ in, @field(token.node, @tagName(T)) };
        }
        return null;
    }

    pub fn expect(self: Cursor, comptime T: TokenTag) ParseError!Pair(Cursor, tokenField(T)) {
        return self.take(T) orelse return ParseError.Unexpected;
    }
};
