// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
//! sweephe4.zig — 1:1 transliteration of sweephe4.c (EP4 fast ephemeris reader).
//! Preserves operation order for bit-exact comparison with the C oracle.
//! Uses C stdio via extern "c" (fopen/fread/fseek) like sweph.zig.
const std = @import("std");
const builtin = @import("builtin");

// ── constants from sweephe4.h / sweodef.h ───────────────────────────────
pub const INVALID_BASE: i32 = 2000000000;
pub const EPBS: usize = 2 * NDB; // 20
pub const EP_MIN_IX: i32 = 2;
pub const EP_MAX_IX: i32 = @as(i32, EPBS) - 4; // 16

pub const PLACALC_SUN: i32 = 0;
pub const PLACALC_EARTH: i32 = 0;
pub const PLACALC_MOON: i32 = 1;
pub const PLACALC_MERCURY: i32 = 2;
pub const PLACALC_VENUS: i32 = 3;
pub const PLACALC_MARS: i32 = 4;
pub const PLACALC_JUPITER: i32 = 5;
pub const PLACALC_SATURN: i32 = 6;
pub const PLACALC_URANUS: i32 = 7;
pub const PLACALC_NEPTUNE: i32 = 8;
pub const PLACALC_PLUTO: i32 = 9;
pub const PLACALC_MEAN_NODE: i32 = 10;
pub const PLACALC_TRUE_NODE: i32 = 11;
pub const PLACALC_CHIRON: i32 = 12;
pub const PLACALC_LILITH: i32 = 13;
pub const PLACALC_CALC_N: i32 = 14;
pub const PLACALC_CERES: i32 = 14;
pub const PLACALC_PALLAS: i32 = 15;
pub const PLACALC_JUNO: i32 = 16;
pub const PLACALC_VESTA: i32 = 17;
pub const PLACALC_EARTHHEL: i32 = 18;

pub const EP_NP: usize = @as(usize, PLACALC_CHIRON) + 3; // 15
pub const EP_ALL_PLANETS: i32 = (1 << (PLACALC_CHIRON + 1)) - 1;
pub const EP_ECL_INDEX: i32 = PLACALC_CHIRON + 1; // 13
pub const EP_NUT_INDEX: i32 = PLACALC_CHIRON + 2; // 14
pub const EP_ECL_BIT: i32 = 1 << EP_ECL_INDEX;
pub const EP_NUT_BIT: i32 = 1 << EP_NUT_INDEX;
pub const EP_ALL_BITS: i32 = EP_ALL_PLANETS | EP_ECL_BIT | EP_NUT_BIT;
pub const EP_BIT_SPEED: i32 = 16;
pub const EP_BIT_MUST_USE_EPHE: i32 = 256;

pub const NDB: i32 = 10;
pub const EP4_NDAYS: i32 = 10000;
pub const EP4_PATH: []const u8 = "/home/ephe/";
pub const EP4_FILE: []const u8 = "sep4_";

pub const AS_MAXCH: usize = 256;
pub const OK: i32 = 0;
pub const ERR: i32 = -1;
pub const FALSE: i32 = 0;
pub const TRUE: i32 = 1;

pub const SEFLG_SPEED: i32 = 256;
pub const SE_ECL_NUT: i32 = -1;
pub const SE_SUN: i32 = 0;
pub const SE_CHIRON: i32 = 15;
pub const SE_MEAN_APOG: i32 = 12;
pub const SE_CERES: i32 = 17;
pub const SE_PALLAS: i32 = 18;
pub const SE_JUNO: i32 = 19;
pub const SE_VESTA: i32 = 20;
pub const SE_EARTH: i32 = 14;

// centisec / degree constants (sweodef.h)
pub const DEG: i32 = 360000;
pub const DEG360: i32 = 360 * DEG; // 129600000
pub const DEG180: i32 = 180 * DEG; // 64800000
pub const CS2DEG: f64 = 1.0 / 360000.0;
pub const DIR_GLUE: u8 = '/';
pub const BFILE_R_ACCESS: []const u8 = "r";
pub const BFILE_W_CREATE: []const u8 = "w";

// ── C stdio for ep4 — wasm uses stubs (use builtin target check, not build_options, to avoid module duplication)
const is_wasm = @import("builtin").target.cpu.arch.isWasm();
fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (is_wasm) return null;
    const c = struct {
        extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
    };
    return c.fopen(path, mode);
}
fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize {
    if (is_wasm) return 0;
    const c = struct {
        extern "c" fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize;
    };
    return c.fread(ptr, size, nitems, stream);
}
fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32 {
    if (is_wasm) return -1;
    const c = struct {
        extern "c" fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32;
    };
    return c.fseek(stream, off, whence);
}
fn ftell(stream: ?*anyopaque) i64 {
    if (is_wasm) return -1;
    const c = struct {
        extern "c" fn ftell(stream: ?*anyopaque) i64;
    };
    return c.ftell(stream);
}
fn fclose(stream: ?*anyopaque) i32 {
    if (is_wasm) return 0;
    const c = struct {
        extern "c" fn fclose(stream: ?*anyopaque) i32;
    };
    return c.fclose(stream);
}

