const std = @import("std");
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Queue = lib.Queue;
const Block = lib.ir.Block;
const Function = lib.ir.Function;
const Set = lib.Set;
const PhiTarget = lib.ir.PhiTarget;
const Phi = lib.ir.Phi;
const Var = lib.Var;

fn markWalk(
    allocator: Allocator,
    ctx: anytype,
    init: []const *Block,
    handle: fn (Allocator, @TypeOf(ctx), *Queue(*Block), *Block) Allocator.Error!void,
) Allocator.Error!void {
    var handled = Set(*Block).init(allocator);
    var working = Queue(*Block).init(allocator);
    try working.addSlice(init);

    while (working.pop()) |node| {
        if (handled.get(node)) continue;
        try handled.set(node);
        try handle(allocator, ctx, &working, node);
    }
}

const Working = *Queue(*Block);
const VarsContext = struct {
    pub fn hash(self: VarsContext, key: Var) u64 {
        // Maybe check if Deep is needed
        // But i dont think thats true
        return std.array_hash_map.getAutoHashStratFn(Var, VarsContext, .Shallow)(self, key);
    }

    pub fn eql(self: VarsContext, lhs: Var, rhs: Var) bool {
        _ = self;
        return lhs.eql(rhs);
    }
};
const Vars = HashMap(Var, Set(*Block), VarsContext, std.hash_map.default_max_load_percentage);
const ConvMap = struct {
    parent: ?*const ConvMap,
    map: Map,

    const Map = HashMap(Var, Var, VarsContext, std.hash_map.default_max_load_percentage);

    fn init(allocator: Allocator) ConvMap {
        return .{
            .parent = null,
            .map = Map.init(allocator)
        };
    }

    fn child(self: *const ConvMap) *ConvMap {
        return .{
            .parent = self,
            .map = Map.init(self.map.allocator),
        };
    }

    fn put(self: *ConvMap, key: Var, value: Var) !void {
        return self.map.put(key, value);
    }

    fn get(self: *const ConvMap, key: Var) ?Var {
        if (key.scope == .global) return key;
        return self.map.get(key);
    }

    fn clone(self: ConvMap) !ConvMap {
        return .{
            .parent = self.parent,
            .map = try self.map.clone()
        };
    }
};

const BlockMap = AutoHashMap(*Block, ConvMap);
const HasVar = struct { *bool, Var, *const Vars };
const StatisizeCtx = struct { *BlockMap, *usize, []const Var };
const Defs = struct {
    *const Vars,
    Var,
    *Set(*Block),
};

//pub fn calcVars(allocator: Allocator, function: Function) Allocator.Error!Vars {
//    var vars = Vars.init(allocator);
//
//    for (function.blocks.items) |*block| {
//        for (block.phis.items) |phi| {
//            const list = vars.getPtr(phi.dest) orelse b: {
//                try vars.put(phi.dest, Set(*Block).init(allocator));
//                break :b vars.getPtr(phi.dest).?;
//            };
//            try list.set(block);
//        }
//    
//        for (block.ops.items) |op| {
//            const dest = op.dest() orelse continue;
//            const list = vars.getPtr(dest) orelse b: {
//                try vars.put(dest, Set(*Block).init(allocator));
//                break :b vars.getPtr(dest).?;
//            };
//            try list.set(block);
//        }
//    }
//
//    return vars;
//}
//
//pub fn hasVar(allocator: Allocator, block: *Block, name: Var, vars: *const Vars) Allocator.Error!bool {
//    var has = false;
//    try markWalk(allocator, .{ &has, name, vars }, &.{block}, _hasVar);
//    return has;
//}
//
//fn _hasVar(allocator: Allocator, ctx: HasVar, working: Working, block: *Block) Allocator.Error!void {
//    _ = allocator;
//    const has, const name, const vars = ctx;
//
//    if (vars.get(name)) |set| {
//        if (set.contains(block)) {
//            has.* = true;
//            working.clear();
//            return;
//        }
//    }
//
//    try working.addSlice(block.preds.items());
//}
//
//pub fn placePhis(allocator: Allocator, vars: *const Vars) Allocator.Error!void {
//    var iter = vars.iterator();
//    while (iter.next()) |entry| {
//        const name = entry.key_ptr.*;
//        const blocks = entry.value_ptr;
//
//        var fronts = ArrayList(*Block).init(allocator);
//        for (blocks.items()) |block|
//            try fronts.appendSlice(block.fronts.items());
//
//        try markWalk(allocator, .{ vars, name, blocks }, fronts.items, _placePhis);
//    }
//}
//
//fn _placePhis(allocator: Allocator, ctx: Defs, working: Working, block: *Block) Allocator.Error!void {
//    const vars, const name, const blocks = ctx;
//
//    const fronts = block.fronts.items();
//    for (fronts) |front|
//        if (blocks.contains(block))
//            try working.add(front);
//
//    var args = ArrayList(PhiTarget).init(allocator);
//    for (block.preds.items()) |pred|
//        if (try hasVar(allocator, pred, name, vars))
//            try args.append(.{
//                .block = pred,
//                .temp = name,
//            });
//
//    // Prevent trivial case
//    if (args.items.len < 2) return;
//
//    try blocks.set(block);
//    try block.phis.append(.{
//        .dest = name,
//        .canon = name,
//        .args = args,
//    });
//}

