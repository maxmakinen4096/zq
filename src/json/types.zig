const std = @import("std");

pub const PrettyPrintOptions = struct {
    indent_size: usize = 2,
    use_colors: bool = false,
    current_indent: usize = 0,
};

pub fn prettyPrint(
    value: std.json.Value,
    writer: anytype,
    options: PrettyPrintOptions,
) anyerror!void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |ns| try writer.writeAll(ns),
        .string => |s| try printString(s, writer),
        .array => |arr| try printArray(arr, writer, options),
        .object => |obj| try printObject(obj, writer, options),
    }
}

fn printString(s: []const u8, writer: anytype) anyerror!void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

fn printArray(
    arr: std.json.Array,
    writer: anytype,
    options: PrettyPrintOptions,
) anyerror!void {
    if (arr.items.len == 0) {
        try writer.writeAll("[]");
        return;
    }

    try writer.writeAll("[\n");

    var new_options = options;
    new_options.current_indent += 1;

    for (arr.items, 0..) |item, i| {
        try writeIndent(writer, new_options.current_indent * options.indent_size);
        try prettyPrint(item, writer, new_options);

        if (i < arr.items.len - 1) {
            try writer.writeByte(',');
        }
        try writer.writeByte('\n');
    }

    try writeIndent(writer, options.current_indent * options.indent_size);
    try writer.writeByte(']');
}

fn printObject(
    obj: std.json.ObjectMap,
    writer: anytype,
    options: PrettyPrintOptions,
) anyerror!void {
    if (obj.count() == 0) {
        try writer.writeAll("{}");
        return;
    }

    try writer.writeAll("{\n");

    var new_options = options;
    new_options.current_indent += 1;

    var iter = obj.iterator();
    var count: usize = 0;
    const total = obj.count();

    while (iter.next()) |entry| {
        try writeIndent(writer, new_options.current_indent * options.indent_size);
        try printString(entry.key_ptr.*, writer);
        try writer.writeAll(": ");
        try prettyPrint(entry.value_ptr.*, writer, new_options);

        count += 1;
        if (count < total) {
            try writer.writeByte(',');
        }
        try writer.writeByte('\n');
    }

    try writeIndent(writer, options.current_indent * options.indent_size);
    try writer.writeByte('}');
}

fn writeIndent(writer: anytype, count: usize) anyerror!void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeByte(' ');
    }
}
