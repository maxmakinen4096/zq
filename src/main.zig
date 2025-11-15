const std = @import("std");
const zq = @import("zq");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var filter: []const u8 = ".";
    var file_path: ?[]const u8 = null;

    if (args.len > 1) {
        filter = args[1];
    }
    if (args.len > 2) {
        file_path = args[2];
    }

    var filter_parser = zq.FilterParser.init(allocator, filter) catch |err| {
        std.debug.print("Error parsing filter: {}\n", .{err});
        std.process.exit(1);
    };
    defer filter_parser.deinit();

    const filter_ast = filter_parser.parse() catch |err| {
        std.debug.print("Error parsing filter: {}\n", .{err});
        std.process.exit(1);
    };
    defer {
        filter_ast.deinit(allocator);
        allocator.destroy(filter_ast);
    }

    const parsed = if (file_path) |path|
        zq.parseFromFile(allocator, path) catch |err| {
            std.debug.print("Error parsing JSON from file: {}\n", .{err});
            std.process.exit(1);
        }
    else
        zq.parseFromStdin(allocator) catch |err| {
            std.debug.print("Error parsing JSON from stdin: {}\n", .{err});
            std.process.exit(1);
        };
    defer parsed.deinit();

    var results = zq.evaluateFilterMulti(filter_ast, parsed.value, allocator) catch |err| {
        std.debug.print("Error evaluating filter: {}\n", .{err});
        std.process.exit(1);
    };
    defer results.deinit(allocator);

    var output_list: std.ArrayList(u8) = .{};
    try output_list.ensureTotalCapacity(allocator, 4096);
    defer output_list.deinit(allocator);

    const ArrayWriter = struct {
        list: *std.ArrayList(u8),
        alloc: std.mem.Allocator,

        pub fn writeByte(self: @This(), byte: u8) !void {
            try self.list.append(self.alloc, byte);
        }

        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.alloc, bytes);
        }

        pub fn print(self: @This(), comptime fmt: []const u8, print_args: anytype) !void {
            var buffer: [256]u8 = undefined;
            const formatted = try std.fmt.bufPrint(&buffer, fmt, print_args);
            try self.writeAll(formatted);
        }
    };

    const writer = ArrayWriter{ .list = &output_list, .alloc = allocator };

    for (results.items) |result| {
        try zq.prettyPrint(result, writer, .{});
        try writer.writeByte('\n');
    }

    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = try stdout_file.write(output_list.items);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
