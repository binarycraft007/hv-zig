const std = @import("std");
const c = @import("c.zig");
const mem = std.mem;
const dns = @import("dns");
const testing = std.testing;
const Resolver = @This();

io: *c.hio_t,
loop: *c.hloop_t,
allocator: mem.Allocator = undefined,
incoming_name: []const u8 = undefined,
packet: dns.Packet = undefined,
is_resolve_success: bool = false,
onCloseFn: ?*const fn (*Resolver) void = null,
onAddrListFn: *const fn (AddressList) void = undefined,

pub const AddressList = struct {
    allocator: std.mem.Allocator,
    addrs: []std.net.Address,
    pub fn deinit(self: @This()) void {
        self.allocator.free(self.addrs);
    }
};

pub const InitOptions = struct {
    loop: *c.hloop_t,
    name_server: [*c]const u8,
};

pub fn init(options: InitOptions) !Resolver {
    var io_maybe = c.hloop_create_udp_client(
        options.loop,
        options.name_server,
        53,
    );
    if (io_maybe) |io| {
        return .{ .io = io, .loop = options.loop };
    }
    return error.InitUdpClientFailed;
}

fn onClose(io: ?*c.hio_t) callconv(.C) void {
    var resolver: *Resolver = @alignCast(@ptrCast(c.hio_context(io)));
    if (resolver.onCloseFn) |onCloseFn| {
        onCloseFn(resolver);
    }
}

fn onRecvPacket(
    io: ?*c.hio_t,
    buf: ?*anyopaque,
    readbytes: c_int,
) callconv(.C) void {
    defer _ = c.hio_close(io);
    var buf_ptr: [*]u8 = @alignCast(@ptrCast(buf));
    var bytes = buf_ptr[0..@intCast(readbytes)];
    var resolver: *Resolver = @alignCast(@ptrCast(c.hio_context(io)));
    var addr_list = parseAddresslist(bytes, resolver.allocator) catch |err| {
        std.log.err("{}", .{err});
        return;
    };
    resolver.is_resolve_success = true;
    resolver.onAddrListFn(addr_list);
}

fn onSendPacket(
    io: ?*c.hio_t,
    buf: ?*const anyopaque,
    readbytes: c_int,
) callconv(.C) void {
    _ = readbytes;
    _ = buf;
    _ = c.hio_setcb_read(io, onRecvPacket);
    _ = c.hio_set_read_timeout(io, 100);
    _ = c.hio_read(io);
}

fn sendPacket(self: *Resolver, packet: dns.Packet) !void {
    var buffer: [1024]u8 = undefined;
    const typ = std.io.FixedBufferStream([]u8);
    var stream = typ{ .buffer = &buffer, .pos = 0 };
    const written_bytes = try packet.writeTo(stream.writer());
    var result = buffer[0..written_bytes];
    c.hio_setcb_write(self.io, onSendPacket);
    _ = c.hio_set_write_timeout(self.io, 100);
    _ = c.hio_write(self.io, result.ptr, result.len);
}

pub const getAddressListOptions = struct {
    incoming_name: []const u8,
    allocator: std.mem.Allocator,
    onAddrListFn: *const fn (AddressList) void,
    onCloseFn: ?*const fn (*Resolver) void = null,
};

pub fn getAddressList(self: *Resolver, options: getAddressListOptions) !void {
    self.allocator = options.allocator;
    self.onCloseFn = options.onCloseFn;
    self.onAddrListFn = options.onAddrListFn;
    c.hio_set_context(self.io, self);
    c.hio_setcb_close(self.io, onClose);
    var name_buffer: [128][]const u8 = undefined;
    var name = try dns.Name.fromString(options.incoming_name, &name_buffer);
    var questions = [_]dns.Question{
        .{
            .name = name,
            .typ = .A,
            .class = .IN,
        },
        .{
            .name = name,
            .typ = .AAAA,
            .class = .IN,
        },
    };
    var packet = dns.Packet{
        .header = .{
            .id = dns.helpers.randomHeaderId(),
            .is_response = false,
            .wanted_recursion = true,
            .question_length = questions.len,
        },
        .questions = &questions,
        .answers = &[_]dns.Resource{},
        .nameservers = &[_]dns.Resource{},
        .additionals = &[_]dns.Resource{},
    };
    try self.sendPacket(packet);
}

fn parseAddresslist(packet_bytes: []const u8, gpa: mem.Allocator) !AddressList {
    var stream = std.io.FixedBufferStream([]const u8){
        .buffer = packet_bytes,
        .pos = 0,
    };
    var ctx = dns.ParserContext{};
    var parser = dns.parser(stream.reader(), &ctx, .{});
    var addrs = std.ArrayList(std.net.Address).init(gpa);
    errdefer addrs.deinit();
    var current_resource: ?dns.Resource = null;
    while (try parser.next()) |part| {
        switch (part) {
            .header => |header| {
                if (!header.is_response) return error.InvalidResponse;
                switch (header.response_code) {
                    .NoError => {},
                    .FormatError => return error.ServerFormatError,
                    .ServerFailure => return error.ServerFailure,
                    .NameError => return error.ServerNameError,
                    .NotImplemented => return error.ServerNotImplemented,
                    .Refused => return error.ServerRefused,
                }
            },
            .answer => |raw_resource| {
                current_resource = raw_resource;
            },
            .answer_rdata => |rdata| {
                // TODO parser.reader()?
                var reader = parser.wrapper_reader.reader();
                defer current_resource = null;
                var maybe_addr = switch (current_resource.?.typ) {
                    .A => blk: {
                        var ip4addr: [4]u8 = undefined;
                        _ = try reader.read(&ip4addr);
                        break :blk std.net.Address.initIp4(ip4addr, 0);
                    },
                    .AAAA => blk: {
                        var ip6_addr: [16]u8 = undefined;
                        _ = try reader.read(&ip6_addr);
                        break :blk std.net.Address.initIp6(ip6_addr, 0, 0, 0);
                    },
                    else => blk: {
                        try reader.skipBytes(rdata.size, .{});
                        break :blk null;
                    },
                };
                if (maybe_addr) |addr| try addrs.append(addr);
            },
            else => {},
        }
    }
    return .{
        .allocator = gpa,
        .addrs = try addrs.toOwnedSlice(),
    };
}

pub fn deinit(self: *Resolver) void {
    _ = c.hio_close(self.io);
}

test "init/deinit" {
    const Context = struct {
        var loop: *c.hloop_t = undefined;
        var success_count: usize = 0;
        var failed_count: usize = 0;
        fn onAddrList(addr_list: AddressList) void {
            defer addr_list.deinit();
        }
        fn onClose(resolver: *Resolver) void {
            _ = c.hloop_stop(resolver.loop);
        }
    };

    var loop = c.hloop_new(0);
    defer c.hloop_free(&loop);
    Context.loop = loop.?;
    var resolver = try Resolver.init(.{
        .loop = loop.?,
        .name_server = "8.8.8.8",
    });
    defer resolver.deinit();
    try resolver.getAddressList(.{
        .incoming_name = "www.google.com",
        .allocator = testing.allocator,
        .onAddrListFn = Context.onAddrList,
        .onCloseFn = Context.onClose,
    });
    _ = c.hloop_run(loop);
}
