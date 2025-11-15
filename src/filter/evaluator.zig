const std = @import("std");
const ast = @import("ast.zig");
const Node = ast.Node;

pub fn evaluateMulti(
    node: *const Node,
    value: std.json.Value,
    allocator: std.mem.Allocator,
) anyerror!std.ArrayList(std.json.Value) {
    var results: std.ArrayList(std.json.Value) = .{};

    switch (node.*) {
        .identity => {
            try results.append(allocator, value);
            return results;
        },
        .array_index => |idx| {
            const result = try evaluateArrayIndex(value, idx.index, allocator);
            try results.append(allocator, result);
            return results;
        },
        .field_access => |field| {
            const result = try evaluateFieldAccess(value, field.field, field.optional, allocator);
            try results.append(allocator, result);
            return results;
        },
        .pipe => |pipe| {
            var left_results = try evaluateMulti(pipe.left, value, allocator);
            defer left_results.deinit(allocator);

            for (left_results.items) |left_value| {
                var right_results = try evaluateMulti(pipe.right, left_value, allocator);
                defer right_results.deinit(allocator);
                for (right_results.items) |right_value| {
                    try results.append(allocator, right_value);
                }
            }
            return results;
        },
        .array_construct => |construct| {
            const result = try evaluateArrayConstruct(construct.filter, value, allocator);
            try results.append(allocator, result);
            return results;
        },
        .array_iterator => {
            return try evaluateArrayIterator(value, allocator);
        },
        .comma => |comma| {
            var left_results = try evaluateMulti(comma.left, value, allocator);
            defer left_results.deinit(allocator);
            var right_results = try evaluateMulti(comma.right, value, allocator);
            defer right_results.deinit(allocator);

            for (left_results.items) |item| {
                try results.append(allocator, item);
            }
            for (right_results.items) |item| {
                try results.append(allocator, item);
            }
            return results;
        },
    }
}

pub fn evaluate(
    node: *const Node,
    value: std.json.Value,
    allocator: std.mem.Allocator,
) anyerror!std.json.Value {
    var results = try evaluateMulti(node, value, allocator);
    defer results.deinit(allocator);

    if (results.items.len == 0) {
        return error.NoOutput;
    }
    return results.items[0];
}

fn evaluateArrayIndex(
    value: std.json.Value,
    index: i64,
    allocator: std.mem.Allocator,
) anyerror!std.json.Value {
    _ = allocator;

    if (value != .array) {
        return error.NotAnArray;
    }

    const array = value.array;
    const len = array.items.len;

    var actual_index: usize = undefined;
    if (index < 0) {
        const neg_index = @abs(index);
        if (neg_index > len) {
            return error.IndexOutOfBounds;
        }
        actual_index = len - @as(usize, @intCast(neg_index));
    } else {
        actual_index = @intCast(index);
    }

    if (actual_index >= len) {
        return error.IndexOutOfBounds;
    }

    return array.items[actual_index];
}

fn evaluateFieldAccess(
    value: std.json.Value,
    field: []const u8,
    optional: bool,
    allocator: std.mem.Allocator,
) anyerror!std.json.Value {
    _ = allocator;

    if (value != .object) {
        if (optional) {
            return std.json.Value{ .null = {} };
        }
        return error.NotAnObject;
    }

    const object = value.object;
    if (object.get(field)) |field_value| {
        return field_value;
    } else {
        if (optional) {
            return std.json.Value{ .null = {} };
        }
        return error.FieldNotFound;
    }
}

fn evaluateArrayIterator(
    value: std.json.Value,
    allocator: std.mem.Allocator,
) anyerror!std.ArrayList(std.json.Value) {
    var results: std.ArrayList(std.json.Value) = .{};

    if (value != .array) {
        return error.NotAnArray;
    }

    for (value.array.items) |item| {
        try results.append(allocator, item);
    }

    return results;
}

fn evaluateArrayConstruct(
    filter: *const Node,
    value: std.json.Value,
    allocator: std.mem.Allocator,
) anyerror!std.json.Value {
    var results = try evaluateMulti(filter, value, allocator);
    defer results.deinit(allocator);

    var array = std.json.Array{
        .items = &[_]std.json.Value{},
        .capacity = 0,
        .allocator = allocator,
    };

    for (results.items) |item| {
        try array.append(item);
    }

    return std.json.Value{ .array = array };
}

test "evaluator - identity" {
    const allocator = std.testing.allocator;

    const json_str = "{\"name\": \"test\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const node = Node{ .identity = {} };
    const result = try evaluate(&node, parsed.value, allocator);

    try std.testing.expect(result == .object);
}

test "evaluator - array index" {
    const allocator = std.testing.allocator;

    const json_str = "[1, 2, 3]";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const node = Node{ .array_index = .{ .index = 1 } };
    const result = try evaluate(&node, parsed.value, allocator);

    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 2), result.integer);
}

test "evaluator - array index negative" {
    const allocator = std.testing.allocator;

    const json_str = "[1, 2, 3]";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const node = Node{ .array_index = .{ .index = -1 } };
    const result = try evaluate(&node, parsed.value, allocator);

    try std.testing.expect(result == .integer);
    try std.testing.expectEqual(@as(i64, 3), result.integer);
}

test "evaluator - field access" {
    const allocator = std.testing.allocator;

    const json_str = "{\"name\": \"John\", \"age\": 30}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const field_name = try allocator.dupe(u8, "name");
    defer allocator.free(field_name);

    var node = Node{ .field_access = .{ .field = field_name, .optional = false } };
    const result = try evaluate(&node, parsed.value, allocator);

    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("John", result.string);
}

test "evaluator - field access optional missing" {
    const allocator = std.testing.allocator;

    const json_str = "{\"name\": \"John\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const field_name = try allocator.dupe(u8, "age");
    defer allocator.free(field_name);

    var node = Node{ .field_access = .{ .field = field_name, .optional = true } };
    const result = try evaluate(&node, parsed.value, allocator);

    try std.testing.expect(result == .null);
}
