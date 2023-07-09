const std = @import("std");
const os = std.os;
const mem = std.mem;
const fs = std.fs;
const math = std.math;
const assert = std.debug.assert;

const Direction = @import("editor.zig").Direction;
const ArrayList = std.ArrayList;

pub const Cursor = struct {
    x: u8,
    y: u8,
};

pub const Buffer = struct {
    const Self = @This();
    allocator: mem.Allocator,
    rows: ArrayList([]u8),
    offset: u16,
    ws_row: u16,
    ws_col: u16,
    cursor_y: u16,
    cursor_x: u16,
    cursor_col: u16,
    file_path: []const u8,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .rows = ArrayList([]u8).init(allocator),
            .offset = 0,
            .ws_col = 0,
            .ws_row = 0,
            .cursor_y = 0,
            .cursor_x = 0,
            .cursor_col = 0,
            .file_path = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.rows.items) |item| {
            self.allocator.free(item);
        }
        self.rows.deinit();
    }

    pub fn insertRow(self: *Self, index: usize, item: []const u8) !void {
        if (index < 0 or index > self.rows.items.len) return;
        try self.rows.insert(index, try self.allocator.dupe(u8, item));
    }

    pub fn openFile(self: *Self, file_path: []const u8) !void {
        const file = try fs.cwd().createFile(file_path, .{ .read = true, .truncate = false });
        defer file.close();

        var file_bytes = try file.reader().readAllAlloc(self.allocator, math.maxInt(u32));
        defer self.allocator.free(file_bytes);

        var it = mem.split(u8, file_bytes, "\n");
        var index: usize = 0;
        while (it.next()) |line| {
            try self.insertRow(index, line);
            index += 1;
        }
    }

    pub fn insert(self: *Self, char: u8) !void {
        var row = self.rows.items[self.cursor_y];
        var copy = try self.allocator.dupe(u8, row);
        var buf = try self.allocator.realloc(row, row.len + 1);
        defer self.allocator.free(buf);
        defer self.allocator.free(copy);

        assert(buf.len > 0);
        if (self.cursor_x > buf.len) {
            assert(self.cursor_x + 1 <= buf.len);
            @memset(buf[self.cursor_x .. self.cursor_x + 1], char);
        } else {
            var j: usize = 0;
            for (0..buf.len) |i| {
                if (i == self.cursor_x) {
                    assert(i < buf.len);
                    buf[i] = char;
                } else {
                    assert(i < buf.len);
                    assert(j < copy.len);
                    buf[i] = copy[j];
                    j += 1;
                }
            }
        }
        self.cursor_x += 1;
        self.cursor_col = self.cursor_x;

        assert(self.cursor_y < self.rows.items.len);
        self.rows.items[self.cursor_y] = try self.allocator.dupe(u8, buf);
    }

    pub fn delete(self: *Self, col: u16) !void {
        if (self.rows.items[self.cursor_y].len == 0) return;

        var row = self.rows.items[self.cursor_y];
        mem.copy(u8, row[col .. row.len - 1], row[col + 1 .. row.len]);

        var buf = try self.allocator.realloc(row, row.len - 1);
        defer self.allocator.free(buf);
        self.rows.items[self.cursor_y] = try self.allocator.dupe(u8, buf);

        if ((col == buf.len or col < self.cursor_x) and buf.len > 0) {
            self.cursor_x -= 1;
            self.cursor_col = self.cursor_x;
        }
    }

    pub fn updateWindowSize(self: *Self) !void {
        var winsize: os.darwin.winsize = undefined;
        const err = os.darwin.ioctl(os.STDOUT_FILENO, os.darwin.T.IOCGWINSZ, @intFromPtr(&winsize));
        if (os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.ws_col = winsize.ws_col;
        self.ws_row = winsize.ws_row;
    }
};
