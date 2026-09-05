// Moon module differential checking: parse the C oracle's moon corpus
// lines (kinds M, E, V, F, I, W, U) and recompute each case with the
// Zig port, comparing bit-for-bit (%.17g round-trips doubles exactly).
// Kinds:
//   M: swi_moshmoon(tjd)              -> retc + x[6] + serr
//   E: swi_epsiln(J, iflag, models)   -> eps
//   V: swi_precess(vec, J, iflag, dir, models) -> vec'
//   F: swi_mean_node(J)               -> retc + pol[3] + serr
//   I: swi_mean_apog(J)               -> retc + pol[3] + serr
//   W: swi_mean_lunar_elements(J)     -> node dnode peri dperi
//   U: swi_intp_apsides(J, ipli)      -> pol[3]
// The oec input (oec.eps/seps/ceps) is derived per tjd exactly like the
// C oracle's calc_epsilon(): eps = swi_epsiln(tjd, 0); seps = sin(eps);
// ceps = cos(eps), using the port's own (differential-tested) swi_epsiln.
const std = @import("std");
const lib = @import("swephlib");
const moon = @import("swemmoon");

// C file statics are process-global; the corpus expects the moon workspace
// (pdp cache, ss/cc tables) to persist across lines in one shared instance.
var moon_ws = moon.MoonWs{};

const AstroModels = lib.AstroModels;
const Eps = lib.Eps;

// C's calc_epsilon uses libm sin/cos; use pure Zig now
const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;

fn bitsEq(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

// Corpus stores '\n' in messages escaped as literal backslash-n so each
// case stays on one physical line; undo that before comparing.
fn unescapeSerr(buf: *[256]u8, src: []const u8) []const u8 {
    var i: usize = 0;
    var n: usize = 0;
    while (i < src.len) {
        if (i + 1 < src.len and src[i] == '\\' and src[i + 1] == 'n') {
            buf[n] = '\n';
            i += 2;
        } else {
            buf[n] = src[i];
            i += 1;
        }
        n += 1;
    }
    return buf[0..n];
}

fn parseFail(line: []const u8) bool {
    std.debug.print("PARSE FAIL: {s}\n", .{line});
    return false;
}

fn parseInt(s: ?[]const u8) ?i32 {
    return std.fmt.parseInt(i32, s.?, 10) catch null;
}

fn parseFloat(s: ?[]const u8) ?f64 {
    return std.fmt.parseFloat(f64, s.?) catch null;
}

fn parseModels(pm: i32, pms: i32, jh: i32) AstroModels {
    return .{ .prec_longterm = pm, .prec_shortterm = pms, .jplhora = jh };
}

fn checkE(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "E")) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const pm = parseInt(tok.next()) orelse return parseFail(line);
    const pms = parseInt(tok.next()) orelse return parseFail(line);
    const jh = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    const got = lib.swi_epsiln(J, iflag, parseModels(pm, pms, jh));
    if (bitsEq(got, want)) return true;
    std.debug.print("MISMATCH: {s}\n  want={x} got={x}\n", .{ line, @as(u64, @bitCast(want)), @as(u64, @bitCast(got)) });
    return false;
}

fn checkV(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "V")) return true;
    var want: [3]f64 = undefined;
    var x: [3]f64 = undefined;
    x[0] = parseFloat(tok.next()) orelse return parseFail(line);
    x[1] = parseFloat(tok.next()) orelse return parseFail(line);
    x[2] = parseFloat(tok.next()) orelse return parseFail(line);
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const dir = parseInt(tok.next()) orelse return parseFail(line);
    const pm = parseInt(tok.next()) orelse return parseFail(line);
    const pms = parseInt(tok.next()) orelse return parseFail(line);
    const jh = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    want[0] = parseFloat(tok.next()) orelse return parseFail(line);
    want[1] = parseFloat(tok.next()) orelse return parseFail(line);
    want[2] = parseFloat(tok.next()) orelse return parseFail(line);
    _ = lib.swi_precess(&x, J, iflag, dir, parseModels(pm, pms, jh));
    if (bitsEq(x[0], want[0]) and bitsEq(x[1], want[1]) and bitsEq(x[2], want[2]))
        return true;
    std.debug.print("MISMATCH: {s}\n  want={x},{x},{x} got={x},{x},{x}\n", .{
        line,
        @as(u64, @bitCast(want[0])),
        @as(u64, @bitCast(want[1])),
        @as(u64, @bitCast(want[2])),
        @as(u64, @bitCast(x[0])),
        @as(u64, @bitCast(x[1])),
        @as(u64, @bitCast(x[2])),
    });
    return false;
}

