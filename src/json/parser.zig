const std = @import("std");

pub fn parseFromFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !std.json.Parsed(std.json.Value) {
    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(content);

    return try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
}

pub fn parseFromStdin(
    allocator: std.mem.Allocator,
) !std.json.Parsed(std.json.Value) {
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const content = try stdin_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    return try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
}

pub fn parseFromString(
    allocator: std.mem.Allocator,
    json_string: []const u8,
) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
}

test "parse simple JSON string" {
    const allocator = std.testing.allocator;

    const json_str =
        \\{"name": "test", "value": 42}
    ;

    const parsed = try parseFromString(allocator, json_str);
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try std.testing.expect(obj.get("name") != null);
    try std.testing.expect(obj.get("value") != null);
}

test "parse array" {
    const allocator = std.testing.allocator;

    const json_str = "[1, 2, 3, 4, 5]";

    const parsed = try parseFromString(allocator, json_str);
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .array);
    try std.testing.expectEqual(@as(usize, 5), parsed.value.array.items.len);
}

test "parse nested structure" {
    const allocator = std.testing.allocator;

    const json_str =
        \\{
        \\  "user": {
        \\    "name": "Alice",
        \\    "age": 28
        \\  }
        \\}
    ;

    const parsed = try parseFromString(allocator, json_str);
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const user = parsed.value.object.get("user").?;
    try std.testing.expect(user == .object);
    try std.testing.expect(user.object.get("name") != null);
}
