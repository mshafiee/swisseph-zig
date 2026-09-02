// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
//! swephgen4.zig — 1:1 transliteration of swephgen4.c (ep4 file generator).
//! Generates ep4 packed ephemeris files by calling swe_calc and writing
//! struct ep4 blocks (1000 blocks per file, NDB=10 days per block).

const std = @import("std");
const builtin = @import("builtin");
const swe = @import("swe_abi");
const ep4m = @import("sweephe4.zig");

// ── C runtime ──────────────────────────────────────────────────────────
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn sprintf(buf: [*]u8, format: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, n: usize, format: [*:0]const u8, ...) c_int;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nitems: usize, stream: ?*anyopaque) usize;
extern "c" fn fclose(stream: ?*anyopaque) c_int;
extern "c" fn scanf(format: [*:0]const u8, ...) c_int;
extern "c" fn exit(code: c_int) noreturn;

fn eprintf(comptime _: []const u8, _: anytype) void {
    // stub: use debug print (stderr)
}
const stdout: ?*anyopaque = null;

// ── constants from sweephe4.h ─────────────────────────────────────────
const EPHR_NPL: usize = 13; // PLACALC_CHIRON + 1
const EP_CALC_N: i32 = 13;
const NDB_I: i32 = ep4m.NDB; // 10
const NDB_USIZE: usize = 10;
const EP4_NDAYS_I: i32 = ep4m.EP4_NDAYS; // 10000

// pull through for 1:1 parity
const PLACALC_SUN: i32 = ep4m.PLACALC_SUN;
const PLACALC_MOON: i32 = ep4m.PLACALC_MOON;
const PLACALC_MERCURY: i32 = ep4m.PLACALC_MERCURY;
const PLACALC_CHIRON: i32 = ep4m.PLACALC_CHIRON;
const SE_ECL_NUT: i32 = ep4m.SE_ECL_NUT;
const DEG: i32 = ep4m.DEG;
const DEG360: i32 = ep4m.DEG360;
const DEG180: i32 = ep4m.DEG180;
const CS2DEG: f64 = ep4m.CS2DEG;
const AS_MAXCH: usize = ep4m.AS_MAXCH;
const OK: i32 = ep4m.OK;
const ERR: i32 = ep4m.ERR;
const TRUE_I: i32 = ep4m.TRUE;
const FALSE_I: i32 = ep4m.FALSE;

// ── globals (mirrors C statics) ────────────────────────────────────────
var arg0: [*:0]const u8 = "swephgen4";
var max_dd: [EPHR_NPL]i32 = [_]i32{0} ** EPHR_NPL;
var max_err: [EPHR_NPL]f64 = [_]f64{0} ** EPHR_NPL;
var verbose: bool = false;
var errtext: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;

// ── split: pack w (centisec) into minutes + 0.01" remainder ─────────────
fn split(w: i32, m: i32, min: *i16, sec: *i16) i32 {
    if (w >= 0) {
        sec.* = @intCast(@rem(w, 60 * m));
        min.* = @intCast(@divTrunc(w, 60 * m));
    } else {
        const aw: i32 = -w;
        sec.* = @intCast(-@rem(aw, 60 * m));
        min.* = @intCast(-@divTrunc(aw, 60 * m));
    }
    return OK;
}