/// The oec the C oracle used for this tjd (calc_epsilon pattern)
fn oecFor(tjd: f64) Eps {
    var e = Eps{};
    e.teps = tjd;
    e.eps = lib.swi_epsiln(tjd, 0, .{});
    e.seps = swe_shim_sin(e.eps);
    e.ceps = swe_shim_cos(e.eps);
    return e;
}

fn checkM(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "M")) return true;
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_retc = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    var got: [6]f64 = [_]f64{0} ** 6;
    const retc = moon.swi_moshmoon(tjd, false, &got, &oecFor(tjd), .{}, &serr, &moon_ws);
    if (retc != want_retc or !bitsEq(got[0], want[0]) or !bitsEq(got[1], want[1]) or
        !bitsEq(got[2], want[2]) or !bitsEq(got[3], want[3]) or !bitsEq(got[4], want[4]) or
        !bitsEq(got[5], want[5]))
    {
        std.debug.print("MISMATCH: {s}\n  retc want={} got={}\n  want={x},{x},{x},{x},{x},{x}\n  got= {x},{x},{x},{x},{x},{x}\n", .{
            line,                        want_retc,                   retc,
            @as(u64, @bitCast(want[0])), @as(u64, @bitCast(want[1])), @as(u64, @bitCast(want[2])),
            @as(u64, @bitCast(want[3])), @as(u64, @bitCast(want[4])), @as(u64, @bitCast(want[5])),
            @as(u64, @bitCast(got[0])),  @as(u64, @bitCast(got[1])),  @as(u64, @bitCast(got[2])),
            @as(u64, @bitCast(got[3])),  @as(u64, @bitCast(got[4])),  @as(u64, @bitCast(got[5])),
        });
        return false;
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

fn checkPol3(line: []const u8, kind: u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind_tok = tok.next() orelse return true;
    if (kind_tok.len != 1 or kind_tok[0] != kind) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_retc = parseInt(tok.next()) orelse return parseFail(line);
    var want: [3]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    var got: [3]f64 = [_]f64{0} ** 3;
    var retc: i32 = undefined;
    if (kind == 'F') {
        retc = moon.swi_mean_node(J, &got, &serr, &moon_ws);
    } else if (kind == 'I') {
        retc = moon.swi_mean_apog(J, &got, &serr, &moon_ws);
    } else if (kind == 'G') {
        retc = moon.swi_intp_apsides(J, &got, 5, &moon_ws); // SEI_INTP_PERG
    } else {
        retc = moon.swi_intp_apsides(J, &got, 4, &moon_ws); // SEI_INTP_APOG
    }
    if (retc != want_retc or !bitsEq(got[0], want[0]) or !bitsEq(got[1], want[1]) or !bitsEq(got[2], want[2])) {
        std.debug.print("MISMATCH: {s}\n  retc want={} got={}\n  want={x},{x},{x}\n  got= {x},{x},{x}\n", .{
            line,                        want_retc,                   retc,
            @as(u64, @bitCast(want[0])), @as(u64, @bitCast(want[1])), @as(u64, @bitCast(want[2])),
            @as(u64, @bitCast(got[0])),  @as(u64, @bitCast(got[1])),  @as(u64, @bitCast(got[2])),
        });
        return false;
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

fn checkW(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "W")) return true;
    const J = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [4]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    var got: [4]f64 = undefined;
    moon.swi_mean_lunar_elements(J, &got[0], &got[1], &got[2], &got[3], &moon_ws);
    if (bitsEq(got[0], want[0]) and bitsEq(got[1], want[1]) and bitsEq(got[2], want[2]) and bitsEq(got[3], want[3]))
        return true;
    std.debug.print("MISMATCH: {s}\n  want={x},{x},{x},{x} got={x},{x},{x},{x}\n", .{
        line,
        @as(u64, @bitCast(want[0])),
        @as(u64, @bitCast(want[1])),
        @as(u64, @bitCast(want[2])),
        @as(u64, @bitCast(want[3])),
        @as(u64, @bitCast(got[0])),
        @as(u64, @bitCast(got[1])),
        @as(u64, @bitCast(got[2])),
        @as(u64, @bitCast(got[3])),
    });
    return false;
}

pub fn checkMoonLine(line: []const u8) bool {
    if (line.len == 0) return true;
    return switch (line[0]) {
        'M' => checkM(line),
        'E' => checkE(line),
        'V' => checkV(line),
        'F' => checkPol3(line, 'F'),
        'I' => checkPol3(line, 'I'),
        'G' => checkPol3(line, 'G'),
        'K' => checkPol3(line, 'K'),
        'W' => checkW(line),
        else => true,
    };
}
