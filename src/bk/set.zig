const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoArrayHashMap = std.AutoArrayHashMap;
const ArrayList = std.ArrayList;

pub fn Set(comptime T: type) type {
    return struct {
        map: AutoArrayHashMap(T, void),

        pub fn init(allocator: Allocator) Set(T) {
            return .{
                .map = AutoArrayHashMap(T, void).init(allocator),
            };
        }

        pub fn deinit(self: *Set(T)) void {
            self.map.deinit();
        }

        pub fn clone(self: *const Set(T)) Allocator.Error!Set(T) {
            return .{
                .map = try self.map.clone(),
            };
        }

        pub fn count(self: *const Set(T)) usize {
            return self.map.count();
        }

        pub fn set(self: *Set(T), key: T) Allocator.Error!void {
            return self.map.put(key, undefined);
        }

        pub fn get(self: *const Set(T), key: T) bool {
            return self.map.get(key) != null;
        }

        pub fn contains(self: *const Set(T), key: T) bool {
            return self.map.contains(key);
        }

        pub fn items(self: *const Set(T)) []T {
            return self.map.keys();
        }

        pub fn intersection(self: Set(T), other: Set(T)) Allocator.Error!Set(T) {
            var out = Set(T).init(self.map.allocator);
            const slice = self.items();
            for (slice) |item|
                if (other.get(item)) try out.set(item);
            return out;
        }

        pub fn eql(self: Set(T), other: Set(T)) bool {
            if (self.map.count() != other.map.count()) return false;

            const slice = self.items();
            for (slice) |item|
                if (!other.get(item)) return false;
            return true;
        }

        fn expectEqual(self: Set(T), other: Set(T)) error{TestExpectedEqual}!void {
            if (self.map.count() != other.map.count())
                std.debug.panic("The given sets are NOT the same size", .{});

            const l_items = self.items();
            const r_items = other.items();

            for (l_items, r_items) |l, r| {
                try std.testing.expectEqualDeep(l, r);
            }
        }
    };
}

test "intersection" {
    const allocator = std.testing.allocator;

    var a = try Set(u8).initFrom(allocator, &.{ 1, 2, 3 });
    defer a.deinit();

    var b = try Set(u8).initFrom(allocator, &.{ 2, 3, 4 });
    defer b.deinit();

    var c = try Set(u8).initFrom(allocator, &.{ 2, 3 });
    defer c.deinit();

    var d = try a.intersection(b);
    defer d.deinit();
    try c.expectEqual(d);
}
