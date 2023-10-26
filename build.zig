const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wepoll_dep = b.dependency("wepoll", .{
        .target = target,
        .optimize = optimize,
    });
    const winpthreads_dep = b.dependency("winpthreads", .{
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addStaticLibrary(.{
        .name = "hv",
        .target = target,
        .optimize = optimize,
    });
    const t = lib.target_info.target;
    lib.linkLibC();
    lib.addCSourceFiles(.{
        .files = &hv_src_files,
        .flags = &.{ "-std=gnu99", "-Wno-int-conversion" },
    });
    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = .{ .path = "hconfig.h.in" } },
        .include_path = "hconfig.h",
    }, .{
        .HAVE_STDBOOL_H = 1,
        .HAVE_STDINT_H = 1,
        .HAVE_STDATOMIC_H = 1,
        .HAVE_SYS_TYPES_H = 1,
        .HAVE_SYS_STAT_H = 1,
        .HAVE_SYS_TIME_H = 1,
        .HAVE_FCNTL_H = 1,
        .HAVE_PTHREAD_H = 1,
        .HAVE_ENDIAN_H = 1,
        .HAVE_SYS_ENDIAN_H = 1,
        .HAVE_GETTID = @intFromBool(t.os.tag == .linux),
        .HAVE_STRLCPY = 1,
        .HAVE_STRLCAT = 1,
        .HAVE_CLOCK_GETTIME = 1,
        .HAVE_GETTIMEOFDAY = 1,
        .HAVE_PTHREAD_SPIN_LOCK = 1,
        .HAVE_PTHREAD_MUTEX_TIMEDLOCK = @intFromBool(t.os.tag == .linux),
        .HAVE_SEM_TIMEDWAIT = @intFromBool(t.os.tag == .linux),
        .HAVE_PIPE = 1,
        .HAVE_SOCKETPAIR = 1,
        .HAVE_EVENTFD = @intFromBool(t.os.tag == .linux),
        .HAVE_SETPROCTITLE = 0,

        .WITH_WEPOLL = @intFromBool(t.os.tag == .windows),
        .WITH_KCP = 1,
    });
    if (t.os.tag == .windows) {
        lib.defineCMacro("WIN32_LEAN_AND_MEAN", "");
        lib.defineCMacro("CRT_SECURE_NO_WARNINGS", "");
        lib.defineCMacro("_WIN32_WINNT", "0x0600");
        lib.linkLibrary(wepoll_dep.artifact("wepoll"));
        lib.linkLibrary(winpthreads_dep.artifact("winpthreads"));
        lib.linkSystemLibrary("secur32");
        lib.linkSystemLibrary("crypt32");
        lib.linkSystemLibrary("winmm");
        lib.linkSystemLibrary("iphlpapi");
        lib.linkSystemLibrary("ws2_32");
    } else {
        lib.linkSystemLibrary("m");
        lib.linkSystemLibrary("dl");
        lib.linkSystemLibrary("pthread");
    }
    lib.addConfigHeader(config_h);
    lib.installConfigHeader(config_h, .{});
    inline for (hv_inc_paths) |path| {
        lib.addIncludePath(.{ .path = path });
    }
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

const hv_inc_paths = [_][]const u8{
    ".",
    "util",
    "base",
    "protocol",
    "http",
    "event",
    "mqtt",
    "ssl",
};

const hv_src_files = [_][]const u8{
    "util/sha1.c",
    "util/base64.c",
    "util/md5.c",
    "base/hbase.c",
    "base/hmain.c",
    "base/hversion.c",
    "base/hsocket.c",
    "base/htime.c",
    "base/rbtree.c",
    "base/hlog.c",
    "base/herr.c",
    "protocol/icmp.c",
    "protocol/smtp.c",
    "protocol/dns.c",
    "protocol/ftp.c",
    "http/httpdef.c",
    "http/multipart_parser.c",
    "http/websocket_parser.c",
    "http/http_parser.c",
    "http/wsdef.c",
    "event/kqueue.c",
    "event/noevent.c",
    "event/iocp.c",
    "event/overlapio.c",
    "event/hloop.c",
    "event/evport.c",
    "event/select.c",
    "event/epoll.c",
    "event/nlog.c",
    "event/rudp.c",
    "event/nio.c",
    "event/kcp/hkcp.c",
    "event/kcp/ikcp.c",
    "event/hevent.c",
    "event/poll.c",
    "event/unpack.c",
    "mqtt/mqtt_protocol.c",
    "mqtt/mqtt_client.c",
};