extern "c" fn swe_calc(tjd: f64, ipl: i32, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) i32;
extern "c" fn swe_close() void;

// ── structs ───────────────────────────────────────────────────────────
pub const Elon = extern struct {
    p0m: i16,
    p0s: i16,
    pd1m: i16,
    pd1s: i16,
    pd2: [8]i16, // NDB-2 == 8
};

pub const Ep4 = extern struct {
    j_10000: i16,
    j_rest: i16,
    ecl0m: i16,
    ecl0s: i16,
    ecld1: [9]i16, // NDB-1 == 9
    nuts: [10]i16, // NDB == 10
    elo: [13]Elon, // PLACALC_CHIRON+1 == 13
};

comptime {
    // 2+2+2+2 + 9*2 +10*2 +13*24 = 358
    std.debug.assert(@sizeOf(Ep4) == 358);
}

// ── globals ───────────────────────────────────────────────────────────
pub var ephfp: ?*anyopaque = null;

pub const qod: [EP_NP]i32 = .{ 5, 5, 5, 5, 5, 3, 3, 3, 3, 3, 3, 5, 3, 3, 3 };

// ephread static state
var ephread_jdbase: i32 = INVALID_BASE;
var ephread_lastplalist: i32 = 0;
var ephread_lon: [EP_NP][EPBS]i32 = [_][EPBS]i32{[_]i32{0} ** EPBS} ** EP_NP;
var ephread_out: [2 * EP_NP]i32 = [_]i32{0} ** (2 * EP_NP);

// dephread2 static state
var dephread_jdbase: i32 = INVALID_BASE;
var dephread_lastplalist: i32 = 0;
var dephread_lon: [EP_NP][EPBS]f64 = [_][EPBS]f64{[_]f64{0} ** EPBS} ** EP_NP;
var dephread_out: [2 * EP_NP]f64 = [_]f64{0} ** (2 * EP_NP);

// eph4_posit static
var eph4_open_filenr: i32 = -10000;

// inpolq_l statics
var inpolq_l_q: f64 = 0;
var inpolq_l_q2: f64 = 0;
var inpolq_l_q3: f64 = 0;
var inpolq_l_q4: f64 = 0;
var inpolq_l_q5: f64 = 0;
var inpolq_l_p2: f64 = 0;
var inpolq_l_p3: f64 = 0;
var inpolq_l_p4: f64 = 0;
var inpolq_l_p5: f64 = 0;
var inpolq_l_u: f64 = 0;
var inpolq_l_u0: f64 = 0;
var inpolq_l_u1: f64 = 0;
var inpolq_l_u2: f64 = 0;
var inpolq_l_lastp: f64 = 9999;

// inpolq statics
var inpolq_q: f64 = 0;
var inpolq_q2: f64 = 0;
var inpolq_q3: f64 = 0;
var inpolq_q4: f64 = 0;
var inpolq_q5: f64 = 0;
var inpolq_p2: f64 = 0;
var inpolq_p3: f64 = 0;
var inpolq_p4: f64 = 0;
var inpolq_p5: f64 = 0;
var inpolq_u: f64 = 0;
var inpolq_u0: f64 = 0;
var inpolq_u1: f64 = 0;
var inpolq_u2: f64 = 0;
var inpolq_lastp: f64 = 9999.0;

// ── helpers ───────────────────────────────────────────────────────────
pub fn old_d2l(x: f64) i32 {
    if (x >= 0) return @intFromFloat(x + 0.5) else return -@as(i32, @intFromFloat(0.5 - x));
}

pub fn swe_d2l(x: f64) i32 {
    return old_d2l(x);
}

fn isIntelByteOrder() bool {
    return builtin.target.cpu.arch.endian() == .little;
}

pub fn shortreorder(p: [*]u8, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 2) {
        const c0 = p[i];
        p[i] = p[i + 1];
        p[i + 1] = c0;
    }
}

fn errClear(errtext: ?[*:0]u8) void {
    if (errtext) |et| et[0] = 0;
}

fn errSet(errtext: ?[*:0]u8, comptime fmt: []const u8, args: anytype) void {
    if (errtext) |et| {
        var buf: [AS_MAXCH]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        const n = @min(msg.len, AS_MAXCH - 1);
        @memcpy(et[0..n], msg[0..n]);
        et[n] = 0;
    }
}

fn errCat(errtext: ?[*:0]u8, msg: []const u8) void {
    if (errtext) |et| {
        const cur_len = std.mem.len(et);
        if (cur_len >= AS_MAXCH - 1) return;
        const remain = AS_MAXCH - 1 - cur_len;
        const n = @min(msg.len, remain);
        @memcpy(et[cur_len .. cur_len + n], msg[0..n]);
        et[cur_len + n] = 0;
    }
}

