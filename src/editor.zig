const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;
const assert = std.debug.assert;

const Termios = @import("termios.zig").Termios;
const Buffer = @import("buffer.zig").Buffer;

pub const Direction = enum(u8) { Up, Down, Left, Right };

pub const Mode = enum(u8) { NORMAL, INSERT };

pub const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    termios: Termios,
    buffer: Buffer,
    mode: Mode,

    pub fn init(allocator: mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .buffer = Buffer.init(allocator),
            .termios = try Termios.init(allocator),
            .mode = Mode.NORMAL,
        };
    }

    pub fn deinit(self: *Self) !void {
        try self.termios.deinit();
        self.buffer.deinit();
    }

    pub fn open_file(self: *Self, file_path: []const u8) !void {
        try self.buffer.open_file(file_path);
    }

    pub fn read_key(self: *Self) !u8 {
        var seq = try self.allocator.alloc(u8, 1);
        defer self.allocator.free(seq);
        _ = try os.read(os.darwin.STDIN_FILENO, seq);
        return seq[0];
    }

    pub fn refresh(self: *Self) !void {
        try self.termios.render(&self.buffer);
    }

    pub fn move_cursor(self: *Self, dir: Direction) void {
        var cursor_x = self.buffer.cursor_x;
        var cursor_y = self.buffer.cursor_y;
        var cursor_col = self.buffer.cursor_col;
        var offset = self.buffer.offset;
        var rows = self.buffer.rows.items;
        var win_rows = self.buffer.ws_row;

        var row_len = if (rows.len == 0) 0 else rows.len - 1;
        var col_len = if (rows[cursor_y].len == 0) 0 else rows[cursor_y].len - 1;

        assert(cursor_y <= row_len);

        switch (dir) {
            .Left => {
                if (cursor_x > 0) cursor_x -= 1;
            },
            .Right => {
                if (col_len > cursor_x) cursor_x += 1;
            },
            .Up => {
                if (cursor_y == 0 and offset == 0) return;
                if (cursor_y > 0) cursor_y -= 1 else offset -= 1;

                assert(row_len >= cursor_y);
                var prev_col_len = if (rows[cursor_y].len == 0) 0 else rows[cursor_y].len - 1;

                if (cursor_x > prev_col_len) {
                    if (cursor_col == 0) cursor_col = cursor_x;
                    cursor_x = @intCast(prev_col_len);
                } else if (prev_col_len > cursor_col and cursor_col > 0) {
                    cursor_x = @intCast(cursor_col);
                    cursor_col = 0;
                } else if (prev_col_len > cursor_x and cursor_col > 0) {
                    cursor_x = @intCast(prev_col_len);
                }
            },
            .Down => {
                if (cursor_y + offset == row_len and offset + cursor_y == row_len) return;
                if (cursor_y < win_rows) cursor_y += 1 else offset += 1;

                assert(row_len >= cursor_y);
                var next_col_len = if (rows[cursor_y].len == 0) 0 else rows[cursor_y].len - 1;

                if (cursor_x > next_col_len) {
                    if (cursor_col == 0) cursor_col = cursor_x;
                    cursor_x = @intCast(next_col_len);
                } else if (next_col_len > cursor_col and cursor_col > 0) {
                    cursor_x = @intCast(cursor_col);
                    cursor_col = 0;
                } else if (next_col_len > cursor_x and cursor_col > 0) {
                    cursor_x = @intCast(next_col_len);
                }
            },
        }

        self.buffer.cursor_x = cursor_x;
        self.buffer.cursor_y = cursor_y;
        self.buffer.cursor_col = cursor_col;
        self.buffer.offset = offset;
    }
};
