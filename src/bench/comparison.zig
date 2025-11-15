const std = @import("std");
const zq = @import("zq");

pub const BenchmarkCase = struct {
    name: []const u8,
    json_input: []const u8,
    filter: []const u8,
    description: []const u8,
};

pub const BenchmarkResult = struct {
    case_name: []const u8,
    zq_time_ns: u64,
    jq_time_ns: u64,
    zq_faster: bool,
    speedup_factor: f64,
    both_succeeded: bool,
    error_msg: ?[]const u8,
};

fn benchmarkZq(allocator: std.mem.Allocator, json_input: []const u8, filter: []const u8) !u64 {
    const start = std.time.nanoTimestamp();

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_input, .{});
    defer parsed.deinit();

    var filter_parser = try zq.FilterParser.init(allocator, filter);
    const filter_ast = try filter_parser.parse();
    defer {
        filter_ast.deinit(allocator);
        allocator.destroy(filter_ast);
    }

    var results = try zq.evaluateFilterMulti(filter_ast, parsed.value, allocator);
    defer results.deinit(allocator);

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    const Writer = struct {
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

    const writer = Writer{ .list = &output_buf, .alloc = allocator };

    for (results.items) |result| {
        try zq.prettyPrint(result, writer, .{});
    }

    const end = std.time.nanoTimestamp();
    return @intCast(end - start);
}

fn benchmarkJq(allocator: std.mem.Allocator, json_input: []const u8, filter: []const u8) !u64 {
    const start = std.time.nanoTimestamp();

    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(allocator);

    try argv.append(allocator, "jq");
    try argv.append(allocator, "-c");
    try argv.append(allocator, filter);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(json_input);
        stdin.close();
        child.stdin = null;
    }

    const stdout = child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        _ = try child.wait();
        return err;
    };
    defer allocator.free(stdout);

    const stderr = child.stderr.?.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        _ = try child.wait();
        return err;
    };
    defer allocator.free(stderr);

    const term = try child.wait();

    const end = std.time.nanoTimestamp();

    if (term != .Exited or term.Exited != 0) {
        return error.JqFailed;
    }

    return @intCast(end - start);
}

fn measureJqBaseline(allocator: std.mem.Allocator, iterations: usize) !u64 {
    var total: u64 = 0;
    const minimal_json = "{}";
    const minimal_filter = ".";

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const time = benchmarkJq(allocator, minimal_json, minimal_filter) catch {
            return 0;
        };
        total += time;
    }

    return total / iterations;
}

fn runBenchmark(allocator: std.mem.Allocator, case: BenchmarkCase, iterations: usize, jq_baseline_ns: u64) !BenchmarkResult {
    var zq_total: u64 = 0;
    var jq_total: u64 = 0;
    var both_succeeded = true;
    var error_msg: ?[]const u8 = null;

    _ = benchmarkZq(allocator, case.json_input, case.filter) catch {};
    _ = benchmarkJq(allocator, case.json_input, case.filter) catch {};

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const zq_time = benchmarkZq(allocator, case.json_input, case.filter) catch |err| {
            both_succeeded = false;
            error_msg = try std.fmt.allocPrint(allocator, "zq failed: {}", .{err});
            break;
        };
        zq_total += zq_time;

        const jq_time = benchmarkJq(allocator, case.json_input, case.filter) catch |err| {
            both_succeeded = false;
            error_msg = try std.fmt.allocPrint(allocator, "jq failed: {}", .{err});
            break;
        };
        const adjusted_jq_time = if (jq_time > jq_baseline_ns) jq_time - jq_baseline_ns else 0;
        jq_total += adjusted_jq_time;
    }

    const zq_avg = if (both_succeeded) zq_total / iterations else 0;
    const jq_avg = if (both_succeeded) jq_total / iterations else 0;

    const zq_faster = zq_avg < jq_avg;
    const speedup_factor = if (both_succeeded and jq_avg > 0)
        @as(f64, @floatFromInt(jq_avg)) / @as(f64, @floatFromInt(zq_avg))
    else
        0.0;

    return BenchmarkResult{
        .case_name = case.name,
        .zq_time_ns = zq_avg,
        .jq_time_ns = jq_avg,
        .zq_faster = zq_faster,
        .speedup_factor = speedup_factor,
        .both_succeeded = both_succeeded,
        .error_msg = error_msg,
    };
}

pub fn printReport(allocator: std.mem.Allocator, results: []const BenchmarkResult) !void {
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    const Writer = struct {
        buf: *std.ArrayList(u8),
        alloc: std.mem.Allocator,

        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.buf.appendSlice(self.alloc, bytes);
        }
    };

    const stdout = Writer{ .buf = &output_buf, .alloc = allocator };

    const printToWriter = struct {
        fn call(writer: Writer, comptime fmt: []const u8, args: anytype) !void {
            var buf: [1024]u8 = undefined;
            const formatted = try std.fmt.bufPrint(&buf, fmt, args);
            try writer.writeAll(formatted);
        }
    }.call;

    try stdout.writeAll("\nzq vs jq Performance Comparison\n\n");

    var wins: usize = 0;
    var losses: usize = 0;
    var total_speedup: f64 = 0.0;

    for (results) |result| {
        if (!result.both_succeeded) {
            const error_msg = result.error_msg orelse "Unknown error";
            try printToWriter(stdout, "{s}: ERROR - {s}\n", .{ result.case_name, error_msg });
            continue;
        }

        const zq_ms = @as(f64, @floatFromInt(result.zq_time_ns)) / 1_000_000.0;
        const jq_ms = @as(f64, @floatFromInt(result.jq_time_ns)) / 1_000_000.0;

        try printToWriter(stdout, "{s}:     zq={d:.3}ms     jq={d:.3}ms\n", .{
            result.case_name,
            zq_ms,
            jq_ms,
        });

        if (result.zq_faster) {
            wins += 1;
        } else {
            losses += 1;
        }
        total_speedup += result.speedup_factor;
    }

    try printToWriter(stdout, "Total benchmarks: {}\n", .{results.len});
    try printToWriter(stdout, "zq faster: {}\n", .{wins});
    try printToWriter(stdout, "jq faster: {}\n", .{losses});

    try stdout.writeAll("\n");

    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = try stdout_file.write(output_buf.items);
}