fn my_makepath(d: [*]u8, s: [*:0]const u8) [*:0]u8 {
    const span = std.mem.span(s);
    const is_abs = span.len > 0 and (span[0] == '/' or span[0] == DIR_GLUE or std.mem.indexOfScalar(u8, span, ':') != null);
    // Original C only strcpy when absolute; for functional behavior we strcpy in both cases.
    // Preserve logic: if absolute, copy; else also copy (otherwise d would be uninitialized).
    _ = is_abs;
    var i: usize = 0;
    while (i < span.len) : (i += 1) d[i] = span[i];
    d[span.len] = 0;
    return @ptrCast(d);
}

pub fn ephe_plac2swe(p: i32) i32 {
    if (p >= PLACALC_SUN and p <= PLACALC_TRUE_NODE) return p;
    if (p == PLACALC_CHIRON) return SE_CHIRON;
    if (p == PLACALC_LILITH) return SE_MEAN_APOG;
    if (p == PLACALC_CERES) return SE_CERES;
    if (p == PLACALC_PALLAS) return SE_PALLAS;
    if (p == PLACALC_JUNO) return SE_JUNO;
    if (p == PLACALC_VESTA) return SE_VESTA;
    if (p == PLACALC_EARTHHEL) return SE_EARTH;
    return -1;
}

// ── inpolq_l (centisec) ───────────────────────────────────────────────
fn inpolq_l(n: i32, o: i32, p: f64, x: [*]const i32, axu: *i32, adxu: *i32) void {
    if (inpolq_l_lastp != p) {
        const q = 1.0 - p;
        inpolq_l_q = q;
        inpolq_l_q2 = q * q;
        inpolq_l_q3 = (q + 1.0) * q * (q - 1.0) / 6.0;
        inpolq_l_p2 = p * p;
        inpolq_l_p3 = (p + 1.0) * p * (p - 1.0) / 6.0;
        inpolq_l_u = (3.0 * inpolq_l_p2 - 1.0) / 6.0;
        inpolq_l_u0 = (3.0 * inpolq_l_q2 - 1.0) / 6.0;
        inpolq_l_q4 = inpolq_l_q2 * inpolq_l_q2;
        inpolq_l_p4 = inpolq_l_p2 * inpolq_l_p2;
        inpolq_l_u1 = (5.0 * inpolq_l_p4 - 15.0 * inpolq_l_p2 + 4.0) / 120.0;
        inpolq_l_u2 = (5.0 * inpolq_l_q4 - 15.0 * inpolq_l_q2 + 4.0) / 120.0;
        inpolq_l_q5 = inpolq_l_q3 * (q + 2.0) * (q - 2.0) / 20.0;
        inpolq_l_p5 = (p + 2.0) * inpolq_l_p3 * (p - 2.0) / 20.0;
        inpolq_l_lastp = p;
    }
    const ni: usize = @intCast(n);
    var dm1: i32 = x[ni] - x[ni - 1];
    if (dm1 >= DEG180) dm1 -= DEG360 else if (dm1 < -DEG180) dm1 += DEG360;
    var d0: i32 = x[ni + 1] - x[ni];
    var offset: i32 = 0;
    if (d0 >= DEG180) {
        d0 -= DEG360;
        offset = DEG360;
    } else if (d0 < -DEG180) {
        d0 += DEG360;
        offset = -DEG360;
    }
    var dp1: i32 = x[ni + 2] - x[ni + 1];
    if (dp1 >= DEG180) dp1 -= DEG360 else if (dp1 < -DEG180) dp1 += DEG360;
    const d20: i32 = d0 - dm1;
    const d2p1: i32 = dp1 - d0;
    var rl: f64 = inpolq_l_q * @as(f64, @floatFromInt(x[ni] + offset)) + inpolq_l_q3 * @as(f64, @floatFromInt(d20)) + p * @as(f64, @floatFromInt(x[ni + 1])) + inpolq_l_p3 * @as(f64, @floatFromInt(d2p1));
    var rlp: f64 = @as(f64, @floatFromInt(d0)) + inpolq_l_u * @as(f64, @floatFromInt(d2p1)) - inpolq_l_u0 * @as(f64, @floatFromInt(d20));
    if (o > 3) {
        var dm2: i32 = x[ni - 1] - x[ni - 2];
        if (dm2 >= DEG180) dm2 -= DEG360 else if (dm2 < -DEG180) dm2 += DEG360;
        var dp2: i32 = x[ni + 3] - x[ni + 2];
        if (dp2 >= DEG180) dp2 -= DEG360 else if (dp2 < -DEG180) dp2 += DEG360;
        const d2m1: i32 = dm1 - dm2;
        const d2p2: i32 = dp2 - dp1;
        const d30: i32 = d20 - d2m1;
        const d3p1: i32 = d2p1 - d20;
        const d3p2: i32 = d2p2 - d2p1;
        const d4p1: i32 = d3p1 - d30;
        const d4p2: i32 = d3p2 - d3p1;
        rl += inpolq_l_p5 * @as(f64, @floatFromInt(d4p2)) + inpolq_l_q5 * @as(f64, @floatFromInt(d4p1));
        rlp += inpolq_l_u1 * @as(f64, @floatFromInt(d4p2)) - inpolq_l_u2 * @as(f64, @floatFromInt(d4p1));
    }
    axu.* = swe_d2l(rl);
    adxu.* = swe_d2l(rlp);
}

