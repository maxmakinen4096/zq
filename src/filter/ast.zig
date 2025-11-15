const std = @import("std");

pub const Node = union(enum) {
    identity: void,

    array_index: ArrayIndex,

    field_access: FieldAccess,

    pipe: Pipe,

    array_construct: ArrayConstruct,

    array_iterator: void,

    comma: Comma,

    pub const ArrayIndex = struct {
        index: i64,
    };

    pub const FieldAccess = struct {
        field: []const u8,
        optional: bool,
    };

    pub const Pipe = struct {
        left: *Node,
        right: *Node,
    };

    pub const ArrayConstruct = struct {
        filter: *Node,
    };

    pub const Comma = struct {
        left: *Node,
        right: *Node,
    };

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .identity => {},
            .array_index => {},
            .array_iterator => {},
            .field_access => |field| {
                allocator.free(field.field);
            },
            .pipe => |pipe| {
                pipe.left.deinit(allocator);
                allocator.destroy(pipe.left);
                pipe.right.deinit(allocator);
                allocator.destroy(pipe.right);
            },
            .array_construct => |construct| {
                construct.filter.deinit(allocator);
                allocator.destroy(construct.filter);
            },
            .comma => |comma| {
                comma.left.deinit(allocator);
                allocator.destroy(comma.left);
                comma.right.deinit(allocator);
                allocator.destroy(comma.right);
            },
        }
    }
};
