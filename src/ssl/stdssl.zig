const c = @cImport(@cInclude("hssl.h"));
export fn hssl_backend() [*c]const u8 {
    return "stdssl";
}
export fn hssl_ctx_new(opt: [*c]c.hssl_ctx_opt_t) c.hssl_ctx_t {
    _ = opt;
    return null;
}
export fn hssl_ctx_free(ssl_ctx: c.hssl_ctx_t) void {
    _ = ssl_ctx;
}
export fn hssl_new(ssl_ctx: c.hssl_ctx_t, fd: c_int) c.hssl_t {
    _ = ssl_ctx;
    var fd_usize: usize = @intCast(fd);
    var fd_ptr: *u8 = @ptrFromInt(fd_usize);
    return @ptrCast(fd_ptr);
}
export fn hssl_free(ssl: c.hssl_t) void {
    _ = ssl;
}
export fn hssl_accept(ssl: c.hssl_t) c_int {
    _ = ssl;
    return 0;
}
export fn hssl_connect(ssl: c.hssl_t) c_int {
    _ = ssl;
    return 0;
}
export fn hssl_read(ssl: c.hssl_t, buf: ?*anyopaque, len: c_int) c_int {
    var fd_usize: usize = @intFromPtr(ssl);
    return @intCast(c.read(@intCast(fd_usize), buf, @intCast(len)));
}
export fn hssl_write(ssl: c.hssl_t, buf: ?*const anyopaque, len: c_int) c_int {
    var fd_usize: usize = @intFromPtr(ssl);
    return @intCast(c.write(@intCast(fd_usize), buf, @intCast(len)));
}
export fn hssl_close(ssl: c.hssl_t) c_int {
    _ = ssl;
    return 0;
}
export fn hssl_set_sni_hostname(ssl: c.hssl_t, hostname: [*c]const u8) c_int {
    _ = hostname;
    _ = ssl;
    return 0;
}