// ── inpolq (double) ───────────────────────────────────────────────────
fn inpolq(n: i32, o: i32, p: f64, x: [*]const f64, axu: *f64, adxu: *f64) i32 {
    if (inpolq_lastp != p) {
        const q = 1.0 - p;
        inpolq_q = q;
        inpolq_q2 = q * q;
        inpolq_q3 = (q + 1.0) * q * (q - 1.0) / 6.0;
        inpolq_p2 = p * p;
        inpolq_p3 = (p + 1.0) * p * (p - 1.0) / 6.0;
        inpolq_u = (3.0 * inpolq_p2 - 1.0) / 6.0;
        inpolq_u0 = (3.0 * inpolq_q2 - 1.0) / 6.0;
        inpolq_q4 = inpolq_q2 * inpolq_q2;
        inpolq_p4 = inpolq_p2 * inpolq_p2;
        inpolq_u1 = (5.0 * inpolq_p4 - 15.0 * inpolq_p2 + 4.0) / 120.0;
        inpolq_u2 = (5.0 * inpolq_q4 - 15.0 * inpolq_q2 + 4.0) / 120.0;
        inpolq_q5 = inpolq_q3 * (q + 2.0) * (q - 2.0) / 20.0;
        inpolq_p5 = (p + 2.0) * inpolq_p3 * (p - 2.0) / 20.0;
        inpolq_lastp = p;
    }
    const ni: usize = @intCast(n);
    var dm1: f64 = x[ni] - x[ni - 1];
    if (dm1 > 180.0) dm1 -= 360.0;
    if (dm1 < -180.0) dm1 += 360.0;
    var d0: f64 = x[ni + 1] - x[ni];
    var offset: f64 = 0.0;
    if (d0 > 180.0) {
        d0 -= 360.0;
        offset = 360.0;
    }
    if (d0 < -180.0) {
        d0 += 360.0;
        offset = -360.0;
    }
    var dp1: f64 = x[ni + 2] - x[ni + 1];
    if (dp1 > 180.0) dp1 -= 360.0;
    if (dp1 < -180.0) dp1 += 360.0;
    const d20: f64 = d0 - dm1;
    const d2p1: f64 = dp1 - d0;
    axu.* = inpolq_q * (x[ni] + offset) + inpolq_q3 * d20 + p * x[ni + 1] + inpolq_p3 * d2p1;
    adxu.* = d0 + inpolq_u * d2p1 - inpolq_u0 * d20;
    if (o > 3) {
        var dm2: f64 = x[ni - 1] - x[ni - 2];
        if (dm2 > 180.0) dm2 -= 360.0;
        if (dm2 < -180.0) dm2 += 360.0;
        var dp2: f64 = x[ni + 3] - x[ni + 2];
        if (dp2 > 180.0) dp2 -= 360.0;
        if (dp2 < -180.0) dp2 += 360.0;
        const d2m1: f64 = dm1 - dm2;
        const d2p2: f64 = dp2 - dp1;
        const d30: f64 = d20 - d2m1;
        const d3p1: f64 = d2p1 - d20;
        const d3p2: f64 = d2p2 - d2p1;
        const d4p1: f64 = d3p1 - d30;
        const d4p2: f64 = d3p2 - d3p1;
        axu.* += inpolq_p5 * d4p2 + inpolq_q5 * d4p1;
        adxu.* += inpolq_u1 * d4p2 - inpolq_u2 * d4p1;
    }
    return OK;
}

