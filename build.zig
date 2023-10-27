const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wepoll_dep = b.dependency("wepoll", .{
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addStaticLibrary(.{
        .name = "hv",
        .root_source_file = .{ .path = "src/ssl/stdssl.zig" },
        .target = target,
        .optimize = optimize,
    });
    const t = lib.target_info.target;
    lib.linkLibC();
    lib.addCSourceFiles(.{
        .files = &hv_src_files,
        .flags = &.{ "-std=gnu11", "-Wno-int-conversion" },
    });
    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = .{ .path = "include/hconfig.h.in" } },
        .include_path = "hconfig.h",
    }, .{
        .HAVE_STDBOOL_H = 1,
        .HAVE_STDINT_H = 1,
        .HAVE_STDATOMIC_H = 1,
        .HAVE_SYS_TYPES_H = 1,
        .HAVE_SYS_STAT_H = 1,
        .HAVE_SYS_TIME_H = 1,
        .HAVE_FCNTL_H = 1,
        .HAVE_PTHREAD_H = @intFromBool(t.os.tag != .windows),
        .HAVE_ENDIAN_H = 1,
        .HAVE_SYS_ENDIAN_H = 1,
        .HAVE_GETTID = @intFromBool(t.os.tag == .linux),
        .HAVE_STRLCPY = 1,
        .HAVE_STRLCAT = 1,
        .HAVE_CLOCK_GETTIME = 1,
        .HAVE_GETTIMEOFDAY = 1,
        .HAVE_PTHREAD_SPIN_LOCK = @intFromBool(t.os.tag != .windows),
        .HAVE_PTHREAD_MUTEX_TIMEDLOCK = @intFromBool(t.os.tag == .linux),
        .HAVE_SEM_TIMEDWAIT = @intFromBool(t.os.tag == .linux),
        .HAVE_PIPE = 1,
        .HAVE_SOCKETPAIR = 1,
        .HAVE_EVENTFD = @intFromBool(t.os.tag == .linux),
        .HAVE_SETPROCTITLE = 0,

        .WITH_WEPOLL = @intFromBool(t.os.tag == .windows),
    });
    if (t.os.tag == .windows) {
        lib.defineCMacro("WIN32_LEAN_AND_MEAN", "");
        lib.defineCMacro("CRT_SECURE_NO_WARNINGS", "");
        lib.defineCMacro("_WIN32_WINNT", "0x0600");
        lib.linkLibrary(wepoll_dep.artifact("wepoll"));
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
    lib.addIncludePath(.{ .path = "include" });
    lib.installHeadersDirectory("include", "");
    inline for (hv_inc_paths) |path| {
        lib.addIncludePath(.{ .path = path });
        lib.installHeadersDirectoryOptions(.{
            .source_dir = .{ .path = path },
            .install_dir = .header,
            .install_subdir = "",
            .include_extensions = &.{".h"},
        });
    }
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "echo_test",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(lib);
    b.installArtifact(exe);

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
    "src/util",
    "src/base",
    "src/protocol",
    "src/http",
    "src/event",
    "src/mqtt",
    "src/ssl",
};

const hv_src_files = [_][]const u8{
    "src/util/sha1.c",
    "src/util/base64.c",
    "src/util/md5.c",
    "src/base/hbase.c",
    "src/base/hmain.c",
    "src/base/hversion.c",
    "src/base/hsocket.c",
    "src/base/htime.c",
    "src/base/rbtree.c",
    "src/base/hlog.c",
    "src/base/herr.c",
    "src/protocol/icmp.c",
    "src/protocol/smtp.c",
    "src/protocol/dns.c",
    "src/protocol/ftp.c",
    "src/http/httpdef.c",
    "src/http/multipart_parser.c",
    "src/http/websocket_parser.c",
    "src/http/http_parser.c",
    "src/http/wsdef.c",
    "src/event/kqueue.c",
    "src/event/noevent.c",
    "src/event/iocp.c",
    "src/event/overlapio.c",
    "src/event/hloop.c",
    "src/event/evport.c",
    "src/event/select.c",
    "src/event/epoll.c",
    "src/event/nlog.c",
    "src/event/rudp.c",
    "src/event/nio.c",
    "src/event/hevent.c",
    "src/event/poll.c",
    "src/event/unpack.c",
    "src/mqtt/mqtt_protocol.c",
    "src/mqtt/mqtt_client.c",
    "src/ssl/hssl.c",
};
