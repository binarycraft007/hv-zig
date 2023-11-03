const std = @import("std");
const c = @import("c.zig");

fn on_close(io: ?*c.hio_t) callconv(.C) void {
    _ = io;
}

fn on_recv(io: ?*c.hio_t, buf: ?*anyopaque, readbytes: c_int) callconv(.C) void {
    _ = c.hio_write(io, buf, @intCast(readbytes));
}

fn on_accept(io: ?*c.hio_t) callconv(.C) void {
    c.hio_setcb_close(io, &on_close);
    c.hio_setcb_read(io, &on_recv);
    _ = c.hio_read(io);
}

pub fn main() void {
    var loop = c.hloop_new(0);
    defer c.hloop_free(&loop);
    var listenio = c.hloop_create_tcp_server(loop, "0.0.0.0", 8080, &on_accept);
    std.debug.assert(listenio != null);
    _ = c.hloop_run(loop);
}
