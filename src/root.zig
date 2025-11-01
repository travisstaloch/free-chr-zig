const chr = @This();
const std = @import("std");
const Type = std.builtin.Type;

/// A struct that tracks which fields of `T` are present using a bit set.  This
/// is a compact representation of `State(T).Optionals`.
pub fn State(T: type) type {
    return struct {
        value: T,
        fields_present: FieldSet,

        const Self = @This();
        pub const Field = std.meta.FieldEnum(T);
        pub const FieldSet = std.enums.EnumSet(Field);
        pub const FieldInt = @typeInfo(Field).@"enum".tag_type;
        const field_names = std.meta.fieldNames(T);

        /// A struct with the same field names and types as T but optional with
        /// null default values.
        pub const Optionals = blk: {
            const fs = std.meta.fields(T);
            var fields: [fs.len]Type.StructField = undefined;
            for (fs, &fields) |tf, *f| {
                f.* = .{
                    .name = tf.name,
                    .type = ?tf.type,
                    .default_value_ptr = &@as(?tf.type, null),
                    .is_comptime = false,
                    .alignment = @alignOf(?tf.type),
                };
            }
            break :blk @Type(.{ .@"struct" = .{
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
                .layout = .auto,
            } });
        };

        pub fn atField(s: Self, comptime field: Field) ?@FieldType(T, @tagName(field)) {
            return if (s.fields_present.contains(field))
                @field(s.value, @tagName(field))
            else
                null;
        }

        pub fn at(
            s: Self,
            comptime field_index: FieldInt,
        ) ?@FieldType(T, field_names[field_index]) {
            return s.atField(@enumFromInt(field_index));
        }

        pub fn set(
            s: *Self,
            comptime field: Field,
            opt_payload: @FieldType(Optionals, @tagName(field)),
        ) void {
            if (opt_payload) |payload| {
                @field(s.value, @tagName(field)) = payload;
                s.fields_present.insert(field);
            } else {
                @field(s.value, @tagName(field)) = undefined;
                s.fields_present.remove(field);
            }
        }

        pub fn fromOptionals(opts: Optionals) Self {
            var ret: Self = .{ .value = undefined, .fields_present = .initEmpty() };
            inline for (std.meta.fields(T), 0..) |f, i| {
                ret.set(@enumFromInt(i), @field(opts, f.name));
            }
            return ret;
        }

        pub const Tuple = blk: {
            const fs = std.meta.fields(T);
            var fields: [fs.len]Type.StructField = undefined;
            for (fs, &fields, 0..) |tf, *f, i| {
                f.* = .{
                    .name = std.fmt.comptimePrint("{}", .{i}),
                    .type = ?tf.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(?tf.type),
                };
            }
            break :blk @Type(.{ .@"struct" = .{
                .fields = &fields,
                .decls = &.{},
                .is_tuple = true,
                .layout = .auto,
            } });
        };

        pub fn fromTuple(tup: Tuple) Self {
            var ret: Self = .{ .value = undefined, .fields_present = .initEmpty() };
            inline for (0..field_names.len) |i| {
                ret.set(@enumFromInt(i), tup[i]);
            }
            return ret;
        }

        pub fn initFull(t: T) Self {
            return .{ .value = t, .fields_present = .initFull() };
        }

        pub fn optionals(s: Self) Optionals {
            var opts: Optionals = .{};
            inline for (std.meta.fields(T), 0..) |f, i| {
                @field(opts, f.name) = s.atField(@enumFromInt(i));
            }
            return opts;
        }

        pub fn format(s: Self, w: *std.Io.Writer) !void {
            try w.writeAll("{ ");
            inline for (0..field_names.len) |i| {
                if (i != 0) try w.writeAll(", ");
                if (s.at(i)) |x|
                    try w.print("{any}", .{x})
                else
                    try w.writeAll("null");
            }
            try w.writeAll(" }");
        }
    };
}

pub fn Solver(T: type, Error: type) type {
    return struct {
        rules: []const Rule(T, Error),

        const Self = @This();

        pub fn solve(slvr: Self, state: *State(T)) Error!void {
            while (true) {
                const old = state.*;
                for (slvr.rules) |r| {
                    trace("solve {f}", .{state});
                    try r.apply(state);
                }
                trace("solve old {f} new {f}\n", .{ old, state });
                if (old.fields_present.bits == state.fields_present.bits and
                    // FIXME: optional user defined eql()
                    std.meta.eql(old.value, state.value)) break;
            }
        }
    };
}

pub fn solver(T: type, Error: type, rules: []const Rule(T, Error)) Solver(T, Error) {
    return .{ .rules = rules };
}

pub fn Rule(T: type, Error: type) type {
    return struct {
        guard: *const fn (*State(T)) Error!bool,
        body: *const fn (*State(T)) Error!void,

        const Self = @This();

        pub fn init(R: type) Self {
            return .{ .guard = R.guard, .body = R.body };
        }

        pub fn apply(r: Self, s: *State(T)) Error!void {
            trace("apply s {f}", .{s});
            if (try r.guard(s)) {
                trace("  guard true", .{});
                try r.body(s);
            } else {
                trace("  guard false", .{});
            }
        }
    };
}

