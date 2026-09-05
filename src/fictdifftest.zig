// Fictitious-planet machinery differential checking: parse the C oracle's
// corpus lines (kinds u/c/d/s/t) and recompute each case with the Zig port,
// comparing bit-for-bit (%.17g round-trips doubles exactly).
// Kind u: swe_calc_ut(tjd_ut, ipl, iflag) -> retflag + xx[6] + serr
// Kind c: swe_get_planet_name(ipl) -> name
// Kind d: read_elements_file(ipl, tjd, mode) -> elems/pname (+ serr, mode 0)
// Kind s: swi_osc_el_plan(tjd, ipl, synthetic earth/sun) -> xp[6] + serr
// Kind t: state changes (ephe path, sid mode, topo)
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");
const sweph = @import("sweph");
const swemplan = @import("swemplan");

fn bitsEq(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

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

var swed_state = sweph.Swed{};
var dctx_state = deltat.DeltatCtx{};
var models_state = lib.AstroModels{};

fn getSerrMarker(line: []const u8) ?struct { raw: []const u8 } {
    const m = std.mem.indexOf(u8, line, " serr='") orelse return null;
    // trailing quote is the last char of the line
    if (line.len == 0 or line[line.len - 1] != '\'') return null;
    return .{ .raw = line[m + 7 .. line.len - 1] };
}

/// kind u: swe_calc_ut over fictitious bodies
fn checkU(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "u")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const sm = getSerrMarker(line) orelse return parseFail(line);
    var serr_want_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_want_buf, sm.raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    var got: [6]f64 = [_]f64{0} ** 6;
    const retflag = sweph.swe_calc_ut(tjd, ipl, iflag, &got, &swed_state, models_state, &dctx_state, &serr);
    if (retflag != want_ret) {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; serr='{s}'\n", .{ line, want_ret, retflag, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    for (got, want) |g, w| {
        if (!bitsEq(g, w)) {
            std.debug.print("MISMATCH: {s}\n  want={x},{x},{x},{x},{x},{x}\n  got= {x},{x},{x},{x},{x},{x}\n", .{
                line,
                @as(u64, @bitCast(want[0])), @as(u64, @bitCast(want[1])), @as(u64, @bitCast(want[2])),
                @as(u64, @bitCast(want[3])), @as(u64, @bitCast(want[4])), @as(u64, @bitCast(want[5])),
                @as(u64, @bitCast(got[0])),  @as(u64, @bitCast(got[1])),  @as(u64, @bitCast(got[2])),
                @as(u64, @bitCast(got[3])),  @as(u64, @bitCast(got[4])),  @as(u64, @bitCast(got[5])),
            });
            return false;
        }
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

/// kind c: swe_get_planet_name for fictitious bodies
fn checkC(line: []const u8) bool {
    // parse: c <ipl> -> '<name>'
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "c")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const q1 = std.mem.indexOfScalarPos(u8, line, 0, '\'') orelse return parseFail(line);
    if (line[line.len - 1] != '\'') return parseFail(line);
    const want_name = line[q1 + 1 .. line.len - 1];
    var sname: [256]u8 = [_]u8{0} ** 256;
    _ = sweph.swe_get_planet_name(ipl, &sname, &swed_state, models_state, &dctx_state, null);
    const got_name = std.mem.sliceTo(&sname, 0);
    if (!std.mem.eql(u8, got_name, want_name)) {
        std.debug.print("MISMATCH: {s}\n  name want='{s}' got='{s}'\n", .{ line, want_name, got_name });
        return false;
    }
    return true;
}

/// kind d: read_elements_file direct
fn checkD(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "d")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const mode = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    // mode 1: -> '<pname>'; mode 0: -> <retc> [elems] fict_ifl + serr
    if (mode == 1) {
        const q1 = std.mem.indexOfScalarPos(u8, line, 0, '\'') orelse return parseFail(line);
        if (line[line.len - 1] != '\'') return parseFail(line);
        const want_name = line[q1 + 1 .. line.len - 1];
        const got = swemplan.swi_get_fict_name(ipl, &swed_state);
        const got_name = std.mem.sliceTo(&got, 0);
        if (!std.mem.eql(u8, got_name, want_name)) {
            std.debug.print("MISMATCH: {s}\n  name want='{s}' got='{s}'\n", .{ line, want_name, got_name });
            return false;
        }
        return true;
    }
    const want_retc = parseInt(tok.next()) orelse return parseFail(line);
    // mode 0: elements. If want_retc == OK, 8 doubles + fict_ifl follow,
    // then serr. On ERR only serr follows (out-params zero on both sides).
    var want: [8]f64 = [_]f64{0} ** 8;
    var want_ifl: i32 = 0;
    if (want_retc == 0) {
        for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
        want_ifl = parseInt(tok.next()) orelse return parseFail(line);
    }
    const sm = getSerrMarker(line) orelse return parseFail(line);
    var serr_want_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_want_buf, sm.raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    const got = swemplan.read_elements_file(ipl, tjd, true, &serr, &swed_state);
    if (got == null) {
        if (want_retc != -1) {
            std.debug.print("MISMATCH: {s}\n  retc want={} got=-1 serr='{s}'\n", .{ line, want_retc, std.mem.sliceTo(&serr, 0) });
            return false;
        }
    } else {
        if (want_retc != 0) {
            std.debug.print("MISMATCH: {s}\n  retc want={} got=0\n", .{ line, want_retc });
            return false;
        }
        if (!bitsEq(got.?.tjd0, want[0]) or !bitsEq(got.?.tequ, want[1]) or
            !bitsEq(got.?.mano, want[2]) or !bitsEq(got.?.sema, want[3]) or
            !bitsEq(got.?.ecce, want[4]) or !bitsEq(got.?.parg, want[5]) or
            !bitsEq(got.?.node, want[6]) or !bitsEq(got.?.incl, want[7]) or
            got.?.fict_ifl != want_ifl)
        {
            std.debug.print("MISMATCH elems: {s}\n  want={x},{x},{x},{x},{x},{x},{x},{x} ifl={}\n  got= {x},{x},{x},{x},{x},{x},{x},{x} ifl={}\n", .{
                line,
                @as(u64, @bitCast(want[0])), @as(u64, @bitCast(want[1])),
                @as(u64, @bitCast(want[2])), @as(u64, @bitCast(want[3])),
                @as(u64, @bitCast(want[4])), @as(u64, @bitCast(want[5])),
                @as(u64, @bitCast(want[6])), @as(u64, @bitCast(want[7])),
                want_ifl,
                @as(u64, @bitCast(got.?.tjd0)),  @as(u64, @bitCast(got.?.tequ)),
                @as(u64, @bitCast(got.?.mano)),  @as(u64, @bitCast(got.?.sema)),
                @as(u64, @bitCast(got.?.ecce)),  @as(u64, @bitCast(got.?.parg)),
                @as(u64, @bitCast(got.?.node)),  @as(u64, @bitCast(got.?.incl)),
                got.?.fict_ifl,
            });
            return false;
        }
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

/// kind s: swi_osc_el_plan direct (scratch xp, synthetic earth/sun —
/// pointer identity with pdp.x is FALSE, matching the C oracle's scratch
/// buffer, so teval/iephe are not written by this path)
fn checkS(line: []const u8) bool {
    const xearth_c = [6]f64{ -0.2, 0.9, 0.397, 1.1e-5, -2.2e-5, 3.3e-6 };
    const xsun_c = [6]f64{ 0.011, -0.022, 0.005, 1.7e-7, 2.3e-8, -1.9e-8 };
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "s")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const sm = getSerrMarker(line) orelse return parseFail(line);
    var serr_want_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_want_buf, sm.raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    var xp: [6]f64 = [_]f64{0} ** 6;
    const retc = swemplan.swi_osc_el_plan(tjd, &xp, ipl, 11, &xearth_c, &xsun_c, models_state, &swed_state, &serr);
    if (retc != want_ret) {
        std.debug.print("MISMATCH: {s}\n  retc want={} got={}; serr='{s}'\n", .{ line, want_ret, retc, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    for (xp, want) |g, w| {
        if (!bitsEq(g, w)) {
            std.debug.print("MISMATCH: {s}\n  want={x},{x},{x},{x},{x},{x}\n  got= {x},{x},{x},{x},{x},{x}\n", .{
                line,
                @as(u64, @bitCast(want[0])), @as(u64, @bitCast(want[1])), @as(u64, @bitCast(want[2])),
                @as(u64, @bitCast(want[3])), @as(u64, @bitCast(want[4])), @as(u64, @bitCast(want[5])),
                @as(u64, @bitCast(xp[0])),  @as(u64, @bitCast(xp[1])),  @as(u64, @bitCast(xp[2])),
                @as(u64, @bitCast(xp[3])),  @as(u64, @bitCast(xp[4])),  @as(u64, @bitCast(xp[5])),
            });
            return false;
        }
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

/// kind t: state changes replayed in corpus order
fn checkT(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "t")) return true;
    const sub = tok.next() orelse return parseFail(line);
    if (std.mem.eql(u8, sub, "ephe")) {
        const path = tok.rest();
        sweph.swe_set_ephe_path(path, &swed_state, &models_state, &dctx_state, null);
        return true;
    } else if (std.mem.eql(u8, sub, "sid")) {
        const mode = parseInt(tok.next()) orelse return parseFail(line);
        const t0 = parseFloat(tok.next()) orelse return parseFail(line);
        const ayan = parseFloat(tok.next()) orelse return parseFail(line);
        sweph.swe_set_sid_mode(mode, t0, ayan, &swed_state, &models_state);
        return true;
    } else if (std.mem.eql(u8, sub, "topo")) {
        const lon = parseFloat(tok.next()) orelse return parseFail(line);
        const lat = parseFloat(tok.next()) orelse return parseFail(line);
        const alt = parseFloat(tok.next()) orelse return parseFail(line);
        sweph.swe_set_topo(lon, lat, alt, &swed_state);
        return true;
    }
    return parseFail(line);
}

pub fn checkFictLine(line: []const u8) bool {
    if (line.len == 0) return true;
    return switch (line[0]) {
        'u' => checkU(line),
        'c' => checkC(line),
        'd' => checkD(line),
        's' => checkS(line),
        't' => checkT(line),
        else => true,
    };
}

test {
    std.testing.refAllDecls(@This());
}
