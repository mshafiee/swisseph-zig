// swecl primitives differential checking: parse the C oracle's corpus lines
// (kinds l/r/e/o/b) and recompute each case with the Zig port, comparing
// bit-for-bit (%.17g round-trips doubles exactly).
// Kind l: swe_set_lapse_rate(x) — state change
// Kind r: swe_refrac(inalt, atpress, attemp, calc_flag) -> double
// Kind e: swe_refrac_extended(inalt, geoalt, atpress, attemp, calc_flag)
//         -> ret + dret[4]   (lapse_rate is the ctx value from kind l)
// Kind o: swe_azalt(tjd_ut, flag, geopos[3], press, temp, xin[2]) -> xaz[3]
// Kind b: swe_azalt_rev(tjd_ut, flag, geopos[3], xin[2]) -> xout[2]
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");
const sweph = @import("sweph");
const swecl = @import("swecl");

fn bitsEq(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

/// NaN has two bit patterns (+nan/-nan): C prints 'nan' for both and
/// Zig's parseFloat produces +nan; treat all NaNs as equal.
fn bitsEqNan(a: f64, b: f64) bool {
    if (std.math.isNan(a) and std.math.isNan(b)) return true;
    return bitsEq(a, b);
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

var swed_state = sweph.Swed{};
var dctx_state = deltat.DeltatCtx{};
var models_state = lib.AstroModels{};
var ctx_state = swecl.SweclCtx{};
var ephe_init_done = false;

/// C oracle calls swe_set_ephe_path("../ephe") once at start
fn ensureEpheInit() void {
    if (ephe_init_done) return;
    ephe_init_done = true;
    sweph.swe_set_ephe_path("../ephe", &swed_state, &models_state, &dctx_state, null);
}

/// kind l: swe_set_lapse_rate(rate) — state change, no output
pub fn checkL(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "l")) return true;
    const rate = parseFloat(tok.next()) orelse return parseFail(line);
    swecl.swe_set_lapse_rate(rate, &ctx_state);
    return true;
}

/// kind r: swe_refrac(inalt, atpress, attemp, calc_flag) -> ret
fn checkR(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "r")) return true;
    const inalt = parseFloat(tok.next()) orelse return parseFail(line);
    const atpress = parseFloat(tok.next()) orelse return parseFail(line);
    const attemp = parseFloat(tok.next()) orelse return parseFail(line);
    const flag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    const got = swecl.swe_refrac(inalt, atpress, attemp, flag);
    if (bitsEq(want, got)) return true;
    std.debug.print("MISMATCH: {s}  want={d} got={d}\n", .{ line, want, got });
    return false;
}

/// kind e: swe_refrac_extended(inalt, geoalt, atpress, attemp, calc_flag)
///         -> ret dret[4]  (lapse rate comes from the ctx set by kind l)
fn checkE(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "e")) return true;
    const inalt = parseFloat(tok.next()) orelse return parseFail(line);
    const geoalt = parseFloat(tok.next()) orelse return parseFail(line);
    const atpress = parseFloat(tok.next()) orelse return parseFail(line);
    const attemp = parseFloat(tok.next()) orelse return parseFail(line);
    const flag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseFloat(tok.next()) orelse return parseFail(line);
    var want_dret: [4]f64 = undefined;
    for (0..4) |i| want_dret[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var dret: [4]f64 = undefined;
    const got_ret = swecl.swe_refrac_extended(inalt, geoalt, atpress, attemp, ctx_state.const_lapse_rate, flag, &dret);
    var ok = bitsEq(want_ret, got_ret);
    for (0..4) |i| {
        if (!bitsEq(want_dret[i], dret[i])) ok = false;
    }
    if (ok) return true;
    std.debug.print("MISMATCH: {s}  want={d} got={d}  want_dret=[{d},{d},{d},{d}] got_dret=[{d},{d},{d},{d}]\n", .{ line, want_ret, got_ret, want_dret[0], want_dret[1], want_dret[2], want_dret[3], dret[0], dret[1], dret[2], dret[3] });
    return false;
}

/// kind o: swe_azalt(tjd_ut, 1, geopos[3], press, temp, xin[2]) -> xaz[3]
fn checkO(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "o")) return true;
    const tjd_ut = parseFloat(tok.next()) orelse return parseFail(line);
    const flag = parseInt(tok.next()) orelse return parseFail(line);
    var geopos: [3]f64 = undefined;
    for (0..3) |i| geopos[i] = parseFloat(tok.next()) orelse return parseFail(line);
    const press = parseFloat(tok.next()) orelse return parseFail(line);
    const temp = parseFloat(tok.next()) orelse return parseFail(line);
    var xin: [3]f64 = undefined;
    for (0..2) |i| xin[i] = parseFloat(tok.next()) orelse return parseFail(line);
    xin[2] = 0;
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [3]f64 = undefined;
    for (0..3) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var xaz: [3]f64 = undefined;
    swecl.swe_azalt(tjd_ut, flag, &geopos, press, temp, &xin, &xaz, &swed_state, models_state, &dctx_state, &ctx_state);
    var ok = true;
    for (0..3) |i| {
        if (!bitsEq(want[i], xaz[i])) ok = false;
    }
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want=[{d},{d},{d}] got=[{d},{d},{d}]\n", .{ line, want[0], want[1], want[2], xaz[0], xaz[1], xaz[2] });
    return false;
}

