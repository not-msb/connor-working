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

//pub const PhiTarget = struct {
//    block: *Block,
//    temp: Var,
//};
//
//pub const Phi = struct {
//    dest: Var,
//    canon: Var,
//    args: ArrayList(PhiTarget),
//};

// TODO: Implement all of these as efficient functions
pub const Block = struct {
    id: usize,
    //phis: ArrayList(Phi),
    ops: ArrayList(Op),
    //preds: Set(*Block),
    //succs: Set(*Block),
    //doms: Set(*Block),
    //subs: Set(*Block),
    //fronts: Set(*Block),

    pub fn new(allocator: Allocator, id: usize) Block {
        return .{
            .id = id,
            .ops = ArrayList(Op).init(allocator),
            //.preds = Set(*Block).init(allocator),
            //.succs = Set(*Block).init(allocator),
            //.doms = Set(*Block).init(allocator),
            //.subs = Set(*Block).init(allocator),
            //.fronts = Set(*Block).init(allocator),
        };
    }

    fn debugPrint(self: Block, allocator: Allocator) Allocator.Error!void {
        //std.debug.print("# Preds", .{});
        //for (self.preds.items()) |pred|
        //    std.debug.print(", {d}", .{pred.id});
        //std.debug.print("\n", .{});

        //std.debug.print("# Succs", .{});
        //for (self.succs.items()) |succ|
        //    std.debug.print(", {d}", .{succ.id});
        //std.debug.print("\n", .{});

        //std.debug.print("# Doms", .{});
        //for (self.doms.items()) |dom|
        //    std.debug.print(", {d}", .{dom.id});
        //std.debug.print("\n", .{});

        //std.debug.print("# Subs", .{});
        //for (self.subs.items()) |sub|
        //    std.debug.print(", {d}", .{sub.id});
        //std.debug.print("\n", .{});

        //std.debug.print("# Fronts", .{});
        //for (self.fronts.items()) |front|
        //    std.debug.print(", {d}", .{front.id});
        //std.debug.print("\n", .{});

        std.debug.print("@L{d}\n", .{self.id});
        //for (self.phis.items) |phi| {
        //    std.debug.print("\t{s} ={s} phi", .{ try phi.dest.fmt(allocator), phi.dest.ty.fmtBase().? });
        //    const args = phi.args.items;
        //    for (args, 0..) |arg, i| {
        //        std.debug.print(" @L{d} {s}", .{ arg.block.id, try arg.temp.fmt(allocator) });
        //        if (i != args.len - 1) std.debug.print(",", .{});
        //    }
        //    std.debug.print("\n", .{});
        //}

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
                        t.dst.ty.fmtBase().?,
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
        //try self.createGraph();

        //const allocator = self.blocks.allocator;
        //const vars = try lib.walk.calcVars(allocator, self.*);
        //try lib.walk.placePhis(allocator, &vars);
        //try lib.walk.statisize(allocator, self.*);
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

    //pub fn createGraph(self: Function) Allocator.Error!void {
    //    for (self.blocks.items) |*block| {
    //        block.preds.map.clearAndFree();
    //        block.succs.map.clearAndFree();
    //        block.doms.map.clearAndFree();
    //        block.subs.map.clearAndFree();
    //        block.fronts.map.clearAndFree();
    //    }

    //    // Preds & Succs
    //    for (self.blocks.items) |*block| {
    //        for (block.ops.items) |op| {
    //            switch (op) {
    //                .Jnz => |t| {
    //                    try block.succs.set(self.get(t.succ));
    //                    try self.get(t.succ).preds.set(block);

    //                    try block.succs.set(self.get(t.fail));
    //                    try self.get(t.fail).preds.set(block);
    //                },
    //                .Jmp => |v| {
    //                    try block.succs.set(self.get(v));
    //                    try self.get(v).preds.set(block);
    //                },
    //                else => continue,
    //            }
    //        }
    //    }

    //    // Doms
    //    const entry = self.get(0);
    //    try entry.doms.set(entry);
    //    for (self.blocks.items[1..]) |*block| {
    //        for (self.blocks.items) |*b|
    //            try block.doms.set(b);
    //    }

    //    while (true) {
    //        var changed = false;

    //        for (self.blocks.items[1..]) |*block| {
    //            const preds = block.preds.items();
    //            var new = switch (preds.len) {
    //                0 => Set(*Block).init(self.blocks.allocator),
    //                else => b: {
    //                    var out = try preds[0].doms.clone();
    //                    for (preds[1..]) |pred|
    //                        out = try out.intersection(pred.doms);
    //                    break :b out;
    //                },
    //            };

    //            try new.set(block);
    //            if (!block.doms.eql(new)) {
    //                block.doms = new;
    //                changed = true;
    //            }
    //        }

    //        if (!changed) break;
    //    }

    //    // Subs
    //    for (self.blocks.items) |*block|
    //        for (block.doms.items()) |dom|
    //            try dom.*.subs.set(block);

    //    // Fronts
    //    for (self.blocks.items) |*block|
    //        for (block.doms.items()) |dom|
    //            for (dom.subs.items()) |sub|
    //                for (sub.succs.items()) |item|
    //                    if (!dom.subs.get(item) or item.id == dom.id)
    //                        try block.fronts.set(item);
    //}

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
