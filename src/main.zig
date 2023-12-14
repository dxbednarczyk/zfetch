const std = @import("std");
const builtin = @import("builtin");

const proc = @cImport(@cInclude("proc/sysinfo.h"));

const OSRelease = struct {
    name: []u8,
    arch: []const u8,
};

const Uptime = struct {
    hours: i32,
    minutes: i32,
};

const Memory = struct {
    used: c_ulong,
    available: c_ulong,
};

const LAYOUT =
    \\{s}@{s}
    \\os       {s} {s}
    \\kernel   {s}
    \\uptime   {d}h {d}m
    \\memory   {d}M / {d}M
    \\
;

fn get_os_release(allocator: std.mem.Allocator) !OSRelease {
    var os_release: OSRelease = undefined;

    const file = try std.fs.openFileAbsolute("/etc/os-release", .{});
    const file_stat = try file.stat();

    const read_bytes = try file.readToEndAlloc(allocator, file_stat.size);
    var lines = std.mem.tokenizeAny(u8, read_bytes, "\n");

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

fn get_uptime() Uptime {
    var uptime: f64 = 0;
    var idle: f64 = 0;
    _ = proc.uptime(&uptime, &idle);

    var upsecs: i32 = @intFromFloat(uptime);

    const h = @divTrunc(upsecs, 3600);
    upsecs -= 3600 * h;

    const m = @divTrunc(upsecs, 60);

    return Uptime{
        .hours = h,
        .minutes = m,
    };
}

fn get_meminfo() Memory {
    proc.meminfo();

    const mb_used = @divTrunc(proc.kb_main_used, 1024);
    const mb_total = @divTrunc(proc.kb_main_total, 1024);

    return Memory{
        .used = mb_used,
        .available = mb_total,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const user = try std.process.getEnvVarOwned(allocator, "USER");

    var hostname_buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&hostname_buf);

    const os_release = try get_os_release(allocator);
    const version = std.os.uname().release;
    const uptime = get_uptime();
    const meminfo = get_meminfo();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ user, hostname, os_release.name, os_release.arch, version, uptime.hours, uptime.minutes, meminfo.used, meminfo.available });
}
