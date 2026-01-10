const std = @import("std");

pub export fn sum(a: i32, b: i32) i32 {
    std.log.info("example.zig @ 3:14 - sum: {any}", .{.{ .a = a, .b = b }});
    return a + b;
}

pub fn main() !void {
    std.log.info("result is of 3 + 2 is {d}", .{sum(3, 2)});
}
