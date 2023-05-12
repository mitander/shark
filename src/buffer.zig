const std = @import("std");
const os = std.os;
const mem = std.mem;
const fs = std.fs;
const math = std.math;

const Direction = @import("main.zig").Direction;
const ArrayList = std.ArrayList;

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
        var winsize: os.darwin.winsize = undefined;
        const err = os.darwin.ioctl(os.STDOUT_FILENO, os.darwin.T.IOCGWINSZ, @ptrToInt(&winsize));
        if (os.errno(err) != .SUCCESS) {
            return error.IoctlError;
        }
        self.ws_col = winsize.ws_col;
        self.ws_row = winsize.ws_row - 1; // TODO : why is this required to render first row?
    }
};
