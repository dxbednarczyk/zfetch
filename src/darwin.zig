const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");

const mach = @cImport(@cInclude("mach/mach.h"));
const vm_stat = @cImport(@cInclude("mach/vm_statistics.h"));
const host = @cImport(@cInclude("mach/host_info.h"));

const time = @cImport(@cInclude("sys/time.h"));
const sysctl = @cImport(@cInclude("sys/sysctl.h"));

const unistd = @cImport(@cInclude("unistd.h"));
const pwd = @cImport(@cInclude("pwd.h"));

const B_MB_RATIO = 1_048_576;
const BILLION = 1_000_000_000;

const OSPRODUCTVERSION = 142;

const LAYOUT =
    \\{s}@{s}
    \\{s}
    \\os       macOS {s} {s}
    \\kernel   Darwin {s}
    \\uptime   up {s}
    \\shell    {s}
    \\memory   {d}M / {d}M
    \\
;

fn get_string(allocator: std.mem.Allocator, mib: []c_int) ![]u8 {
    var len: usize = undefined;

    try std.posix.sysctl(mib, null, &len, null, 0);

    const buf = try allocator.alloc(u8, len);

    try std.posix.sysctl(mib, @ptrCast(buf), &len, null, 0);

    return buf;
}

fn get(comptime T: type, mib: []c_int) !T {
    var value: T = undefined;
    var len: usize = @sizeOf(T);

    try std.posix.sysctl(mib, &value, &len, null, 0);

    return value;
}

fn get_memory() !common.Memory {
    var mib = [2]c_int{ sysctl.CTL_HW, sysctl.HW_MEMSIZE };
    const res = try get(usize, &mib);

    const mb_total = @divTrunc(res, B_MB_RATIO);

    var stats: vm_stat.vm_statistics64 = undefined;
    var count: c_uint = @sizeOf(host.vm_statistics64_data_t) / @sizeOf(c_int);

    const ret = mach.host_statistics64(mach.mach_host_self(), host.HOST_VM_INFO64, @ptrCast(&stats), &count);

    if (ret != mach.KERN_SUCCESS) {
        std.process.exit(@intCast(ret));
    }

    const b_free: u64 = @as(u64, stats.free_count + stats.inactive_count) * std.mem.page_size;
    const mb_free = @divTrunc(b_free, B_MB_RATIO);

    return common.Memory{
        .used = @as(c_uint, @truncate(mb_total - mb_free)),
        .total = @as(c_uint, @truncate(mb_total)),
    };
}

fn get_os_release(allocator: std.mem.Allocator) !common.OSRelease {
    var mib = [2]c_int{ sysctl.CTL_KERN, OSPRODUCTVERSION };
    const os = try get_string(allocator, &mib);

    return common.OSRelease{ .name = os, .arch = @tagName(builtin.cpu.arch) };
}

fn get_uptime(allocator: std.mem.Allocator) ![]const u8 {
    var mib = [2]c_int{ sysctl.CTL_KERN, sysctl.KERN_BOOTTIME };
    const boottime = try get(time.timeval, &mib);
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
    return std.mem.sliceTo(printed, '\x00');
}

pub fn fetch(allocator: std.mem.Allocator) !void {
    const username = pwd.getpwuid(unistd.geteuid()).*.pw_name;

    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.posix.gethostname(&buf);

    const separator = try common.get_separator(allocator, std.mem.len(username), hostname.len);
    const os_release = try get_os_release(allocator);

    var mib = [2]c_int{ sysctl.CTL_KERN, sysctl.KERN_OSRELEASE };
    const kernel = try get_string(allocator, &mib);

    const uptime = try get_uptime(allocator);
    const shell = try std.process.getEnvVarOwned(allocator, "SHELL");
    const memory = try get_memory();

    var stdout = std.io.getStdOut().writer();
    try stdout.print(LAYOUT, .{ username, hostname, separator, os_release.name, os_release.arch, kernel, uptime, shell, memory.used, memory.total });
}
