// Houses differential checking: parse the C oracle's house corpus lines
// (kinds H, P, T, N) and recompute each case with the Zig port, comparing
// bit-for-bit (%.17g round-trips doubles exactly).
const std = @import("std");
const house = @import("swehouse");

// Sunshine memo (C file static): process-lifetime, like the oracle
var hctx = house.HouseCtx{};

const Pair = struct { key: u8, idx: u32, val: f64 };

fn parsePair(tok: []const u8) ?Pair {
    // format: <letter><index>=<double>
    if (tok.len < 3) return null;
    const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return null;
    if (eq < 1) return null;
    const key = tok[0];
    if (key != 'c' and key != 'a' and key != 's' and key != 'b') return null;
    const idx = std.fmt.parseInt(u32, tok[1..eq], 10) catch return null;
    const val = std.fmt.parseFloat(f64, tok[eq + 1 ..]) catch return null;
    return .{ .key = key, .idx = idx, .val = val };
}

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

// A silently-skipped case looks like a pass; make every parse failure loud.
fn parseFail(line: []const u8) bool {
    std.debug.print("PARSE FAIL: {s}\n", .{line});
    return false;
}

fn reportH(ok: bool, line: []const u8, want: f64, got: f64) bool {
    if (!ok) {
        std.debug.print("MISMATCH: {s}\n", .{line});
        std.debug.print("  want={x} got={x}\n", .{ @as(u64, @bitCast(want)), @as(u64, @bitCast(got)) });
    }
    return ok;
}

fn checkH(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (!std.mem.eql(u8, kind, "H")) return true;
    const hs_tok = tok.next() orelse return parseFail(line);
    const hsys: i32 = @intCast(hs_tok[0]);
    const armc = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    const eps = parseFloat(tok.next()) orelse return parseFail(line);
    const iflag = parseInt(tok.next()) orelse return parseFail(line);
    const arrow = tok.next() orelse return parseFail(line);
    if (!std.mem.eql(u8, arrow, "->")) return parseFail(line);
    const want_retc = parseInt(tok.next()) orelse return parseFail(line);

    // expected values until " serr='"
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const expect_part = line[0..serr_marker];
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

    var want_c: [37]f64 = [_]f64{0} ** 37;
    var want_a: [10]f64 = [_]f64{0} ** 10;
    var want_s: [37]f64 = [_]f64{0} ** 37;
    var want_b: [10]f64 = [_]f64{0} ** 10;
    // Mirror the C generator's input setup: arrays zeroed, then
    // ascmc[9] = 12.3 (Sunshine sun declination input).
    var have_c: [37]f64 = [_]f64{0} ** 37;
    var have_a: [10]f64 = [_]f64{0} ** 10;
    var have_s: [37]f64 = [_]f64{0} ** 37;
    var have_b: [10]f64 = [_]f64{0} ** 10;
    have_a[9] = 12.3;
    var it = std.mem.tokenizeScalar(u8, expect_part, ' ');
    // Skip header tokens: "H" hsys armc geolat eps iflag -> retc
    for (0..8) |_| _ = it.next();
    while (it.next()) |t| {
        const p = parsePair(t) orelse return parseFail(line);
        switch (p.key) {
            'c' => want_c[p.idx] = p.val,
            'a' => want_a[p.idx] = p.val,
            's' => want_s[p.idx] = p.val,
            'b' => want_b[p.idx] = p.val,
            else => return false,
        }
    }

    var serr: [256]u8 = [_]u8{0} ** 256;
    const cusp_speed: ?*[37]f64 = if ((iflag & 1) != 0) &have_s else null;
    const ascmc_speed: ?*[10]f64 = if ((iflag & 2) != 0) &have_b else null;
    const retc = house.swe_houses_armc_ex2(armc, geolat, eps, hsys, &have_c, &have_a, cusp_speed, ascmc_speed, &serr, &hctx);

    if (retc != want_retc)
        return reportH(false, line, @floatFromInt(want_retc), @floatFromInt(retc));
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    const ito: usize = if (std.ascii.toUpper(@intCast(hsys)) == 'G') 36 else 12;
    var i: usize = 0;
    while (i <= ito) : (i += 1) {
        if ((iflag & 1) != 0 and !bitsEq(have_s[i], want_s[i]))
            return reportH(false, line, want_s[i], have_s[i]);
    }
    i = 0;
    while (i < 10) : (i += 1) {
        if ((iflag & 2) != 0 and !bitsEq(have_b[i], want_b[i]))
            return reportH(false, line, want_b[i], have_b[i]);
        if (!bitsEq(have_a[i], want_a[i]))
            return reportH(false, line, want_a[i], have_a[i]);
    }
    i = 0;
    while (i <= ito) : (i += 1) {
        if (!bitsEq(have_c[i], want_c[i]))
            return reportH(false, line, want_c[i], have_c[i]);
    }
    return true;
}

