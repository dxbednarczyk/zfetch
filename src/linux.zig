const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");

const meminfo = @cImport(@cInclude("libproc2/meminfo.h"));
const misc = @cImport(@cInclude("libproc2/misc.h"));

const pwd = @cImport(@cInclude("pwd.h"));

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

fn get_username() [*c]u8 {
    const uid = std.os.linux.getuid();
    const pws = pwd.getpwuid(uid);

    return pws.*.pw_name;
}

fn get_os_release(allocator: std.mem.Allocator) !common.OSRelease {
    var os_release = common.OSRelease{
        .arch = @tagName(builtin.cpu.arch),
    };

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
        switch (std.os.errno(rc)) {
            .NOENT => std.debug.print("/proc/meminfo does not exist\n", .{}),
            else => std.debug.print("failed to create meminfo struct\n", .{}),
        }

        std.os.exit(@as(u8, @intCast(-rc)));
    }

    return common.Memory{
        .used = @divTrunc(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_USED).*.result.s_int, 1024),
        .total = @divTrunc(meminfo.procps_meminfo_get(info, meminfo.MEMINFO_MEM_TOTAL).*.result.s_int, 1024),
    };
}

pub fn fetch(allocator: std.mem.Allocator) !void {
    const user = get_username();

    var hostname_buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&hostname_buf);

    const length_of_text = user.len + hostname.len + 1;
    const separator = try allocator.alloc(u8, length_of_text);
    @memset(separator, '-');

    const os_release = try get_os_release(allocator);
    const version = std.os.uname().release;
    const uptime = misc.procps_uptime_sprint_short()[3..];
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");
    const memory = get_memory();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ user, hostname, separator, os_release.name, os_release.arch, version, uptime, shell, memory.used, memory.total });
}