// ── eph4_posit ────────────────────────────────────────────────────────
pub fn eph4_posit(jlong: i32, writeflag: i32, errtext: ?[*:0]u8) callconv(.c) i32 {
    var filenr: i32 = @divTrunc(jlong, EP4_NDAYS);
    if (jlong < 0 and filenr * EP4_NDAYS != jlong) filenr -= 1;
    var posit: i64 = @as(i64, jlong) - @as(i64, filenr) * @as(i64, EP4_NDAYS);
    posit = @divTrunc(posit, @as(i64, NDB)) * @as(i64, @sizeOf(Ep4));
    if (eph4_open_filenr != filenr) {
        if (ephfp != null) {
            _ = fclose(ephfp);
            eph4_open_filenr = -10000;
        }
        var s_buf: [80]u8 = undefined;
        // build s = EP4_PATH + EP4_FILE + filenr (or M + -filenr)
        var s_len: usize = 0;
        if (filenr >= 0) {
            const msg = std.fmt.bufPrint(&s_buf, "{s}{s}{d}", .{ EP4_PATH, EP4_FILE, filenr }) catch "";
            s_len = msg.len;
        } else {
            const msg = std.fmt.bufPrint(&s_buf, "{s}{s}M{d}", .{ EP4_PATH, EP4_FILE, -filenr }) catch "";
            s_len = msg.len;
        }
        s_buf[s_len] = 0;
        const s_c: [*:0]const u8 = @ptrCast(&s_buf[0]);

        var fname_buf: [AS_MAXCH]u8 = undefined;
        _ = my_makepath(@ptrCast(&fname_buf), s_c);
        // ensure fname is NUL terminated already by my_makepath
        const fname_c: [*:0]const u8 = @ptrCast(&fname_buf);

        // BFILE_* are without NUL; create NUL-terminated copy
        var mode_buf: [4]u8 = undefined;
        const mode_src = if (writeflag != 0) BFILE_W_CREATE else BFILE_R_ACCESS;
        @memcpy(mode_buf[0..mode_src.len], mode_src);
        mode_buf[mode_src.len] = 0;
        // Use mode_buf as C string
        const mode_c: [*:0]const u8 = @ptrCast(&mode_buf[0]);

        ephfp = fopen(fname_c, mode_c);
        if (ephfp == null) {
            if (errtext) |et| {
                if (writeflag == 0) {
                    errSet(errtext, "eph4_posit: file {s} does not exist\n", .{std.mem.span(s_c)});
                } else {
                    errSet(errtext, "eph4_posit: could not create file {s}\n", .{std.mem.span(s_c)});
                }
                _ = et;
            }
            return ERR;
        }
        eph4_open_filenr = filenr;
    }
    if (fseek(ephfp, posit, 0) == 0 and ftell(ephfp) == posit) {
        return OK;
    } else {
        errSet(errtext, "eph4_posit: fseek({d}) of file nr {d} failed\n", .{ posit, eph4_open_filenr });
        return ERR;
    }
}

// ── ephe4_unpack (centisec) ───────────────────────────────────────────
fn ephe4_unpack(jdl: i32, plalist: i32, lon: *[EP_NP][EPBS]i32, ioff: usize, errs: ?[*:0]u8) i32 {
    var e: Ep4 = undefined;
    if (eph4_posit(jdl, FALSE, errs) != OK) return ERR;
    if (fread(@ptrCast(&e), @sizeOf(Ep4), 1, ephfp) != 1) {
        errSet(errs, "ephe4_unpack: fread for jd={d} failed", .{jdl});
        return ERR;
    }
    if (isIntelByteOrder()) {
        shortreorder(@ptrCast(&e), @sizeOf(Ep4));
    }
    var p: i32 = PLACALC_SUN;
    var pf: i32 = 1;
    while (p <= PLACALC_CHIRON) : ({
        p += 1;
        pf <<= 1;
    }) {
        if ((plalist & pf) == 0) continue;
        var l_ret: i32 = @as(i32, e.elo[@intCast(p)].p0m) * 6000 + @as(i32, e.elo[@intCast(p)].p0s);
        var d_ret: i32 = @as(i32, e.elo[@intCast(p)].pd1m) * 6000 + @as(i32, e.elo[@intCast(p)].pd1s);
        lon[@intCast(p)][ioff] = l_ret;
        l_ret += d_ret;
        if (l_ret < 0) {
            lon[@intCast(p)][ioff + 1] = l_ret + DEG360;
        } else if (l_ret >= DEG360) {
            lon[@intCast(p)][ioff + 1] = l_ret - DEG360;
        } else {
            lon[@intCast(p)][ioff + 1] = l_ret;
        }
        var i: i32 = 2;
        while (i < NDB) : (i += 1) {
            if (p == PLACALC_MOON or p == PLACALC_MERCURY) {
                d_ret += @as(i32, e.elo[@intCast(p)].pd2[@intCast(i - 2)]) * 10;
            } else {
                d_ret += @as(i32, e.elo[@intCast(p)].pd2[@intCast(i - 2)]);
            }
            l_ret += d_ret;
            const idx: usize = ioff + @as(usize, @intCast(i));
            if (l_ret < 0) {
                lon[@intCast(p)][idx] = l_ret + DEG360;
            } else if (l_ret >= DEG360) {
                lon[@intCast(p)][idx] = l_ret - DEG360;
            } else {
                lon[@intCast(p)][idx] = l_ret;
            }
        }
    }
    if ((plalist & EP_ECL_BIT) != 0) {
        const l_ret: i32 = @as(i32, e.ecl0m) * 6000 + @as(i32, e.ecl0s);
        lon[@intCast(EP_ECL_INDEX)][ioff] = l_ret;
        var i: i32 = 1;
        while (i < NDB) : (i += 1) {
            lon[@intCast(EP_ECL_INDEX)][ioff + @as(usize, @intCast(i))] = l_ret + @as(i32, e.ecld1[@intCast(i - 1)]);
        }
    }
    if ((plalist & EP_NUT_BIT) != 0) {
        var i: i32 = 0;
        while (i < NDB) : (i += 1) {
            lon[@intCast(EP_NUT_INDEX)][ioff + @as(usize, @intCast(i))] = @as(i32, e.nuts[@intCast(i)]);
        }
    }
    return OK;
}