// ── eph4_pack: pack 10 days of longitudes and write one ep4 block ───────
pub fn eph4_pack(jd: i32, l: *const [14][NDB_USIZE]f64, ecliptic: *const [NDB_USIZE]f64, nutation: *const [NDB_USIZE]f64) i32 {
    var e: ep4m.Ep4 = undefined;
    // jd split as in C: j_10000 = jd/10000.0, j_rest = jd -10000*j_10000
    // Use truncating division (C truncates toward 0 for double->short).
    const j10000: i32 = @divTrunc(jd, 10000);
    e.j_10000 = @intCast(j10000);
    e.j_rest = @intCast(jd - 10000 * j10000);

    var w0: i32 = swe.swe_d2l(ecliptic[0] * @as(f64, @floatFromInt(DEG)));
    _ = split(w0, 100, &e.ecl0m, &e.ecl0s);
    for (1..NDB_USIZE) |i| {
        e.ecld1[i - 1] = @intCast(swe.swe_d2l(ecliptic[i] * @as(f64, @floatFromInt(DEG)) - @as(f64, @floatFromInt(w0))));
    }
    for (0..NDB_USIZE) |i| {
        e.nuts[i] = @intCast(swe.swe_d2l(nutation[i] * @as(f64, @floatFromInt(DEG))));
    }
    var p: i32 = PLACALC_SUN;
    while (p <= PLACALC_CHIRON) : (p += 1) {
        const ps: usize = @intCast(p);
        w0 = swe.swe_d2l(l[ps][0] * @as(f64, @floatFromInt(DEG)));
        var d1: i32 = swe.swe_d2l(l[ps][1] * @as(f64, @floatFromInt(DEG)) - @as(f64, @floatFromInt(w0)));
        if (d1 >= DEG180) d1 -= DEG360 else if (d1 <= -DEG180) d1 += DEG360;
        _ = split(w0, 100, &e.elo[ps].p0m, &e.elo[ps].p0s);
        _ = split(d1, 100, &e.elo[ps].pd1m, &e.elo[ps].pd1s);
        var d_ret: i32 = d1;
        var w_ret: i32 = w0 + d_ret;
        for (2..NDB_USIZE) |ii| {
            var d2: i32 = swe.swe_d2l(l[ps][ii] * @as(f64, @floatFromInt(DEG)) - @as(f64, @floatFromInt(w_ret)));
            if (d2 >= DEG180) d2 -= DEG360 else if (d2 <= -DEG180) d2 += DEG360;
            var dd: i32 = d2 - d_ret;
            if (p == PLACALC_MOON or p == PLACALC_MERCURY) {
                dd = swe.swe_d2l(@as(f64, @floatFromInt(dd)) / 10.0);
            }
            if (verbose) {
                const add = dd;
                const cur = max_dd[ps];
                if (add < 0) {
                    if (-add > -cur and cur <= 0) {} // keep signed max logic simple: compare abs
                }
                // original: if (abs(dd) > abs(max_dd[ps])) max_dd[ps]=dd;
                const abs_dd: i32 = if (dd < 0) -dd else dd;
                const abs_cur: i32 = if (cur < 0) -cur else cur;
                if (abs_dd > abs_cur) max_dd[ps] = dd;
            }
            e.elo[ps].pd2[ii - 2] = @intCast(dd);
            if (p == PLACALC_MOON or p == PLACALC_MERCURY) {
                d_ret += @as(i32, e.elo[ps].pd2[ii - 2]) * 10;
            } else {
                d_ret += @as(i32, e.elo[ps].pd2[ii - 2]);
            }
            w_ret += d_ret;
            if (verbose) {
                const err: f64 = swe.swe_difdeg2n(@as(f64, @floatFromInt(w_ret)) / 360000.0, l[ps][ii]);
                const ae: f64 = if (err < 0) -err else err;
                const am: f64 = if (max_err[ps] < 0) -max_err[ps] else max_err[ps];
                if (ae > am) max_err[ps] = err;
            }
        }
    }
    if (builtin.target.cpu.arch.endian() == .little) {
        ep4m.shortreorder(@ptrCast(&e), @sizeOf(ep4m.Ep4));
    }
    _ = fwrite(@ptrCast(&e), @sizeOf(ep4m.Ep4), 1, ep4m.ephfp);
    return OK;
}

