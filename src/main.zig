const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const ArrayList = std.ArrayList;

const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    raw_mode: bool = false,
    orig_termios: os.termios = undefined,
    file_path: []const u8,

    fn init(allocator: mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .file_path = undefined,
        };
    }

    fn open(self: *Self, file_path: []const u8) !void {
        self.file_path = file_path;

        const file = try std.fs.cwd().createFile(self.file_path, .{
            .read = true,
            .truncate = false,
        });
        defer file.close();

        var i: usize = 0;
        var file_bytes = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(u32));
        var it = std.mem.split(u8, file_bytes, "\n");
        while (it.next()) |line| {
            debug("{s}", .{line});
            i += 1;
        }

        return;
    }

    fn enableRawMode(self: *Self) !void {
        if (self.raw_mode) return;

        const VMIN = 5;
        const VTIME = 6;

        self.orig_termios = try os.tcgetattr(os.STDIN_FILENO);
        var termios = self.orig_termios;

        // input modes: no break, no CR to NL, no parity check, no strip char, no start/stop output ctrl.
        termios.iflag &= ~(os.darwin.BRKINT | os.darwin.ICRNL | os.darwin.INPCK | os.darwin.ISTRIP | os.darwin.IXON);
        // output modes: disable post processing
        termios.oflag &= ~(os.darwin.OPOST);
        // control modes: set 8 bit chars
        termios.cflag |= os.darwin.CS8;
        // local modes: choign off, canonical off, no extended functions, no signal chars (^Z, ^C)
        termios.lflag &= ~(os.darwin.ECHO | os.darwin.ICANON | os.darwin.IEXTEN | os.darwin.ISIG);
        termios.cc[VMIN] = 0;
        termios.cc[VTIME] = 1;

        _ = os.darwin.tcsetattr(os.darwin.STDIN_FILENO, .FLUSH, &termios);
        self.raw_mode = true;
    }

    fn disableRawMode(self: *Self) !void {
        if (self.raw_mode) {
            _ = os.darwin.tcsetattr(os.darwin.STDIN_FILENO, .FLUSH, &self.orig_termios);
            self.raw_mode = false;
        }
    }
};

pub fn main() !void {
    const stdin = std.io.getStdOut().reader();
    _ = stdin;
    var buf: [100]u8 = undefined;
    _ = buf;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var editor = try Editor.init(allocator);
    try editor.enableRawMode();
    defer editor.disableRawMode() catch unreachable;

    try editor.open("./src/main.zig");

    // while (true) {
    //     if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
    //         switch (input[0]) {
    //             'q' => {
    //                 debug("quitting..", .{});
    //                 break;
    //             },
    //             else => debug("{s}", .{input}),
    //         }
    //     } else {
    //         break;
    //     }
    // }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
