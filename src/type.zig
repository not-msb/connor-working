const lib = @import("lib.zig");
const Function = lib.ir.Function;

pub const Type = union(enum) {
    Type,
    Function: struct {
        params: []const Type,
        ret: *const Type,
    },
    Ptr: *const Type,
    Void,
    NoReturn,
    Bool,
    CompInt,
    U8,
    U32,
    U64,

    pub fn size(self: Type) ?usize {
        return switch (self) {
            .Function, .Ptr => 8,
            .Void => 0,
            .Bool => 1,
            .U8 => 1,
            .U32 => 4,
            .U64, .CompInt => 8,
            else => 0,
            //else => |s| @import("std").debug.panic("S: {}", .{s}),
        };
    }

    pub fn isNumeric(self: Type) bool {
        return switch (self) {
            .U8, .U32, .U64, .CompInt => true,
            else => false,
        };
    }

    pub fn maxNumeric(self: Type, rhs: Type) ?Type {
        if (!(self.isNumeric() or rhs.isNumeric())) return null;
        if (self == .CompInt) return rhs;
        if (rhs == .CompInt) return self;
        return if (self.size().? >= rhs.size().?) self else rhs;
    }

    pub fn eql(self: Type, rhs: Type) bool {
        return switch (self) {
            .Function => |t| {
                if (rhs != .Function) return false;
                const u = rhs.Function;

                if (!t.ret.eql(u.ret.*)) return false;
                for (t.params, u.params) |tp, up|
                    if (!tp.eql(up)) return false;

                return true;
            },
            .Ptr => |v| rhs == .Ptr and v.eql(rhs.Ptr.*),
            .Type => rhs == .Type,
            .Void => rhs == .Void,
            .Bool => rhs == .Bool,
            .U8 => rhs == .U8,
            .U32 => rhs == .U32,
            .U64 => rhs == .U64,
            .CompInt => rhs == .CompInt,
            else => false,
        };
    }

    pub fn coercible(self: Type, rhs: Type) bool {
        if (self.eql(rhs)) return true;

        return switch (self) {
            .NoReturn => true,
            .CompInt => rhs.isNumeric(),
            else => false,
        };
    }

    pub fn compatible(self: Type, rhs: Type) bool {
        return self.coercible(rhs) or rhs.coercible(self);
    }

    pub fn fmtBase(self: Type) ?[]const u8 {
        return switch (self) {
            .Function => "l",
            .Ptr => "l",
            .Void => "",
            .Bool => "w",
            .U8 => "w",
            .U32 => "w",
            .U64 => "l",
            .CompInt => "l",
            //else => null,
            else => "???",
        };
    }

    pub fn fmtAbi(self: Type) ?[]const u8 {
        return switch (self) {
            .Function => "l",
            .Ptr => "l",
            .Void => "",
            .Bool => "ub",
            .U8 => "ub",
            .U32 => "w",
            .U64 => "l",
            .CompInt => "l",
            //else => null,
            else => "???",
        };
    }
};
