const std = @import("std");

const c = @cImport({
    @cInclude("proc/sysinfo.h");
    @cInclude("proc/version.h");
    @cInclude("unistd.h");
});

const Version = struct {
    major: i32,
    minor: i32,
    patch: i32,
};

fn getLinuxVersion() Version {
    var linux_version = c.procps_linux_version();

    return Version{
        .major = c.LINUX_VERSION_MAJOR(linux_version),
        .minor = c.LINUX_VERSION_MINOR(linux_version),
        .patch = c.LINUX_VERSION_PATCH(linux_version),
    };
}

const Uptime = struct {
    hours: i32,
    minutes: i32,
};

fn getUptime() Uptime {
    var uptime: f64 = 0;
    var idle: f64 = 0;
    _ = c.uptime(&uptime, &idle);

    var upsecs: i32 = @intFromFloat(uptime);

    var h = @divTrunc(upsecs, 3600);
    upsecs -= 3600 * h;

    var m = @divTrunc(upsecs, 60);

    return Uptime{
        .hours = h,
        .minutes = m,
    };
}

const Memory = struct {
    used: c_ulong,
    available: c_ulong,
};

fn getMemInfo() Memory {
    c.meminfo();

    var mb_used = @divTrunc(c.kb_main_used, 1000);
    var mb_available = @divTrunc(c.kb_main_available, 1000);

    return Memory{
        .used = mb_used,
        .available = mb_available,
    };
}

const Title = struct {
    user: []u8,
    hostname: []u8,
};

const HostnameError = error{InvalidExitCode};
const MAX_HOSTNAME_LEN: usize = 64;

fn getHostname(dest: []u8) HostnameError!void {
    var hostname: [MAX_HOSTNAME_LEN]u8 = undefined;
    const res = c.gethostname(&hostname, MAX_HOSTNAME_LEN);

    if (res != 0) {
        return HostnameError.InvalidExitCode;
    }

    @memcpy(dest, &hostname);
}

const LAYOUT =
    \\ {s}
    \\ kernel   {s}
    \\ uptime   {s}
    \\ memory   {s}
    \\
;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const user = try std.process.getEnvVarOwned(allocator, "USER");
    var hostname: [MAX_HOSTNAME_LEN]u8 = undefined;
    try getHostname(&hostname);

    var idx = std.mem.indexOf(u8, &hostname, "\x00");
    if (idx == null) {
        idx = MAX_HOSTNAME_LEN;
    }

    var title_string = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ user, hostname[0..idx.?] });

    const version = getLinuxVersion();
    var version_string = try std.fmt.allocPrint(allocator, "{}.{}.{}", .{ version.major, version.minor, version.patch });

    const uptime = getUptime();
    var uptime_string = try std.fmt.allocPrint(allocator, "{}h {}m", .{ uptime.hours, uptime.minutes });

    const meminfo = getMemInfo();
    var meminfo_string = try std.fmt.allocPrint(allocator, "{}M / {}M", .{ meminfo.used, meminfo.available });

    std.debug.print(LAYOUT, .{ title_string, version_string, uptime_string, meminfo_string });
}
