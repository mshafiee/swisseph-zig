// swe_calc differential checking: parse the C oracle's corpus lines
// (kind U) and recompute each case with the Zig port, comparing
// bit-for-bit (%.17g round-trips doubles exactly).
// Kind U: swe_calc_ut(tjd_ut, ipl, iflag) -> retflag + xx[6] + serr
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");
const sweph = @import("sweph");

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

fn stripSerrPrefix(rest: []const u8) []const u8 {
    // oracle emits: serr='...' — return the quoted part
    if (std.mem.startsWith(u8, rest, "serr='")) return rest[6..];
    return rest;
}

fn bitsEqArr(a: *const [6]f64, b: *const [6]f64) bool {
    for (0..6) |i| {
        if (!bitsEq(a[i], b[i])) return false;
    }
    return true;
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
var ephe_init_done = false;

/// C oracle calls swe_set_ephe_path("../ephe") once at start
fn ensureEpheInit() void {
    if (ephe_init_done) return;
    ephe_init_done = true;
    sweph.swe_set_ephe_path("../ephe", &swed_state, &models_state, &dctx_state, null);
}

/// kind L: swe_set_sid_mode(sidmode, t0, ayan_t0) — state change, no output
fn checkL(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "L")) return true;
    const sidmode = parseInt(tok.next()) orelse return parseFail(line);
    const t0 = parseFloat(tok.next()) orelse return parseFail(line);
    const ayan_t0 = parseFloat(tok.next()) orelse return parseFail(line);
    sweph.swe_set_sid_mode(sidmode, t0, ayan_t0, &swed_state, &models_state);
    return true;
}

/// kind v: swe_set_topo(geolon, geolat, geoalt) — state change, no output
fn checkV(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "v")) return true;
    const geolon = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    const geoalt = parseFloat(tok.next()) orelse return parseFail(line);
    sweph.swe_set_topo(geolon, geolat, geoalt, &swed_state);
    return true;
}

/// kind pn: swe_get_planet_name(ipl) -> ret 'name'
fn checkPlanetName(line: []const u8) bool {
    ensureEpheInit();
    // parse: pn <ipl> -> <ret> '<name>'
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "pn")) return parseFail(line);
    const ipl = parseInt(tok.next() orelse return parseFail(line)) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next() orelse return parseFail(line)) orelse return parseFail(line);
    // name = between the first quote after "-> <ret> " and the last quote of the line
    const arrow = std.mem.indexOf(u8, line, "->") orelse return parseFail(line);
    const q1 = std.mem.indexOfScalarPos(u8, line, arrow + 2, '\'') orelse return parseFail(line);
    const q2 = std.mem.lastIndexOfScalar(u8, line, '\'') orelse return parseFail(line);
    if (q2 <= q1) return parseFail(line);
    const want_name = line[q1 + 1 .. q2];
    var sname: [256]u8 = [_]u8{0} ** 256;
    const got_ret = sweph.swe_get_planet_name(ipl, &sname, &swed_state, models_state, &dctx_state, null);
    const got_name = std.mem.sliceTo(&sname, 0);
    if (got_ret != want_ret or !std.mem.eql(u8, got_name, want_name)) {
        std.debug.print("MISMATCH: {s}\n  want ret={d} name='{s}' got ret={d} name='{s}'\n", .{ line, want_ret, want_name, got_ret, got_name });
        return false;
    }
    return true;
}

/// kind n: swe_set_interpolate_nut(do_interpolate) — state change, no output
fn checkN(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "n")) return true;
    const mode = parseInt(tok.next()) orelse return parseFail(line);
    sweph.swe_set_interpolate_nut(mode != 0, &swed_state);
    return true;
}

/// kind j: swe_set_jpl_file(fname) — state change, no output
fn checkJpl(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "j")) return true;
    const fname = tok.next() orelse return parseFail(line);
    var fbuf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(fbuf[0..fname.len], fname);
    fbuf[fname.len] = 0;
    sweph.swe_set_jpl_file(fname, &swed_state, &models_state, &dctx_state);
    return true;
}

fn getQuoted(line: []const u8, start: usize) ?struct { content: []const u8, end: usize } {
    const q1 = std.mem.indexOfScalarPos(u8, line, start, '\'') orelse return null;
    const q2 = std.mem.indexOfScalarPos(u8, line, q1 + 1, '\'') orelse return null;
    return .{ .content = line[q1 + 1 .. q2], .end = q2 + 1 };
}

