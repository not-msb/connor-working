const std = @import("std");
const Allocator = std.mem.Allocator;
const TailQueue = std.TailQueue;

pub fn Queue(comptime T: type) type {
    return struct {
        allocator: Allocator,
        queue: TailQueue(T),

        const Self = Queue(T);
        const Node = TailQueue(T).Node;

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .queue = .{},
            };
        }

        pub fn add(self: *Self, item: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.data = item;
            self.queue.append(node);
        }

        pub fn addSlice(self: *Self, items: []const T) Allocator.Error!void {
            for (items) |item|
                try self.add(item);
        }

        pub fn pop(self: *Self) ?T {
            const first = self.queue.popFirst() orelse return null;
            return first.data;
        }

        pub fn clear(self: *Self) void {
            while (self.pop()) |_| {}
        }
    };
}
