const std = @import("std");

pub const TokenType = enum {
    dot,
    left_bracket,
    right_bracket,
    pipe,
    question,
    comma,
    number,
    identifier,
    string,
    eof,
};

pub const Token = struct {
    type: TokenType,
    value: ?[]const u8 = null,
    position: usize,
};

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Lexer {
        return .{
            .input = input,
            .position = 0,
            .allocator = allocator,
        };
    }

    pub fn nextToken(self: *Lexer) !Token {
        self.skipWhitespace();

        if (self.position >= self.input.len) {
            return Token{
                .type = .eof,
                .position = self.position,
            };
        }

        const start_pos = self.position;
        const ch = self.input[self.position];

        switch (ch) {
            '.' => {
                self.position += 1;
                return Token{
                    .type = .dot,
                    .position = start_pos,
                };
            },
            '[' => {
                self.position += 1;
                return Token{
                    .type = .left_bracket,
                    .position = start_pos,
                };
            },
            ']' => {
                self.position += 1;
                return Token{
                    .type = .right_bracket,
                    .position = start_pos,
                };
            },
            '|' => {
                self.position += 1;
                return Token{
                    .type = .pipe,
                    .position = start_pos,
                };
            },
            '?' => {
                self.position += 1;
                return Token{
                    .type = .question,
                    .position = start_pos,
                };
            },
            ',' => {
                self.position += 1;
                return Token{
                    .type = .comma,
                    .position = start_pos,
                };
            },
            '"' => {
                return try self.readString();
            },
            '-', '0'...'9' => {
                return try self.readNumber();
            },
            'a'...'z', 'A'...'Z', '_' => {
                return try self.readIdentifier();
            },
            else => {
                return error.UnexpectedCharacter;
            },
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.position < self.input.len) {
            const ch = self.input[self.position];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.position += 1;
            } else {
                break;
            }
        }
    }

    fn readString(self: *Lexer) !Token {
        const start_pos = self.position;
        self.position += 1;

        const start = self.position;
        while (self.position < self.input.len and self.input[self.position] != '"') {
            if (self.input[self.position] == '\\') {
                self.position += 1;
            }
            self.position += 1;
        }

        if (self.position >= self.input.len) {
            return error.UnterminatedString;
        }

        const value = self.input[start..self.position];
        self.position += 1;

        const owned_value = try self.allocator.dupe(u8, value);

        return Token{
            .type = .string,
            .value = owned_value,
            .position = start_pos,
        };
    }

    fn readNumber(self: *Lexer) !Token {
        const start_pos = self.position;
        const start = self.position;

        if (self.input[self.position] == '-') {
            self.position += 1;
        }

        while (self.position < self.input.len and
            self.input[self.position] >= '0' and
            self.input[self.position] <= '9')
        {
            self.position += 1;
        }

        const value = self.input[start..self.position];
        const owned_value = try self.allocator.dupe(u8, value);

        return Token{
            .type = .number,
            .value = owned_value,
            .position = start_pos,
        };
    }

    fn readIdentifier(self: *Lexer) !Token {
        const start_pos = self.position;
        const start = self.position;

        while (self.position < self.input.len) {
            const ch = self.input[self.position];
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '_')
            {
                self.position += 1;
            } else {
                break;
            }
        }

        const value = self.input[start..self.position];
        const owned_value = try self.allocator.dupe(u8, value);

        return Token{
            .type = .identifier,
            .value = owned_value,
            .position = start_pos,
        };
    }
};

test "lexer - simple tokens" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, ".");
    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.dot, token1.type);

    var lexer2 = Lexer.init(allocator, "[]");
    const token2 = try lexer2.nextToken();
    try std.testing.expectEqual(TokenType.left_bracket, token2.type);
    const token3 = try lexer2.nextToken();
    try std.testing.expectEqual(TokenType.right_bracket, token3.type);
}

test "lexer - number" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "42");
    const token = try lexer.nextToken();
    defer if (token.value) |v| allocator.free(v);

    try std.testing.expectEqual(TokenType.number, token.type);
    try std.testing.expectEqualStrings("42", token.value.?);
}

test "lexer - identifier" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "field_name");
    const token = try lexer.nextToken();
    defer if (token.value) |v| allocator.free(v);

    try std.testing.expectEqual(TokenType.identifier, token.type);
    try std.testing.expectEqualStrings("field_name", token.value.?);
}