pub fn getDefaultBenchmarks(allocator: std.mem.Allocator) ![]const BenchmarkCase {
    var cases: std.ArrayList(BenchmarkCase) = .{};

    try cases.append(allocator, .{
        .name = "Identity (small)",
        .json_input = "{\"name\":\"John\",\"age\":30}",
        .filter = ".",
        .description = "Simple identity filter on small object",
    });

    try cases.append(allocator, .{
        .name = "Field access (small)",
        .json_input = "{\"name\":\"John\",\"age\":30,\"city\":\"NYC\"}",
        .filter = ".name",
        .description = "Simple field access",
    });

    try cases.append(allocator, .{
        .name = "Array index (small)",
        .json_input = "[1,2,3,4,5]",
        .filter = ".[2]",
        .description = "Array indexing",
    });

    try cases.append(allocator, .{
        .name = "Nested access",
        .json_input = "{\"user\":{\"profile\":{\"name\":\"Alice\",\"age\":25}}}",
        .filter = ".user.profile.name",
        .description = "Deeply nested field access",
    });

    try cases.append(allocator, .{
        .name = "Array iteration",
        .json_input = "[1,2,3,4,5,6,7,8,9,10]",
        .filter = ".[]",
        .description = "Iterate over array elements",
    });

    try cases.append(allocator, .{
        .name = "Array construction",
        .json_input = "[{\"name\":\"John\"},{\"name\":\"Jane\"},{\"name\":\"Bob\"}]",
        .filter = "[.[].name]",
        .description = "Collect fields into new array",
    });

    try cases.append(allocator, .{
        .name = "Pipe operation",
        .json_input = "{\"users\":[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]}",
        .filter = ".users | .[0] | .name",
        .description = "Chained pipe operations",
    });

    var medium_buf: std.ArrayList(u8) = .{};
    defer medium_buf.deinit(allocator);

    try medium_buf.appendSlice(allocator, "{\"items\":[");
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        if (i > 0) try medium_buf.appendSlice(allocator, ",");
        try medium_buf.appendSlice(allocator, "{\"id\":");
        var id_buf: [16]u8 = undefined;
        const id_str = try std.fmt.bufPrint(&id_buf, "{}", .{i + 1});
        try medium_buf.appendSlice(allocator, id_str);
        try medium_buf.appendSlice(allocator, ",\"name\":\"Item");
        try medium_buf.appendSlice(allocator, id_str);
        try medium_buf.appendSlice(allocator, "\",\"value\":100}");
    }
    try medium_buf.appendSlice(allocator, "],\"total\":50}");

    const medium_json = try allocator.dupe(u8, medium_buf.items);

    try cases.append(allocator, .{
        .name = "Medium JSON identity",
        .json_input = medium_json,
        .filter = ".",
        .description = "Identity on medium-sized JSON",
    });

    try cases.append(allocator, .{
        .name = "Medium JSON field",
        .json_input = medium_json,
        .filter = ".items",
        .description = "Field access on medium JSON",
    });

    try cases.append(allocator, .{
        .name = "Comma operator",
        .json_input = "{\"a\":1,\"b\":2,\"c\":3}",
        .filter = ".a, .b, .c",
        .description = "Multiple outputs with comma",
    });

    try cases.append(allocator, .{
        .name = "Array construction with comma",
        .json_input = "{\"a\":1,\"b\":2,\"c\":3}",
        .filter = "[.a, .b, .c]",
        .description = "Array from multiple fields",
    });

    return cases.toOwnedSlice(allocator);
}

pub fn runBenchmarks(allocator: std.mem.Allocator, iterations: usize) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    var msg_buf: [256]u8 = undefined;
    const msg = try std.fmt.bufPrint(&msg_buf, "Running benchmarks ({} iterations per test)...\n", .{iterations});
    _ = try stdout_file.write(msg);

    _ = try stdout_file.write("Measuring jq baseline overhead... ");
    const jq_baseline_ns = try measureJqBaseline(allocator, iterations);
    const baseline_ms = @as(f64, @floatFromInt(jq_baseline_ns)) / 1_000_000.0;
    var baseline_msg_buf: [256]u8 = undefined;
    const baseline_msg = try std.fmt.bufPrint(&baseline_msg_buf, "{d:.3} ms\n\n", .{baseline_ms});
    _ = try stdout_file.write(baseline_msg);

    const cases = try getDefaultBenchmarks(allocator);
    defer allocator.free(cases);

    var results: std.ArrayList(BenchmarkResult) = .{};
    defer results.deinit(allocator);

    for (cases) |case| {
        var case_msg_buf: [512]u8 = undefined;
        const case_msg = try std.fmt.bufPrint(&case_msg_buf, "  Running: {s}... \n", .{case.name});
        _ = try stdout_file.write(case_msg);

        const result = try runBenchmark(allocator, case, iterations, jq_baseline_ns);
        try results.append(allocator, result);
    }

    try printReport(allocator, results.items);
}
