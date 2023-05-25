const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const Mode = @import("editor.zig").Mode;
const Editor = @import("editor.zig").Editor;
const Direction = @import("editor.zig").Direction;

const Key = enum(u8) {
    ESC = 27,
    BACKSPACE = 127,
    _,
};

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
        switch (editor.mode) {
            .NORMAL => {
                switch (try editor.readKey()) {
                    'q' => break, // quit
                    'j' => editor.moveCursor(Direction.Down),
                    'k' => editor.moveCursor(Direction.Up),
                    'h' => editor.moveCursor(Direction.Left),
                    'l' => editor.moveCursor(Direction.Right),
                    'x' => try editor.buffer.delete(editor.buffer.cursor_x),
                    'i' => editor.mode = Mode.INSERT,
                    else => continue,
                }
            },
            .INSERT => {
                var key = try editor.readKey();
                switch (@intToEnum(Key, key)) {
                    .ESC => editor.mode = Mode.NORMAL,
                    .BACKSPACE => if (editor.buffer.cursor_x > 0) try editor.buffer.delete(editor.buffer.cursor_x - 1),
                    else => try editor.buffer.insert(key),
                }
            },
        }
    }
}