/// kind b: swe_azalt_rev(tjd_ut, 1, geopos[3], xin[2]) -> xout[2]
fn checkB(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "b")) return true;
    const tjd_ut = parseFloat(tok.next()) orelse return parseFail(line);
    const flag = parseInt(tok.next()) orelse return parseFail(line);
    var geopos: [3]f64 = undefined;
    for (0..3) |i| geopos[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var xin: [3]f64 = undefined;
    for (0..2) |i| xin[i] = parseFloat(tok.next()) orelse return parseFail(line);
    xin[2] = 0;
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    var want: [2]f64 = undefined;
    for (0..2) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var xout: [2]f64 = undefined;
    swecl.swe_azalt_rev(tjd_ut, flag, &geopos, &xin, &xout, &swed_state, models_state, &dctx_state);
    var ok = true;
    for (0..2) |i| {
        if (!bitsEq(want[i], xout[i])) ok = false;
    }
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want=[{d},{d}] got=[{d},{d}]\n", .{ line, want[0], want[1], xout[0], xout[1] });
    return false;
}

pub fn checkSweclLine(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (std.mem.eql(u8, kind, "l")) return checkL(line);
    if (std.mem.eql(u8, kind, "r")) return checkR(line);
    if (std.mem.eql(u8, kind, "e")) return checkE(line);
    if (std.mem.eql(u8, kind, "o")) return checkO(line);
    if (std.mem.eql(u8, kind, "b")) return checkB(line);
    if (std.mem.eql(u8, kind, "p")) return checkP(line);
    if (std.mem.eql(u8, kind, "q")) return checkQ(line);
    if (std.mem.eql(u8, kind, "w")) return checkW(line);
    if (std.mem.eql(u8, kind, "i") or std.mem.eql(u8, kind, "k")) return checkRise(line);
    if (std.mem.eql(u8, kind, "g")) return checkG(line);
    if (std.mem.eql(u8, kind, "a")) return checkA(line);
    if (std.mem.eql(u8, kind, "m")) return checkM(line);
    if (std.mem.eql(u8, kind, "f")) return checkF(line);
    if (std.mem.eql(u8, kind, "h")) return checkH(line);
    // unknown kind: not ours
    return true;
}

/// kinds i/y: swe_rise_trans / swe_rise_trans_true_hor
///   <kind> <ipl> <tjd_ut> <epheflag> <rsmi> '<star>' <geopos[3]> <atpress>
///   <attemp> [<horhgt> for y] -> <retc> <tret> serr='...'
/// starname '-' means NULL/empty (mutated by swe_fixstar, so the checker
/// copies it into its own buffer)
fn checkRise(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    const truehor = std.mem.eql(u8, kind, "k");
    if (!std.mem.eql(u8, kind, "i") and !truehor) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd_ut = parseFloat(tok.next()) orelse return parseFail(line);
    const epheflag = parseInt(tok.next()) orelse return parseFail(line);
    const rsmi = parseInt(tok.next()) orelse return parseFail(line);
    const star_field = tok.next() orelse return parseFail(line);
    if (star_field.len < 2 or star_field[0] != '\'') return parseFail(line);
    const star_name = star_field[1 .. star_field.len - 1];
    var geopos: [3]f64 = undefined;
    for (0..3) |i| geopos[i] = parseFloat(tok.next()) orelse return parseFail(line);
    const atpress = parseFloat(tok.next()) orelse return parseFail(line);
    const attemp = parseFloat(tok.next()) orelse return parseFail(line);
    var horhgt: f64 = 0;
    if (truehor) {
        horhgt = parseFloat(tok.next()) orelse return parseFail(line);
    }
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want_tret = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var tret: f64 = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    // swe_fixstar mutates the starname buffer: own a mutable copy
    var star_buf: [AS_MAXCH_BUF]u8 = [_]u8{0} ** AS_MAXCH_BUF;
    var starname: ?[]u8 = null;
    if (!std.mem.eql(u8, star_name, "-")) {
        @memcpy(star_buf[0..star_name.len], star_name);
        starname = star_buf[0..star_name.len];
    }
    const got_ret = if (truehor)
        swecl.swe_rise_trans_true_hor(tjd_ut, ipl, starname, epheflag, rsmi, &geopos, atpress, attemp, horhgt, &tret, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state)
    else
        swecl.swe_rise_trans(tjd_ut, ipl, starname, epheflag, rsmi, &geopos, atpress, attemp, &tret, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    const ok = want_ret == got_ret and bitsEq(want_tret, tret) and
        std.mem.eql(u8, want_serr, got_serr);
    // the starname buffer is mutated in place (C contract); the corpus
    // cannot compare it, but the call must not hang or crash
    if (starname != null) starname.?[0] = star_buf[0];
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want_tret={d} got_tret={d}\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want_tret, tret, want_serr, got_serr });
    return false;
}