fn checkP(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (!std.mem.eql(u8, kind, "P")) return true;
    const hs_tok = tok.next() orelse return parseFail(line);
    const hsys: i32 = @intCast(hs_tok[0]);
    const armc = parseFloat(tok.next()) orelse return parseFail(line);
    const geolat = parseFloat(tok.next()) orelse return parseFail(line);
    const eps = parseFloat(tok.next()) orelse return parseFail(line);
    const x0 = parseFloat(tok.next()) orelse return parseFail(line);
    const x1 = parseFloat(tok.next()) orelse return parseFail(line);
    const arrow = tok.next() orelse return parseFail(line);
    if (!std.mem.eql(u8, arrow, "->")) return parseFail(line);
    const want_hp = parseFloat(tok.next()) orelse return parseFail(line);
    const serr_marker = std.mem.indexOf(u8, line, " serr='") orelse return parseFail(line);
    const want_serr_raw = line[serr_marker + 7 .. line.len - 1];
    var serr_buf: [256]u8 = undefined;
    const want_serr = unescapeSerr(&serr_buf, want_serr_raw);

    var serr: [256]u8 = [_]u8{0} ** 256;
    const xpin = [6]f64{ x0, x1, 1, 0, 0, 0 };
    const hp = house.swe_house_pos(armc, geolat, eps, hsys, &xpin, &serr, &hctx);
    if (!bitsEq(hp, want_hp)) {
        std.debug.print("MISMATCH: {s}\n  want={x} got={x}\n", .{ line, @as(u64, @bitCast(want_hp)), @as(u64, @bitCast(hp)) });
        return false;
    }
    if (!std.mem.eql(u8, std.mem.sliceTo(&serr, 0), want_serr)) {
        std.debug.print("MISMATCH serr: {s}\n  want='{s}' got='{s}'\n", .{ line, want_serr, std.mem.sliceTo(&serr, 0) });
        return false;
    }
    return true;
}

fn checkT(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (!std.mem.eql(u8, kind, "T")) return true;
    var x: [3]f64 = undefined;
    var want: [3]f64 = undefined;
    x[0] = parseFloat(tok.next()) orelse return parseFail(line);
    x[1] = parseFloat(tok.next()) orelse return parseFail(line);
    x[2] = parseFloat(tok.next()) orelse return parseFail(line);
    const eps = parseFloat(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    want[0] = parseFloat(tok.next()) orelse return parseFail(line);
    want[1] = parseFloat(tok.next()) orelse return parseFail(line);
    want[2] = parseFloat(tok.next()) orelse return parseFail(line);
    var got: [3]f64 = undefined;
    house.swe_cotrans(&x, &got, eps);
    if (bitsEq(got[0], want[0]) and bitsEq(got[1], want[1]) and bitsEq(got[2], want[2]))
        return true;
    std.debug.print("MISMATCH: {s}\n  want={x},{x},{x} got={x},{x},{x}\n", .{
        line,
        @as(u64, @bitCast(want[0])),
        @as(u64, @bitCast(want[1])),
        @as(u64, @bitCast(want[2])),
        @as(u64, @bitCast(got[0])),
        @as(u64, @bitCast(got[1])),
        @as(u64, @bitCast(got[2])),
    });
    return false;
}

fn checkN(line: []const u8) bool {
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (!std.mem.eql(u8, kind, "N")) return true;
    const code = parseInt(tok.next()) orelse return parseFail(line);
    if (!std.mem.eql(u8, tok.next() orelse return parseFail(line), "->")) return parseFail(line);
    // names can contain spaces ("equal (MC)"): take the span between the
    // first and last quote of the line
    const q1 = std.mem.indexOfScalar(u8, line, '\'') orelse return parseFail(line);
    const q2 = std.mem.lastIndexOfScalar(u8, line, '\'') orelse return parseFail(line);
    if (q2 <= q1) return parseFail(line);
    const want = line[q1 + 1 .. q2];
    const got = house.swe_house_name(code);
    const got_slice = std.mem.sliceTo(got, 0);
    if (!std.mem.eql(u8, got_slice, want)) {
        std.debug.print("MISMATCH: {s}\n  want='{s}' got='{s}'\n", .{ line, want, got_slice });
        return false;
    }
    return true;
}

fn parseInt(s: ?[]const u8) ?i32 {
    return std.fmt.parseInt(i32, s.?, 10) catch null;
}

fn parseFloat(s: ?[]const u8) ?f64 {
    return std.fmt.parseFloat(f64, s.?) catch null;
}

pub fn checkHousesLine(line: []const u8) bool {
    if (line.len == 0) return true;
    return switch (line[0]) {
        'H' => checkH(line),
        'P' => checkP(line),
        'T' => checkT(line),
        'N' => checkN(line),
        else => true,
    };
}
