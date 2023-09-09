const std = @import("std");

const c = @cImport({
    @cInclude("proc/sysinfo.h");
    @cInclude("proc/version.h");
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
    var hostname_buf: [std.os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.os.gethostname(&hostname_buf);

    var title_string = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ user, hostname });

    const version = getLinuxVersion();
    var version_string = try std.fmt.allocPrint(allocator, "{}.{}.{}", .{ version.major, version.minor, version.patch });

    const uptime = getUptime();
    var uptime_string = try std.fmt.allocPrint(allocator, "{}h {}m", .{ uptime.hours, uptime.minutes });

    const meminfo = getMemInfo();
    var meminfo_string = try std.fmt.allocPrint(allocator, "{}M / {}M", .{ meminfo.used, meminfo.available });

    std.debug.print(LAYOUT, .{ title_string, version_string, uptime_string, meminfo_string });
}
