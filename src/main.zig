const std = @import("std");
const os = std.os;

pub fn main() !void {
    const stdin = std.io.getStdOut().reader();
    var buf: [100]u8 = undefined;

    while (true) {
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            switch (input[0]) {
                'q' => {
                    std.log.debug("quitting..", .{});
                    break;
                },
                else => std.log.debug("{s}", .{input}),
            }
        } else {
            break;
        }
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
