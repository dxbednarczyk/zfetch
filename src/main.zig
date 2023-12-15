const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");

const meminfo = @cImport(@cInclude("libproc2/meminfo.h"));
const misc = @cImport(@cInclude("libproc2/misc.h"));

const OSRelease = struct {
    name: []u8,
    arch: []const u8,
};

const Uptime = struct {
    hours: i32,
    minutes: i32,
};

const Memory = struct {
    used: c_int,
    total: c_int,
};

const LAYOUT =
    \\{s}@{s}
    \\{s}
    \\os       {s} {s}
    \\kernel   {s}
    \\uptime   {s}
    \\shell    {s}
    \\memory   {d}M / {d}M
    \\
;

fn getUsername(allocator: std.mem.Allocator, uid: std.os.uid_t) ![]const u8 {
    const read_bytes = try util.readFile(allocator, "/etc/passwd");
    var lines = std.mem.splitBackwardsAny(u8, read_bytes, "\n");
    // skip newline at end of file
    _ = lines.next();

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, ":");

        const user = tokens.next().?;
        _ = tokens.next();
        const uid_token = tokens.next().?;

        if (uid == try std.fmt.parseInt(u32, uid_token, 10)) {
            const username = try allocator.alloc(u8, user.len);
            std.mem.copyForwards(u8, username, user);

            return username;
        }
    }

    return "unknown";
}

fn getOSRelease(allocator: std.mem.Allocator) !OSRelease {
    var os_release: OSRelease = undefined;

    const read_bytes = try util.readFile(allocator, "/etc/os-release");
    var lines = std.mem.splitAny(u8, read_bytes, "\n");

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, "=");

        const key = tokens.next().?;
        if (std.mem.eql(u8, key, "PRETTY_NAME")) {
            const value_with_quotes = tokens.next().?;

            const size = std.mem.replacementSize(u8, value_with_quotes, "\"", "");
            const value = try allocator.alloc(u8, size);

            _ = std.mem.replace(u8, value_with_quotes, "\"", "", value);

            os_release.name = value;
            break;
        }
    }

    os_release.arch = @tagName(builtin.cpu.arch);

    return os_release;
}

fn getMeminfo() Memory {
    var info: ?*meminfo.struct_meminfo_info = null;

    const rc = meminfo.procps_meminfo_new(@ptrCast(&info));
    if (rc < 0) {
        switch (std.os.errno(rc)) {
            .NOENT => std.debug.print("/proc/meminfo does not exist\n", .{}),
            else => std.debug.print("failed to create meminfo struct\n", .{}),
        }

        std.os.exit(@as(u8, @intCast(-rc)));
    }

    var memory: Memory = undefined;

    memory.used = @divTrunc(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_USED).*.result.s_int, 1024);
    memory.total = @divTrunc(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_TOTAL).*.result.s_int, 1024);

    return memory;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const user = try getUsername(allocator, std.os.linux.getuid());

    var hostname_buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&hostname_buf);

    const length_of_text = user.len + hostname.len + 1;
    const separator = try allocator.alloc(u8, length_of_text);
    @memset(separator, '-');

    const os_release = try getOSRelease(allocator);
    const version = std.os.uname().release;
    const uptime = misc.procps_uptime_sprint_short()[3..];
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");
    const mem = getMeminfo();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ user, hostname, separator, os_release.name, os_release.arch, version, uptime, shell, mem.used, mem.total });
}
