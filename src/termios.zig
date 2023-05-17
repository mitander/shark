const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;
const fs = std.fs;
const io = std.io;
const fmt = std.fmt;
const assert = std.debug.assert;

const ArrayList = std.ArrayList;
const Buffer = @import("buffer.zig").Buffer;

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

pub const Termios = struct {
    const Self = @This();
    orig_termios: os.termios = undefined,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) !Self {
        const VMIN = 5;
        const VTIME = 6;

        // copy "original" termios for restore
        var orig_termios = try os.tcgetattr(os.STDIN_FILENO);
        var termios = orig_termios;

        // non-blocking polling
        termios.cc[VMIN] = 0;
        // tenths of a second elapses between bytes
        termios.cc[VTIME] = 1;

        // input:   no break, no CR to NL, no parity check, no strip char, no start/stop output ctrl.
        // output:  disable post processing
        // control: set 8 bit chars
        // local:   choign off, canonical off, no extended functions, no signal chars (^Z, ^C)
        termios.iflag &= ~(os.darwin.BRKINT | os.darwin.ICRNL | os.darwin.ISTRIP | os.darwin.IXON);
        termios.oflag &= ~(os.darwin.OPOST);
        termios.cflag |= os.darwin.CS8;
        termios.lflag &= ~(os.darwin.ECHO | os.darwin.ICANON | os.darwin.IEXTEN | os.darwin.ISIG);
        _ = os.darwin.tcsetattr(os.STDIN_FILENO, .FLUSH, &termios);

        return .{
            .orig_termios = orig_termios,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) !void {
        _ = os.darwin.tcsetattr(os.STDIN_FILENO, .FLUSH, &self.orig_termios); // restore terminal
        _ = try os.write(os.STDOUT_FILENO, CURSOR_SHOW); // restore cursor
    }

    pub fn render(self: *Self, buffer: Buffer) !void {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try list.appendSlice(CLEAR_ALL ++ CURSOR_HIDE ++ "\x1b[H");
        try list.appendSlice(CURSOR_HIDE);
        try list.appendSlice("\x1b[H");

        var end: usize = if (buffer.offset + buffer.ws_row > buffer.rows.items.len) buffer.rows.items.len else buffer.offset + buffer.ws_row;
        assert(buffer.rows.items.len > 0);
        assert(end <= buffer.rows.items.len);

        for (buffer.rows.items[buffer.offset..end]) |item| {
            try list.appendSlice(item.render);
            try list.appendSlice("\r\n");
        }

        // draw cursor
        var buf: [32]u8 = undefined;
        try list.appendSlice(try fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ buffer.cursor_y + 1, buffer.cursor_x + 1 }));
        try list.appendSlice("\x1b[?25h");

        _ = try os.write(os.STDOUT_FILENO, list.items);
    }
};
