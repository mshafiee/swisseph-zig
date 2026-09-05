// Planet module differential checking: parse the C oracle's plan corpus
// lines (kind A) and recompute each case with the Zig port, comparing
// bit-for-bit (%.17g round-trips doubles exactly).
// Kind A: swi_moshplan(tjd, ipli, do_save=FALSE, &xp, &xe, serr)
//         -> retc + xp[6] + xe[6] + serr
// The oec2000 obliquity is constant (calc_epsilon(J2000, 0) pattern);
// oec is per-tjd (calc_epsilon(tjd, 0)); both via the port's own
// (differential-tested) swi_epsiln and the libm shim for sin/cos, as C.
const std = @import("std");
const lib = @import("swephlib");
const plan = @import("swemplan");
const sweph = @import("sweph");

extern "c" fn swe_shim_sin(x: f64) f64;
extern "c" fn swe_shim_cos(x: f64) f64;

fn bitsEq(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

var plandifftest_swed = sweph.Swed{};
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

fn parseFloat(s: ?[]const u8) ?f64 {
    return std.fmt.parseFloat(f64, s.?) catch null;
}

fn parseInt(s: ?[]const u8) ?i32 {
    return std.fmt.parseInt(i32, s.?, 10) catch null;
}

fn oecFor(tjd: f64) lib.Eps {
    var e = lib.Eps{};
    e.teps = tjd;
    e.eps = lib.swi_epsiln(tjd, 0, .{});
    e.seps = swe_shim_sin(e.eps);
    e.ceps = swe_shim_cos(e.eps);
    return e;
}

fn oec2000() lib.Eps {
    var e = lib.Eps{};
    e.teps = lib.J2000;
    e.eps = lib.swi_epsiln(lib.J2000, 0, .{});
    e.seps = swe_shim_sin(e.eps);
    e.ceps = swe_shim_cos(e.eps);
    return e;
}

fn checkA(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "A")) return true;
    const ipli = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_retc = parseInt(tok.next()) orelse return parseFail(line);
    var want_xp: [6]f64 = undefined;
    var want_xe: [6]f64 = undefined;
    for (&want_xp) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    for (&want_xe) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    var got_xp: [6]f64 = [_]f64{0} ** 6;
    var got_xe: [6]f64 = [_]f64{0} ** 6;
    const oec = oecFor(tjd);
    const o2k = oec2000();
    const retc = plan.swi_moshplan(tjd, @intCast(ipli), false, &got_xp, &got_xe, &oec, &o2k, .{}, &serr, &plandifftest_swed);
    var vals_ok = true;
    for (got_xp, want_xp) |g, w| {
        if (!bitsEq(g, w)) vals_ok = false;
    }
    for (got_xe, want_xe) |g, w| {
        if (!bitsEq(g, w)) vals_ok = false;
    }
    if (retc != want_retc or !vals_ok) {
        std.debug.print("MISMATCH: {s}\n  retc want={} got={}\n", .{ line, want_retc, retc });
        std.debug.print("  xp want={x},{x},{x},{x},{x},{x}\n  xp got= {x},{x},{x},{x},{x},{x}\n", .{
            @as(u64, @bitCast(want_xp[0])), @as(u64, @bitCast(want_xp[1])), @as(u64, @bitCast(want_xp[2])),
            @as(u64, @bitCast(want_xp[3])), @as(u64, @bitCast(want_xp[4])), @as(u64, @bitCast(want_xp[5])),
            @as(u64, @bitCast(got_xp[0])),  @as(u64, @bitCast(got_xp[1])),  @as(u64, @bitCast(got_xp[2])),
            @as(u64, @bitCast(got_xp[3])),  @as(u64, @bitCast(got_xp[4])),  @as(u64, @bitCast(got_xp[5])),
        });
        std.debug.print("  xe want={x},{x},{x},{x},{x},{x}\n  xe got= {x},{x},{x},{x},{x},{x}\n", .{
            @as(u64, @bitCast(want_xe[0])), @as(u64, @bitCast(want_xe[1])), @as(u64, @bitCast(want_xe[2])),
            @as(u64, @bitCast(want_xe[3])), @as(u64, @bitCast(want_xe[4])), @as(u64, @bitCast(want_xe[5])),
            @as(u64, @bitCast(got_xe[0])),  @as(u64, @bitCast(got_xe[1])),  @as(u64, @bitCast(got_xe[2])),
            @as(u64, @bitCast(got_xe[3])),  @as(u64, @bitCast(got_xe[4])),  @as(u64, @bitCast(got_xe[5])),
        });
        return false;
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

pub fn checkPlanLine(line: []const u8) bool {
    if (line.len == 0) return true;
    return switch (line[0]) {
        'A' => checkA(line),
        else => true,
    };
}
