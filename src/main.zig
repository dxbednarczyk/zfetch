const std = @import("std");
const proc = @cImport(@cInclude("proc/sysinfo.h"));

const QUOTES_OFFSET = 2;
const EMPTY_STRING: []u8 = undefined;

pub fn get_os_release(allocator: std.mem.Allocator) ![]u8 {
    var os_release: []u8 = undefined;

    const file = try std.fs.openFileAbsolute("/etc/os-release", .{});
    const file_stat = try file.stat();

    const read_bytes = try file.readToEndAlloc(allocator, file_stat.size);
    var lines = std.mem.tokenizeAny(u8, read_bytes, "\n");

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, "=");

        const key = tokens.next().?;
        const value_with_quotes = tokens.next().?;

        var value = try allocator.alloc(u8, value_with_quotes.len - QUOTES_OFFSET);
        _ = std.mem.replace(u8, value_with_quotes, "\"", "", value);

        if (std.mem.eql(u8, key, "PRETTY_NAME")) {
            os_release = value;
            break;
        }
    }

    return os_release;
}

const Uptime = struct {
    hours: i32,
    minutes: i32,
};

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

const Memory = struct {
    used: c_ulong,
    available: c_ulong,
};

fn get_meminfo() Memory {
    proc.meminfo();

    const mb_used = @divTrunc(proc.kb_main_used, 1000);
    const mb_total = @divTrunc(proc.kb_main_total, 1000);

    return Memory{
        .used = mb_used,
        .available = mb_total,
    };
}

const LAYOUT =
    \\ {s}@{s}
    \\ os       {s}
    \\ kernel   {s}
    \\ uptime   {d}h {d}m
    \\ memory   {d}M / {d}M
    \\
;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const user = try std.process.getEnvVarOwned(allocator, "USER");
    var hostname_buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&hostname_buf);

    const os_release = try get_os_release(allocator);
    const version = std.os.uname();
    const uptime = get_uptime();
    const meminfo = get_meminfo();

    var stdout = std.io.getStdOut().writer();
    stdout.print(LAYOUT, .{ user, hostname, os_release, version.release, uptime.hours, uptime.minutes, meminfo.used, meminfo.available }) catch return;
}
