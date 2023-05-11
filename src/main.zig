const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;

const ArrayList = std.ArrayList;

// VT100 escape codes
const ESC = "\x1B";
const CSI = ESC ++ "[";
const STYLE_RESET = CSI ++ "0m";
const STYLE_BOLD = CSI ++ "1m";
const STYLE_DIM = CSI ++ "2m";
const STYLE_ITALIC = CSI ++ "3m";
const STYLE_UNDERLINE = CSI ++ "4m";
const STYLE_REVERSE = CSI ++ "7m";
const STYLE_STRIKETHROUGH = CSI ++ "9m";
const CLEAR_ALL = CSI ++ "2J";
const CURSOR_HIDE = CSI ++ "?25l";
const CURSOR_SHOW = CSI ++ "?25h";

const Row = struct {
    src: []u8,
    render: []u8,
};

const Terminal = struct {
    const Self = @This();
    orig_termios: os.termios = undefined,
    raw_mode: bool = false,
    allocator: std.mem.Allocator,
    offset: u16,
    cols: u16,
    rows: u16,
    in: std.fs.File,
    out: std.fs.File,
    ansi_escape_codes: bool,

    fn init(allocator: std.mem.Allocator) !Self {
        const VMIN = 5;
        const VTIME = 6;

        // copy "original" termios for reset
        var orig_termios = try os.tcgetattr(os.STDIN_FILENO);
        var termios = orig_termios;

        var out = std.io.getStdOut();

        // TODO: make this work for all platforms
        termios.cc[VMIN] = 0;
        termios.cc[VTIME] = 1;

        // input modes:   no break, no CR to NL, no parity check, no strip char, no start/stop output ctrl.
        // output modes:  disable post processing
        // control modes: set 8 bit chars
        // local modes:   choign off, canonical off, no extended functions, no signal chars (^Z, ^C)
        termios.iflag &= ~(os.darwin.BRKINT | os.darwin.ICRNL | os.darwin.INPCK | os.darwin.ISTRIP | os.darwin.IXON);
        termios.oflag &= ~(os.darwin.OPOST);
        termios.cflag |= os.darwin.CS8;
        termios.lflag &= ~(os.darwin.ECHO | os.darwin.ICANON | os.darwin.IEXTEN | os.darwin.ISIG);
        _ = os.darwin.tcsetattr(out.handle, .FLUSH, &termios);

        return .{
            .orig_termios = orig_termios,
            .raw_mode = false,
            .allocator = allocator,
            .offset = 0,
            .rows = 0,
            .cols = 0,
            .in = std.io.getStdIn(),
            .out = out,
            .ansi_escape_codes = out.supportsAnsiEscapeCodes(),
        };
    }

    fn deinit(self: *Self) !void {
        _ = try os.write(self.out.handle, CURSOR_SHOW); // restore cursor
        _ = os.darwin.tcsetattr(self.in.handle, .FLUSH, &self.orig_termios); // restore terminal
    }

    fn render(self: *Self, rows: []Row) !void {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try self.updateWindowSize();
        try list.appendSlice(CLEAR_ALL);
        try list.appendSlice(CURSOR_HIDE);
        try list.appendSlice("\x1b[H"); // TODO: what dis do?

        for (rows[self.offset .. self.offset + self.rows]) |item| {
            try list.appendSlice(item.src);
            try list.appendSlice("\r\n");
        }
        _ = try os.write(self.out.handle, list.items);
    }

    fn updateWindowSize(self: *Self) !void {
        var winsize: std.os.darwin.winsize = undefined;
        const err = std.os.darwin.ioctl(self.in.handle, std.os.darwin.T.IOCGWINSZ, @ptrToInt(&winsize));
        if (std.os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.cols = winsize.ws_col;
        self.rows = winsize.ws_row - 1; // TODO: why is this required to render first row?
    }
};

const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    file_path: []const u8,
    rows: ArrayList(Row),
    terminal: Terminal,

    fn init(allocator: mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .file_path = undefined,
            .rows = ArrayList(Row).init(allocator),
            .terminal = try Terminal.init(allocator),
        };
    }

    fn deinit(self: *Self) !void {
        for (self.rows.items) |item| {
            self.allocator.free(item.src);
            self.allocator.free(item.render);
        }
        self.rows.deinit();

        try self.terminal.deinit();
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

    fn refresh(self: *Self) !void {
        try self.terminal.render(self.rows.items);
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
        try editor.refresh();
        const key = try editor.readKey();
        switch (key) {
            'q' => {
                debug("quitting..", .{});
                break;
            },
            'j' => {
                if (editor.terminal.offset < editor.rows.items.len - editor.terminal.rows) editor.terminal.offset += 1;
            },
            'k' => {
                if (editor.terminal.offset > 0) editor.terminal.offset -= 1;
            },
            else => debug("{any}", .{key}),
        }
    }
}
