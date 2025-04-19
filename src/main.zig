const std = @import("std");
const ws = @import("websocket");

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const BUFFER_SIZE: usize = 4096;

pub fn main() !void {
    defer if (gpa.deinit() == .leak) {
        @panic("memory leak");
    };

    var server = try ws.Server(Handler).init(allocator, .{
        .port = 8250,
        .address = "0.0.0.0",
        .handshake = .{
            .timeout = 300,
            .max_size = 65535,
            .max_headers = 0,
        },
    });

    const thread = try server.listenInNewThread({});
    defer thread.join();
}

const Handler = struct {
    conn: *ws.Conn,
    writer_thread: std.Thread,

    const Self = @This();

    pub fn init(handshake: ws.Handshake, conn: *ws.Conn, ctx: void) !Self {
        _ = handshake;
        _ = ctx;

        return .{
            .conn = conn,
            .writer_thread = undefined,
        };
    }

    pub fn afterInit(self: *Self) !void {
        self.writer_thread = try std.Thread.spawn(.{}, spinningWriter, .{ self.conn });
    }

    pub fn clientClose(self: *Self, data: []u8) !void {
        _ = data;
        std.log.info("cleaning up the writer thread.", .{});
        self.writer_thread.join();
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        _ = self;

        try stdout.print("Received data:\n{s}\n\n", .{ data });
    }
};

fn spinningWriter(conn: *ws.Conn) !void {
    std.log.info("spawned writer thread.", .{});
    while (true) {
        try stdout.print("Input: (use \"%\" for end of message)\n", .{});

        const buffer = stdin.readUntilDelimiterAlloc(allocator, '%', 4096) catch {
            break;
        };
        defer allocator.free(buffer);

        try conn.write(buffer);
    }

    std.log.info("closing connection.", .{});
    try conn.close(.{});
}
