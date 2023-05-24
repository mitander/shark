const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const Editor = @import("editor.zig").Editor;
const Direction = @import("editor.zig").Direction;

pub fn main() !void {
    var args = std.process.args();
    _ = args.next(); // ignore binary name

    var file_path = args.next() orelse {
        std.debug.print("Usage: shark [filename]\n", .{});
        return error.NoFileName;
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var editor = try Editor.init(allocator);
    defer editor.deinit() catch unreachable;

    try editor.openFile(file_path);

    while (true) {
        try editor.refresh();
        switch (try editor.readKey()) {
            'q' => {
                break;
            },
            'j' => editor.moveCursor(Direction.Down),
            'k' => editor.moveCursor(Direction.Up),
            'h' => editor.moveCursor(Direction.Left),
            'l' => editor.moveCursor(Direction.Right),
            'i' => while (true) {
                var key: u8 = try editor.readKey();
                switch (key) {
                    'q' => break,
                    127 => {
                        try editor.buffer.delete();
                    },
                    else => {
                        try editor.buffer.insert(key);
                    },
                }
                try editor.refresh();
            },
            'x' => try editor.buffer.delete(),
            else => continue,
        }
    }
}
