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

pub const Direction = enum(u8) { Up, Down, Left, Right };

pub const Cursor = struct {
    x: u8,
    y: u8,
};

const Row = struct {
    src: []u8,
    render: []u8,
};

pub const Buffer = struct {
    const Self = @This();
    allocator: mem.Allocator,
    rows: ArrayList(Row),
    offset: u16,
    ws_row: u16,
    ws_col: u16,
    cursor_y: u16,
    cursor_x: u16,
    file_path: []const u8,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .rows = ArrayList(Row).init(allocator),
            .offset = 0,
            .ws_col = 0,
            .ws_row = 0,
            .cursor_y = 0,
            .cursor_x = 0,
            .file_path = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.rows.items) |item| {
            self.allocator.free(item.src);
            self.allocator.free(item.render);
        }
        self.rows.deinit();
    }

    pub fn insertRow(self: *Self, index: usize, item: []const u8) !void {
        try self.rows.insert(index, .{
            .src = try self.allocator.dupe(u8, item),
            .render = try self.allocator.dupe(u8, item),
        });
    }

    pub fn openFile(self: *Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{ .read = true, .truncate = false });
        defer file.close();

        var file_bytes = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(u32));
        defer self.allocator.free(file_bytes);

        var it = std.mem.split(u8, file_bytes, "\n");
        var index: usize = 0;
        while (it.next()) |line| {
            try self.insertRow(index, line);
            index += 1;
        }
    }

    pub fn moveCursor(self: *Self, dir: Direction) void {
        switch (dir) {
            .Left => {
                if (self.cursor_x > 0) {
                    self.cursor_x -= 1;
                }
            },
            .Right => {
                if (self.cursor_x < self.ws_col) {
                    self.cursor_x += 1;
                }
            },
            .Up => {
                if (self.cursor_y > 0) {
                    self.cursor_y -= 1;
                } else if (self.offset > 0) {
                    self.offset -= 1;
                }
            },
            .Down => {
                if (self.cursor_y < self.ws_row) {
                    self.cursor_y += 1;
                } else if (self.offset < self.rows.items.len - self.ws_row) {
                    self.offset += 1;
                }
            },
        }
    }

    pub fn updateWindowSize(self: *Self) !void {
        var winsize: std.os.darwin.winsize = undefined;
        const err = std.os.darwin.ioctl(os.STDOUT_FILENO, std.os.darwin.T.IOCGWINSZ, @ptrToInt(&winsize));
        if (std.os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.ws_col = winsize.ws_col;
        self.ws_row = winsize.ws_row - 1; // TODO : why is this required to render first row?
    }
};

pub const Terminal = struct {
    const Self = @This();
    orig_termios: os.termios = undefined,
    raw_mode: bool = false,
    allocator: std.mem.Allocator,
    in: std.fs.File,
    out: std.fs.File,
    ansi_escape_codes: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
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
            .in = std.io.getStdIn(),
            .out = out,
            .ansi_escape_codes = out.supportsAnsiEscapeCodes(),
        };
    }

    pub fn deinit(self: *Self) !void {
        _ = try os.write(self.out.handle, CURSOR_SHOW); // restore cursor
        _ = os.darwin.tcsetattr(self.in.handle, .FLUSH, &self.orig_termios); // restore terminal
    }

    pub fn render(self: *Self, buffer: Buffer) !void {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try list.appendSlice(CLEAR_ALL ++ CURSOR_HIDE ++ "\x1b[H");
        try list.appendSlice(CURSOR_HIDE);
        try list.appendSlice("\x1b[H");

        for (buffer.rows.items[buffer.offset .. buffer.offset + buffer.ws_row]) |item| {
            try list.appendSlice(item.src);
            try list.appendSlice("\r\n");
        }

        // draw cursor
        var buf: [32]u8 = undefined;
        try list.appendSlice(try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ buffer.cursor_y, buffer.cursor_x }));
        try list.appendSlice("\x1b[?25h");

        _ = try os.write(self.out.handle, list.items);
    }
};
