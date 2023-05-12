const std = @import("std");
const os = std.os;
const mem = std.mem;
const debug = std.log.debug;
const assert = std.debug.assert;

const Termios = @import("termios.zig").Termios;
const Buffer = @import("buffer.zig").Buffer;

pub const Direction = enum(u8) { Up, Down, Left, Right };

pub const Editor = struct {
    const Self = @This();
    allocator: mem.Allocator,
    termios: Termios,
    buffer: Buffer,

    pub fn init(allocator: mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .buffer = Buffer.init(allocator),
            .termios = try Termios.init(allocator),
        };
    }

    pub fn deinit(self: *Self) !void {
        try self.termios.deinit();
        self.buffer.deinit();
    }

    pub fn openFile(self: *Self, file_path: []const u8) !void {
        try self.buffer.openFile(file_path);
    }

    pub fn readKey(self: *Self) !u8 {
        var seq = try self.allocator.alloc(u8, 1);
        defer self.allocator.free(seq);
        _ = try os.read(os.darwin.STDIN_FILENO, seq);
        return seq[0];
    }

    pub fn refresh(self: *Self) !void {
        try self.buffer.updateWindowSize();
        try self.termios.render(self.buffer);
    }

    pub fn moveCursor(self: *Self, dir: Direction) void {
        switch (dir) {
            .Left => {
                if (self.buffer.cursor_x > 0) {
                    self.buffer.cursor_x -= 1;
                }
            },
            .Right => {
                if (self.buffer.cursor_y >= self.buffer.rows.items.len) return;
                if (self.buffer.cursor_x < self.buffer.rows.items[self.buffer.cursor_y].render.len) {
                    self.buffer.cursor_x += 1;
                }
            },
            .Up => {
                if (self.buffer.cursor_y > 0) {
                    self.buffer.cursor_y -= 1;
                } else if (self.buffer.offset > 0) {
                    self.buffer.offset -= 1;
                } else {
                    return;
                }

                var index = self.buffer.offset + self.buffer.cursor_y;
                if (index >= self.buffer.rows.items.len) return;

                if (self.buffer.cursor_x == 0) self.buffer.cursor_x = @intCast(u16, self.buffer.rows.items[index].render.len);
                if (self.buffer.rows.items[index].render.len < self.buffer.cursor_x) {
                    self.buffer.cursor_x = @intCast(u16, self.buffer.rows.items[index].render.len);
                }
            },
            .Down => {
                if (self.buffer.offset + self.buffer.cursor_y >= self.buffer.rows.items.len) return;

                if (self.buffer.cursor_y < self.buffer.ws_row) {
                    self.buffer.cursor_y += 1;
                } else if (self.buffer.offset < self.buffer.rows.items.len - self.buffer.ws_row) {
                    self.buffer.offset += 1;
                } else {
                    return;
                }

                var index = self.buffer.offset + self.buffer.cursor_y;
                if (index >= self.buffer.rows.items.len) return;

                if (self.buffer.cursor_x == 0) self.buffer.cursor_x = @intCast(u16, self.buffer.rows.items[index].render.len);
                if (self.buffer.rows.items[index].render.len < self.buffer.cursor_x) {
                    self.buffer.cursor_x = @intCast(u16, self.buffer.rows.items[index].render.len);
                }
            },
        }
    }
};
