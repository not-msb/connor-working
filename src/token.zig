const std = @import("std");
const lib = @import("lib.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ParseError = lib.Error;
const Location = lib.Location;
const Type = lib.Type;
const Ast = lib.ast.Ast;
const Cursor = lib.TextCursor;

pub const Token = struct {
    node: Node,
    loc: Location,

    pub const Node = union(enum) {
        Eof,
        Add,
        Sub,
        Mul,
        Ref,
        Assign,
        Eq,
        Ne,
        LParen,
        RParen,
        LBracket,
        RBracket,
        SemiColon,
        Point,
        Comma,
        Const,
        Var,
        Fn,
        If,
        Else,
        While,
        Return,
        Export,
        Extern,
        Comptime,
        Type: Type,
        Integer: usize,
        Identifier: []const u8,
    };

    const Power = union(enum) {
        post: u8,
        infix: struct {
            l: u8,
            r: u8,
        },
    };

    const keywords = std.StaticStringMap(Node).initComptime(.{
        .{ "const", .Const },
        .{ "var", .Var },
        .{ "fn", .Fn },
        .{ "if", .If },
        .{ "else", .Else },
        .{ "while", .While },
        .{ "return", .Return },
        .{ "extern", .Extern },
        .{ "export", .Export },
        .{ "comptime", .Comptime },
        .{ "u8", .{ .Type = .U8 } },
        .{ "u32", .{ .Type = .U32 } },
        .{ "u64", .{ .Type = .U64 } },
        .{ "type", .{ .Type = .Type } },
        .{ "void", .{ .Type = .Void } },
        .{ "noreturn", .{ .Type = .NoReturn } },
    });

    pub fn parse(allocator: Allocator, source: []const u8) ParseError![]Token {
        var tokens = ArrayList(Token).init(allocator);
        var input = Cursor.new(source);

        while (input.next()) |pair| {
            const clone = input;
            input, const char = pair;

            const node: Node = switch (char) {
                ' ', '\n', '\t', '\r', 0x0B, 0xC => continue,
                '+' => .Add,
                '-' => .Sub,
                '*' => .Mul,
                '&' => .Ref,
                '/' => if (input.take('/')) |first| {
                    input = first;
                    while (input.next()) |next| {
                        input, const c = next;
                        if (c == '\n') break;
                    }
                    continue;
                } else return ParseError.Unexpected,
                '=' => if (input.take('=')) |i| b: {
                    input = i;
                    break :b .Eq;
                } else .Assign,
                '!' => if (input.take('=')) |i| b: {
                    input = i;
                    break :b .Ne;
                } else return ParseError.Unexpected,
                '(' => .LParen,
                ')' => .RParen,
                '{' => .LBracket,
                '}' => .RBracket,
                ';' => .SemiColon,
                '.' => .Point,
                ',' => .Comma,
                '0'...'9' => b: {
                    while (input.peek()) |c| switch (c) {
                        '0'...'9' => {
                            input, _ = input.next().?;
                        },
                        else => break,
                    };
                    const int = std.fmt.parseInt(usize, clone.items[0..clone.len()-input.len()], 10) catch unreachable;
                    break :b .{ .Integer = int };
                },
                'a'...'z', 'A'...'Z', '_' => b: {
                    while (input.peek()) |c| switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                            input, _ = input.next().?;
                        },
                        else => break,
                    };
                    const word = clone.items[0..clone.len()-input.len()];
                    break :b keywords.get(word) orelse .{ .Identifier = word };
                },
                else => {
                    return ParseError.Unexpected;
                },
            };

            try tokens.append(.{
                .node = node,
                .loc = .{
                    .row = clone.row,
                    .col = clone.col,
                },
            });
        }

        return try tokens.toOwnedSlice();
    }

    pub fn powerPrefix(self: Token) ?u8 {
        return switch (self.node) {
            .Mul => 9,
            else => null,
        };
    }

    pub fn power(self: Token) ?Power {
        return switch (self.node) {
            .LParen => .{ .post = 10 },
            .Assign => .{ .infix = .{ .l = 2, .r = 1 } },
            .Eq, .Ne => .{ .infix = .{ .l = 3, .r = 4 } },
            .Add, .Sub => .{ .infix = .{ .l = 5, .r = 6 } },
            .Mul => .{ .infix = .{ .l = 7, .r = 8 } },
            else => null,
        };
    }

    pub fn kind(self: Token) ?Ast.Kind {
        return switch (self.node) {
            .Add => .Add,
            .Sub => .Sub,
            .Mul => .Mul,
            .Eq => .Eq,
            .Ne => .Ne,
            else => null,
        };
    }
};