// ── degstr: format t degrees as " ±DDD MM'SS.ss"" ──────────────────────
var degstr_buf: [20]u8 = undefined;
fn degstr(t: f64) [*:0]const u8 {
    var sign: u8 = ' ';
    var tt = t;
    if (tt < 0) {
        sign = '-';
        tt = -tt;
    } else {
        sign = ' ';
    }
    const ideg: i32 = @intFromFloat(@floor(tt));
    const min_f: f64 = (tt - @as(f64, @floatFromInt(ideg))) * 60.0;
    const imin: i32 = @intFromFloat(@floor(min_f));
    const sec: f64 = (min_f - @as(f64, @floatFromInt(imin))) * 60.0;
    // use snprintf like C
    _ = snprintf(@ptrCast(&degstr_buf), 20, "%c%3d %2d'%5.2f\"", sign, ideg, imin, sec);
    return @ptrCast(&degstr_buf);
}

// ── eph_test: interactive reader test (mirrors C while(TRUE)) ────────────
fn eph_test() noreturn {
    var jday: i32 = 0;
    var jmon: i32 = 0;
    var jyear: i32 = 0;
    while (true) {
        _ = printf("date ?");
        const n = scanf("%d%d%d", &jday, &jmon, &jyear);
        if (n < 1) exit(1);
        var cal: u8 = 'g';
        if (jyear < 1600) cal = 'j' else cal = 'g';
        var jd: f64 = 0;
        _ = swe.swe_date_conversion(jyear, jmon, jday, 0, cal, &jd);
        const eperr: ?[*:0]u8 = @ptrCast(&errtext);
        const cp_opt = ep4m.ephread(jd, 0, 0, eperr);
        if (cp_opt == null) {
            std.debug.print("{s}: {s}", .{ std.mem.span(arg0), std.mem.sliceTo(&errtext, 0) });
            exit(1);
        }
        const cp = cp_opt.?;
        _ = printf("ephgen test d=%12.1f  dmy %d.%d.%d", jd, jday, jmon, jyear);
        if (cal == 'g') _ = printf(" greg") else _ = printf(" julian");
        _ = printf("\n\tecliptic %s ", degstr(@as(f64, @floatFromInt(cp[@intCast(ep4m.EP_ECL_INDEX)])) * CS2DEG));
        _ = printf("nutation %s\n", degstr(@as(f64, @floatFromInt(cp[@intCast(ep4m.EP_NUT_INDEX)])) * CS2DEG));
        var p2: i32 = 0;
        while (p2 <= PLACALC_CHIRON) : (p2 += 1) {
            const al: f64 = @as(f64, @floatFromInt(cp[@intCast(p2)])) * CS2DEG;
            _ = printf("%2d%18s\n", p2, degstr(al));
        }
    }
}