const AS_MAXCH_BUF: usize = 256;

/// kind p: swe_pheno(ipl, tjd, iflag) -> retflag + attr[6 of 20] + serr
fn checkP(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "p")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (0..6) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    // serr is the last field: find " serr='" in the raw line (the content
    // itself can contain spaces and single quotes)
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var attr: [20]f64 = undefined;
    for (0..20) |i| attr[i] = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_pheno(tjd, ipl, iflag, &attr, &serr_buf, &swed_state, models_state, &dctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..6) |i| {
        if (!bitsEq(want[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want_attr=[{d},{d},{d},{d},{d},{d}] got_attr=[{d},{d},{d},{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want[0], want[1], want[2], want[3], want[4], want[5], attr[0], attr[1], attr[2], attr[3], attr[4], attr[5], want_serr, got_serr });
    return false;
}

/// kind q: swe_pheno_ut(ipl, tjd_ut, iflag) -> retflag + attr[6 of 20] + serr
fn checkQ(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "q")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd_ut = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (0..6) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var attr: [20]f64 = undefined;
    for (0..20) |i| attr[i] = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_pheno_ut(tjd_ut, ipl, iflag, &attr, &serr_buf, &swed_state, models_state, &dctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..6) |i| {
        if (!bitsEq(want[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want_attr=[{d},{d},{d},{d},{d},{d}] got_attr=[{d},{d},{d},{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want[0], want[1], want[2], want[3], want[4], want[5], attr[0], attr[1], attr[2], attr[3], attr[4], attr[5], want_serr, got_serr });
    return false;
}

/// kind w: swe_set_topo(geolon, geolat, geoalt) — state change, no output.
/// (Distinct token from the swecalc corpus's 'v' because each corpus owns
/// its own Swed instance on the C side; tokens must not be shared between
/// checkers with separate state.)
fn checkW(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "w")) return true;
    const geolon = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    const geoalt = parseFloat(tok.next()) orelse return parseFail(line);
    sweph.swe_set_topo(geolon, geolat, geoalt, &swed_state);
    return true;
}

fn unescapeSerr(buf: *[256]u8, src: []const u8) []const u8 {
    // serr is the last field of the line: content runs to the final quote.
    // Messages can contain single quotes (e.g. file 'x' not found), so the
    // content is everything between "serr='" and the line's trailing "'".
    var end = src.len;
    if (end > 0 and src[end - 1] == '\'') end -= 1;
    var i: usize = 0;
    var n: usize = 0;
    while (i < end) {
        if (i + 1 < end and src[i] == '\\' and src[i + 1] == 'n') {
            buf[n] = '\n';
            i += 2;
        } else if (i + 1 < end and src[i] == '\\' and src[i + 1] == '\\') {
            buf[n] = '\\';
            i += 2;
        } else {
            buf[n] = src[i];
            i += 1;
        }
        n += 1;
    }
    return buf[0..n];
}

const swehel = @import("swehel");

var swed_hel = sweph.Swed{};
var dctx_hel = deltat.DeltatCtx{};
var models_hel = lib.AstroModels{};
var cctx_hel = swecl.SweclCtx{};
var hctx_hel = swehel.SwehelCtx{};
var ephe_init_hel = false;

fn ensureEpheInitHel() void {
    if (ephe_init_hel) return;
    ephe_init_hel = true;
    sweph.swe_set_ephe_path("../ephe", &swed_hel, &models_hel, &dctx_hel, null);
}

/// kind g: swe_vis_limit_mag(tjdut, site, atm, obs, helflag, 'name')
///         -> retval + dret[8] + serr
fn checkG(line: []const u8) bool {
    ensureEpheInitHel();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "g")) return true;
    const tjdut = parseFloat(tok.next()) orelse return parseFail(line);
    const s = parseInt(tok.next()) orelse return parseFail(line);
    const a = parseInt(tok.next()) orelse return parseFail(line);
    const o = parseInt(tok.next()) orelse return parseFail(line);
    const helflag = parseInt(tok.next()) orelse return parseFail(line);
    const name_field = tok.next() orelse return parseFail(line);
    if (name_field.len < 2 or name_field[0] != '\'') return parseFail(line);
    const name_in = name_field[1 .. name_field.len - 1];
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [8]f64 = undefined;
    for (0..8) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    const geo = sitesList[@intCast(s)];
    const atm_in = atmsList[@intCast(a)];
    const obs_in = obssList[@intCast(o)];
    var dgeo: [3]f64 = geo;
    var datm: [4]f64 = atm_in;
    var dobs: [6]f64 = obs_in;
    var name_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(name_buf[0..name_in.len], name_in);
    var dret: [8]f64 = undefined;
    for (0..8) |i| dret[i] = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swehel.swe_vis_limit_mag(tjdut, &dgeo, &datm, &dobs, name_buf[0..name_in.len], helflag, &dret, &serr_buf, &swed_hel, models_hel, &dctx_hel, &cctx_hel, &hctx_hel);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..8) |i| {
        if (!bitsEq(want[i], dret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want=[{d},{d},{d},{d},{d},{d},{d},{d}] got=[{d},{d},{d},{d},{d},{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want[0], want[1], want[2], want[3], want[4], want[5], want[6], want[7], dret[0], dret[1], dret[2], dret[3], dret[4], dret[5], dret[6], dret[7], want_serr, got_serr });
    return false;
}

const sitesList = [5][3]f64{
    .{ 13.5, 52.5, 40 }, .{ -74.0, 40.7, 10 }, .{ 15, 70, 0 },
    .{ 0, 0, 0 },        .{ 180, -33.9, 1200 },
};
const atmsList = [5][4]f64{
    .{ 0, 0, 0, 0 },
    .{ 1013.25, 15, 40, 0 },
    .{ 1013.25, 25, 80, 0 },
    .{ 980, 5, 20, 0 },
    .{ 1013.25, 15, 40, 40 },
};
const obssList = [4][6]f64{
    .{ 0, 0, 0, 0, 0, 0 },
    .{ 23, 1, 0, 0, 0, 0 },
    .{ 65, 0.8, 0, 0, 0, 0 },
    .{ 30, 1.2, 1, 1, 50, 0.8 },
};

/// kind a: swe_topo_arcus_visionis(tjdut, s, a, o, helflag, mag,
///         azi_obj, alt_obj, azi_sun, azi_moon, alt_moon) -> ret + dret + serr
fn checkA(line: []const u8) bool {
    ensureEpheInitHel();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "a")) return true;
    const tjdut = parseFloat(tok.next()) orelse return parseFail(line);
    const s = parseInt(tok.next()) orelse return parseFail(line);
    const a = parseInt(tok.next()) orelse return parseFail(line);
    const o = parseInt(tok.next()) orelse return parseFail(line);
    const helflag = parseInt(tok.next()) orelse return parseFail(line);
    const mag = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_obj = parseFloat(tok.next()) orelse return parseFail(line);
    const alt_obj = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_sun = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_moon = parseFloat(tok.next()) orelse return parseFail(line);
    const alt_moon = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dgeo: [3]f64 = sitesList[@intCast(s)];
    var datm: [4]f64 = atmsList[@intCast(a)];
    var dobs: [6]f64 = obssList[@intCast(o)];
    var dret: f64 = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swehel.swe_topo_arcus_visionis(tjdut, &dgeo, &datm, &dobs, helflag, mag, azi_obj, alt_obj, azi_sun, azi_moon, alt_moon, &dret, &serr_buf, &swed_hel, models_hel, &dctx_hel, &cctx_hel, &hctx_hel);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    const ok = want_ret == got_ret and bitsEq(want, dret) and
        std.mem.eql(u8, want_serr, got_serr);
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want={d} got={d}\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want, dret, want_serr, got_serr });
    return false;
}

