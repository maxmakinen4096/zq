const std = @import("std");
const bench = @import("bench/comparison.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    const check_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "jq", "--version" },
    }) catch {
        _ = try stdout.write("Error: jq is not installed or not in PATH\n");
        _ = try stdout.write("Please install jq to run benchmarks: https://jqlang.github.io/jq/download/\n");
        std.process.exit(1);
    };
    defer {
        allocator.free(check_result.stdout);
        allocator.free(check_result.stderr);
    }

    if (check_result.term != .Exited or check_result.term.Exited != 0) {
        _ = try stdout.write("Error: jq is not working correctly\n");
        std.process.exit(1);
    }

    const jq_version = std.mem.trim(u8, check_result.stdout, &std.ascii.whitespace);
    var version_buf: [256]u8 = undefined;
    const version_msg = try std.fmt.bufPrint(&version_buf, "Found jq version: {s}\n", .{jq_version});
    _ = try stdout.write(version_msg);

    const iterations: usize = 50;
    try bench.runBenchmarks(allocator, iterations);
}
