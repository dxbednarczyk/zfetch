const std = @import("std");
const builtin = @import("builtin");

const linux = @import("linux.zig");
const darwin = @import("darwin.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try switch (builtin.os.tag) {
        .linux => linux.fetch(allocator),
        .macos => darwin.fetch(allocator),
        else => std.debug.print("unsupported os\n", .{}),
    };
}
