// Nutation + sidereal time differential checking: parse the C oracle's
// corpus lines (kinds B, O, X, Y, Z) and recompute with the Zig port,
// comparing bit-for-bit (%.17g round-trips doubles exactly).
// Kinds:
//   B: swi_nutation(J, iflag, nut/jplhora)      -> nutlo[2]
//   O: swi_bias(x[6], J, iflag, dir, bias/jplhora) -> x[6]
//   X: swi_icrs2fk5(x[6], iflag, dir)           -> x[6]
//   Y: swe_sidtime0(J, eps, nut, sidt)          -> sidtime hours
//   Z: swe_sidtime(J_ut, sidt)                  -> sidtime hours
// astro_models entries are corpus inputs; EOP tables empty as in the C
// oracle (SEFLG_JPLHOR excluded there: unreachable without eop.txt).
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");

const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;

fn bitsEq(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

fn parseFail(line: []const u8) bool {
    std.debug.print("PARSE FAIL: {s}\n", .{line});
    return false;
}

fn parseFloat(s: ?[]const u8) ?f64 {
    return std.fmt.parseFloat(f64, s.?) catch null;
}

fn parseInt(s: ?[]const u8) ?i32 {
    return std.fmt.parseInt(i32, s.?, 10) catch null;
}

var dctx = deltat.DeltatCtx{};

fn checkB(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "B")) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const nut = parseInt(tok.next()) orelse return parseFail(line);
    const jh = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [2]f64 = undefined;
    want[0] = parseFloat(tok.next()) orelse return parseFail(line);
    want[1] = parseFloat(tok.next()) orelse return parseFail(line);
    const models = lib.AstroModels{ .nut = nut, .jplhora = jh };
    var got: [2]f64 = undefined;
    _ = lib.swi_nutation(J, iflag, &got, models, null);
    if (bitsEq(got[0], want[0]) and bitsEq(got[1], want[1])) return true;
    std.debug.print("MISMATCH: {s}\n  want={x},{x} got={x},{x}\n", .{
        line,
        @as(u64, @bitCast(want[0])),
        @as(u64, @bitCast(want[1])),
        @as(u64, @bitCast(got[0])),
        @as(u64, @bitCast(got[1])),
    });
    return false;
}

fn checkO(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "O")) return true;
    var x_in: [3]f64 = undefined;
    x_in[0] = parseFloat(tok.next()) orelse return parseFail(line);
    x_in[1] = parseFloat(tok.next()) orelse return parseFail(line);
    x_in[2] = parseFloat(tok.next()) orelse return parseFail(line);
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const dir = parseInt(tok.next()) orelse return parseFail(line);
    const bias = parseInt(tok.next()) orelse return parseFail(line);
    const jh = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    var got: [6]f64 = .{ x_in[0], x_in[1], x_in[2], 0.01, -0.02, 0.003 };
    const models = lib.AstroModels{ .bias = bias, .jplhora = jh };
    lib.swi_bias(&got, J, iflag, dir != 0, models);
    for (got, want) |g, w| {
        if (!bitsEq(g, w)) {
            std.debug.print("MISMATCH: {s}\n  want={x},{x},{x},{x},{x},{x}\n  got= {x},{x},{x},{x},{x},{x}\n", .{
                line,
                @as(u64, @bitCast(want[0])),
                @as(u64, @bitCast(want[1])),
                @as(u64, @bitCast(want[2])),
                @as(u64, @bitCast(want[3])),
                @as(u64, @bitCast(want[4])),
                @as(u64, @bitCast(want[5])),
                @as(u64, @bitCast(got[0])),
                @as(u64, @bitCast(got[1])),
                @as(u64, @bitCast(got[2])),
                @as(u64, @bitCast(got[3])),
                @as(u64, @bitCast(got[4])),
                @as(u64, @bitCast(got[5])),
            });
            return false;
        }
    }
    return true;
}

fn checkX(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "X")) return true;
    var x_in: [3]f64 = undefined;
    x_in[0] = parseFloat(tok.next()) orelse return parseFail(line);
    x_in[1] = parseFloat(tok.next()) orelse return parseFail(line);
    x_in[2] = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const dir = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    var got: [6]f64 = .{ x_in[0], x_in[1], x_in[2], 0.01, -0.02, 0.003 };
    lib.swi_icrs2fk5(&got, iflag, dir != 0);
    // without SEFLG_SPEED the C function never writes x[3..5] (stack
    // garbage in the oracle); compare positions only in that case
    const want_speed = (iflag & 256) != 0;
    for (got, want, 0..) |g, w, ci| {
        if (ci >= 3 and !want_speed) break;
        if (!bitsEq(g, w)) {
            std.debug.print("MISMATCH: {s}\n  want={x},{x},{x},{x},{x},{x}\n  got= {x},{x},{x},{x},{x},{x}\n", .{
                line,
                @as(u64, @bitCast(want[0])),
                @as(u64, @bitCast(want[1])),
                @as(u64, @bitCast(want[2])),
                @as(u64, @bitCast(want[3])),
                @as(u64, @bitCast(want[4])),
                @as(u64, @bitCast(want[5])),
                @as(u64, @bitCast(got[0])),
                @as(u64, @bitCast(got[1])),
                @as(u64, @bitCast(got[2])),
                @as(u64, @bitCast(got[3])),
                @as(u64, @bitCast(got[4])),
                @as(u64, @bitCast(got[5])),
            });
            return false;
        }
    }
    return true;
}

fn checkY(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "Y")) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const eps = parseFloat(tok.next()) orelse return parseFail(line);
    const nut = parseFloat(tok.next()) orelse return parseFail(line);
    const sidt = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    const models = lib.AstroModels{ .sidt = sidt };
    const got = lib.swe_sidtime0(J, eps, nut, models, &dctx, null);
    if (bitsEq(got, want)) return true;
    std.debug.print("MISMATCH: {s}\n  want={x} got={x}\n", .{ line, @as(u64, @bitCast(want)), @as(u64, @bitCast(got)) });
    return false;
}

fn checkZ(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "Z")) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const sidt = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    const models = lib.AstroModels{ .sidt = sidt };
    const got = lib.swe_sidtime(J, models, &dctx, null);
    if (bitsEq(got, want)) return true;
    std.debug.print("MISMATCH: {s}\n  want={x} got={x}\n", .{ line, @as(u64, @bitCast(want)), @as(u64, @bitCast(got)) });
    return false;
}

pub fn checkNutLine(line: []const u8) bool {
    if (line.len == 0) return true;
    return switch (line[0]) {
        'B' => checkB(line),
        'O' => checkO(line),
        'X' => checkX(line),
        'Y' => checkY(line),
        'Z' => checkZ(line),
        else => true,
    };
}
