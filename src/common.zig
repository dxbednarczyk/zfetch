const std = @import("std");

const pwd = @cImport(@cInclude("pwd.h"));

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

pub fn get_username(uid: c_uint) [*c]u8 {
    const pws = pwd.getpwuid(uid);

    return pws.*.pw_name;
}

pub fn get_hostname(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const name = try std.os.gethostname(&buf);

    var split_name = std.mem.splitScalar(u8, name, '.');
    const next = split_name.next().?;

    var hname = try allocator.alloc(u8, next.len);
    @memcpy(hname, next);

    return hname;
}
