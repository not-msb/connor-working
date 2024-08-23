const std = @import("std");
const lib = @import("lib.zig");
const cwd = std.fs.cwd;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Ast = lib.ast.Ast;
const Block = lib.ir.Block;
const Function = lib.ir.Function;
const Cursor = lib.Cursor;
const Context = lib.Context;
const Var = lib.Var;
const Token = lib.token.Token;
const Error = lib.Error;

fn handleError(filename: []const u8, input: []const u8, err: Error) void {
    const loc = lib.global_error;
    var offset: usize = 0;

    for (0..loc.row - 1) |_| {
        while (input[offset] != '\n') offset += 1 else offset += 1;
    }

    var end = offset;
    while (input[end] != '\n') end += 1 else end += 1;

    std.debug.print("{} in {s}:{d}:{d}:\n", .{err, filename, loc.row, loc.col});
    std.debug.print("    {s}", .{input[offset..end]});
    for (0..loc.col - 1) |_|
        std.debug.print(" ", .{});
    std.debug.print("    ^\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next().?;
    const filename = args.next() orelse {
        std.debug.print("Usage: ./connor {{filename}}\n", .{});
        return;
    };

    const input = try cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
    const tokens = try Token.parse(allocator, input);

    const file = Ast.parse(allocator, tokens) catch |err| {
        handleError(filename, input, err);
        return;
    };

    try file.scan(allocator);
    // TODO: Actually make handling somewhat good
    //file.scan(allocator) catch |err| {
    //    handleError(filename, input, err);
    //    return;
    //};

    for (file.functions) |*function| {
        if (function.attr.is_comptime)
            continue;
        try function.actualInit();
    }

    for (file.functions) |function| {
        if (function.attr.is_comptime)
            continue;
        try function.debugPrint();
    }
}
