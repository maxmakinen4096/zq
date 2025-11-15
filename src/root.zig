const std = @import("std");

const parser = @import("json/parser.zig");
const types = @import("json/types.zig");
const filter_parser = @import("filter/parser.zig");
const filter_evaluator = @import("filter/evaluator.zig");

pub const parseFromFile = parser.parseFromFile;
pub const parseFromStdin = parser.parseFromStdin;
pub const parseFromString = parser.parseFromString;

pub const prettyPrint = types.prettyPrint;
pub const PrettyPrintOptions = types.PrettyPrintOptions;

pub const FilterParser = filter_parser.Parser;
pub const evaluateFilter = filter_evaluator.evaluate;
pub const evaluateFilterMulti = filter_evaluator.evaluateMulti;

test "library API - parse JSON" {
    const allocator = std.testing.allocator;

    const json_str = "{\"test\": true}";
    const parsed = try parseFromString(allocator, json_str);
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
}
