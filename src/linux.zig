const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");

const meminfo = @cImport(@cInclude("libproc2/meminfo.h"));
const misc = @cImport(@cInclude("libproc2/misc.h"));

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

pub fn read_file(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(filename, .{});
    const file_stat = try file.stat();

    return try file.readToEndAlloc(allocator, file_stat.size);
}

fn get_os_release(allocator: std.mem.Allocator) !common.OSRelease {
    var os_release: common.OSRelease = undefined;
    os_release.arch = @tagName(builtin.cpu.arch);

    const read_bytes = try read_file(allocator, "/etc/os-release");
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

    return os_release;
}

fn get_memory() common.Memory {
    var info: ?*meminfo.struct_meminfo_info = null;

    const rc = meminfo.procps_meminfo_new(@ptrCast(&info));
    if (rc < 0) {
        std.os.exit(@as(u8, @intCast(-rc)));
    }

    const used: c_uint = @intCast(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_USED).*.result.s_int);
    const total: c_uint = @intCast(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_TOTAL).*.result.s_int);

    return common.Memory{
        .used = @divTrunc(used, 1024),
        .total = @divTrunc(total, 1024),
    };
}

pub fn fetch(allocator: std.mem.Allocator) !void {
    const user = common.get_username(std.os.linux.getuid());
    const hostname = try common.get_hostname(allocator);

    const separator = common.get_separator(allocator, std.mem.len(user), hostname.len);

    const os_release = try get_os_release(allocator);
    const kernel = std.os.uname().release;
    const uptime = misc.procps_uptime_sprint_short();
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");
    const memory = get_memory();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ user, hostname, separator, os_release.name, os_release.arch, kernel, uptime, shell, memory.used, memory.total });
}
