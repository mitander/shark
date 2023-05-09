const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const ArrayList = std.ArrayList;

const Row = struct {
    src: []u8,
    render: []u8,
};

const Window = struct {
    width: u16,
    height: u16,
};

const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    raw_mode: bool = false,
    orig_termios: os.termios = undefined,
    file_path: []const u8,
    window: Window,
    rows: ArrayList(Row),

    fn init(allocator: mem.Allocator) !Self {
        var self = Self{
            .allocator = allocator,
            .file_path = undefined,
            .window = .{ .width = 0, .height = 0 },
            .rows = ArrayList(Row).init(allocator),
        };
        try self.enableRawMode();
        return self;
    }
    fn deinit(self: *Self) void {
        self.disableRawMode() catch unreachable;
        for (self.rows.items) |item| {
            self.allocator.free(item.src);
            self.allocator.free(item.render);
        }
        self.rows.deinit();
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
            var row = Row{
                .src = try self.allocator.dupe(u8, line),
                .render = try self.allocator.dupe(u8, line),
            };

            try self.rows.insert(index, row);
            index += 1;
        }
        return;
    }

    fn enableRawMode(self: *Self) !void {
        if (self.raw_mode) return;

        const VMIN = 5;
        const VTIME = 6;

        // Copy "original" termios for reset
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

    fn getWinSize(self: *Self, handle: std.os.fd_t) !void {
        var window_size: std.os.darwin.winsize = undefined;
        const err = std.os.darwin.ioctl(handle, std.os.darwin.T.IOCGWINSZ, @ptrToInt(&window_size));
        if (std.os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.window = .{ .width = window_size.ws_col, .height = window_size.ws_row };
    }

    fn draw(self: *Self) !void {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try list.appendSlice("\x1b[?25l"); // Hide cursor
        try list.appendSlice("\x1b[H");

        for (self.rows.items) |item| {
            try list.appendSlice(item.src);
            try list.appendSlice("\r\n");
        }
        _ = try os.write(os.darwin.STDOUT_FILENO, list.items);
        var in = std.io.getStdIn();
        try self.getWinSize(in.handle);
        debug("{any}", .{self.window.width});
    }

    fn readKey(self: *Self) !u8 {
        var seq = try self.allocator.alloc(u8, 1);
        defer self.allocator.free(seq);
        _ = try os.read(os.darwin.STDIN_FILENO, seq);
        return seq[0];
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.open("./src/main.zig");

    while (true) {
        try editor.draw();
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