fn trace(comptime fmt: []const u8, args: anytype) void {
    const log = std.log.scoped(.chr);
    if (@import("build_options").log)
        log.debug(fmt, args);
}

const testing = std.testing;

/// supports named struct and tuples by using .fromTuple() and .at()
fn checkGcd(T: type, expected: anytype, initial: T) !void {
    const Error = error{};
    const gcd = chr.solver(T, Error, &.{
        .init(struct { // a <= 0
            pub fn guard(s: *State(T)) Error!bool {
                return if (s.at(0)) |n| n <= 0 else false;
            }
            pub fn body(s: *State(T)) Error!void {
                s.* = .fromTuple(.{ null, s.at(1) });
            }
        }),
        .init(struct { // 0 < a <= b
            pub fn guard(s: *State(T)) Error!bool {
                const a = s.at(0) orelse return false;
                const b = s.at(1) orelse return false;
                return 0 < a and a <= b;
            }
            pub fn body(s: *State(T)) Error!void {
                s.* = .fromTuple(.{
                    s.at(0),
                    s.at(1).? - s.at(0).?,
                });
            }
        }),
        .init(struct { // 0 < b < a
            pub fn guard(s: *State(T)) Error!bool {
                const a = s.at(0) orelse return false;
                const b = s.at(1) orelse return false;
                return 0 < b and b < a;
            }
            pub fn body(s: *State(T)) Error!void {
                s.* = .fromTuple(.{
                    s.at(1),
                    s.at(0).? - s.at(1).?,
                });
            }
        }),
    });
    var s: State(T) = .initFull(initial);
    try gcd.solve(&s);

    try testing.expectEqual(expected, s.at(0));
}

test "gcd" {
    const a = 4;
    const b = 12;
    try checkGcd(struct { i32, i32 }, a, .{ a, b });
    try checkGcd(struct { i32, i32 }, a, .{ b, a });
    try checkGcd(struct { a: i32, b: i32 }, a, .{ .a = a, .b = b });
    try checkGcd(struct { a: i32, b: i32 }, a, .{ .a = b, .b = a });
}

test "gcd fuzz against std.math.gcd oracle" {
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    for (0..100) |_| {
        const a = random.intRangeLessThan(u32, 0, 10_000);
        const b = random.intRangeLessThan(u32, 0, 10_000);
        const expected = std.math.gcd(a, b);

        try checkGcd(struct { u32, u32 }, expected, .{ a, b });
        try checkGcd(struct { u32, u32 }, expected, .{ b, a });
    }
}

test "fib" {
    const T = struct { i32, i32, i32 };
    const Error = error{};
    const fib = chr.solver(T, Error, &.{
        .init(struct { // a > 0
            pub fn guard(s: *State(T)) Error!bool {
                return if (s.at(0)) |n| n > 0 else false;
            }
            pub fn body(s: *State(T)) Error!void {
                s.* = .fromTuple(.{
                    s.at(0).? - 1,
                    s.at(2).?,
                    s.at(1).? + s.at(2).?,
                });
            }
        }),
    });

    var s: State(T) = .initFull(.{ 3, 4, 5 });
    try fib.solve(&s);
    const expected = .{ 0, 14, 23 };
    try testing.expectEqual(expected, s.value);
}

test "nub list deduplication" {
    const T = struct {
        input: []const u8,
        output: std.ArrayList(u8),
    };
    const Error = error{};

    const nub = chr.solver(T, Error, &.{
        .init(struct {
            pub fn guard(s: *State(T)) Error!bool {
                return (s.value.input.len != 0);
            }
            pub fn body(s: *State(T)) Error!void {
                if (std.mem.indexOfScalar(u8, s.value.output.items, s.value.input[0]) == null) {
                    s.value.output.appendAssumeCapacity(s.value.input[0]);
                }
                s.value.input = s.value.input[1..];
            }
        }),
    });

    const input = &.{ 1, 2, 3, 2, 4, 1, 5 };
    const expected = &.{ 1, 2, 3, 4, 5 };
    var output: [expected.len]u8 = undefined;
    var s: State(T) = .initFull(.{
        .input = input,
        .output = .initBuffer(&output),
    });
    try nub.solve(&s);

    try testing.expectEqualSlices(u8, expected, &output);
}

test "all different" {
    const T = struct { v: [3]u8 };
    const Error = error{};
    const all_diff = chr.solver(T, Error, &.{
        .init(struct {
            pub fn guard(s: *State(T)) Error!bool {
                const a, const b, const c = s.value.v;
                return a == b or b == c or a == c;
            }
            pub fn body(s: *State(T)) Error!void {
                const a, const b, const c = s.value.v;
                if (a == b)
                    s.value.v = .{ a, b + 1, c }
                else if (b == c)
                    s.value.v = .{ a, b, c + 1 }
                else if (a == c)
                    s.value.v = .{ a, b, c + 1 };
            }
        }),
    });

    var s: State(T) = .initFull(.{ .v = .{ 5, 5, 5 } });
    try all_diff.solve(&s);

    try testing.expectEqualSlices(u8, &.{ 5, 6, 7 }, &s.value.v);
}
