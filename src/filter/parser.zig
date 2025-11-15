const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;
const ast = @import("ast.zig");
const Node = ast.Node;

pub const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !Parser {
        var lexer = Lexer.init(allocator, input);
        const current_token = try lexer.nextToken();

        return .{
            .lexer = lexer,
            .current_token = current_token,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) anyerror!*Node {
        return try self.parsePipe();
    }

    fn parsePipe(self: *Parser) anyerror!*Node {
        var left = try self.parseComma();

        while (self.current_token.type == .pipe) {
            try self.advance();
            const right = try self.parseComma();

            const pipe_node = try self.allocator.create(Node);
            pipe_node.* = Node{
                .pipe = .{
                    .left = left,
                    .right = right,
                },
            };
            left = pipe_node;
        }

        return left;
    }

    fn parseComma(self: *Parser) anyerror!*Node {
        var left = try self.parsePostfix();

        while (self.current_token.type == .comma) {
            try self.advance();
            const right = try self.parsePostfix();

            const comma_node = try self.allocator.create(Node);
            comma_node.* = Node{
                .comma = .{
                    .left = left,
                    .right = right,
                },
            };
            left = comma_node;
        }

        return left;
    }

    fn parsePostfix(self: *Parser) anyerror!*Node {
        var node = try self.parsePrimary();

        while (true) {
            switch (self.current_token.type) {
                .left_bracket => {
                    node = try self.parseArrayIndex(node);
                },
                .dot => {
                    const next_pos = self.lexer.position;
                    if (next_pos < self.lexer.input.len) {
                        try self.advance();
                        if (self.current_token.type == .identifier or
                            self.current_token.type == .left_bracket)
                        {
                            node = try self.parseFieldOrIndex(node);
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }

        return node;
    }

    fn parsePrimary(self: *Parser) anyerror!*Node {
        switch (self.current_token.type) {
            .dot => {
                try self.advance();

                switch (self.current_token.type) {
                    .identifier => {
                        return try self.parseFieldAccess();
                    },
                    .left_bracket => {
                        return try self.parseArrayIndexOrString();
                    },
                    else => {
                        const node = try self.allocator.create(Node);
                        node.* = Node{ .identity = {} };
                        return node;
                    },
                }
            },
            .left_bracket => {
                try self.advance();
                const filter = try self.parsePipe();
                try self.expect(.right_bracket);

                const node = try self.allocator.create(Node);
                node.* = Node{
                    .array_construct = .{
                        .filter = filter,
                    },
                };
                return node;
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }

    fn parseFieldAccess(self: *Parser) anyerror!*Node {
        if (self.current_token.type != .identifier) {
            return error.ExpectedIdentifier;
        }

        const field_name = self.current_token.value.?;
        const owned_field = try self.allocator.dupe(u8, field_name);
        try self.advance();

        const optional = if (self.current_token.type == .question) blk: {
            try self.advance();
            break :blk true;
        } else false;

        const node = try self.allocator.create(Node);
        node.* = Node{
            .field_access = .{
                .field = owned_field,
                .optional = optional,
            },
        };
        return node;
    }

    fn parseArrayIndexOrString(self: *Parser) anyerror!*Node {
        try self.expect(.left_bracket);

        switch (self.current_token.type) {
            .number => {
                return try self.parseArrayIndexNumber();
            },
            .string => {
                return try self.parseFieldAccessString();
            },
            .right_bracket => {
                try self.advance();
                const node = try self.allocator.create(Node);
                node.* = Node{ .array_iterator = {} };
                return node;
            },
            else => {
                return error.ExpectedNumberOrString;
            },
        }
    }

    fn parseArrayIndexNumber(self: *Parser) anyerror!*Node {
        if (self.current_token.type != .number) {
            return error.ExpectedNumber;
        }

        const num_str = self.current_token.value.?;
        const index = try std.fmt.parseInt(i64, num_str, 10);
        try self.advance();
        try self.expect(.right_bracket);

        const node = try self.allocator.create(Node);
        node.* = Node{
            .array_index = .{
                .index = index,
            },
        };
        return node;
    }

    fn parseFieldAccessString(self: *Parser) anyerror!*Node {
        if (self.current_token.type != .string) {
            return error.ExpectedString;
        }

        const field_name = self.current_token.value.?;
        const owned_field = try self.allocator.dupe(u8, field_name);
        try self.advance();
        try self.expect(.right_bracket);

        const optional = if (self.current_token.type == .question) blk: {
            try self.advance();
            break :blk true;
        } else false;

        const node = try self.allocator.create(Node);
        node.* = Node{
            .field_access = .{
                .field = owned_field,
                .optional = optional,
            },
        };
        return node;
    }

    fn parseArrayIndex(self: *Parser, base: *Node) anyerror!*Node {
        try self.expect(.left_bracket);

        if (self.current_token.type != .number) {
            return error.ExpectedNumber;
        }

        const num_str = self.current_token.value.?;
        const index = try std.fmt.parseInt(i64, num_str, 10);
        try self.advance();
        try self.expect(.right_bracket);

        const index_node = try self.allocator.create(Node);
        index_node.* = Node{
            .array_index = .{
                .index = index,
            },
        };

        const pipe_node = try self.allocator.create(Node);
        pipe_node.* = Node{
            .pipe = .{
                .left = base,
                .right = index_node,
            },
        };

        return pipe_node;
    }

    fn parseFieldOrIndex(self: *Parser, base: *Node) anyerror!*Node {
        const field_node = switch (self.current_token.type) {
            .identifier => try self.parseFieldAccess(),
            .left_bracket => try self.parseArrayIndexOrString(),
            else => return error.UnexpectedToken,
        };

        const pipe_node = try self.allocator.create(Node);
        pipe_node.* = Node{
            .pipe = .{
                .left = base,
                .right = field_node,
            },
        };

        return pipe_node;
    }

    fn advance(self: *Parser) !void {
        if (self.current_token.value) |v| {
            self.allocator.free(v);
        }
        self.current_token = try self.lexer.nextToken();
    }

    fn expect(self: *Parser, expected: TokenType) !void {
        if (self.current_token.type != expected) {
            return error.UnexpectedToken;
        }
        try self.advance();
    }

    pub fn deinit(self: *Parser) void {
        if (self.current_token.value) |v| {
            self.allocator.free(v);
        }
    }
};

test "parser - identity" {
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator, ".");
    defer parser.deinit();

    const node = try parser.parse();
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .identity);
}

test "parser - array index" {
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator, ".[0]");
    defer parser.deinit();

    const node = try parser.parse();
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .array_index);
    try std.testing.expectEqual(@as(i64, 0), node.array_index.index);
}

test "parser - field access" {
    const allocator = std.testing.allocator;

    var parser = try Parser.init(allocator, ".name");
    defer parser.deinit();

    const node = try parser.parse();
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .field_access);
    try std.testing.expectEqualStrings("name", node.field_access.field);
}
