const std = @import("std");
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const Function = lib.ir.Function;
const Error = lib.Error;
const File = lib.ast.File;
const Ast = lib.ast.Ast;
const Type = lib.Type;
const Var = lib.Var;

pub const Context = struct {
    funcs: StringHashMap(*const Function),
    map: StringHashMap(Var),
    locals: AutoHashMap(usize, Var),
    count: *usize,

    parent: ?*Context = null,
    ret: ?Type = null,

    pub fn init(file: *const File, allocator: Allocator) Allocator.Error!Context {
        var funcs = StringHashMap(*const Function).init(allocator);
        for (file.functions) |*function|
            try funcs.put(function.name, function);

        return .{
            .funcs = funcs,
            .map = StringHashMap(Var).init(allocator),
            .locals = AutoHashMap(usize, Var).init(allocator),
            .count = try lib.box(allocator, @as(usize, 0)),
            .ret = null,
        };
    }

    pub fn child(self: *Context, ret: ?Type) Allocator.Error!*Context {
        const context: Context = .{
            .funcs = self.funcs,
            .map = StringHashMap(Var).init(self.map.allocator),
            .locals = AutoHashMap(usize, Var).init(self.map.allocator),
            .count = self.count,
            .parent = self,
            .ret = ret orelse self.ret,
        };
        return lib.box(self.map.allocator, context);
    }

    pub fn lvalue(self: *const Context, key: []const u8) ?Var {
        const value = self.get(key) orelse return null;
        var dst = value;
        dst.tag = .{ .named = key };
        return dst;
    }

    pub fn get(self: *const Context, key: []const u8) ?Var {
        return self.map.get(key) orelse if (self.parent) |parent| parent.get(key) else null;
    }

    pub fn getLocal(self: *const Context, key: usize) ?Var {
        return self.locals.get(key) orelse if (self.parent) |parent| parent.getLocal(key) else null;
    }

    pub fn put(self: *Context, key: []const u8, value: Var) Allocator.Error!void {
        // Temp, a bit looser
        // TODO: Make strict again
        //return self.map.putNoClobber(key, value);
        return self.map.put(key, value);
    }
    pub fn putLocal(self: *Context, key: usize, value: Var) Allocator.Error!void {
        return self.locals.put(key, value);
    }

    // Weird name ik, will probs never get to fixing it 
    pub fn resolve(self: *const Context, tag: Var.Tag) Var {
        return switch (tag) {
            .named => |v| self.get(v) orelse std.debug.panic("named: {s}", .{v}),
            .local => |v| self.getLocal(v) orelse std.debug.panic("local: {d}", .{v}),
            // probs very reachable
            // it was (x1)
            else => {
                std.debug.panic("tag: {}", .{tag});
                unreachable;
            },
        };
    }

    pub fn newVar(self: *Context, access: Var.Access, ty: Type) Var {
        const v = .{
            .scope = .local,
            .access = access,
            .tag = .{ .local = self.count.* },
            .ty = ty,
        };

        self.putLocal(self.count.*, v) catch unreachable;
        self.count.* += 1;
        return v;
    }

    pub fn check(self: *Context, expr: *Ast) Error!Type {
        switch (expr.*) {
            .Integer => return .CompInt,
            .Identifier => |v| {
                const symbol = self.get(v) orelse return Error.NonExistent;
                return symbol.ty;
            },
            .Type => return .Type,
            .Deref => |v| {
                const ty = try self.check(v);
                return switch (ty) {
                    .Ptr => |pv| pv.*,
                    else => Error.TypeNonPointer,
                };
            },
            .Assign => |t| {
                const src = try self.check(t.src);
                const dst = try self.check(t.dst);

                // TODO: remove this, when adding consts as defgault
                if (dst == .Type)
                    std.debug.panic("Ay sorry bruv, cant mutate types", .{});

                if (!src.coercible(dst)) return Error.TypeIncompatible;
                return dst;
            },
            .BinOp => |t| {
                const lhs = try self.check(t.lhs);
                const rhs = try self.check(t.rhs);
                switch (t.kind) {
                    .Add, .Sub, .Mul => {
                        if (!(lhs.isNumeric() or rhs.isNumeric())) return Error.TypeArithmeticNonInteger;
                        if (!lhs.compatible(rhs)) return Error.TypeIncompatible;
                        return Type.maxNumeric(lhs, rhs).?;
                    },
                    .Eq, .Ne => {
                        if (!lhs.compatible(rhs)) return Error.TypeIncompatible;
                        return .Bool;
                    },
                }
            },
            .If => |t| {
                const cond = try self.check(t.cond);
                const succ = try self.check(t.succ);
                const fail = try self.check(t.fail);
                if (!cond.coercible(.Bool)) return Error.TypeIncompatible;
                if (!fail.compatible(succ)) return Error.TypeIncompatible;

                return Type.maxNumeric(succ, fail) orelse succ;
            },
            .While => |t| {
                const cond = try self.check(t.cond);
                const body = try self.check(t.body);
                if (!cond.coercible(.Bool)) return Error.TypeIncompatible;
                _ = body;
                return .Void;
            },
            .Call => |t| {
                const func = try self.check(t.name);
                const prms, const ret = switch (func) {
                    .Function => |t2| .{ t2.params, t2.ret },
                    else => return Error.TypeNonFunction,
                };

                for (t.args, 0..) |*arg, i| {
                    const ty = try self.check(arg);
                    if (!ty.coercible(prms[i]))
                        return Error.TypeIncompatible;
                }

                return ret.*;
            },
            .Block => |*t| {
                t.ctx = try self.child(null);

                var ret: Type = .Void;
                for (t.body) |*e| {
                    switch (e.*) {
                        .Ast => |*v| {
                            const ty = try t.ctx.check(v);
                            if (ty == .NoReturn) ret = .NoReturn;
                        },
                        .Declare => |t2| {
                            const src = try t.ctx.check(t2.src);
                            const value = try t2.ty.eval(t.ctx);
                            std.debug.assert(value.ty == .Type);
                            const ty = value.tag.ty;

                            if (self.get(t2.dst)) |_|
                                return Error.Unrewritable;

                            const tag = switch (ty) {
                                .Type => b: {
                                    const val = try t2.src.eval(t.ctx);
                                    break :b Var.Tag{ .ty = val.tag.ty };
                                },
                                else => .none,
                            };

                            // TODO: replace with an actual "is_comptime" check
                            const scope: Var.Scope = switch (ty) {
                                .Type => .compile_time,
                                else => .local,
                            };

                            const dst = .{
                                .scope = scope,
                                .access = .deferred,
                                .tag = tag,
                                .ty = ty,
                            };

                            try t.ctx.put(t2.dst, dst);
                            if (!src.coercible(ty)) return Error.TypeIncompatible;
                        },
                    }
                }
                return ret;
            },
            .Return => |v| {
                const ty = try self.check(v);
                const ret = self.ret orelse return Error.NonReturnCtx;
                if (!ty.coercible(ret)) return Error.TypeIncompatible;
                return .NoReturn;
            },
        }
    }
};