// TODO: Add this to some type
fn newLocal(map: *ConvMap, name: *Var, count: *usize) Allocator.Error!void {
    if (name.scope == .global) return map.put(name.*, name.*);
    const v = .{
        .scope = .local,
        .access = name.access,
        .tag = .{ .local = count.* },
        .ty = name.ty,
    };
    try map.put(name.*, v);
    name.* = v;
    count.* += 1;
}

pub fn statisize(allocator: Allocator, function: Function) Allocator.Error!void {
    const prms = function.params;
    var params = try allocator.alloc(Var, prms.names.len);
    for (prms.names, prms.types, 0..) |name, ty, i|
        params[i] = .{
            .scope = .local,
            .access = .direct,
            .tag = .{ .named = name },
            .ty = ty,
        };

    var block_map = BlockMap.init(allocator);
    var count: usize = 0;
    try markWalk(allocator, .{ &block_map, &count, params }, &.{function.get(0)}, _statisize);

    //for (function.blocks.items) |block| {
    //    for (block.phis.items) |phi| {
    //        for (phi.args.items) |*arg| {
    //            if (!arg.temp.eql(phi.canon)) continue;
    //            const sub_map = block_map.get(arg.block).?;
    //            arg.temp = sub_map.get(phi.canon).?;
    //        }
    //    }
    //}
}

fn _statisize(allocator: Allocator, ctx: StatisizeCtx, working: Working, block: *Block) Allocator.Error!void {
    const block_map, const count, const params = ctx;
    const map = block_map.getPtr(block) orelse b: {
        try block_map.put(block, ConvMap.init(allocator));
        break :b block_map.getPtr(block).?;
    };

    for (params) |param|
        try map.put(param, param);

    //for (block.phis.items) |*phi| {
    //    try newLocal(map, &phi.dest, count);
    //}

    for (block.ops.items) |*op| {
        switch (op.*) {
            .Copy => |*t| {
                try newLocal(map, &t.dst, count);
                t.src = map.get(t.src).?;
            },
            .Alloc => |*t| {
                try newLocal(map, &t.dst, count);
            },
            .Load => |*t| {
                try newLocal(map, &t.dst, count);
                t.src = map.get(t.src).?;
            },
            .Store => |*t| {
                t.dst = map.get(t.dst).?;
                t.src = map.get(t.src).?;
            },
            .BinOp => |*t| {
                t.lhs = map.get(t.lhs).?;
                t.rhs = map.get(t.rhs).?;

                try newLocal(map, &t.dst, count);
            },
            .Call => |*t| {
                if (t.dest) |*dst|
                    try newLocal(map, dst, count);
                for (t.args, 0..) |arg, i|
                    t.args[i] = map.get(arg).?;
            },
            .Jnz => |*t| {
                t.cond = map.get(t.cond).?;
            },
            .Jmp => {},
            .Ret => |*v| {
                v.* = map.get(v.*).?;
            },
        }
    }

    // TODO: Pray that this is safe
    for (block.succs.items()) |succ| {
        if (block_map.getPtr(succ)) |sub_map| {
            var keys = sub_map.map.keyIterator();
            while (keys.next()) |key|
                if (map.get(key.*) == null)
                    sub_map.map.removeByPtr(key);
        } else {
            try block_map.put(succ, try map.clone());
        }
    }
    try working.addSlice(block.succs.items());
}
