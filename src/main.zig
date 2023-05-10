const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const ArrayList = std.ArrayList;

const Row = struct {
    src: []u8,
    render: []u8,
};

const Terminal = struct {
    const Self = @This();
    orig_termios: os.termios = undefined,
    raw_mode: bool = false,
    allocator: std.mem.Allocator,
    cols: u16,
    rows: u16,
    in: std.fs.File,
    out: std.fs.File,

    fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .orig_termios = try os.tcgetattr(os.STDIN_FILENO),
            .raw_mode = false,
            .allocator = allocator,
            .rows = 0,
            .cols = 0,
            .in = std.io.getStdIn(),
            .out = std.io.getStdOut(),
        };
    }

    fn update(self: *Self) !void {
        var winsize: std.os.darwin.winsize = undefined;
        const err = std.os.darwin.ioctl(self.in.handle, std.os.darwin.T.IOCGWINSZ, @ptrToInt(&winsize));
        if (std.os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.cols = winsize.ws_col;
        self.rows = winsize.ws_row;
    }

    fn enableRawMode(self: *Self) !void {
        if (self.raw_mode) return;

        const VMIN = 5;
        const VTIME = 6;

        // Copy "original" termios for reset
        var termios = self.orig_termios;

        // input modes: no break, no CR to NL, no parity check, no strip char, no start/stop output ctrl.
        // output modes: disable post processing
        // control modes: set 8 bit chars
        // local modes: choign off, canonical off, no extended functions, no signal chars (^Z, ^C)
        termios.iflag &= ~(os.darwin.BRKINT | os.darwin.ICRNL | os.darwin.INPCK | os.darwin.ISTRIP | os.darwin.IXON);
        termios.oflag &= ~(os.darwin.OPOST);
        termios.cflag |= os.darwin.CS8;
        termios.lflag &= ~(os.darwin.ECHO | os.darwin.ICANON | os.darwin.IEXTEN | os.darwin.ISIG);

        termios.cc[VMIN] = 0;
        termios.cc[VTIME] = 1;

        _ = os.darwin.tcsetattr(os.darwin.STDIN_FILENO, .FLUSH, &termios);
        self.raw_mode = true;
    }

    fn disableRawMode(self: *Self) void {
        if (self.raw_mode) {
            _ = os.darwin.tcsetattr(os.darwin.STDIN_FILENO, .FLUSH, &self.orig_termios);
            self.raw_mode = false;
        }
    }
};

const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    file_path: []const u8,
    rows: ArrayList(Row),
    terminal: Terminal,

    fn init(allocator: mem.Allocator) !Self {
        var term = try Terminal.init(allocator);
        try term.enableRawMode();

        return .{
            .allocator = allocator,
            .file_path = undefined,
            .rows = ArrayList(Row).init(allocator),
            .terminal = term,
        };
    }

    fn deinit(self: *Self) !void {
        for (self.rows.items) |item| {
            self.allocator.free(item.src);
            self.allocator.free(item.render);
        }
        self.rows.deinit();

        _ = try os.write(os.darwin.STDOUT_FILENO, "\x1b[?25h"); // Restore cursor
        self.terminal.disableRawMode();
    }

    fn open(self: *Self, file_path: []const u8) !void {
        self.file_path = file_path;

        const file = try std.fs.cwd().createFile(self.file_path, .{ .read = true, .truncate = false });
        defer file.close();

        var file_bytes = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(u32));
        defer self.allocator.free(file_bytes);
        var it = std.mem.split(u8, file_bytes, "\n");

        var index: u8 = 0;
        while (it.next()) |line| {
            try self.rows.insert(index, .{
                .src = try self.allocator.dupe(u8, line),
                .render = try self.allocator.dupe(u8, line),
            });
            index += 1;
        }
    }

    fn readKey(self: *Self) !u8 {
        var seq = try self.allocator.alloc(u8, 1);
        defer self.allocator.free(seq);
        _ = try os.read(os.darwin.STDIN_FILENO, seq);
        return seq[0];
    }

    fn render(self: *Self) !void {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try self.terminal.update();

        // hide cursor
        try list.appendSlice("\x1b[?25l");
        try list.appendSlice("\x1b[H");

        for (self.rows.items) |item| {
            try list.appendSlice(item.src);
            try list.appendSlice("\r\n");
        }
        _ = try os.write(os.darwin.STDOUT_FILENO, list.items);
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

    try editor.open(file_path);

    while (true) {
        try editor.render();
        const key = try editor.readKey();
        switch (key) {
            'q' => {
                debug("quitting..", .{});
                break;
            },
            else => debug("{any}", .{key}),
        }
    }
}