// ── ephe4_unpack_d (double) ───────────────────────────────────────────
fn ephe4_unpack_d(jdl: i32, plalist: i32, lon: *[EP_NP][EPBS]f64, ioff: usize, errs: ?[*:0]u8) i32 {
    var e: Ep4 = undefined;
    if (eph4_posit(jdl, FALSE, errs) != OK) return ERR;
    if (fread(@ptrCast(&e), @sizeOf(Ep4), 1, ephfp) != 1) {
        errSet(errs, "ephe4_unpack: fread for jd={d} failed", .{jdl});
        return ERR;
    }
    if (isIntelByteOrder()) {
        shortreorder(@ptrCast(&e), @sizeOf(Ep4));
    }
    var p: i32 = PLACALC_SUN;
    var pf: i32 = 1;
    while (p <= PLACALC_CHIRON) : ({
        p += 1;
        pf <<= 1;
    }) {
        if ((plalist & pf) == 0) continue;
        var l_ret: f64 = @as(f64, @floatFromInt(@as(i32, e.elo[@intCast(p)].p0m) * 6000 + @as(i32, e.elo[@intCast(p)].p0s))) * CS2DEG;
        var d_ret: f64 = @as(f64, @floatFromInt(@as(i32, e.elo[@intCast(p)].pd1m) * 6000 + @as(i32, e.elo[@intCast(p)].pd1s))) * CS2DEG;
        lon[@intCast(p)][ioff] = l_ret;
        l_ret += d_ret;
        if (l_ret < 0) {
            lon[@intCast(p)][ioff + 1] = l_ret + 360.0;
        } else if (l_ret >= 360.0) {
            lon[@intCast(p)][ioff + 1] = l_ret - 360.0;
        } else {
            lon[@intCast(p)][ioff + 1] = l_ret;
        }
        var i: i32 = 2;
        while (i < NDB) : (i += 1) {
            if (p == PLACALC_MOON or p == PLACALC_MERCURY) {
                d_ret += @as(f64, @floatFromInt(e.elo[@intCast(p)].pd2[@intCast(i - 2)])) * 10.0 * CS2DEG;
            } else {
                d_ret += @as(f64, @floatFromInt(e.elo[@intCast(p)].pd2[@intCast(i - 2)])) * CS2DEG;
            }
            l_ret += d_ret;
            const idx: usize = ioff + @as(usize, @intCast(i));
            if (l_ret < 0) {
                lon[@intCast(p)][idx] = l_ret + 360.0;
            } else if (l_ret >= 360.0) {
                lon[@intCast(p)][idx] = l_ret - 360.0;
            } else {
                lon[@intCast(p)][idx] = l_ret;
            }
        }
    }
    if ((plalist & EP_ECL_BIT) != 0) {
        const l_ret: f64 = @as(f64, @floatFromInt(@as(i32, e.ecl0m) * 6000 + @as(i32, e.ecl0s))) * CS2DEG;
        lon[@intCast(EP_ECL_INDEX)][ioff] = l_ret;
        var i: i32 = 1;
        while (i < NDB) : (i += 1) {
            lon[@intCast(EP_ECL_INDEX)][ioff + @as(usize, @intCast(i))] = l_ret + @as(f64, @floatFromInt(e.ecld1[@intCast(i - 1)])) * CS2DEG;
        }
    }
    if ((plalist & EP_NUT_BIT) != 0) {
        var i: i32 = 0;
        while (i < NDB) : (i += 1) {
            lon[@intCast(EP_NUT_INDEX)][ioff + @as(usize, @intCast(i))] = @as(f64, @floatFromInt(e.nuts[@intCast(i)])) * CS2DEG;
        }
    }
    return OK;
}

