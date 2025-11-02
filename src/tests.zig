const std = @import("std");
const testing = std.testing;
const chr = @import("chr");
const State = chr.State;

/// supports named structs and tuples by using `fromTuple()` and `at()`
fn checkGcd(T: type, expected: anytype, initial: T) !void {
    const gcd = chr.solver(T, .{}, &.{
        .init(struct { // a <= 0
            pub fn guard(s: *State(T)) !bool {
                return if (s.at(0)) |n| n <= 0 else false;
            }
            pub fn body(s: *State(T)) !void {
                s.* = .fromTuple(.{ null, s.at(1) });
            }
        }),
        .init(struct { // 0 < a <= b
            pub fn guard(s: *State(T)) !bool {
                const a = s.at(0) orelse return false;
                const b = s.at(1) orelse return false;
                return 0 < a and a <= b;
            }
            pub fn body(s: *State(T)) !void {
                s.* = .fromTuple(.{
                    s.at(0),
                    s.at(1).? - s.at(0).?,
                });
            }
        }),
        .init(struct { // 0 < b < a
            pub fn guard(s: *State(T)) !bool {
                const a = s.at(0) orelse return false;
                const b = s.at(1) orelse return false;
                return 0 < b and b < a;
            }
            pub fn body(s: *State(T)) !void {
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

    const fib = chr.solver(T, .{}, &.{
        .init(struct { // a > 0
            pub fn guard(s: *State(T)) !bool {
                return if (s.at(0)) |n| n > 0 else false;
            }
            pub fn body(s: *State(T)) !void {
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
    const nub = chr.solver(T, .{}, &.{
        .init(struct {
            pub fn guard(s: *State(T)) !bool {
                return (s.value.input.len != 0);
            }
            pub fn body(s: *State(T)) !void {
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

test "all different with custom eql()" {
    const T = struct { v: [3]u8 };

    const all_diff = chr.solver(T, .{ .eql = struct {
        fn eql(a: anytype, b: anytype) bool {
            return std.mem.eql(u8, &a.v, &b.v);
        }
    }.eql }, &.{
        .init(struct {
            pub fn guard(s: *State(T)) !bool {
                const a, const b, const c = s.value.v;
                return a == b or b == c or a == c;
            }
            pub fn body(s: *State(T)) !void {
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

test "empty solver" {
    const T = struct {};
    const empty = chr.solver(T, .{}, &.{});
    var s: State(T) = .initFull(.{});
    try empty.solve(&s);
}

test "empty rule defaults" {
    const T = struct {};
    const empty = chr.solver(T, .{}, &.{.{}});
    var s: State(T) = .initFull(.{});
    testing.log_level = .debug;
    try empty.solve(&s);
}