/// kind x: swe_fixstar2(star, tjd_et, iflag)
fn checkX(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "x")) return true;
    var starname: []const u8 = undefined;
    var q1end: usize = undefined;
    {
        const q = getQuoted(line, 2) orelse return parseFail(line);
        starname = q.content;
        q1end = q.end;
    }
    // parse after the closing quote: tjd iflag -> ret 6 vals 'starout' serr='...'
    var tok2 = std.mem.tokenizeScalar(u8, line[q1end..], ' ');
    const tjd = parseFloat(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: tjd parse failed\n", .{});
        return parseFail(line);
    };
    const iflag = parseInt(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: iflag parse failed\n", .{});
        return parseFail(line);
    };
    if (!std.mem.eql(u8, tok2.next() orelse return parseFail(line), "->")) {
        std.debug.print("DBG x: arrow missing\n", .{});
        return parseFail(line);
    }
    const want_ret = parseInt(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: ret parse failed\n", .{});
        return parseFail(line);
    };
    var want_x: [6]f64 = undefined;
    for (0..6) |i| want_x[i] = parseFloat(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: val {d} parse failed\n", .{i});
        return parseFail(line);
    };
    const want_star_q = getQuoted(line[q1end..], 0) orelse {
        std.debug.print("DBG x: starout quote missing\n", .{});
        return parseFail(line);
    };
    const want_star = want_star_q.content;
    const serr_part = std.mem.trimStart(u8, line[q1end + want_star_q.end ..], " ");
    const want_serr = if (std.mem.startsWith(u8, serr_part, "serr='") and serr_part.len >= 7)
        serr_part[6 .. serr_part.len - 1]
    else
        serr_part;
    var got: [6]f64 = undefined;
    var star_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(star_buf[0..starname.len], starname);
    star_buf[starname.len] = 0;
    var serr: [256]u8 = [_]u8{0} ** 256;
    const retflag = sweph.swe_fixstar2(star_buf[0..], tjd, iflag, &got, &swed_state, models_state, &dctx_state, &serr);
    if (retflag != want_ret or !bitsEqArr(&got, &want_x) or
        !std.mem.eql(u8, std.mem.sliceTo(&star_buf, 0), want_star) or
        !std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr))
    {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; vals want=", .{ line, want_ret, retflag });
        for (want_x) |v| std.debug.print("{x} ", .{@as(u64, @bitCast(v))});
        std.debug.print(" got=", .{});
        for (got) |v| std.debug.print("{x} ", .{@as(u64, @bitCast(v))});
        std.debug.print("\n  star want='{s}' got='{s}'; serr want='{s}' got='{s}'\n", .{
            want_star, std.mem.sliceTo(&star_buf, 0), want_serr, std.mem.sliceTo(&serr, 0),
        });
        return false;
    }
    return true;
}

/// kind y: swe_fixstar2_mag(star)
fn checkY(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "y")) return true;
    const q = getQuoted(line, 2) orelse return parseFail(line);
    const starname = q.content;
    const q1end = q.end;
    var tok2 = std.mem.tokenizeScalar(u8, line[q1end..], ' ');
    if (!std.mem.eql(u8, tok2.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok2.next() orelse return parseFail(line)) orelse return parseFail(line);
    const want_mag = parseFloat(tok2.next() orelse return parseFail(line)) orelse return parseFail(line);
    const want_star_q = getQuoted(line[q1end..], 0) orelse return parseFail(line);
    const want_star = want_star_q.content;
    const serr_part = std.mem.trimStart(u8, line[q1end + want_star_q.end ..], " ");
    const want_serr = if (std.mem.startsWith(u8, serr_part, "serr='") and serr_part.len >= 7)
        serr_part[6 .. serr_part.len - 1]
    else
        serr_part;
    var got_mag: f64 = 0;
    var star_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(star_buf[0..starname.len], starname);
    star_buf[starname.len] = 0;
    var serr: [256]u8 = [_]u8{0} ** 256;
    const retflag = sweph.swe_fixstar2_mag(star_buf[0..], &got_mag, &swed_state, &serr);
    if (retflag != want_ret or !bitsEq(got_mag, want_mag) or
        !std.mem.eql(u8, std.mem.sliceTo(&star_buf, 0), want_star) or
        !std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr))
    {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; mag want={x} got={x}; star want='{s}' got='{s}'; serr want='{s}' got='{s}'\n", .{
            line,      want_ret,                      retflag,   @as(u64, @bitCast(want_mag)), @as(u64, @bitCast(got_mag)),
            want_star, std.mem.sliceTo(&star_buf, 0), want_serr, std.mem.sliceTo(&serr, 0),
        });
        return false;
    }
    return true;
}

