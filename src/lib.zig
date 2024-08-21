const std = @import("std");
const Allocator = std.mem.Allocator;

// Tree-like
pub const token = @import("token.zig");
pub const ast = @import("ast.zig");
pub const ir = @import("ir.zig");
//pub const walk = @import("walk.zig");

// Single-Type
//pub const Cursor = @import("cursor.zig").Cursor;
pub const Type = @import("type.zig").Type;
pub const Context = @import("ctx.zig").Context;
//pub const Set = @import("set.zig").Set;
//pub const Queue = @import("queue.zig").Queue;

pub const Var = struct {
    scope: Scope,
    access: Access,
    tag: Tag,
    ty: Type,

    pub const Scope = enum {
        compile_time,
        global,
        local,
    };

    pub const Access = enum {
        direct,
        deferred,
    };

    pub const Tag = union(enum) {
        named: []const u8,
        local: usize,
        liter: usize,
        ty: Type,
        none,
    };

    pub fn eql(self: Var, rhs: Var) bool {
        const activeTag = std.meta.activeTag;
        if (activeTag(self.tag) != activeTag(rhs.tag)) return false;
        if (self.scope != rhs.scope) return false;
        return switch (self.tag) {
            .named => |name| std.mem.eql(u8, name, rhs.tag.named),
            .local => |index| index == rhs.tag.local,
            .liter => |liter| liter == rhs.tag.liter,
            .ty => |t| Type.eql(t, rhs.tag.ty),
            .none => true,
        };
    }

    pub fn fmt(self: Var, allocator: Allocator) ![]const u8 {
        const prefix: u8 = switch (self.scope) {
            .compile_time => undefined,
            .global => '$',
            .local => '%',
        };

        return switch (self.tag) {
            .named => |name| std.fmt.allocPrint(allocator, "{c}{s}", .{ prefix, name }),
            .local => |index| std.fmt.allocPrint(allocator, "{c}t{d}", .{ prefix, index }),
            .liter => |liter| std.fmt.allocPrint(allocator, "{d}", .{ liter }),
            .ty => "'type'",
            .none => "'none'",
        };
    }
};

pub var global_error: Location = undefined;

pub const Location = struct {
    row: usize,
    col: usize,
};

pub const Error = error{
    Eof,
    Unexpected,
    Unrewritable,
    NonExistent,
    NonReturnCtx,
    NonComptimeFunc,
    NonComptimeEval,
    TypeIncompatible,
    TypeArithmeticNonInteger,
    TypeNonPointer,
    TypeNonFunction,
} || Allocator.Error;

pub fn Pair(comptime L: type, comptime R: type) type {
    return struct { L, R };
}

pub fn box(allocator: Allocator, value: anytype) Allocator.Error!*@TypeOf(value) {
    const ptr = try allocator.create(@TypeOf(value));
    ptr.* = value;
    return ptr;
}
