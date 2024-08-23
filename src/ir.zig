const std = @import("std");
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Context = lib.Context;
const Location = lib.Location;
const ParseError = lib.Error;
const Ast = lib.ast.Ast;
const Type = lib.Type;
const Set = lib.Set;
const Var = lib.Var;

pub const Op = union(enum) {
    Copy: struct {
        dst: Var,
        src: Var,
    },
    Alloc: struct {
        // TODO: Care about alignment someday
        // default 4
        dst: Var,
        amount: usize,
    },
    Load: struct {
        dst: Var,
        src: Var,
    },
    Store: struct {
        dst: Var,
        src: Var,
    },
    BinOp: struct {
        kind: Ast.Kind,
        dst: Var,
        lhs: Var,
        rhs: Var,
    },
    Call: struct {
        dest: ?Var,
        name: Var,
        args: []Var,
    },
    Jnz: struct {
        cond: Var,
        succ: usize,
        fail: usize,
    },
    Jmp: usize,
    Ret: Var,

    pub fn dest(self: Op) ?Var {
        return switch (self) {
            .Copy => |t| t.dst,
            .BinOp => |t| t.dst,
            .Call => |t| t.dest,
            else => null,
        };
    }
};

pub const Block = struct {
    id: usize,
    ops: ArrayList(Op),

    pub fn new(allocator: Allocator, id: usize) Block {
        return .{
            .id = id,
            .ops = ArrayList(Op).init(allocator),
        };
    }

    fn debugPrint(self: Block, allocator: Allocator) Allocator.Error!void {
        std.debug.print("@L{d}\n", .{self.id});

        for (self.ops.items) |op| {
            switch (op) {
                .Copy => |t| std.debug.print("\t{s} ={s} copy {s}\n", .{ try t.dst.fmt(allocator), t.dst.ty.fmtBase().?, try t.src.fmt(allocator) }),
                .Alloc => |t| {
                    std.debug.print("\t{s} =l alloc4 {d}\n", .{
                        try t.dst.fmt(allocator),
                        t.amount,
                    });
                },
                .Load => |t| {
                    std.debug.print("\t{s} ={s} load{s} {s}\n", .{
                        try t.dst.fmt(allocator),
                        t.dst.ty.fmtBase().?,
                        t.src.ty.fmtBase().?,
                        try t.src.fmt(allocator),
                    });
                },
                .Store => |t| {
                    std.debug.print("\tstore{s} {s}, {s}\n", .{
                        t.dst.ty.fmtExt().?,
                        try t.src.fmt(allocator),
                        try t.dst.fmt(allocator),
                    });
                },
                .BinOp => |t| {
                    const fmt = switch (t.kind) {
                        .Add => "add",
                        .Sub => "sub",
                        .Mul => "mul",
                        .Eq => "ceql",
                        .Ne => "cnel",
                    };
                    std.debug.print("\t{s} ={s} {s} {s}, {s}\n", .{
                        try t.dst.fmt(allocator),
                        t.dst.ty.fmtBase().?,
                        fmt,
                        try t.lhs.fmt(allocator),
                        try t.rhs.fmt(allocator),
                    });
                },
                .Call => |t| {
                    std.debug.print("\t", .{});
                    if (t.dest) |dst|
                        std.debug.print("{s} ={s} ", .{ try dst.fmt(allocator), dst.ty.fmtAbi().? });
                    std.debug.print("call {s}(", .{try t.name.fmt(allocator)});
                    for (t.args) |arg|
                        std.debug.print("{s} {s},", .{ arg.ty.fmtAbi().?, try arg.fmt(allocator) });
                    std.debug.print(")\n", .{});
                },
                .Jnz => |t| std.debug.print("\tjnz {s}, @L{d}, @L{d}\n", .{ try t.cond.fmt(allocator), t.succ, t.fail }),
                .Jmp => |v| std.debug.print("\tjmp @L{d}\n", .{v}),
                .Ret => |v| std.debug.print("\tret {s}\n", .{try v.fmt(allocator)}),
            }
        }
    }
};

pub const Function = struct {
    ctx: *Context,
    name: []const u8,
    params: Params,
    ret: Type,
    attr: Attr,
    tree: *Ast,
    blocks: ArrayList(Block),
    // For debugging purposes
    loc: Location,

    pub const Params = struct {
        names: []const []const u8,
        types: []const Type,
    };

    pub const Attr = struct {
        exported: bool = false,
        is_comptime: bool = false,
    };

    pub fn actualInit(self: *Function) ParseError!void {
        var block = try self.newBlock();
        _ = try self.tree.flatten(self.ctx, self, &block);
    }

    pub fn addJmp(self: *Function, start: *Block, end: *Block) Allocator.Error!void {
        const last = start.ops.getLastOrNull() orelse return start.ops.append(.{ .Jmp = end.id });

        switch (last) {
            .Copy, .Alloc, .Load, .Store, .BinOp, .Call => try start.ops.append(.{ .Jmp = end.id }),
            .Jnz => |t| {
                try self.addJmp(self.get(t.succ), end);
                try self.addJmp(self.get(t.fail), end);
            },
            .Jmp => |v| try self.addJmp(self.get(v), end),
            .Ret => {},
        }
    }

    pub fn addJnz(self: *Function, start: *Block, cond: Var, succ: *Block, fail: *Block) Allocator.Error!void {
        const last = start.ops.getLastOrNull() orelse return start.ops.append(.{ .Jnz = .{
            .cond = cond,
            .succ = succ.id,
            .fail = fail.id,
        }});

        switch (last) {
            .Copy, .Alloc, .Load, .Store, .BinOp, .Call => try start.ops.append(.{ .Jnz = .{
                .cond = cond,
                .succ = succ.id,
                .fail = fail.id,
            }}),
            .Jnz => |t| {
                try self.addJnz(self.get(t.succ), cond, succ, fail);
                try self.addJnz(self.get(t.fail), cond, succ, fail);
            },
            .Jmp => |v| try self.addJnz(self.get(v), cond, succ, fail),
            .Ret => {},
        }
    }

    pub fn newBlock(self: *Function) Allocator.Error!*Block {
        try self.blocks.append(Block.new(
            self.blocks.allocator,
            self.blocks.items.len,
        ));
        return self.get(self.blocks.items.len - 1);
    }

    pub fn get(self: Function, index: usize) *Block {
        return &self.blocks.items[index];
    }

    pub fn debugPrint(self: Function) Allocator.Error!void {
        if (self.attr.exported)
            std.debug.print("export ", .{});
        std.debug.print("function {s} ${s}(", .{ self.ret.fmtAbi().?, self.name });
        for (self.params.names, self.params.types) |name, ty|
            std.debug.print("{s} %{s},", .{ ty.fmtAbi().?, name });
        std.debug.print(") {{\n", .{});
        for (self.blocks.items) |block|
            try block.debugPrint(self.ctx.map.allocator);
        std.debug.print("}}\n", .{});
    }
};
