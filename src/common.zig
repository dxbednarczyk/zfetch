const std = @import("std");

pub const OSRelease = struct {
    name: []const u8,
    arch: []const u8,
};

pub const Uptime = struct {
    hours: i32,
    minutes: i32,
};

pub const Memory = struct {
    used: c_uint,
    total: c_uint,
};

pub fn get_separator(allocator: std.mem.Allocator, username_len: usize, hostname_len: usize) ![]u8 {
    const length_of_text = username_len + hostname_len + 1;
    const separator = try allocator.alloc(u8, length_of_text);
    @memset(separator, '-');

    return separator;
}