// ── ephread (centisec) ────────────────────────────────────────────────
pub fn ephread(jd: f64, plalist_in: i32, flag: i32, errtext: ?[*:0]u8) callconv(.c) ?[*]i32 {
    errClear(errtext);
    var plalist: i32 = plalist_in;
    if (plalist == 0) plalist = EP_ALL_BITS;
    if ((plalist & ephread_lastplalist) != plalist) {
        ephread_jdbase = INVALID_BASE;
    }
    ephread_lastplalist = plalist;
    const jdlong: i32 = @intFromFloat(@floor(jd - 0.5));
    var ix: i32 = jdlong - ephread_jdbase;
    if (ix < EP_MIN_IX or ix >= @as(i32, @intCast(EPBS))) {
        var newbase: i32 = @divTrunc(jdlong - EP_MIN_IX, NDB) * NDB;
        if (newbase > jdlong - EP_MIN_IX) newbase -= NDB;
        ephread_jdbase = newbase;
        if (ephe4_unpack(ephread_jdbase, plalist, &ephread_lon, 0, errtext) != OK) {
            return ephread_errExit(plalist, flag, jd, errtext);
        }
        if (ephe4_unpack(ephread_jdbase + NDB, plalist, &ephread_lon, @as(usize, @intCast(NDB)), errtext) != OK) {
            return ephread_errExit(plalist, flag, jd, errtext);
        }
        ix = jdlong - ephread_jdbase;
    } else if (ix > EP_MAX_IX) {
        ephread_jdbase += NDB;
        var p: usize = 0;
        while (p < EP_NP) : (p += 1) {
            @memcpy(ephread_lon[p][0..@as(usize, @intCast(NDB))], ephread_lon[p][@as(usize, @intCast(NDB)) .. @as(usize, @intCast(NDB)) + @as(usize, @intCast(NDB))]);
        }
        if (ephe4_unpack(ephread_jdbase + NDB, plalist, &ephread_lon, @as(usize, @intCast(NDB)), errtext) != OK) {
            return ephread_errExit(plalist, flag, jd, errtext);
        }
        ix = jdlong - ephread_jdbase;
    }
    const jfract: f64 = jd - 0.5 - @as(f64, @floatFromInt(jdlong));
    var p: i32 = 0;
    var pf: i32 = 1;
    while (p < @as(i32, @intCast(EP_NP))) : ({
        p += 1;
        pf <<= 1;
    }) {
        if ((plalist & pf) != 0) {
            var clp: i32 = 0;
            inpolq_l(ix, qod[@intCast(p)], jfract, @ptrCast(&ephread_lon[@intCast(p)]), @ptrCast(&ephread_out[@intCast(p)]), &clp);
            if (p <= PLACALC_CHIRON) {
                if (ephread_out[@intCast(p)] < 0) ephread_out[@intCast(p)] += DEG360 else if (ephread_out[@intCast(p)] >= DEG360) ephread_out[@intCast(p)] -= DEG360;
            }
            if ((flag & EP_BIT_SPEED) != 0) ephread_out[@intCast(p + @as(i32, @intCast(EP_NP)))] = clp;
        }
    }
    return @ptrCast(&ephread_out[0]);
}

fn ephread_errExit(plalist: i32, flag: i32, jd: f64, errtext: ?[*:0]u8) ?[*]i32 {
    ephread_jdbase = INVALID_BASE;
    ephread_lastplalist = 0;
    if ((flag & EP_BIT_MUST_USE_EPHE) == 0) {
        var sweflag: i32 = 0;
        if ((flag & EP_BIT_SPEED) != 0) sweflag = SEFLG_SPEED;
        if (errtext != null) errSet(errtext, "ephread failed for jd={d:.6}; used swe_calc().", .{jd});
        var x: [6]f64 = undefined;
        var p: i32 = 0;
        var pf: i32 = 1;
        while (p < PLACALC_CALC_N) : ({
            p += 1;
            pf <<= 1;
        }) {
            if ((plalist & pf) != 0) {
                const iflagret = swe_calc(jd, ephe_plac2swe(p), sweflag, @ptrCast(&x), null);
                if (iflagret != ERR) {
                    ephread_out[@intCast(p)] = swe_d2l(x[0] * @as(f64, @floatFromInt(DEG)));
                    if ((flag & EP_BIT_SPEED) != 0) ephread_out[@intCast(p + @as(i32, @intCast(EP_NP)))] = swe_d2l(x[3] * @as(f64, @floatFromInt(DEG)));
                    if (ephread_out[@intCast(p)] < 0) ephread_out[@intCast(p)] += DEG360 else if (ephread_out[@intCast(p)] >= DEG360) ephread_out[@intCast(p)] -= DEG360;
                } else {
                    swe_close();
                    if (errtext != null) errCat(errtext, " calc failed too.");
                    return null;
                }
            }
        }
        var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        const iflagret2 = swe_calc(jd, SE_ECL_NUT, 0, @ptrCast(&x), @ptrCast(&serr));
        if (iflagret2 == ERR) {
            swe_close();
            errSet(errtext, "error in swe_calc() {s}\n", .{std.mem.sliceTo(&serr, 0)});
            return null;
        }
        ephread_out[@intCast(EP_ECL_INDEX)] = swe_d2l(x[0] * @as(f64, @floatFromInt(DEG)));
        ephread_out[@intCast(EP_NUT_INDEX)] = swe_d2l(x[2] * @as(f64, @floatFromInt(DEG)));
        ephread_out[@intCast(EP_ECL_INDEX + @as(i32, @intCast(EP_NP)))] = 0;
        ephread_out[@intCast(EP_NUT_INDEX + @as(i32, @intCast(EP_NP)))] = 0;
        return @ptrCast(&ephread_out[0]);
    }
    return null;
}

