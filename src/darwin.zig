const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");

const mach = @cImport(@cInclude("mach/mach.h"));
const vm_stat = @cImport(@cInclude("mach/vm_statistics.h"));
const host = @cImport(@cInclude("mach/host_info.h"));

const unistd = @cImport(@cInclude("unistd.h"));

const B_MB_RATIO = 1048576;
const BILLION = 1_000_000_000;
const LAYOUT =
    \\{s}@{s}
    \\{s}
    \\os       macOS {s} {s}
    \\kernel   {s}
    \\uptime   up {s}
    \\shell    {s}
    \\memory   {d}M / {d}M
    \\
;

const timeval = extern struct {
    tv_sec: c_int,
    tv_usec: c_long,
};

fn sysctl_name(comptime T: type, name: [*:0]const u8) !T {
    var value: T = undefined;
    var len: usize = @sizeOf(T);

    try std.os.sysctlbynameZ(name, &value, &len, null, 0);

    return value;
}

fn get_memory() !common.Memory {
    const mb_total = @divTrunc(try sysctl_name(u64, "hw.memsize"), B_MB_RATIO);

    var stats: vm_stat.vm_statistics64 = undefined;
    var count: c_uint = @sizeOf(host.vm_statistics64_data_t) / @sizeOf(c_int);

    const ret = mach.host_statistics64(mach.mach_host_self(), host.HOST_VM_INFO64, @ptrCast(&stats), &count);

    if (ret != mach.KERN_SUCCESS) {
        std.process.exit(1);
    }

    const b_free: u64 = @as(u64, stats.free_count + stats.inactive_count) * std.mem.page_size;
    const mb_free = @divTrunc(b_free, B_MB_RATIO);

    return common.Memory{
        .used = @as(c_uint, @truncate(mb_total - mb_free)),
        .total = @as(c_uint, @truncate(mb_total)),
    };
}

fn get_os_release(allocator: std.mem.Allocator) !common.OSRelease {
    var len: usize = 8;
    var value = std.mem.zeroes([8]u8);

    try std.os.sysctlbynameZ("kern.osproductversion", &value, &len, null, 0);

    const trimmed = std.mem.trimRight(u8, &value, "\x00");

    const trimmed_buf = try allocator.alloc(u8, trimmed.len);
    @memcpy(trimmed_buf, trimmed);

    return common.OSRelease{ .name = trimmed_buf, .arch = @tagName(builtin.cpu.arch) };
}

fn get_kernel(allocator: std.mem.Allocator) ![]const u8 {
    const kern = try sysctl_name([128]u8, "kern.version");

    var split_kern = std.mem.splitScalar(u8, &kern, ':');
    const next = split_kern.next().?;

    const kernbuf = try allocator.alloc(u8, next.len);
    @memcpy(kernbuf, next);

    return kernbuf;
}

fn get_uptime(allocator: std.mem.Allocator) ![]const u8 {
    const boottime = try sysctl_name(timeval, "kern.boottime");
    const timestamp = std.time.timestamp();

    var upt = (timestamp - boottime.tv_sec) * BILLION;

    // stripped out of std.fmt.fmtDuration
    var buf = std.mem.zeroes([23]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    var buf_writer = fbs.writer();

    // zig fmt: off
    inline for (.{ 
        .{ .ns = 365 * std.time.ns_per_day, .sep = "y " },
        .{ .ns = std.time.ns_per_week, .sep = "w " },
        .{ .ns = std.time.ns_per_day, .sep = "d " },
        .{ .ns = std.time.ns_per_hour, .sep = "h " },
        .{ .ns = std.time.ns_per_min, .sep = "m " },
        .{ .ns = std.time.ns_per_s, .sep = "s" }
    }) |unit| {
        if (upt >= unit.ns) {
            const units = @divTrunc(upt, unit.ns);

            try std.fmt.formatInt(units, 10, .lower, .{}, buf_writer);
            try buf_writer.writeAll(unit.sep);

            upt -= units * unit.ns;
        }
    }
    // zig fmt: on

    const printed = try std.fmt.allocPrint(allocator, "{s}", .{buf});

    return std.mem.trimRight(u8, printed, "\x00");
}

pub fn fetch(allocator: std.mem.Allocator) !void {
    const username = common.get_username(unistd.geteuid());
    const hostname = try common.get_hostname(allocator);

    const separator = try common.get_separator(allocator, std.mem.len(username), hostname.len);

    const os_release = try get_os_release(allocator);
    const kernel = try get_kernel(allocator);
    const uptime = try get_uptime(allocator);
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");
    const memory = try get_memory();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ username, hostname, separator, os_release.name, os_release.arch, kernel, uptime, shell, memory.used, memory.total });
}
