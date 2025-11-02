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

pub fn Solver(T: type, comptime options: Options) type {
    return struct {
        rules: []const Rule(T, options.Error),

        const Self = @This();

        pub fn solve(slvr: Self, state: *State(T)) options.Error!void {
            while (true) {
                const old = state.*;
                for (slvr.rules) |r| {
                    trace("solve {f}", .{state});
                    try r.apply(state);
                }
                trace("solve old {f} new {f}\n", .{ old, state });
                if (old.fields_present.bits == state.fields_present.bits and
                    options.eql(old.value, state.value)) break;
            }
        }
    };
}

pub const Options = struct {
    Error: type = error{},
    eql: @TypeOf(std.meta.eql) = std.meta.eql,
};

pub fn solver(
    T: type,
    comptime options: Options,
    rules: []const Rule(T, options.Error),
) Solver(T, options) {
    return .{ .rules = rules };
}

pub fn Rule(T: type, Error: type) type {
    return struct {
        guard: *const fn (*State(T)) Error!bool = nopGuard,
        body: *const fn (*State(T)) Error!void = nopBody,

        const Self = @This();

        pub fn init(R: type) Self {
            var rule: Self = .{};
            if (@hasDecl(R, "guard")) rule.guard = R.guard;
            if (@hasDecl(R, "body")) rule.body = R.body;
            return rule;
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

        pub fn nopGuard(_: *State(T)) Error!bool {
            return false;
        }
        pub fn nopBody(_: *State(T)) Error!void {}
    };
}

fn trace(comptime fmt: []const u8, args: anytype) void {
    const log = std.log.scoped(.chr);
    if (@import("build_options").log)
        log.debug(fmt, args);
}
