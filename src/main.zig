const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const Termios = @import("termios.zig").Termios;
const Buffer = @import("buffer.zig").Buffer;

pub const Direction = enum(u8) { Up, Down, Left, Right };

const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    termios: Termios,
    buffer: Buffer,

    fn init(allocator: mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .buffer = Buffer.init(allocator),
            .termios = try Termios.init(allocator),
        };
    }

    fn deinit(self: *Self) !void {
        try self.termios.deinit();
        self.buffer.deinit();
    }

    fn openFile(self: *Self, file_path: []const u8) !void {
        try self.buffer.openFile(file_path);
    }

    fn readKey(self: *Self) !u8 {
        var seq = try self.allocator.alloc(u8, 1);
        defer self.allocator.free(seq);
        _ = try os.read(os.darwin.STDIN_FILENO, seq);
        return seq[0];
    }

    fn refresh(self: *Self) !void {
        try self.buffer.updateWindowSize();
        try self.termios.render(self.buffer);
    }
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
        switch (try editor.readKey()) {
            'q' => {
                break;
            },
            'j' => editor.buffer.moveCursor(Direction.Down),
            'k' => editor.buffer.moveCursor(Direction.Up),
            'h' => editor.buffer.moveCursor(Direction.Left),
            'l' => editor.buffer.moveCursor(Direction.Right),
            'i' => while (true) {
                var key: u8 = try editor.readKey();
                if (key == 'q') {
                    break;
                }
                try editor.buffer.insert(key);
                try editor.refresh();
            },
            else => continue,
        }
    }
}