/// kind m: swe_heliacal_angle(tjdut, s, a, o, helflag, mag,
///         azi_obj, azi_sun, azi_moon, alt_moon) -> ret + dangret[3] + serr
fn checkM(line: []const u8) bool {
    ensureEpheInitHel();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "m")) return true;
    const tjdut = parseFloat(tok.next()) orelse return parseFail(line);
    const s = parseInt(tok.next()) orelse return parseFail(line);
    const a = parseInt(tok.next()) orelse return parseFail(line);
    const o = parseInt(tok.next()) orelse return parseFail(line);
    const helflag = parseInt(tok.next()) orelse return parseFail(line);
    const mag = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_obj = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_sun = parseFloat(tok.next()) orelse return parseFail(line);
    const azi_moon = parseFloat(tok.next()) orelse return parseFail(line);
    const alt_moon = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [3]f64 = undefined;
    for (0..3) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dgeo: [3]f64 = sitesList[@intCast(s)];
    var datm: [4]f64 = atmsList[@intCast(a)];
    var dobs: [6]f64 = obssList[@intCast(o)];
    var dang: [3]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swehel.swe_heliacal_angle(tjdut, &dgeo, &datm, &dobs, helflag, mag, azi_obj, azi_sun, azi_moon, alt_moon, &dang, &serr_buf, &swed_hel, models_hel, &dctx_hel, &cctx_hel, &hctx_hel);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..3) |i| {
        if (!bitsEq(want[i], dang[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want=[{d},{d},{d}] got=[{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want[0], want[1], want[2], dang[0], dang[1], dang[2], want_serr, got_serr });
    return false;
}

/// kind f: swe_heliacal_pheno_ut(tjdut, s, a, o, helflag, type, 'name')
///         -> ret + darr[28] + serr
fn checkF(line: []const u8) bool {
    ensureEpheInitHel();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "f")) return true;
    const tjdut = parseFloat(tok.next()) orelse return parseFail(line);
    const s = parseInt(tok.next()) orelse return parseFail(line);
    const a = parseInt(tok.next()) orelse return parseFail(line);
    const o = parseInt(tok.next()) orelse return parseFail(line);
    const helflag = parseInt(tok.next()) orelse return parseFail(line);
    const type_event = parseInt(tok.next()) orelse return parseFail(line);
    const name_field = tok.next() orelse return parseFail(line);
    if (name_field.len < 2 or name_field[0] != '\'') return parseFail(line);
    const name_in = name_field[1 .. name_field.len - 1];
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [28]f64 = undefined;
    for (0..28) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dgeo: [3]f64 = sitesList[@intCast(s)];
    var datm: [4]f64 = atmsList[@intCast(a)];
    var dobs: [6]f64 = obssList[@intCast(o)];
    var name_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(name_buf[0..name_in.len], name_in);
    var darr: [40]f64 = [_]f64{0} ** 40;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swehel.swe_heliacal_pheno_ut(tjdut, &dgeo, &datm, &dobs, name_buf[0..name_in.len], type_event, helflag, &darr, &serr_buf, &swed_hel, models_hel, &dctx_hel, &cctx_hel, &hctx_hel);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..28) |i| {
        if (!bitsEq(want[i], darr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..28) |i| {
        if (!bitsEq(want[i], darr[i]))
            std.debug.print("  darr[{d}]: want={d} got={d}\n", .{ i, want[i], darr[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

/// kind h: swe_heliacal_ut(tjdstart, s, a, o, helflag, type, 'name')
///         -> ret + dret[3] + serr
fn checkH(line: []const u8) bool {
    ensureEpheInitHel();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "h")) return true;
    const tjdstart = parseFloat(tok.next()) orelse return parseFail(line);
    const s = parseInt(tok.next()) orelse return parseFail(line);
    const a = parseInt(tok.next()) orelse return parseFail(line);
    const o = parseInt(tok.next()) orelse return parseFail(line);
    const helflag = parseInt(tok.next()) orelse return parseFail(line);
    const type_event = parseInt(tok.next()) orelse return parseFail(line);
    const name_field = tok.next() orelse return parseFail(line);
    if (name_field.len < 2 or name_field[0] != '\'') return parseFail(line);
    const name_in = name_field[1 .. name_field.len - 1];
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [3]f64 = undefined;
    for (0..3) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dgeo: [3]f64 = sitesList[@intCast(s)];
    var datm: [4]f64 = atmsList[@intCast(a)];
    var dobs: [6]f64 = obssList[@intCast(o)];
    var name_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(name_buf[0..name_in.len], name_in);
    var dret: [10]f64 = [_]f64{0} ** 10;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swehel.swe_heliacal_ut(tjdstart, &dgeo, &datm, &dobs, name_buf[0..name_in.len], type_event, helflag, &dret, &serr_buf, &swed_hel, models_hel, &dctx_hel, &cctx_hel, &hctx_hel);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..3) |i| {
        if (!bitsEq(want[i], dret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want=[{d},{d},{d}] got=[{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want[0], want[1], want[2], dret[0], dret[1], dret[2], want_serr, got_serr });
    return false;
}

/// kinds c/d/s/t/u + tp: nodes/apsides, orbital elements, distances,
/// gauquelin sector (all real-value kinds)
fn parseVec6(tok: *std.mem.TokenIterator(u8, .scalar), out: *[6]f64) bool {
    for (0..6) |i| {
        out[i] = parseFloat(tok.next()) orelse return false;
    }
    return true;
}

fn checkNod(line: []const u8, ut: bool) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    const want_kind: []const u8 = if (ut) "n2" else "n1";
    if (!std.mem.eql(u8, kind, want_kind)) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const method = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_nasc: [6]f64 = undefined;
    var want_ndsc: [6]f64 = undefined;
    var want_peri: [6]f64 = undefined;
    var want_aphe: [6]f64 = undefined;
    if (!parseVec6(&tok, &want_nasc)) return parseFail(line);
    if (!parseVec6(&tok, &want_ndsc)) return parseFail(line);
    if (!parseVec6(&tok, &want_peri)) return parseFail(line);
    if (!parseVec6(&tok, &want_aphe)) return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    // the oracle zeroes the output arrays before each call (trap 8e:
    // C's error paths leave outputs untouched)
    var got_nasc: [6]f64 = [_]f64{0} ** 6;
    var got_ndsc: [6]f64 = [_]f64{0} ** 6;
    var got_peri: [6]f64 = [_]f64{0} ** 6;
    var got_aphe: [6]f64 = [_]f64{0} ** 6;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = if (ut)
        swecl.swe_nod_aps_ut(tjd, ipl, iflag, method, &got_nasc, &got_ndsc, &got_peri, &got_aphe, &serr_buf, &swed_state, models_state, &dctx_state)
    else
        swecl.swe_nod_aps(tjd, ipl, iflag, method, &got_nasc, &got_ndsc, &got_peri, &got_aphe, &serr_buf, &swed_state, models_state, &dctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..6) |i| {
        if (!bitsEqNan(want_nasc[i], got_nasc[i])) ok = false;
        if (!bitsEqNan(want_ndsc[i], got_ndsc[i])) ok = false;
        if (!bitsEqNan(want_peri[i], got_peri[i])) ok = false;
        if (!bitsEqNan(want_aphe[i], got_aphe[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..6) |i| {
        if (!bitsEqNan(want_nasc[i], got_nasc[i]))
            std.debug.print("  nasc[{d}]: want={d} got={d}\n", .{ i, want_nasc[i], got_nasc[i] });
        if (!bitsEqNan(want_ndsc[i], got_ndsc[i]))
            std.debug.print("  ndsc[{d}]: want={d} got={d}\n", .{ i, want_ndsc[i], got_ndsc[i] });
        if (!bitsEqNan(want_peri[i], got_peri[i]))
            std.debug.print("  peri[{d}]: want={d} got={d}\n", .{ i, want_peri[i], got_peri[i] });
        if (!bitsEqNan(want_aphe[i], got_aphe[i]))
            std.debug.print("  aphe[{d}]: want={d} got={d}\n", .{ i, want_aphe[i], got_aphe[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkOrel(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "o1")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [17]f64 = undefined;
    for (0..17) |i| want[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dret: [50]f64 = [_]f64{0} ** 50;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_get_orbital_elements(tjd, ipl, iflag, &dret, &serr_buf, &swed_state, models_state, &dctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..17) |i| {
        if (!bitsEq(want[i], dret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..17) |i| {
        if (!bitsEq(want[i], dret[i]))
            std.debug.print("  dret[{d}]: want={d} got={d}\n", .{ i, want[i], dret[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkOmax(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "o2")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want_max = parseFloat(tok.next()) orelse return parseFail(line);
    const want_min = parseFloat(tok.next()) orelse return parseFail(line);
    const want_true = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    var dmax: f64 = 0;
    var dmin: f64 = 0;
    var dtrue: f64 = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_orbit_max_min_true_distance(tjd, ipl, iflag, &dmax, &dmin, &dtrue, &serr_buf, &swed_state, models_state, &dctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret and bitsEq(want_max, dmax) and bitsEq(want_min, dmin) and bitsEq(want_true, dtrue);
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want=[{d},{d},{d}] got=[{d},{d},{d}]\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want_max, want_min, want_true, dmax, dmin, dtrue, want_serr, got_serr });
    return false;
}

fn checkGauq(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "g1")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const star_field = tok.next() orelse return parseFail(line);
    if (star_field.len < 2 or star_field[0] != '\'') return parseFail(line);
    const star_name = star_field[1 .. star_field.len - 1];
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const imeth = parseInt(tok.next()) orelse return parseFail(line);
    const geolon = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    // the oracle emits geolon/geolat only (not geoalt/atpress/attemp — the
    // values are fixed: geoalt from the site, press 1013.25, temp 10);
    // recover the site's geoalt by matching the (lon, lat) pair
    var geoalt: f64 = 0;
    for (sitesList) |s| {
        if (s[0] == geolon and s[1] == geolat) geoalt = s[2];
    }
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    var want_serr: []const u8 = "";
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        want_serr = unescapeSerr(&want_serr_buf, line[sp + 7 ..]);
    }
    const geopos = [3]f64{ geolon, geolat, geoalt };
    var dgsect: f64 = 0;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    // swe_fixstar mutates the star buffer; own a copy
    var star_buf: [256]u8 = [_]u8{0} ** 256;
    var stararg: ?[]u8 = null;
    if (!std.mem.eql(u8, star_name, "-")) {
        @memcpy(star_buf[0..star_name.len], star_name);
        stararg = star_buf[0..255];
    }
    const got_ret = swecl.swe_gauquelin_sector(tjd, ipl, stararg, iflag, imeth, &geopos, 1013.25, 10, &dgsect, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    const ok = want_ret == got_ret and bitsEq(want, dgsect) and
        std.mem.eql(u8, want_serr, got_serr);
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d} want={d} got={d}\n  want_serr='{s}' got_serr='{s}'\n", .{ line, want_ret, got_ret, want, dgsect, want_serr, got_serr });
    return false;
}

/// kind tp: swe_set_topo for the osc corpus
fn checkTp(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "tp")) return true;
    const geolon = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    const geoalt = parseFloat(tok.next()) orelse return parseFail(line);
    sweph.swe_set_topo(geolon, geolat, geoalt, &swed_state);
    return true;
}

pub fn checkOscLine(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (std.mem.eql(u8, kind, "n1")) return checkNod(line, false);
    if (std.mem.eql(u8, kind, "n2")) return checkNod(line, true);
    if (std.mem.eql(u8, kind, "o1")) return checkOrel(line);
    if (std.mem.eql(u8, kind, "o2")) return checkOmax(line);
    if (std.mem.eql(u8, kind, "g1")) return checkGauq(line);
    if (std.mem.eql(u8, kind, "tp")) return checkTp(line);
    // unknown kind: not ours
    return true;
}

/// eclipse/occultation corpus kinds (ew/ow/eh/eg/og/el/ol/lh/lg/ll)
fn eclWantSerr(line: []const u8, buf: *[256]u8) []const u8 {
    if (std.mem.indexOf(u8, line, " serr='")) |sp| {
        return unescapeSerr(buf, line[sp + 7 ..]);
    }
    return "";
}

fn checkEwOw(line: []const u8, occult: bool) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (occult) {
        if (!std.mem.eql(u8, kind, "ow")) return true;
    } else {
        if (!std.mem.eql(u8, kind, "ew")) return true;
    }
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    var ipl: i32 = 0;
    var iflag: i32 = sweph.SEFLG_SWIEPH;
    if (occult) {
        // oracle's ow line: ow tjd ipl -> (no iflag; SEFLG_SWIEPH)
        ipl = parseInt(tok.next()) orelse return parseFail(line);
    } else {
        iflag = parseInt(tok.next()) orelse return parseFail(line);
    }
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_gp: [2]f64 = undefined;
    for (0..2) |i| want_gp[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_attr: [11]f64 = undefined;
    for (0..11) |i| want_attr[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var got_gp: [2]f64 = undefined;
    var attr: [20]f64 = [_]f64{0} ** 20;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = if (occult)
        swecl.swe_lun_occult_where(tjd, ipl, null, iflag, &got_gp, &attr, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state)
    else
        swecl.swe_sol_eclipse_where(tjd, iflag, &got_gp, &attr, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..2) |i| {
        if (!bitsEq(want_gp[i], got_gp[i])) ok = false;
    }
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..2) |i| {
        if (!bitsEq(want_gp[i], got_gp[i]))
            std.debug.print("  geopos[{d}]: want={d} got={d}\n", .{ i, want_gp[i], got_gp[i] });
    }
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i]))
            std.debug.print("  attr[{d}]: want={d} got={d}\n", .{ i, want_attr[i], attr[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkEh(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "eh")) return true;
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    var geopos: [3]f64 = undefined;
    for (0..3) |i| geopos[i] = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_attr: [11]f64 = undefined;
    for (0..11) |i| want_attr[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var attr: [20]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_sol_eclipse_how(tjd, iflag, &geopos, &attr, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i]))
            std.debug.print("  attr[{d}]: want={d} got={d}\n", .{ i, want_attr[i], attr[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkEg(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "eg")) return true;
    const tjd_start = parseFloat(tok.next()) orelse return parseFail(line);
    const ifltype = parseInt(tok.next()) orelse return parseFail(line);
    const backward = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_tret: [10]f64 = undefined;
    for (0..10) |i| want_tret[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var tret: [10]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_sol_eclipse_when_glob(tjd_start, sweph.SEFLG_SWIEPH, ifltype, &tret, backward != 0, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i]))
            std.debug.print("  tret[{d}]: want={d} got={d}\n", .{ i, want_tret[i], tret[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkOg(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "og")) return true;
    const tjd_start = parseFloat(tok.next()) orelse return parseFail(line);
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    _ = parseInt(tok.next()) orelse return parseFail(line); // placeholder 0 (was backward)
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_tret: [10]f64 = undefined;
    for (0..10) |i| want_tret[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var tret: [10]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_lun_occult_when_glob(tjd_start, ipl, null, sweph.SEFLG_SWIEPH, 0, &tret, 0, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i]))
            std.debug.print("  tret[{d}]: want={d} got={d}\n", .{ i, want_tret[i], tret[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkElOl(line: []const u8, occult: bool) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (occult) {
        if (!std.mem.eql(u8, kind, "ol")) return true;
    } else {
        if (!std.mem.eql(u8, kind, "el")) return true;
    }
    const tjd_start = parseFloat(tok.next()) orelse return parseFail(line);
    var iflag: i32 = sweph.SEFLG_SWIEPH;
    var ipl: i32 = 0;
    if (occult) {
        // oracle's ol line: tjd ipl lon lat 0 -> (no iflag; SEFLG_SWIEPH)
        ipl = parseInt(tok.next()) orelse return parseFail(line);
    } else {
        iflag = parseInt(tok.next()) orelse return parseFail(line);
    }
    var geopos: [3]f64 = undefined;
    for (0..3) |i| geopos[i] = parseFloat(tok.next()) orelse return parseFail(line);
    _ = parseInt(tok.next()) orelse return parseFail(line); // trailing 0 (backward)
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_tret: [10]f64 = undefined;
    for (0..10) |i| want_tret[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_attr: [11]f64 = undefined;
    for (0..11) |i| want_attr[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    // the oracle memsets tret/attr before each call; eclipse_when_loc does
    // not zero untouched slots (trap 8e)
    var tret: [10]f64 = [_]f64{0} ** 10;
    var attr: [20]f64 = [_]f64{0} ** 20;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = if (occult)
        swecl.swe_lun_occult_when_loc(tjd_start, ipl, null, iflag, &geopos, &tret, &attr, 0, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state)
    else
        swecl.swe_sol_eclipse_when_loc(tjd_start, iflag, &geopos, &tret, &attr, false, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i])) ok = false;
    }
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i]))
            std.debug.print("  tret[{d}]: want={d} got={d}\n", .{ i, want_tret[i], tret[i] });
    }
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i]))
            std.debug.print("  attr[{d}]: want={d} got={d}\n", .{ i, want_attr[i], attr[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkLh(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "lh")) return true;
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    // geopos: either 3 values or none (NULL variant)
    var geopos: [3]f64 = undefined;
    var have_geopos = false;
    {
        var probe = tok;
        var n: usize = 0;
        while (probe.next()) |t2| {
            if (std.mem.eql(u8, t2, "->")) break;
            n += 1;
        }
        if (n == 3) {
            geopos[0] = parseFloat(tok.next()) orelse return parseFail(line);
            geopos[1] = parseFloat(tok.next()) orelse return parseFail(line);
            geopos[2] = parseFloat(tok.next()) orelse return parseFail(line);
            have_geopos = true;
        }
    }
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_attr: [11]f64 = undefined;
    for (0..11) |i| want_attr[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var attr: [20]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = if (have_geopos)
        swecl.swe_lun_eclipse_how(tjd, iflag, &geopos, &attr, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state)
    else
        swecl.swe_lun_eclipse_how(tjd, iflag, null, &attr, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..11) |i| {
        if (!bitsEqNan(want_attr[i], attr[i]))
            std.debug.print("  attr[{d}]: want={d} got={d}\n", .{ i, want_attr[i], attr[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

fn checkLg(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "lg")) return true;
    const tjd_start = parseFloat(tok.next()) orelse return parseFail(line);
    const ifltype = parseInt(tok.next()) orelse return parseFail(line);
    const backward = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want_tret: [10]f64 = undefined;
    for (0..10) |i| want_tret[i] = parseFloat(tok.next()) orelse return parseFail(line);
    var want_serr_buf: [256]u8 = [_]u8{0} ** 256;
    const want_serr = eclWantSerr(line, &want_serr_buf);
    var tret: [10]f64 = undefined;
    var serr_buf: [256]u8 = [_]u8{0} ** 256;
    const got_ret = swecl.swe_lun_eclipse_when(tjd_start, sweph.SEFLG_SWIEPH, ifltype, &tret, backward, &serr_buf, &swed_state, models_state, &dctx_state, &ctx_state);
    const got_serr = std.mem.sliceTo(&serr_buf, 0);
    var ok = want_ret == got_ret;
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i])) ok = false;
    }
    if (!std.mem.eql(u8, want_serr, got_serr)) ok = false;
    if (ok) return true;
    std.debug.print("MISMATCH: {s}\n  want_ret={d} got_ret={d}\n", .{ line, want_ret, got_ret });
    for (0..10) |i| {
        if (!bitsEq(want_tret[i], tret[i]))
            std.debug.print("  tret[{d}]: want={d} got={d}\n", .{ i, want_tret[i], tret[i] });
    }
    std.debug.print("  want_serr='{s}' got_serr='{s}'\n", .{ want_serr, got_serr });
    return false;
}

pub fn checkEclLine(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (std.mem.eql(u8, kind, "ew")) return checkEwOw(line, false);
    if (std.mem.eql(u8, kind, "ow")) return checkEwOw(line, true);
    if (std.mem.eql(u8, kind, "eh")) return checkEh(line);
    if (std.mem.eql(u8, kind, "eg")) return checkEg(line);
    if (std.mem.eql(u8, kind, "og")) return checkOg(line);
    if (std.mem.eql(u8, kind, "el")) return checkElOl(line, false);
    if (std.mem.eql(u8, kind, "ol")) return checkElOl(line, true);
    if (std.mem.eql(u8, kind, "lh")) return checkLh(line);
    if (std.mem.eql(u8, kind, "lg")) return checkLg(line);
    if (std.mem.eql(u8, kind, "ll")) return checkElOl(line, false);
    // unknown kind: not ours
    return true;
}