// ── main ─────────────────────────────────────────────────────────────────
pub fn main(init: std.process.Init) !void {
    var arena = init.arena;
    const allocator = arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len > 0) {
        // args[0] is already NUL-terminated via toSlice? ensure copy
        // Keep pointer to first arg for error prefix
        arg0 = @ptrCast(args[0].ptr);
    }

    var fnr: i32 = -10000;
    var nfiles: i32 = 1;

    // parse options 1:1 with C (expects -fNNN  -nNN  -v  -t concatenated)
    for (args[1..]) |a| {
        if (a.len >= 2 and a[0] == '-') {
            const opt = a[1];
            if (opt == 'f') {
                const num_str = if (a.len > 2) a[2..] else "0";
                fnr = std.fmt.parseInt(i32, num_str, 10) catch 0;
                if (fnr < -20 or fnr > 300) {
                    _ = printf("file number out of range -20 ... 300");
                    exit(1);
                }
            } else if (opt == 'n') {
                const num_str = if (a.len > 2) a[2..] else "1";
                nfiles = std.fmt.parseInt(i32, num_str, 10) catch 1;
            } else if (opt == 'v') {
                verbose = true;
            } else if (opt == 't') {
                eph_test();
                exit(0);
            }
        }
    }

    if (fnr == -10000) {
        std.debug.print("missing file number -fNNN\n", .{});
        exit(1);
    }

    // l[14][10] to accommodate p <= EP_CALC_N (13) without overflow
    var l: [14][NDB_USIZE]f64 = [_][NDB_USIZE]f64{[_]f64{0} ** NDB_USIZE} ** 14;
    var ecliptic: [NDB_USIZE]f64 = [_]f64{0} ** NDB_USIZE;
    var nutation: [NDB_USIZE]f64 = [_]f64{0} ** NDB_USIZE;
    var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var x: [6]f64 = undefined;

    var file: i32 = fnr;
    while (file < fnr + nfiles) : (file += 1) {
        if (file > fnr) _ = printf("\n");
        _ = printf("file = %d\n", file);
        var jd0: f64 = @as(f64, @floatFromInt(EP4_NDAYS_I * file)) + 0.5;
        var jlong: i32 = @intFromFloat(@floor(jd0));
        const eperr: ?[*:0]u8 = @ptrCast(&errtext);
        if (ep4m.eph4_posit(jlong, TRUE_I, eperr) != OK) {
            std.debug.print("{s}: {s}", .{ std.mem.span(arg0), std.mem.sliceTo(&errtext, 0) });
            exit(1);
        }
        var n: i32 = 0;
        while (n < EP4_NDAYS_I) : ({
            n += NDB_I;
            jd0 += @as(f64, @floatFromInt(NDB_I));
        }) {
            if (@rem(n, 500) == 0) {
                if (n > 0 and verbose) {
                    _ = printf("\ndd");
                    for (0..11) |pp| {
                        const v: i32 = if (pp < EPHR_NPL) max_dd[pp] else 0;
                        _ = printf("%6d ", v);
                        if (pp < EPHR_NPL) max_dd[pp] = 0;
                    }
                    _ = printf("\ner");
                    for (0..11) |pp| {
                        const v: f64 = if (pp < EPHR_NPL) max_err[pp] * 3600.0 else 0;
                        _ = printf("%6.3f ", v);
                        if (pp < EPHR_NPL) max_err[pp] = 0;
                    }
                }
                _ = printf("\n%d ", n);
            } else {
                _ = printf(".");
            }
            for (0..NDB_USIZE) |day| {
                const jd: f64 = jd0 + @as(f64, @floatFromInt(day));
                var p: i32 = PLACALC_SUN;
                while (p <= EP_CALC_N) : (p += 1) {
                    const ipl = ep4m.ephe_plac2swe(p);
                    // ephe_plac2swe can return -1 for unknown p (e.g. 13==LILITH -> SE_MEAN_APOG=12)
                    // C still calls swe_calc; we replicate.
                    const iflagret = swe.swe_calc(jd, ipl, 0, @ptrCast(&x), @ptrCast(&serr));
                    if (iflagret == ERR) {
                        swe.swe_close();
                        _ = printf("error in swe_calc() %s\n", @as([*:0]u8, @ptrCast(&serr)));
                        exit(1);
                    }
                    if (p >= 0 and @as(usize, @intCast(p)) < l.len) {
                        l[@intCast(p)][day] = x[0];
                    }
                }
                {
                    const iflagret = swe.swe_calc(jd, SE_ECL_NUT, 0, @ptrCast(&x), @ptrCast(&serr));
                    if (iflagret == ERR) {
                        swe.swe_close();
                        _ = printf("error in swe_calc() %s\n", @as([*:0]u8, @ptrCast(&serr)));
                        exit(1);
                    }
                    ecliptic[day] = x[0];
                    nutation[day] = x[2];
                }
            }
            jlong = @intFromFloat(@floor(jd0));
            _ = eph4_pack(jlong, &l, &ecliptic, &nutation);
        }
        _ = printf("\n");
        _ = fclose(ep4m.ephfp);
        ep4m.ephfp = null;
    }
    swe.swe_close();
}