/// kind z: swe_fixstar (old record path)
fn checkZ(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "z")) return true;
    const q = getQuoted(line, 2) orelse return parseFail(line);
    const starname = q.content;
    const q1end = q.end;
    var tok2 = std.mem.tokenizeScalar(u8, line[q1end..], ' ');
    const tjd = parseFloat(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: tjd parse failed\n", .{});
        return parseFail(line);
    };
    const iflag = parseInt(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: iflag parse failed\n", .{});
        return parseFail(line);
    };
    if (!std.mem.eql(u8, tok2.next() orelse return parseFail(line), "->")) {
        std.debug.print("DBG x: arrow missing\n", .{});
        return parseFail(line);
    }
    const want_ret = parseInt(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: ret parse failed\n", .{});
        return parseFail(line);
    };
    var want_x: [6]f64 = undefined;
    for (0..6) |i| want_x[i] = parseFloat(tok2.next() orelse return parseFail(line)) orelse {
        std.debug.print("DBG x: val {d} parse failed\n", .{i});
        return parseFail(line);
    };
    const want_star_q = getQuoted(line[q1end..], 0) orelse {
        std.debug.print("DBG x: starout quote missing\n", .{});
        return parseFail(line);
    };
    const want_star = want_star_q.content;
    const serr_part = std.mem.trimStart(u8, line[q1end + want_star_q.end ..], " ");
    const want_serr = if (std.mem.startsWith(u8, serr_part, "serr='") and serr_part.len >= 7)
        serr_part[6 .. serr_part.len - 1]
    else
        serr_part;
    var got: [6]f64 = undefined;
    var star_buf: [256]u8 = [_]u8{0} ** 256;
    @memcpy(star_buf[0..starname.len], starname);
    star_buf[starname.len] = 0;
    var serr: [256]u8 = [_]u8{0} ** 256;
    const retflag = sweph.swe_fixstar(star_buf[0..], tjd, iflag, &got, &swed_state, models_state, &dctx_state, &serr);
    if (retflag != want_ret or !bitsEqArr(&got, &want_x) or
        !std.mem.eql(u8, std.mem.sliceTo(&star_buf, 0), want_star) or
        !std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr))
    {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; vals want=", .{ line, want_ret, retflag });
        for (want_x) |v| std.debug.print("{x} ", .{@as(u64, @bitCast(v))});
        std.debug.print(" got=", .{});
        for (got) |v| std.debug.print("{x} ", .{@as(u64, @bitCast(v))});
        std.debug.print("\n  star want='{s}' got='{s}'; serr want='{s}' got='{s}'\n", .{
            want_star, std.mem.sliceTo(&star_buf, 0), want_serr, std.mem.sliceTo(&serr, 0),
        });
        return false;
    }
    return true;
}

/// kind S: swe_get_ayanamsa_ex(tjd_et, iflag) -> retflag + daya
fn checkS(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "S")) return true;
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want_daya = parseFloat(tok.next()) orelse return parseFail(line);

    var daya: f64 = 0;
    const retflag = sweph.swe_get_ayanamsa_ex(tjd, iflag, &daya, &swed_state, models_state, &dctx_state, null);
    if (retflag != want_ret or !bitsEq(daya, want_daya)) {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; daya want={x} got={x}\n", .{
            line, want_ret, retflag, @as(u64, @bitCast(want_daya)), @as(u64, @bitCast(daya)),
        });
        return false;
    }
    return true;
}

/// kind Q: swe_get_ayanamsa_ex_ut(tjd_ut, iflag) -> retflag + daya
fn checkQ(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "Q")) return true;
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    const want_daya = parseFloat(tok.next()) orelse return parseFail(line);

    var daya: f64 = 0;
    const retflag = sweph.swe_get_ayanamsa_ex_ut(tjd, iflag, &daya, &swed_state, models_state, &dctx_state, null);
    if (retflag != want_ret or !bitsEq(daya, want_daya)) {
        std.debug.print("MISMATCH: {s}\n  retflag want={} got={}; daya want={x} got={x}\n", .{
            line, want_ret, retflag, @as(u64, @bitCast(want_daya)), @as(u64, @bitCast(daya)),
        });
        return false;
    }
    return true;
}

fn checkU(line: []const u8) bool {
    ensureEpheInit();
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tok.next() orelse return true, "U")) return true;
    const ipl = parseInt(tok.next()) orelse return parseFail(line);
    const tjd = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    const want_ret = parseInt(tok.next()) orelse return parseFail(line);
    var want: [6]f64 = undefined;
    for (&want) |*w| w.* = parseFloat(tok.next()) orelse return parseFail(line);
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

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
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

pub fn checkSwecalcLine(line: []const u8) bool {
    if (line.len == 0) return true;
    // multi-char kind pn (swe_get_planet_name) — handled before the
    // single-char switch, which keys on line[0] ('p' here).
    if (std.mem.startsWith(u8, line, "pn ")) return checkPlanetName(line);
    return switch (line[0]) {
        'U' => checkU(line),
        'L' => checkL(line),
        'S' => checkS(line),
        'Q' => checkQ(line),
        'v' => checkV(line),
        'n' => checkN(line),
        'j' => checkJpl(line),
        'x' => checkX(line),
        'y' => checkY(line),
        'z' => checkZ(line),
        else => true,
    };
}
