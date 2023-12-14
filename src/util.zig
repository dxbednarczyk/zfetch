const std = @import("std");

pub fn readFile(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(filename, .{});
    const file_stat = try file.stat();

    return try file.readToEndAlloc(allocator, file_stat.size);
}