// ── dephread2 (double) ────────────────────────────────────────────────
pub fn dephread2(jd: f64, plalist_in: i32, flag: i32, errtext: ?[*:0]u8) callconv(.c) ?[*]f64 {
    errClear(errtext);
    var plalist: i32 = plalist_in;
    if (plalist == 0) plalist = EP_ALL_BITS;
    if ((plalist & dephread_lastplalist) != plalist) {
        dephread_jdbase = INVALID_BASE;
    }
    dephread_lastplalist = plalist;
    const jdlong: i32 = @intFromFloat(@floor(jd - 0.5));
    var ix: i32 = jdlong - dephread_jdbase;
    if (ix < EP_MIN_IX or ix >= @as(i32, @intCast(EPBS))) {
        var newbase: i32 = @divTrunc(jdlong - EP_MIN_IX, NDB) * NDB;
        if (newbase > jdlong - EP_MIN_IX) newbase -= NDB;
        dephread_jdbase = newbase;
        if (ephe4_unpack_d(dephread_jdbase, plalist, &dephread_lon, 0, errtext) != OK) {
            return dephread_errExit(plalist, flag, jd, errtext);
        }
        if (ephe4_unpack_d(dephread_jdbase + NDB, plalist, &dephread_lon, @as(usize, @intCast(NDB)), errtext) != OK) {
            return dephread_errExit(plalist, flag, jd, errtext);
        }
        ix = jdlong - dephread_jdbase;
    } else if (ix > EP_MAX_IX) {
        dephread_jdbase += NDB;
        var p: usize = 0;
        while (p < EP_NP) : (p += 1) {
            @memcpy(dephread_lon[p][0..@as(usize, @intCast(NDB))], dephread_lon[p][@as(usize, @intCast(NDB)) .. @as(usize, @intCast(NDB)) + @as(usize, @intCast(NDB))]);
        }
        if (ephe4_unpack_d(dephread_jdbase + NDB, plalist, &dephread_lon, @as(usize, @intCast(NDB)), errtext) != OK) {
            return dephread_errExit(plalist, flag, jd, errtext);
        }
        ix = jdlong - dephread_jdbase;
    }
    const jfract: f64 = jd - 0.5 - @as(f64, @floatFromInt(jdlong));
    var p: i32 = 0;
    var pf: i32 = 1;
    while (p < @as(i32, @intCast(EP_NP))) : ({
        p += 1;
        pf <<= 1;
    }) {
        if ((plalist & pf) != 0) {
            var lp: f64 = 0;
            _ = inpolq(ix, qod[@intCast(p)], jfract, @ptrCast(&dephread_lon[@intCast(p)]), @ptrCast(&dephread_out[@intCast(p)]), &lp);
            if (p <= PLACALC_CHIRON) {
                if (dephread_out[@intCast(p)] < 0) dephread_out[@intCast(p)] += 360.0 else if (dephread_out[@intCast(p)] >= 360.0) dephread_out[@intCast(p)] -= 360.0;
            }
            if ((flag & EP_BIT_SPEED) != 0) dephread_out[@intCast(p + @as(i32, @intCast(EP_NP)))] = lp;
        }
    }
    return @ptrCast(&dephread_out[0]);
}

fn dephread_errExit(plalist: i32, flag: i32, jd: f64, errtext: ?[*:0]u8) ?[*]f64 {
    dephread_jdbase = INVALID_BASE;
    dephread_lastplalist = 0;
    if ((flag & EP_BIT_MUST_USE_EPHE) == 0) {
        var sweflag: i32 = 0;
        if ((flag & EP_BIT_SPEED) != 0) sweflag = SEFLG_SPEED;
        if (errtext != null) errSet(errtext, "ephread failed for jd={d:.6}; used swe_calc().", .{jd});
        var x: [6]f64 = undefined;
        var p: i32 = 0;
        var pf: i32 = 1;
        while (p < PLACALC_CALC_N) : ({
            p += 1;
            pf <<= 1;
        }) {
            if ((plalist & pf) != 0) {
                const iflagret = swe_calc(jd, ephe_plac2swe(p), sweflag, @ptrCast(&x), null);
                if (iflagret != ERR) {
                    dephread_out[@intCast(p)] = x[0];
                    if ((flag & EP_BIT_SPEED) != 0) dephread_out[@intCast(p + @as(i32, @intCast(EP_NP)))] = x[3];
                    if (dephread_out[@intCast(p)] < 0) dephread_out[@intCast(p)] += 360.0 else if (dephread_out[@intCast(p)] >= 360.0) dephread_out[@intCast(p)] -= 360.0;
                } else {
                    swe_close();
                    if (errtext != null) errCat(errtext, " calc failed too.");
                    return null;
                }
            }
        }
        var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        const iflagret2 = swe_calc(jd, SE_ECL_NUT, 0, @ptrCast(&x), @ptrCast(&serr));
        if (iflagret2 == ERR) {
            swe_close();
            errSet(errtext, "error in swe_calc() {s}\n", .{std.mem.sliceTo(&serr, 0)});
            return null;
        }
        dephread_out[@intCast(EP_ECL_INDEX)] = x[0];
        dephread_out[@intCast(EP_NUT_INDEX)] = x[2];
        dephread_out[@intCast(EP_ECL_INDEX + @as(i32, @intCast(EP_NP)))] = 0;
        dephread_out[@intCast(EP_NUT_INDEX + @as(i32, @intCast(EP_NP)))] = 0;
        return @ptrCast(&dephread_out[0]);
    }
    return null;
}

// ── tests ─────────────────────────────────────────────────────────────
test "ep4 structs size" {
    try std.testing.expectEqual(@as(usize, 358), @sizeOf(Ep4));
}
