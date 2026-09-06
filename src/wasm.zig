// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
//
// Browser production root for swe.wasm (wasm32-freestanding, no libc).
//
// Unlike src/swe_abi.zig (per-OS-thread globals mirroring C TLS statics),
// this root is safe under worker task interleaving: all mutable engine state
// lives in explicit session bundles created by swe_session_init(). A yielded
// sweep can never be corrupted by an interleaved natal request because the
// two tasks own different sessions; topo/sidereal for sweeps travel inside
// SweepRequest (hermetic per call), never in shared globals.
//
// Sessions must persist across calls: Swed caches open VFS handles and
// unpacked Chebyshev segments, so a fresh context per chunk would exhaust
// the 16-handle VFS table and re-parse records every chunk. swe_session_free()
// releases a session (mirrors SweState.deinit + swe_close).
//
// Return-code convention (mirrors C): negative = error (-1 bad handle/args,
// -2 engine error with serr set, plus engine BEYOND codes); non-negative =
// success, and many functions echo request flags/mode bits rather than 0
// (e.g. fixstar→iflag, pheno→epheflag). Assert `rc >= 0`, not `rc == 0`.
const std = @import("std");
const builtin = @import("builtin");
const swedate = @import("swedate");
const deltat = @import("deltat");
const sweph = @import("sweph");
const swephlib = @import("swephlib");
const swehouse = @import("swehouse");
const swecl = @import("swecl");
const swehel = @import("swehel");
const vfs = @import("vfs");

const Swed = sweph.Swed;
const DeltatCtx = deltat.DeltatCtx;
const AstroModels = swephlib.AstroModels;

const is_wasm = builtin.target.cpu.arch.isWasm();
const AS_MAXCH: usize = 256;

/// Bridge ABI version. The TS bindings generator pins this: bump on any
/// export signature/layout change so mismatched glue fails loudly.
pub export fn swe_bridge_version() callconv(.c) i32 {
    return 1;
}

// ---------------------------------------------------------------------------
// sessions
// ---------------------------------------------------------------------------
const MAX_SESSIONS = 4;

const Session = struct {
    used: bool = false,
    swed: Swed = .{},
    house: swehouse.HouseCtx = .{},
    models: AstroModels = .{},
    dctx: DeltatCtx = .{},
    cctx: swecl.SweclCtx = .{},
    hctx: swehel.SwehelCtx = .{},
};

var sessions: [MAX_SESSIONS]Session = [_]Session{.{}} ** MAX_SESSIONS;

fn sessionOf(h: i32) ?*Session {
    if (h < 0 or h >= MAX_SESSIONS) return null;
    if (!sessions[@intCast(h)].used) return null;
    return &sessions[@intCast(h)];
}

/// Create an isolated engine instance. Returns 0..3, or -1 when full.
/// One session per worker task; never share a session across tasks without
/// external serialization.
pub export fn swe_session_init() callconv(.c) i32 {
    for (&sessions, 0..) |*s, i| {
        if (!s.used) {
            s.* = .{ .used = true };
            return @intCast(i);
        }
    }
    return -1;
}

/// Release a session: frees the fixstar backing buffer (mirrors
/// SweState.deinit) and closes VFS-backed files (swe_close), then resets.
pub export fn swe_session_free(h: i32) callconv(.c) void {
    const s = sessionOf(h) orelse return;
    sessionCleanup(s);
    s.* = .{ .used = false };
}

fn sessionCleanup(s: *Session) void {
    if (s.swed.fixstar_buf.len > 0) {
        sweph.fsAlloc(&s.swed).free(s.swed.fixstar_buf);
    }
    sweph.swe_close(&s.swed);
    s.swed.fixstar_buf = &[_]sweph.FixedStar{};
    s.swed.fixed_stars = &[_]sweph.FixedStar{};
    s.swed.n_fixstars_records = 0;
}

// ---------------------------------------------------------------------------
// shared plumbing for replicated flows
// ---------------------------------------------------------------------------
const CROSS_PRECISION: f64 = 1.0 / 3600000.0;

inline fn abiDelta(s: *Session, tjd: f64, epheflag: i32) f64 {
    s.dctx.sweph_denum = s.swed.fidat[1].sweph_denum;
    s.dctx.jpldenum = s.swed.jpldenum;
    s.dctx.jpl_file_is_open = s.swed.jpl_file_is_open;
    return deltat.swe_deltat_ex(&s.dctx, tjd, epheflag);
}

fn abiGetDenum(s: *Session, epheflag: i32) i32 {
    if ((epheflag & sweph.SEFLG_MOSEPH) != 0) return 403;
    if ((epheflag & sweph.SEFLG_JPLEPH) != 0) {
        if (s.swed.jpldenum > 0) return s.swed.jpldenum else return 431;
    }
    if (s.swed.fidat[0].sweph_denum != 0) return s.swed.fidat[0].sweph_denum;
    return 431;
}

fn plausAbi(s: *Session, iflag_in: i32, ipl: i32, serr: [*]u8) i32 {
    var iflag = iflag_in;
    if ((iflag & sweph.SEFLG_JPLHOR) != 0) iflag &= ~sweph.SEFLG_JPLHOR_APPROX;
    if ((iflag & sweph.SEFLG_TOPOCTR) != 0) iflag &= ~(sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR);
    if ((iflag & sweph.SEFLG_BARYCTR) != 0) iflag &= ~sweph.SEFLG_HELCTR;
    if ((iflag & sweph.SEFLG_HELCTR) != 0) iflag &= ~sweph.SEFLG_BARYCTR;
    if ((iflag & (sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR)) != 0) iflag |= sweph.SEFLG_NOABERR | sweph.SEFLG_NOGDEFL;
    if ((iflag & sweph.SEFLG_J2000) != 0) iflag |= sweph.SEFLG_NONUT;
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
        iflag |= sweph.SEFLG_NONUT;
        iflag &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    }
    if ((iflag & sweph.SEFLG_TRUEPOS) != 0) iflag |= sweph.SEFLG_NOGDEFL | sweph.SEFLG_NOABERR;
    var epheflag: i32 = 0;
    if ((iflag & sweph.SEFLG_MOSEPH) != 0) epheflag = sweph.SEFLG_MOSEPH else if ((iflag & sweph.SEFLG_SWIEPH) != 0) epheflag = sweph.SEFLG_SWIEPH else if ((iflag & sweph.SEFLG_JPLEPH) != 0) epheflag = sweph.SEFLG_JPLEPH;
    if (epheflag == 0) epheflag = 2;
    iflag = (iflag & ~sweph.SEFLG_EPHMASK) | epheflag;
    if ((epheflag & sweph.SEFLG_JPLEPH) == 0) iflag &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    if (ipl == 11 or ipl == 10 or ipl == 12 or ipl == 13 or ipl == 21 or ipl == 22) iflag &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    if (ipl >= 40 and ipl <= 999) iflag &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    if ((iflag & sweph.SEFLG_JPLHOR) != 0) {
        if (s.swed.eop_dpsi_loaded <= 0) {
            const msg: []const u8 = switch (s.swed.eop_dpsi_loaded) {
                0 => "you did not call swe_set_jpl_file(); default to SEFLG_JPLHOR_APPROX",
                -1 => "file eop_1962_today.txt not found; default to SEFLG_JPLHOR_APPROX",
                -2 => "file eop_1962_today.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                -3 => "file eop_finals.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                else => "",
            };
            if (msg.len > 0) {
                const n = @min(msg.len, AS_MAXCH - 1);
                @memcpy(serr[0..n], msg[0..n]);
                serr[n] = 0;
            }
        }
        iflag &= ~sweph.SEFLG_JPLHOR;
        iflag |= sweph.SEFLG_JPLHOR_APPROX;
    }
    if ((iflag & sweph.SEFLG_JPLHOR) != 0) iflag |= sweph.SEFLG_ICRS;
    if ((iflag & sweph.SEFLG_JPLHOR_APPROX) != 0 and s.models.jplhora == 2) iflag |= sweph.SEFLG_ICRS;
    return iflag;
}

// ---------------------------------------------------------------------------
// version / names / stubs
// ---------------------------------------------------------------------------
/// Writes the version string, returns bytes written (excl. NUL).
pub export fn swe_version(out_ptr: usize, out_len: usize) callconv(.c) usize {
    if (out_ptr == 0 or out_len == 0) return 0;
    const v = "2.10.03";
    const n = @min(v.len, out_len - 1);
    const dst: [*]u8 = @ptrFromInt(out_ptr);
    @memcpy(dst[0..n], v[0..n]);
    dst[n] = 0;
    return n;
}

/// Stub: library path is meaningless in wasm; writes empty string.
pub export fn swe_get_library_path(out_ptr: usize, out_len: usize) callconv(.c) usize {
    if (out_ptr == 0 or out_len == 0) return 0;
    const dst: [*]u8 = @ptrFromInt(out_ptr);
    dst[0] = 0;
    return 0;
}

/// Writes the planet name, returns bytes written (excl. NUL).
pub export fn swe_get_planet_name(h: i32, ipl: i32, out_ptr: usize, out_len: usize) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (out_ptr == 0 or out_len == 0) return -1;
    var buf: [256]u8 = undefined;
    _ = sweph.swe_get_planet_name(ipl, &buf, &s.swed, s.models, &s.dctx, null);
    const l = std.mem.indexOfScalar(u8, &buf, 0) orelse 0;
    const dst: [*]u8 = @ptrFromInt(out_ptr);
    const n = @min(l, out_len - 1);
    @memcpy(dst[0..n], buf[0..n]);
    dst[n] = 0;
    return @intCast(n);
}

/// Stub: zeros outputs, returns 0.
pub export fn swe_get_current_file_data(h: i32, ifno: i32, tfstart: *f64, tfend: *f64, denum: *i32) callconv(.c) i32 {
    _ = h;
    _ = ifno;
    tfstart.* = 0;
    tfend.* = 0;
    denum.* = 0;
    return 0;
}

/// Stub: model hooks are test-only no-ops here.
pub export fn swe_get_astro_models(samod_ptr: usize, samod_len: usize, sdet_ptr: usize, sdet_len: usize, iflag: i32) callconv(.c) void {
    _ = iflag;
    if (samod_ptr != 0 and samod_len > 0) @as([*]u8, @ptrFromInt(samod_ptr))[0] = 0;
    if (sdet_ptr != 0 and sdet_len > 0) @as([*]u8, @ptrFromInt(sdet_ptr))[0] = 0;
}

pub export fn swe_set_astro_models(samod_ptr: usize, samod_len: usize, iflag: i32) callconv(.c) void {
    _ = samod_ptr;
    _ = samod_len;
    _ = iflag;
}

pub export fn swe_set_timeout(tsec: i32) callconv(.c) void {
    _ = tsec;
}

pub export fn swe_set_interpolate_nut(h: i32, do_interpolate: i32) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sweph.swe_set_interpolate_nut(do_interpolate != 0, &s.swed);
    return 0;
}

pub export fn swe_sidtime0(h: i32, tjd_ut: f64, eps: f64, nut: f64) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return swephlib.swe_sidtime0(tjd_ut, eps, nut, s.models, &s.dctx, null);
}

pub export fn swe_sidtime(h: i32, tjd_ut: f64) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return swephlib.swe_sidtime(tjd_ut, s.models, &s.dctx, null);
}

pub export fn swe_get_ayanamsa(h: i32, tjd_et: f64) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    var d: f64 = 0;
    _ = sweph.swe_get_ayanamsa_ex(tjd_et, 0, &d, &s.swed, s.models, &s.dctx, null);
    return d;
}

pub export fn swe_get_ayanamsa_ut(h: i32, tjd_ut: f64) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    var d: f64 = 0;
    _ = sweph.swe_get_ayanamsa_ex_ut(tjd_ut, 0, &d, &s.swed, s.models, &s.dctx, null);
    return d;
}

// ---------------------------------------------------------------------------
// planetocentric positions (full replica with session state)
// ---------------------------------------------------------------------------
pub export fn swe_calc_pctr(h: i32, tjd: f64, ipl: i32, iplctr: i32, iflag_in: i32, xxret: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var iflag = iflag_in;
    if (ipl == iplctr) {
        const msg = "ipl and iplctr must not be identical";
        const n = @min(msg.len, AS_MAXCH - 1);
        @memcpy(serr[0..n], msg[0..n]);
        serr[n] = 0;
        return -1;
    }
    iflag = plausAbi(s, iflag, ipl, serr);
    const epheflag = iflag & sweph.SEFLG_EPHMASK;
    {
        var xx_tmp: [6]f64 = undefined;
        const dt0 = abiDelta(s, tjd, epheflag);
        _ = sweph.swe_calc(tjd + dt0, -1, iflag, &xx_tmp, &s.swed, s.models, &s.dctx, serrToZig(serr));
    }
    iflag &= ~(sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR);
    var iflag2: i32 = epheflag;
    iflag2 |= (sweph.SEFLG_BARYCTR | sweph.SEFLG_J2000 | sweph.SEFLG_ICRS | sweph.SEFLG_TRUEPOS | sweph.SEFLG_EQUATORIAL | sweph.SEFLG_XYZ | sweph.SEFLG_SPEED);
    iflag2 |= (sweph.SEFLG_NOABERR | sweph.SEFLG_NOGDEFL);
    var xx: [6]f64 = undefined;
    var xxctr: [6]f64 = undefined;
    var xxctr2: [6]f64 = undefined;
    var xx0: [6]f64 = undefined;
    var xxsv: [24]f64 = [_]f64{0} ** 24;
    var xxsp: [6]f64 = [_]f64{0} ** 6;
    var dx: [6]f64 = undefined;
    var xreturn: [24]f64 = [_]f64{0} ** 24;
    var t: f64 = 0;
    var dt: f64 = 0;
    var dtsave_for_defl: f64 = 0;
    var daya: [2]f64 = .{ 0, 0 };
    var retc = sweph.swe_calc(tjd, iplctr, iflag2, &xxctr, &s.swed, s.models, &s.dctx, serrToZig(serr));
    if (retc == -1) return -1;
    retc = sweph.swe_calc(tjd, ipl, iflag2, &xx, &s.swed, s.models, &s.dctx, serrToZig(serr));
    if (retc == -1) return -1;
    for (0..6) |i| xx0[i] = xx[i];
    if ((iflag & sweph.SEFLG_TRUEPOS) == 0) {
        const niter: usize = 1;
        if ((iflag & sweph.SEFLG_SPEED) != 0) {
            for (0..3) |i| {
                xxsv[i] = xx[i] - xx[i + 3];
                xxsp[i] = xxsv[i];
            }
            var j: usize = 0;
            while (j <= niter) : (j += 1) {
                for (0..3) |i| {
                    dx[i] = xxsp[i];
                    dx[i] -= (xxctr[i] - xxctr[i + 3]);
                }
                dt = @sqrt(sweph.square_sum(dx[0..3])) * swephlib.AUNIT / swephlib.CLIGHT / 86400.0;
                for (0..3) |i| xxsp[i] = xxsv[i] - dt * xx0[i + 3];
            }
            for (0..3) |i| xxsp[i] = xxsv[i] - xxsp[i];
        }
        var j: usize = 0;
        while (j <= niter) : (j += 1) {
            for (0..3) |i| {
                dx[i] = xx[i];
                dx[i] -= xxctr[i];
            }
            dt = @sqrt(sweph.square_sum(dx[0..3])) * swephlib.AUNIT / swephlib.CLIGHT / 86400.0;
            t = tjd - dt;
            dtsave_for_defl = dt;
            for (0..3) |i| xx[i] = xx0[i] - dt * xx0[i + 3];
        }
        for (0..3) |i| xxsp[i] = xx0[i] - xx[i] - xxsp[i];
    }
    retc = sweph.swe_calc(t, iplctr, iflag2, &xxctr2, &s.swed, s.models, &s.dctx, serrToZig(serr));
    retc = sweph.swe_calc(t, ipl, iflag2, &xx, &s.swed, s.models, &s.dctx, serrToZig(serr));
    if ((iflag & sweph.SEFLG_HELCTR) == 0 and (iflag & sweph.SEFLG_BARYCTR) == 0) {
        for (0..6) |i| xx[i] -= xxctr[i];
        if ((iflag & sweph.SEFLG_TRUEPOS) == 0) {
            if ((iflag & sweph.SEFLG_SPEED) != 0) {
                for (3..6) |i| xx[i] -= xxsp[i - 3];
            }
        }
    }
    if ((iflag & sweph.SEFLG_SPEED) == 0) {
        for (3..6) |i| xx[i] = 0;
    }
    if ((iflag & sweph.SEFLG_TRUEPOS) == 0 and (iflag & sweph.SEFLG_NOGDEFL) == 0) {
        sweph.swi_deflect_light(&xx, dtsave_for_defl, iflag, &s.swed);
    }
    if ((iflag & sweph.SEFLG_TRUEPOS) == 0 and (iflag & sweph.SEFLG_NOABERR) == 0) {
        sweph.swi_aberr_light(&xx, &xxctr, iflag);
        if ((iflag & sweph.SEFLG_SPEED) != 0) {
            for (3..6) |i| xx[i] += xxctr[i] - xxctr2[i];
        }
    }
    if ((iflag & sweph.SEFLG_SPEED) == 0) {
        for (3..6) |i| xx[i] = 0;
    }
    if ((iflag & sweph.SEFLG_ICRS) == 0 and abiGetDenum(s, epheflag) >= 403) {
        swephlib.swi_bias(&xx, t, iflag, false, s.models);
    }
    for (0..6) |i| xxsv[i] = xx[i];
    var oe: *const swephlib.Eps = undefined;
    if ((iflag & sweph.SEFLG_J2000) == 0) {
        _ = swephlib.swi_precess(@as(*[3]f64, @ptrCast(&xx[0])), tjd, iflag, swephlib.J2000_TO_J, s.models);
        if ((iflag & sweph.SEFLG_SPEED) != 0) sweph.swi_precess_speed(&xx, tjd, iflag, swephlib.J2000_TO_J, &s.swed, s.models);
        oe = &s.swed.oec;
    } else {
        oe = &s.swed.oec2000;
    }
    if ((iflag & sweph.SEFLG_NONUT) == 0) sweph.swi_nutate(&xx, iflag, false, &s.swed);
    for (0..6) |i| xreturn[18 + i] = xx[i];
    swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[0])), @as(*[3]f64, @ptrCast(&xx[0])), oe.seps, oe.ceps);
    if ((iflag & sweph.SEFLG_SPEED) != 0) swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[3])), @as(*[3]f64, @ptrCast(&xx[3])), oe.seps, oe.ceps);
    if ((iflag & sweph.SEFLG_NONUT) == 0) {
        swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[0])), @as(*[3]f64, @ptrCast(&xx[0])), s.swed.nut.snut, s.swed.nut.cnut);
        if ((iflag & sweph.SEFLG_SPEED) != 0) swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[3])), @as(*[3]f64, @ptrCast(&xx[3])), s.swed.nut.snut, s.swed.nut.cnut);
    }
    for (0..6) |i| xreturn[6 + i] = xx[i];
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
        if ((s.swed.sidd.sid_mode & sweph.SE_SIDBIT_ECL_T0) != 0) {
            if (sweph.swi_trop_ra2sid_lon(@as(*const [6]f64, @ptrCast(&xxsv[0])), @as(*[6]f64, @ptrCast(&xreturn[6])), @as(*[6]f64, @ptrCast(&xreturn[18])), iflag, &s.swed, s.models, &s.dctx) != 0) return -1;
        } else if ((s.swed.sidd.sid_mode & sweph.SE_SIDBIT_SSY_PLANE) != 0) {
            if (sweph.swi_trop_ra2sid_lon_sosy(@as(*const [6]f64, @ptrCast(&xxsv[0])), @as(*[6]f64, @ptrCast(&xreturn[6])), iflag, &s.swed, s.models, &s.dctx) != 0) return -1;
        } else {
            swephlib.swi_cartpol_sp(@as(*[6]f64, @ptrCast(&xreturn[6])), @as(*[6]f64, @ptrCast(&xreturn[0])));
            for (0..24) |i| xxsv[i] = xreturn[i];
            if (sweph.swi_get_ayanamsa_with_speed(tjd, iflag, &daya, &s.swed, s.models, &s.dctx, serrToZig(serr)) == -1) return -1;
            for (0..24) |i| xreturn[i] = xxsv[i];
            xreturn[0] -= daya[0] * swephlib.DEGTORAD;
            xreturn[3] -= daya[1] * swephlib.DEGTORAD;
            swephlib.swi_polcart_sp(@as(*[6]f64, @ptrCast(&xreturn[0])), @as(*[6]f64, @ptrCast(&xreturn[6])));
        }
    }
    swephlib.swi_cartpol_sp(@as(*[6]f64, @ptrCast(&xreturn[18])), @as(*[6]f64, @ptrCast(&xreturn[12])));
    swephlib.swi_cartpol_sp(@as(*[6]f64, @ptrCast(&xreturn[6])), @as(*[6]f64, @ptrCast(&xreturn[0])));
    for (0..2) |i| {
        xreturn[i] *= swephlib.RADTODEG;
        xreturn[i + 3] *= swephlib.RADTODEG;
        xreturn[i + 12] *= swephlib.RADTODEG;
        xreturn[i + 15] *= swephlib.RADTODEG;
    }
    var xs: [*]f64 = undefined;
    if ((iflag & sweph.SEFLG_EQUATORIAL) != 0) xs = @ptrCast(&xreturn[12]) else xs = @ptrCast(&xreturn[0]);
    if ((iflag & sweph.SEFLG_XYZ) != 0) xs = @ptrCast(xs[6..]);
    for (0..6) |i| xxret[i] = xs[i];
    if ((iflag & sweph.SEFLG_SPEED) == 0) {
        for (3..6) |i| xxret[i] = 0;
    }
    if ((iflag & sweph.SEFLG_RADIANS) != 0) {
        for (0..2) |i| xxret[i] *= swephlib.DEGTORAD;
        if ((iflag & sweph.SEFLG_SPEED) != 0) {
            for (3..5) |i| xxret[i] *= swephlib.DEGTORAD;
        }
    }
    if (retc == -1) return -1;
    return iflag;
}

// ---------------------------------------------------------------------------
// longitude crossings (iterative, session state)
// ---------------------------------------------------------------------------
fn bodyCross(s: *Session, ipl: i32, x2cross: f64, jd0: f64, comptime use_ut: bool, flag_in: i32, serr: [*]u8) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    const calc0 = if (use_ut) sweph.swe_calc_ut else sweph.swe_calc;
    if (calc0(jd0, ipl, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return jd0 - 1;
    const xlp: f64 = if (ipl == 0) 360.0 / 365.24 else 360.0 / 27.32;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd = jd0 + dist / xlp;
    while (true) {
        if (calc0(jd, ipl, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return jd0 - 1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    return jd;
}

pub export fn swe_solcross(h: i32, x2cross: f64, jd_et: f64, flag_in: i32, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return bodyCross(s, 0, x2cross, jd_et, false, flag_in, serr);
}

pub export fn swe_solcross_ut(h: i32, x2cross: f64, jd_ut: f64, flag_in: i32, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return bodyCross(s, 0, x2cross, jd_ut, true, flag_in, serr);
}

pub export fn swe_mooncross(h: i32, x2cross: f64, jd_et: f64, flag_in: i32, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return bodyCross(s, 1, x2cross, jd_et, false, flag_in, serr);
}

pub export fn swe_mooncross_ut(h: i32, x2cross: f64, jd_ut: f64, flag_in: i32, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return bodyCross(s, 1, x2cross, jd_ut, true, flag_in, serr);
}

fn moonNodeCross(s: *Session, jd0: f64, comptime use_ut: bool, flag_in: i32, xlon: *f64, xlat: *f64, serr: [*]u8) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    const calc0 = if (use_ut) sweph.swe_calc_ut else sweph.swe_calc;
    if (calc0(jd0, 1, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return jd0 - 1;
    const xlat0 = x[1];
    var jd = jd0 + 1;
    while (true) {
        if (calc0(jd, 1, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return jd0 - 1;
        if ((x[1] >= 0 and xlat0 < 0) or (x[1] < 0 and xlat0 > 0)) break;
        jd += 1;
    }
    var dist = x[1];
    while (true) {
        jd -= dist / x[4];
        if (calc0(jd, 1, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return jd0 - 1;
        dist = x[1];
        if (@abs(dist) < CROSS_PRECISION) {
            xlon.* = x[0];
            xlat.* = x[1];
            break;
        }
    }
    return jd;
}

pub export fn swe_mooncross_node(h: i32, jd_et: f64, flag_in: i32, xlon: *f64, xlat: *f64, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return moonNodeCross(s, jd_et, false, flag_in, xlon, xlat, serr);
}

pub export fn swe_mooncross_node_ut(h: i32, jd_ut: f64, flag_in: i32, xlon: *f64, xlat: *f64, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return moonNodeCross(s, jd_ut, true, flag_in, xlon, xlat, serr);
}

fn helioCross(s: *Session, ipl: i32, x2cross: f64, jd0: f64, comptime use_ut: bool, iflag_in: i32, dir: i32, jd_cross: *f64, serr: [*]u8) i32 {
    const flag = iflag_in | sweph.SEFLG_SPEED | sweph.SEFLG_HELCTR;
    if (ipl == 0 or ipl == 1 or (ipl >= 10 and ipl <= 13) or (ipl >= 21 and ipl < 23)) {
        const msg = "swe_helio_cross: not possible for this object";
        const n = @min(msg.len, AS_MAXCH - 1);
        @memcpy(serr[0..n], msg[0..n]);
        serr[n] = 0;
        return -1;
    }
    var x: [6]f64 = undefined;
    const calc0 = if (use_ut) sweph.swe_calc_ut else sweph.swe_calc;
    if (calc0(jd0, ipl, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return -1;
    var xlp = x[3];
    if (ipl == 15) xlp = 0.01971;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd: f64 = undefined;
    if (dir >= 0) jd = jd0 + dist / xlp else {
        dist = 360.0 - dist;
        jd = jd0 - dist / xlp;
    }
    while (true) {
        if (calc0(jd, ipl, flag, &x, &s.swed, s.models, &s.dctx, serrToZig(serr)) < 0) return -1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    jd_cross.* = jd;
    return 0;
}

pub export fn swe_helio_cross(h: i32, ipl: i32, x2cross: f64, jd_et: f64, iflag_in: i32, dir: i32, jd_cross: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return helioCross(s, ipl, x2cross, jd_et, false, iflag_in, dir, jd_cross, serr);
}

pub export fn swe_helio_cross_ut(h: i32, ipl: i32, x2cross: f64, jd_ut: f64, iflag_in: i32, dir: i32, jd_cross: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return helioCross(s, ipl, x2cross, jd_ut, true, iflag_in, dir, jd_cross, serr);
}

/// swisseph-zig swe_cleanup equivalent: frees per-session heap resources
/// but keeps the session usable.
pub export fn swe_cleanup(h: i32) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sessionCleanup(s);
    s.swed = .{};
    s.*.used = true;
    return 0;
}

// ---------------------------------------------------------------------------
// staging allocator (mirrors swe_abi.swe_wasm_alloc contract)
// ---------------------------------------------------------------------------
pub export fn swe_wasm_alloc(n: usize) ?[*]u8 {
    if (!is_wasm or n == 0) return null;
    const mem = std.heap.wasm_allocator.alloc(u8, n) catch return null;
    return mem.ptr;
}

pub export fn swe_wasm_free(ptr: ?[*]u8, n: usize) void {
    if (!is_wasm) return;
    const p = ptr orelse return;
    if (n == 0) return;
    std.heap.wasm_allocator.free(p[0..n]);
}

// ---------------------------------------------------------------------------
// VFS registration (delegates to vfs; copy-on-register contract)
// ---------------------------------------------------------------------------
pub export fn swe_vfs_register(name_ptr: ?[*]const u8, name_len: usize, data_ptr: ?[*]const u8, data_len: usize) callconv(.c) i32 {
    const np = name_ptr orelse return -3;
    if (name_len == 0 or name_len >= vfs.MAX_NAME) return -3;
    const dp = data_ptr orelse (if (data_len == 0) &[0]u8{} else return -1);
    return vfs.register(np[0..name_len], dp[0..data_len]);
}

pub export fn swe_vfs_clear() callconv(.c) void {
    vfs.clear();
}

pub export fn swe_vfs_count() callconv(.c) i32 {
    return @intCast(vfs.fileCount());
}

pub export fn swe_vfs_heap_choice() callconv(.c) i32 {
    return vfs.heapChoiceForTest();
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
inline fn serrToZig(serr: [*]u8) []u8 {
    return serr[0..AS_MAXCH];
}

inline fn sliceOf(ptr: ?[*:0]const u8) ?[]const u8 {
    const p = ptr orelse return null;
    return p[0..std.mem.len(p)];
}

// ---------------------------------------------------------------------------
// hermetic single calls (session handle first; never touch globals)
// ---------------------------------------------------------------------------
pub export fn swe_julday(year: i32, month: i32, day: i32, hour: f64, gregflag: i32) callconv(.c) f64 {
    return swedate.swe_julday(year, month, day, hour, gregflag);
}

pub export fn swe_calc_ut(h: i32, tjd_ut: f64, ipl: i32, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var buf: [6]f64 = undefined;
    const ret = sweph.swe_calc_ut(tjd_ut, ipl, iflag, &buf, &s.swed, s.models, &s.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = buf[i];
    return ret;
}

pub export fn swe_calc(h: i32, tjd: f64, ipl: i32, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var buf: [6]f64 = undefined;
    const ret = sweph.swe_calc(tjd, ipl, iflag, &buf, &s.swed, s.models, &s.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = buf[i];
    return ret;
}

pub export fn swe_set_topo(h: i32, geolon: f64, geolat: f64, geoalt: f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sweph.swe_set_topo(geolon, geolat, geoalt, &s.swed);
    return 0;
}

pub export fn swe_set_sid_mode(h: i32, sid_mode: i32, t0: f64, ayan_t0: f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sweph.swe_set_sid_mode(sid_mode, t0, ayan_t0, &s.swed, &s.models);
    return 0;
}

pub export fn swe_get_ayanamsa_ex_ut(h: i32, tjd_ut: f64, iflag: i32, daya: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return sweph.swe_get_ayanamsa_ex_ut(tjd_ut, iflag, daya, &s.swed, s.models, &s.dctx, serrToZig(serr));
}

pub export fn swe_set_ephe_path(h: i32, path: ?[*:0]const u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sweph.swe_set_ephe_path(sliceOf(path), &s.swed, &s.models, &s.dctx, null);
    return 0;
}

pub export fn swe_set_jpl_file(h: i32, fname: ?[*:0]const u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    const p = sliceOf(fname) orelse return -1;
    sweph.swe_set_jpl_file(p, &s.swed, &s.models, &s.dctx);
    return 0;
}

pub export fn swe_deltat_ex(h: i32, tjd: f64, iflag: i32) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return deltat.swe_deltat_ex(&s.dctx, tjd, iflag);
}

pub export fn swe_eop_status(h: i32) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return s.swed.eop_dpsi_loaded;
}

// ---------------------------------------------------------------------------
// houses (armc/eps supplied by caller; speeds omitted — null)
// ---------------------------------------------------------------------------
pub export fn swe_houses_armc_ex2(h: i32, armc: f64, geolat: f64, eps: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var cs: [37]f64 = [_]f64{0} ** 37;
    var asc: [10]f64 = [_]f64{0} ** 10;
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const ret = swehouse.swe_houses_armc_ex2(armc, geolat, eps, hsys, &cs, &asc, null, null, &serr_buf, &s.house);
    for (0..37) |i| cusps[i] = cs[i];
    for (0..10) |i| ascmc[i] = asc[i];
    @memcpy(serr[0..AS_MAXCH], &serr_buf);
    return ret;
}

pub export fn swe_house_pos(h: i32, armc: f64, geolat: f64, eps: f64, hsys: i32, lon: f64, lat: f64, serr: [*]u8) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    const xin: [6]f64 = .{ lon, lat, 0, 0, 0, 0 };
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const ret = swehouse.swe_house_pos(armc, geolat, eps, hsys, &xin, &serr_buf, &s.house);
    @memcpy(serr[0..AS_MAXCH], &serr_buf);
    return ret;
}

/// Returns the address of a static NUL-terminated house-system name.
pub export fn swe_house_name(hsys: i32) callconv(.c) usize {
    return @intFromPtr(swehouse.swe_house_name(hsys));
}

// ---------------------------------------------------------------------------
// fixed stars (caller staging buffer copied in; normalized name copied back)
// ---------------------------------------------------------------------------
fn starBuf(star_ptr: usize, star_len: usize, buf: *[512]u8) ?[]u8 {
    if (star_ptr == 0 or star_len == 0 or star_len >= 512) return null;
    const src: [*]const u8 = @ptrFromInt(star_ptr);
    @memcpy(buf[0..star_len], src[0..star_len]);
    buf[star_len] = 0;
    return buf[0..];
}

fn starWriteback(star_ptr: usize, buf: *[512]u8) void {
    const dst: [*]u8 = @ptrFromInt(star_ptr);
    const slen = std.mem.indexOfScalar(u8, buf, 0) orelse 511;
    @memcpy(dst[0..slen], buf[0..slen]);
    dst[slen] = 0;
}

fn starCalc(s: *Session, star_ptr: usize, star_len: usize, tjd: f64, iflag: i32, xx: [*]f64, serr: [*]u8, comptime use_ut: bool, comptime use_v2: bool) i32 {
    var sb: [512]u8 = undefined;
    const star = starBuf(star_ptr, star_len, &sb) orelse return -1;
    var out: [6]f64 = undefined;
    const f = if (use_v2) (if (use_ut) sweph.swe_fixstar2_ut else sweph.swe_fixstar2) else (if (use_ut) sweph.swe_fixstar_ut else sweph.swe_fixstar);
    const ret = f(star, tjd, iflag, &out, &s.swed, s.models, &s.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = out[i];
    starWriteback(star_ptr, &sb);
    return ret;
}

pub export fn swe_fixstar(h: i32, star_ptr: usize, star_len: usize, tjd: f64, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return starCalc(s, star_ptr, star_len, tjd, iflag, xx, serr, false, false);
}

pub export fn swe_fixstar_ut(h: i32, star_ptr: usize, star_len: usize, tjd_ut: f64, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return starCalc(s, star_ptr, star_len, tjd_ut, iflag, xx, serr, true, false);
}

pub export fn swe_fixstar2(h: i32, star_ptr: usize, star_len: usize, tjd: f64, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return starCalc(s, star_ptr, star_len, tjd, iflag, xx, serr, false, true);
}

pub export fn swe_fixstar2_ut(h: i32, star_ptr: usize, star_len: usize, tjd_ut: f64, iflag: i32, xx: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return starCalc(s, star_ptr, star_len, tjd_ut, iflag, xx, serr, true, true);
}

pub export fn swe_fixstar_mag(h: i32, star_ptr: usize, star_len: usize, mag: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var sb: [512]u8 = undefined;
    const star = starBuf(star_ptr, star_len, &sb) orelse return -1;
    return sweph.swe_fixstar_mag(star, mag, &s.swed, serrToZig(serr));
}

// ---------------------------------------------------------------------------
// phenomena, nodes, rise/transit, eclipses
// ---------------------------------------------------------------------------
pub export fn swe_pheno(h: i32, tjd_et: f64, ipl: i32, iflag: i32, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_pheno(tjd_et, ipl, iflag, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx);
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_pheno_ut(h: i32, tjd_ut: f64, ipl: i32, iflag: i32, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_pheno_ut(tjd_ut, ipl, iflag, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx);
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_nod_aps_ut(h: i32, tjd_ut: f64, ipl: i32, iflag: i32, method: i32, xnasc: [*]f64, xndsc: [*]f64, xperi: [*]f64, xaphe: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var na: [6]f64 = undefined;
    var nd: [6]f64 = undefined;
    var pe: [6]f64 = undefined;
    var ap: [6]f64 = undefined;
    const ret = swecl.swe_nod_aps_ut(tjd_ut, ipl, iflag, method, &na, &nd, &pe, &ap, serrToZig(serr), &s.swed, s.models, &s.dctx);
    for (0..6) |i| {
        xnasc[i] = na[i];
        xndsc[i] = nd[i];
        xperi[i] = pe[i];
        xaphe[i] = ap[i];
    }
    return ret;
}

inline fn optStar(star_ptr: usize, star_len: usize, buf: *[256]u8) ?[]u8 {
    if (star_ptr == 0 or star_len == 0) return null;
    const n = @min(star_len, 255);
    const src: [*]const u8 = @ptrFromInt(star_ptr);
    @memcpy(buf[0..n], src[0..n]);
    buf[n] = 0;
    if (n == 0 or buf[0] == 0) return null;
    return buf[0..];
}

pub export fn swe_rise_trans(h: i32, tjd_ut: f64, ipl: i32, star_ptr: usize, star_len: usize, epheflag: i32, rsmi: i32, glon: f64, glat: f64, galt: f64, atpress: f64, attemp: f64, tret: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var sb: [256]u8 = undefined;
    var geo: [3]f64 = .{ glon, glat, galt };
    return swecl.swe_rise_trans(tjd_ut, ipl, optStar(star_ptr, star_len, &sb), epheflag, rsmi, &geo, atpress, attemp, tret, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
}

pub export fn swe_rise_trans_true_hor(h: i32, tjd_ut: f64, ipl: i32, star_ptr: usize, star_len: usize, epheflag: i32, rsmi: i32, glon: f64, glat: f64, galt: f64, atpress: f64, attemp: f64, horhgt: f64, tret: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var sb: [256]u8 = undefined;
    var geo: [3]f64 = .{ glon, glat, galt };
    return swecl.swe_rise_trans_true_hor(tjd_ut, ipl, optStar(star_ptr, star_len, &sb), epheflag, rsmi, &geo, atpress, attemp, horhgt, tret, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
}

pub export fn swe_sol_eclipse_when_glob(h: i32, tjd: f64, ifl: i32, ifltype: i32, tret: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var tb: [10]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_when_glob(tjd, ifl, ifltype, &tb, backward != 0, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    return ret;
}

pub export fn swe_sol_eclipse_when_loc(h: i32, tjd: f64, ifl: i32, glon: f64, glat: f64, galt: f64, tret: [*]f64, attr: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var geo: [3]f64 = .{ glon, glat, galt };
    var tb: [10]f64 = undefined;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_when_loc(tjd, ifl, &geo, &tb, &ab, backward != 0, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_lun_eclipse_when(h: i32, tjd: f64, ifl: i32, ifltype: i32, tret: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var tb: [10]f64 = undefined;
    const ret = swecl.swe_lun_eclipse_when(tjd, ifl, ifltype, &tb, backward, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    return ret;
}

pub export fn swe_deltat(h: i32, tjd: f64) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    return deltat.swe_deltat_ex(&s.dctx, tjd, -1);
}

pub export fn swe_get_ayanamsa_ex(h: i32, tjd_et: f64, iflag: i32, daya: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return sweph.swe_get_ayanamsa_ex(tjd_et, iflag, daya, &s.swed, s.models, &s.dctx, serrToZig(serr));
}

// ---------------------------------------------------------------------------
// pure angle helpers (stateless transliterations)
// ---------------------------------------------------------------------------
pub export fn swe_degnorm(x: f64) callconv(.c) f64 {
    return swephlib.swe_degnorm(x);
}

pub export fn swe_radnorm(x: f64) callconv(.c) f64 {
    return swephlib.swe_radnorm(x);
}

pub export fn swe_difdeg2n(p1: f64, p2: f64) callconv(.c) f64 {
    return swephlib.swe_difdeg2n(p1, p2);
}

pub export fn swe_difrad2n(p1: f64, p2: f64) callconv(.c) f64 {
    return swephlib.swe_difrad2n(p1, p2);
}

pub export fn swe_difdegn(p1: f64, p2: f64) callconv(.c) f64 {
    return swephlib.swe_degnorm(p1 - p2);
}

pub export fn swe_deg_midp(x1: f64, x0: f64) callconv(.c) f64 {
    return swephlib.swe_deg_midp(x1, x0);
}

pub export fn swe_rad_midp(x1: f64, x0: f64) callconv(.c) f64 {
    return swephlib.swe_rad_midp(x1, x0);
}

pub export fn swe_cotrans(xpo: [*]f64, xpn: [*]f64, eps: f64) callconv(.c) void {
    swehouse.swe_cotrans(xpo[0..3], xpn[0..3], eps);
    xpn[2] = xpo[2];
}

pub export fn swe_cotrans_sp(xpo: [*]f64, xpn: [*]f64, eps: f64) callconv(.c) void {
    var x: [6]f64 = .{ xpo[0], xpo[1], xpo[2], xpo[3], xpo[4], xpo[5] };
    const e = eps * swephlib.DEGTORAD;
    x[0] *= swephlib.DEGTORAD;
    x[1] *= swephlib.DEGTORAD;
    x[2] = 1;
    x[3] *= swephlib.DEGTORAD;
    x[4] *= swephlib.DEGTORAD;
    swephlib.swi_polcart_sp(&x, &x);
    var t0: [3]f64 = .{ x[0], x[1], x[2] };
    var t1: [3]f64 = .{ x[3], x[4], x[5] };
    swephlib.swi_coortrf(&t0, &t0, e);
    swephlib.swi_coortrf(&t1, &t1, e);
    x[0] = t0[0];
    x[1] = t0[1];
    x[2] = t0[2];
    x[3] = t1[0];
    x[4] = t1[1];
    x[5] = t1[2];
    var out: [6]f64 = undefined;
    swephlib.swi_cartpol_sp(&x, &out);
    xpn[0] = out[0] * swephlib.RADTODEG;
    xpn[1] = out[1] * swephlib.RADTODEG;
    xpn[2] = xpo[2];
    xpn[3] = out[3] * swephlib.RADTODEG;
    xpn[4] = out[4] * swephlib.RADTODEG;
    xpn[5] = xpo[5];
}

pub export fn swe_csnorm(p: i32) callconv(.c) i32 {
    var pp = p;
    if (pp < 0) {
        while (pp < 0) pp += 360 * 360000;
    } else if (pp >= 360 * 360000) {
        while (pp >= 360 * 360000) pp -= 360 * 360000;
    }
    return pp;
}

pub export fn swe_difcsn(p1: i32, p2: i32) callconv(.c) i32 {
    return swe_csnorm(p1 - p2);
}

pub export fn swe_difcs2n(p1: i32, p2: i32) callconv(.c) i32 {
    var d = swe_csnorm(p1 - p2);
    if (d >= 180 * 360000) d -= 360 * 360000;
    return d;
}

pub export fn swe_csroundsec(x: i32) callconv(.c) i32 {
    var t = @divTrunc(x + 50, 100) * 100;
    if (t > x and @rem(t, 30 * 360000) == 0) t = @divTrunc(x, 100) * 100;
    return t;
}

pub export fn swe_d2l(x: f64) callconv(.c) i32 {
    if (x >= 0) return @intFromFloat(x + 0.5) else return -@as(i32, @intFromFloat(0.5 - x));
}

pub export fn swe_day_of_week(jd: f64) callconv(.c) i32 {
    const d = @floor(jd - 2433282 - 1.5);
    const r = @rem(@as(i32, @intFromFloat(d)), 7);
    return @mod(r + 7, 7);
}

pub export fn swe_cs2timestr(t: i32, sep: i32, suppress_zero: i32, out_ptr: usize, out_len: usize) callconv(.c) usize {
    if (out_ptr == 0 or out_len < 9) return 0;
    const a: [*]u8 = @ptrFromInt(out_ptr);
    const sc: u8 = @intCast(sep & 0xFF);
    @memcpy(a[0..8], "        ");
    a[8] = 0;
    a[2] = sc;
    a[5] = sc;
    var tt = @rem(@divTrunc(t + 50, 100), 24 * 3600);
    if (tt < 0) tt += 24 * 3600;
    const s: i32 = @rem(tt, 60);
    const m: i32 = @rem(@divTrunc(tt, 60), 60);
    const h: i32 = @rem(@divTrunc(tt, 3600), 100);
    if (s == 0 and suppress_zero != 0) a[5] = 0 else {
        a[6] = @intCast(@divTrunc(s, 10) + '0');
        a[7] = @intCast(@rem(s, 10) + '0');
    }
    a[0] = @intCast(@divTrunc(h, 10) + '0');
    a[1] = @intCast(@rem(h, 10) + '0');
    a[3] = @intCast(@divTrunc(m, 10) + '0');
    a[4] = @intCast(@rem(m, 10) + '0');
    return 8;
}

pub export fn swe_cs2lonlatstr(t: i32, pchar: u8, mchar: u8, out_ptr: usize, out_len: usize) callconv(.c) usize {
    if (out_ptr == 0 or out_len < 10) return 0;
    const sp: [*]u8 = @ptrFromInt(out_ptr);
    var a: [10]u8 = undefined;
    @memcpy(a[0..9], "      '  ");
    a[9] = 0;
    var pch = pchar;
    if (t < 0) pch = mchar;
    const tt: i32 = @divTrunc(@as(i32, @intCast(@abs(t))) + 50, 100);
    const s: i32 = @rem(tt, 60);
    const m: i32 = @rem(@divTrunc(tt, 60), 60);
    const h: i32 = @rem(@divTrunc(tt, 3600), 1000);
    if (s == 0) a[6] = 0 else {
        a[7] = @intCast(@divTrunc(s, 10) + '0');
        a[8] = @intCast(@rem(s, 10) + '0');
    }
    a[3] = pch;
    if (h > 99) a[0] = @intCast(@divTrunc(h, 100) + '0');
    if (h > 9) a[1] = @intCast(@rem(@divTrunc(h, 10), 10) + '0');
    a[2] = @intCast(@rem(h, 10) + '0');
    a[4] = @intCast(@divTrunc(m, 10) + '0');
    a[5] = @intCast(@rem(m, 10) + '0');
    var aa: usize = 0;
    while (aa < 9 and a[aa] == ' ') aa += 1;
    const len = 9 - aa;
    @memcpy(sp[0..len], a[aa..9]);
    sp[len] = 0;
    return len;
}

/// Manual "%2d°%02d'%02d" (no snprintf import on freestanding).
pub export fn swe_cs2degstr(t: i32, out_ptr: usize, out_len: usize) callconv(.c) usize {
    if (out_ptr == 0 or out_len < 12) return 0;
    const a: [*]u8 = @ptrFromInt(out_ptr);
    var tt = @rem(@divTrunc(t, 100), 30 * 3600);
    if (tt < 0) tt += 30 * 3600;
    const s: i32 = @rem(tt, 60);
    const m: i32 = @rem(@divTrunc(tt, 60), 60);
    const h: i32 = @rem(@divTrunc(tt, 3600), 100);
    a[0] = if (h >= 10) @intCast(@divTrunc(h, 10) + '0') else ' ';
    a[1] = @intCast(@rem(h, 10) + '0');
    a[2] = 0xC2;
    a[3] = 0xB0;
    a[4] = @intCast(@divTrunc(m, 10) + '0');
    a[5] = @intCast(@rem(m, 10) + '0');
    a[6] = '\'';
    a[7] = @intCast(@divTrunc(s, 10) + '0');
    a[8] = @intCast(@rem(s, 10) + '0');
    a[9] = 0;
    return 9;
}

// ---------------------------------------------------------------------------
// calendar conversions (leap-second aware UTC <-> JD)
// ---------------------------------------------------------------------------
pub export fn swe_revjul(jd: f64, gregflag: i32, jyear: *i32, jmon: *i32, jday: *i32, jut: *f64) callconv(.c) void {
    const r = swedate.swe_revjul(jd, gregflag);
    jyear.* = r.year;
    jmon.* = r.mon;
    jday.* = r.day;
    jut.* = r.ut;
}

pub export fn swe_date_conversion(y: i32, m: i32, d: i32, utime: f64, c: u8, tjd: *f64) callconv(.c) i32 {
    const r = swedate.swe_date_conversion(y, m, d, utime, c);
    tjd.* = r.tjd;
    return r.rc;
}

pub export fn swe_utc_time_zone(iyear: i32, imonth: i32, iday: i32, ihour: i32, imin: i32, dsec: f64, d_timezone: f64, iyear_out: *i32, imonth_out: *i32, iday_out: *i32, ihour_out: *i32, imin_out: *i32, dsec_out: *f64) callconv(.c) void {
    const r = swedate.swe_utc_time_zone(iyear, imonth, iday, ihour, imin, dsec, d_timezone);
    iyear_out.* = r.year;
    imonth_out.* = r.mon;
    iday_out.* = r.day;
    ihour_out.* = r.hour;
    imin_out.* = r.min;
    dsec_out.* = r.sec;
}

// ---------------------------------------------------------------------------
// split_deg (with session-aware nakshatra path)
// ---------------------------------------------------------------------------
fn splitDegNakshatra(s: *Session, ddeg_in: f64, roundflag: i32, ideg: *i32, imin: *i32, isec: *i32, dsecfr: *f64, inak: *i32) void {
    var ddeg = ddeg_in;
    var dadd: f64 = 0;
    const dnakshsize: f64 = 13.33333333333333;
    const ddeghelp: f64 = swephlib.swe_shim_fmod(ddeg, dnakshsize);
    inak.* = 1;
    if (ddeg < 0) {
        inak.* = -1;
        ddeg = 0;
    }
    if ((s.swed.sidd.sid_mode & 39) == 39) {
        ddeg = swephlib.swe_degnorm(ddeg + 3.33333333333333);
    }
    if ((roundflag & 4) != 0) {
        dadd = 0.5;
    } else if ((roundflag & 2) != 0) {
        dadd = 0.5 / 60.0;
    } else if ((roundflag & 1) != 0) {
        dadd = 0.5 / 3600.0;
    }
    if ((roundflag & 32) != 0) {
        if (@as(i32, @intFromFloat(ddeghelp + dadd)) - @as(i32, @intFromFloat(ddeghelp)) > 0) {
            dadd = 0;
        }
    } else if ((roundflag & 16) != 0) {
        if (ddeghelp + dadd >= dnakshsize) {
            dadd = 0;
        }
    }
    ddeg += dadd;
    inak.* = @as(i32, @intFromFloat(ddeg / dnakshsize));
    if (inak.* == 27) inak.* = 0;
    ddeg = swephlib.swe_shim_fmod(ddeg, dnakshsize);
    ideg.* = @as(i32, @intFromFloat(ddeg));
    ddeg -= @as(f64, @floatFromInt(ideg.*));
    imin.* = @as(i32, @intFromFloat(ddeg * 60.0));
    ddeg -= @as(f64, @floatFromInt(imin.*)) / 60.0;
    isec.* = @as(i32, @intFromFloat(ddeg * 3600.0));
    if ((roundflag & (4 | 2 | 1)) == 0) {
        dsecfr.* = ddeg * 3600.0 - @as(f64, @floatFromInt(isec.*));
    } else {
        dsecfr.* = 0;
    }
    if ((roundflag & 4) != 0) imin.* = 0;
    if ((roundflag & (4 | 2)) != 0) isec.* = 0;
}

pub export fn swe_split_deg(h: i32, ddeg: f64, roundflag: i32, ideg: *i32, imin: *i32, isec: *i32, dsecfr: *f64, isgn: *i32) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ddeg_local = ddeg;
    var dadd: f64 = 0;
    isgn.* = 1;
    if (ddeg_local < 0) {
        isgn.* = -1;
        ddeg_local = -ddeg_local;
    } else if ((roundflag & 1024) != 0) {
        splitDegNakshatra(s, ddeg_local, roundflag, ideg, imin, isec, dsecfr, isgn);
        return 0;
    }
    if ((roundflag & 4) != 0) {
        dadd = 0.5;
    } else if ((roundflag & 2) != 0) {
        dadd = 0.5 / 60.0;
    } else if ((roundflag & 1) != 0) {
        dadd = 0.5 / 3600.0;
    }
    if ((roundflag & 32) != 0) {
        if (@as(i32, @intFromFloat(ddeg_local + dadd)) - @as(i32, @intFromFloat(ddeg_local)) > 0) {
            dadd = 0;
        }
    } else if ((roundflag & 16) != 0) {
        if (swephlib.swe_shim_fmod(ddeg_local, 30.0) + dadd >= 30.0) {
            dadd = 0;
        }
    }
    ddeg_local += dadd;
    if ((roundflag & 8) != 0) {
        isgn.* = @as(i32, @intFromFloat(ddeg_local / 30.0));
        if (isgn.* == 12) isgn.* = 0;
        ddeg_local = swephlib.swe_shim_fmod(ddeg_local, 30.0);
    }
    ideg.* = @as(i32, @intFromFloat(ddeg_local));
    ddeg_local -= @as(f64, @floatFromInt(ideg.*));
    imin.* = @as(i32, @intFromFloat(ddeg_local * 60.0));
    ddeg_local -= @as(f64, @floatFromInt(imin.*)) / 60.0;
    isec.* = @as(i32, @intFromFloat(ddeg_local * 3600.0));
    if ((roundflag & (4 | 2 | 1)) == 0) {
        dsecfr.* = ddeg_local * 3600.0 - @as(f64, @floatFromInt(isec.*));
    } else {
        dsecfr.* = 0;
    }
    if ((roundflag & 4) != 0) imin.* = 0;
    if ((roundflag & (4 | 2)) != 0) isec.* = 0;
    return 0;
}

// ---------------------------------------------------------------------------
// tidal acceleration / user delta-T
// ---------------------------------------------------------------------------
pub export fn swe_get_tid_acc(h: i32) callconv(.c) f64 {
    const s = sessionOf(h) orelse return std.math.nan(f64);
    if (s.dctx.is_tid_acc_manual) return s.dctx.tid_acc;
    return deltat.SE_TIDAL_DEFAULT;
}

pub export fn swe_set_tid_acc(h: i32, t: f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (t == 999999) {
        s.dctx.is_tid_acc_manual = false;
        s.swed.is_tid_acc_manual = false;
    } else {
        s.dctx.is_tid_acc_manual = true;
        s.dctx.tid_acc = t;
        s.swed.tid_acc = t;
        s.swed.is_tid_acc_manual = true;
    }
    return 0;
}

pub export fn swe_set_delta_t_userdef(h: i32, dt: f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (dt == -1e-10) s.dctx.delta_t_userdef_is_set = false else {
        s.dctx.delta_t_userdef_is_set = true;
        s.dctx.delta_t_userdef = dt;
    }
    return 0;
}

pub export fn swe_set_lapse_rate(h: i32, rate: f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    swecl.swe_set_lapse_rate(rate, &s.cctx);
    return 0;
}

// ---------------------------------------------------------------------------
// equation of time + mean/apparent local time
// ---------------------------------------------------------------------------
fn timeEqu(s: *Session, tjd_ut: f64, e_out: *f64, serr: [*]u8) i32 {
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var sidt = swephlib.swe_sidtime(tjd_ut, s.models, &s.dctx, null);
    var iflag: i32 = sweph.SEFLG_EQUATORIAL;
    iflag = sweph.plausPublic(iflag, -1, tjd_ut, &s.swed, s.models);
    if (!s.swed.ephe_path_is_set and !s.swed.jpl_file_is_open and (iflag & sweph.SEFLG_MOSEPH) == 0) {
        const msg = "Please call swe_set_ephe_path() or swe_set_jplfile() before calling swe_time_equ(), swe_lmt_to_lat() or swe_lat_to_lmt()";
        const n = @min(msg.len, AS_MAXCH - 1);
        @memcpy(serr[0..n], msg[0..n]);
        serr[n] = 0;
    }
    if (s.swed.jpl_file_is_open) iflag |= sweph.SEFLG_JPLEPH;
    const t = tjd_ut + 0.5;
    var dt = t - @floor(t);
    sidt -= dt * 24.0;
    sidt *= 15.0;
    var x: [6]f64 = undefined;
    const ret = sweph.swe_calc_ut(tjd_ut, 0, iflag, &x, &s.swed, s.models, &s.dctx, &serr_buf);
    if (ret == -1) {
        e_out.* = 0;
        const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
        @memcpy(serr[0..l], serr_buf[0..l]);
        serr[l] = 0;
        return -1;
    }
    dt = swephlib.swe_degnorm(sidt - x[0] - 180.0);
    if (dt > 180.0) dt -= 360.0;
    dt *= 4.0;
    e_out.* = dt / 1440.0;
    const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
    @memcpy(serr[0..l], serr_buf[0..l]);
    serr[l] = 0;
    return 0;
}

pub export fn swe_time_equ(h: i32, tjd_ut: f64, e_out: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return timeEqu(s, tjd_ut, e_out, serr);
}

pub export fn swe_lmt_to_lat(h: i32, tjd_lmt: f64, geolon: f64, tjd_lat: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var e: f64 = 0;
    const tjd_lmt0 = tjd_lmt - geolon / 360.0;
    const ret = timeEqu(s, tjd_lmt0, &e, serr);
    tjd_lat.* = tjd_lmt + e;
    return ret;
}

pub export fn swe_lat_to_lmt(h: i32, tjd_lat: f64, geolon: f64, tjd_lmt: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var e: f64 = 0;
    const tjd_lmt0 = tjd_lat - geolon / 360.0;
    var ret = timeEqu(s, tjd_lmt0, &e, serr);
    ret = timeEqu(s, tjd_lmt0 - e, &e, serr);
    ret = timeEqu(s, tjd_lmt0 - e, &e, serr);
    tjd_lmt.* = tjd_lat - e;
    return ret;
}

// ---------------------------------------------------------------------------
// UTC <-> Julian day (leap-second aware)
// ---------------------------------------------------------------------------
const J1972: f64 = 2441317.5;
const NLEAP_INIT: i32 = 10;
const LEAP_SECONDS: [100]i32 = blk: {
    var arr: [100]i32 = [_]i32{0} ** 100;
    const vals = [_]i32{ 19720630, 19721231, 19731231, 19741231, 19751231, 19761231, 19771231, 19781231, 19791231, 19810630, 19820630, 19830630, 19850630, 19871231, 19891231, 19901231, 19920630, 19930630, 19940630, 19951231, 19970630, 19981231, 20051231, 20081231, 20120630, 20150630, 20161231 };
    for (vals, 0..) |v, i| arr[i] = v;
    break :blk arr;
};

inline fn sDelta(s: *Session, tjd: f64) f64 {
    return abiDelta(s, tjd, -1);
}

fn writeSerrFmt(serr: [*]u8, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(serr[0 .. AS_MAXCH - 1], fmt, args) catch return;
    serr[msg.len] = 0;
}

pub export fn swe_utc_to_jd(h: i32, iyear: i32, imonth: i32, iday: i32, ihour: i32, imin: i32, dsec: f64, gregflag: i32, dret0: *f64, dret1: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var dret: [2]f64 = undefined;
    const rc = utcToJdInner(s, iyear, imonth, iday, ihour, imin, dsec, gregflag, &dret, serr);
    dret0.* = dret[0];
    dret1.* = dret[1];
    return rc;
}

fn jdetToUtc(s: *Session, tjd_et: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) void {
    var second_60: i32 = 0;
    var iyear2: i32 = 0;
    var imonth2: i32 = 0;
    var iday2: i32 = 0;
    var nleap: i32 = 0;
    var ndat: i32 = 0;
    var tabsiz_nleap: i32 = 0;
    var d: f64 = 0;
    var tjd: f64 = 0;
    const tjd_et_1972: f64 = J1972 + (32.184 + @as(f64, @floatFromInt(NLEAP_INIT))) / 86400.0;
    d = sDelta(s, tjd_et);
    var tjd_ut: f64 = tjd_et - sDelta(s, tjd_et - d);
    tjd_ut = tjd_et - sDelta(s, tjd_ut);
    if (tjd_et < tjd_et_1972) {
        const r = swedate.swe_revjul(tjd_ut, gregflag);
        iyear.* = r.year;
        imonth.* = r.mon;
        iday.* = r.day;
        ihour.* = @intFromFloat(r.ut);
        d = r.ut - @as(f64, @floatFromInt(ihour.*));
        d *= 60;
        imin.* = @intFromFloat(d);
        dsec.* = (d - @as(f64, @floatFromInt(imin.*))) * 60.0;
        return;
    }
    tabsiz_nleap = 0;
    for (LEAP_SECONDS) |v| {
        if (v == 0) break;
        tabsiz_nleap += 1;
    }
    {
        const r = swedate.swe_revjul(tjd_ut - 1, swedate.SE_GREG_CAL);
        iyear2 = r.year;
        imonth2 = r.mon;
        iday2 = r.day;
    }
    ndat = iyear2 * 10000 + imonth2 * 100 + iday2;
    nleap = 0;
    var ii: i32 = 0;
    while (ii < tabsiz_nleap) : (ii += 1) {
        if (ndat <= LEAP_SECONDS[@intCast(ii)]) break;
        nleap += 1;
    }
    if (nleap < tabsiz_nleap) {
        const leap = LEAP_SECONDS[@intCast(nleap)];
        iyear2 = @divTrunc(leap, 10000);
        imonth2 = @divTrunc(@rem(leap, 10000), 100);
        iday2 = @rem(leap, 100);
        tjd = swedate.swe_julday(iyear2, imonth2, iday2, 0, swedate.SE_GREG_CAL);
        {
            const r = swedate.swe_revjul(tjd + 1, swedate.SE_GREG_CAL);
            iyear2 = r.year;
            imonth2 = r.mon;
            iday2 = r.day;
        }
        var dret2: [2]f64 = undefined;
        _ = utcToJd(s, iyear2, imonth2, iday2, 0, 0, 0, swedate.SE_GREG_CAL, &dret2);
        d = tjd_et - dret2[0];
        if (d >= 0) {
            nleap += 1;
        } else if (d < 0 and d > -1.0 / 86400.0) {
            second_60 = 1;
        }
    }
    tjd = J1972 + (tjd_et - tjd_et_1972) - @as(f64, @floatFromInt(nleap + second_60)) / 86400.0;
    {
        const r = swedate.swe_revjul(tjd, swedate.SE_GREG_CAL);
        iyear.* = r.year;
        imonth.* = r.mon;
        iday.* = r.day;
        d = r.ut;
    }
    ihour.* = @intFromFloat(d);
    d -= @as(f64, @floatFromInt(ihour.*));
    d *= 60;
    imin.* = @intFromFloat(d);
    dsec.* = (d - @as(f64, @floatFromInt(imin.*))) * 60.0 + @as(f64, @floatFromInt(second_60));
    d = sDelta(s, tjd_et);
    d = sDelta(s, tjd_et - d);
    if (d * 86400.0 - @as(f64, @floatFromInt(nleap + NLEAP_INIT)) - 32.184 >= 1.0) {
        const r = swedate.swe_revjul(tjd_et - d, swedate.SE_GREG_CAL);
        iyear.* = r.year;
        imonth.* = r.mon;
        iday.* = r.day;
        d = r.ut;
        ihour.* = @intFromFloat(d);
        d -= @as(f64, @floatFromInt(ihour.*));
        d *= 60;
        imin.* = @intFromFloat(d);
        dsec.* = (d - @as(f64, @floatFromInt(imin.*))) * 60.0;
    }
    if (gregflag == swedate.SE_JUL_CAL) {
        tjd = swedate.swe_julday(iyear.*, imonth.*, iday.*, 0, swedate.SE_GREG_CAL);
        const r = swedate.swe_revjul(tjd, gregflag);
        iyear.* = r.year;
        imonth.* = r.mon;
        iday.* = r.day;
    }
}

fn utcToJd(s: *Session, iyear: i32, imonth: i32, iday: i32, ihour: i32, imin: i32, dsec: f64, gregflag: i32, dret: *[2]f64) i32 {
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    return utcToJdInner(s, iyear, imonth, iday, ihour, imin, dsec, gregflag, dret, &serr_buf);
}

fn utcToJdInner(s: *Session, iyear: i32, imonth: i32, iday: i32, ihour: i32, imin: i32, dsec: f64, gregflag: i32, dret: *[2]f64, serr: [*]u8) i32 {
    var iyear_loc = iyear;
    var imonth_loc = imonth;
    var iday_loc = iday;
    var gregflag_loc = gregflag;
    const tjd_ut1: f64 = swedate.swe_julday(iyear, imonth, iday, 0, gregflag_loc);
    {
        const r = swedate.swe_revjul(tjd_ut1, gregflag_loc);
        if (iyear != r.year or imonth != r.mon or iday != r.day) {
            writeSerrFmt(serr, "invalid date: year = {d}, month = {d}, day = {d}", .{ iyear, imonth, iday });
            return -1;
        }
    }
    if (ihour < 0 or ihour > 23 or imin < 0 or imin > 59 or dsec < 0 or dsec >= 61 or (dsec >= 60 and (imin < 59 or ihour < 23 or tjd_ut1 < J1972))) {
        writeSerrFmt(serr, "invalid time: {d}:{d}:{d:.2}", .{ ihour, imin, dsec });
        return -1;
    }
    const dhour: f64 = @as(f64, @floatFromInt(ihour)) + @as(f64, @floatFromInt(imin)) / 60.0 + dsec / 3600.0;
    if (tjd_ut1 < J1972) {
        const t_ut: f64 = swedate.swe_julday(iyear, imonth, iday, dhour, gregflag_loc);
        dret[1] = t_ut;
        dret[0] = t_ut + sDelta(s, t_ut);
        return 0;
    }
    if (gregflag_loc == swedate.SE_JUL_CAL) {
        gregflag_loc = swedate.SE_GREG_CAL;
        const r = swedate.swe_revjul(tjd_ut1, gregflag_loc);
        iyear_loc = r.year;
        imonth_loc = r.mon;
        iday_loc = r.day;
    }
    var tabsiz_nleap: i32 = 0;
    for (LEAP_SECONDS) |v| {
        if (v == 0) break;
        tabsiz_nleap += 1;
    }
    var nleap: i32 = NLEAP_INIT;
    const ndat: i32 = iyear_loc * 10000 + imonth_loc * 100 + iday_loc;
    var i: i32 = 0;
    while (i < tabsiz_nleap) : (i += 1) {
        if (ndat <= LEAP_SECONDS[@intCast(i)]) break;
        nleap += 1;
    }
    var d: f64 = sDelta(s, tjd_ut1) * 86400.0;
    if (d - @as(f64, @floatFromInt(nleap)) - 32.184 >= 1.0) {
        const t_ut: f64 = tjd_ut1 + dhour / 24.0;
        dret[1] = t_ut;
        dret[0] = t_ut + sDelta(s, t_ut);
        return 0;
    }
    if (dsec >= 60) {
        var j: i32 = 0;
        i = 0;
        while (i < tabsiz_nleap) : (i += 1) {
            if (ndat == LEAP_SECONDS[@intCast(i)]) {
                j = 1;
                break;
            }
        }
        if (j != 1) {
            writeSerrFmt(serr, "invalid time (no leap second!): {d}:{d}:{d:.2}", .{ ihour, imin, dsec });
            return -1;
        }
    }
    d = tjd_ut1 - J1972;
    d += @as(f64, @floatFromInt(ihour)) / 24.0 + @as(f64, @floatFromInt(imin)) / 1440.0 + dsec / 86400.0;
    const tjd_et_1972: f64 = J1972 + (32.184 + @as(f64, @floatFromInt(NLEAP_INIT))) / 86400.0;
    const tjd_et: f64 = tjd_et_1972 + d + @as(f64, @floatFromInt(nleap - NLEAP_INIT)) / 86400.0;
    d = sDelta(s, tjd_et);
    var tjd_ut1_calc: f64 = tjd_et - sDelta(s, tjd_et - d);
    tjd_ut1_calc = tjd_et - sDelta(s, tjd_ut1_calc);
    dret[0] = tjd_et;
    dret[1] = tjd_ut1_calc;
    return 0;
}

pub export fn swe_jdet_to_utc(h: i32, tjd_et: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    jdetToUtc(s, tjd_et, gregflag, iyear, imonth, iday, ihour, imin, dsec);
    return 0;
}

pub export fn swe_jdut1_to_utc(h: i32, tjd_ut: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    const tjd_et: f64 = tjd_ut + sDelta(s, tjd_ut);
    jdetToUtc(s, tjd_et, gregflag, iyear, imonth, iday, ihour, imin, dsec);
    return 0;
}

pub export fn swe_close(h: i32) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    sweph.swe_close(&s.swed);
    return 0;
}

// ---------------------------------------------------------------------------
// houses from Julian day (full replica with session state)
// ---------------------------------------------------------------------------
pub export fn swe_houses_ex2(h: i32, tjd_ut: f64, iflag: i32, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var cs: [37]f64 = [_]f64{0} ** 37;
    var asc: [10]f64 = [_]f64{0} ** 10;
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0 and !s.swed.ayana_is_set) {
        sweph.swe_set_sid_mode(0, 0, 0, &s.swed, &s.models);
    }
    const tjde = tjd_ut + deltat.swe_deltat_ex(&s.dctx, tjd_ut, iflag);
    const eps_mean = swephlib.swi_epsiln(tjde, 0, s.models) * swephlib.RADTODEG;
    var nutlo: [2]f64 = undefined;
    _ = swephlib.swi_nutation(tjde, 0, &nutlo, s.models, null, sweph.eopViewOf(&s.swed));
    nutlo[0] *= swephlib.RADTODEG;
    nutlo[1] *= swephlib.RADTODEG;
    if ((iflag & sweph.SEFLG_NONUT) != 0) {
        nutlo[0] = 0;
        nutlo[1] = 0;
    }
    const armc = swephlib.swe_degnorm(swephlib.swe_sidtime0(tjd_ut, eps_mean + nutlo[1], nutlo[0], s.models, &s.dctx, null) * 15.0 + geolon);
    var xp: [6]f64 = undefined;
    var retc_makr: i32 = 0;
    const hsys_u: u8 = std.ascii.toUpper(@as(u8, @truncate(@as(u32, @bitCast(hsys)))));
    if (hsys_u == 'I') {
        const flags: i32 = sweph.SEFLG_SPEED | sweph.SEFLG_EQUATORIAL;
        retc_makr = sweph.swe_calc_ut(tjd_ut, 0, flags, &xp, &s.swed, s.models, &s.dctx, null);
        if (retc_makr >= 0) {
            asc[9] = xp[1];
        }
    }
    var retc: i32 = 0;
    var ito: usize = 12;
    if (hsys_u == 'G') ito = 36;
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
        var ay: f64 = 0;
        _ = sweph.swe_get_ayanamsa_ex(tjde, iflag, &ay, &s.swed, s.models, &s.dctx, null);
        var hsys2: i32 = hsys;
        if (hsys_u == 'W') hsys2 = 'E';
        retc = swehouse.swe_houses_armc_ex2(armc, geolat, eps_mean + nutlo[1], hsys2, &cs, &asc, null, null, &serr_buf, &s.house);
        for (1..ito + 1) |i| {
            cs[i] = swephlib.swe_degnorm(cs[i] - ay);
            if (hsys_u == 'W') {
                const f = swephlib.swe_shim_fmod(cs[i], 30.0);
                cs[i] = cs[i] - f;
                cs[i] = swephlib.swe_degnorm(cs[i]);
            }
        }
        if (hsys_u == 'N') {
            for (1..ito + 1) |i| cs[i] = @as(f64, @floatFromInt(i - 1)) * 30.0;
        }
        for (0..8) |i| {
            if (i == 2) continue;
            asc[i] = swephlib.swe_degnorm(asc[i] - ay);
        }
    } else {
        var eff_hsys: i32 = hsys;
        if (hsys_u == 'I' and retc_makr < 0) eff_hsys = 'O';
        retc = swehouse.swe_houses_armc_ex2(armc, geolat, eps_mean + nutlo[1], eff_hsys, &cs, &asc, null, null, &serr_buf, &s.house);
        if (hsys_u == 'I' and retc_makr >= 0) asc[9] = xp[1];
    }
    if ((iflag & sweph.SEFLG_RADIANS) != 0) {
        for (1..ito + 1) |i| cs[i] *= swephlib.DEGTORAD;
        for (0..8) |i| asc[i] *= swephlib.DEGTORAD;
    }
    for (0..13) |i| cusps[i] = cs[i];
    cusps[0] = cs[0];
    for (0..10) |i| ascmc[i] = asc[i];
    const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
    @memcpy(serr[0..l], serr_buf[0..l]);
    serr[l] = 0;
    if (hsys_u == 'I' and retc_makr < 0) return retc_makr;
    return retc;
}

pub export fn swe_houses(h: i32, tjd_ut: f64, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, serr: [*]u8) callconv(.c) i32 {
    return swe_houses_ex2(h, tjd_ut, 0, geolat, geolon, hsys, cusps, ascmc, serr);
}

pub export fn swe_houses_ex(h: i32, tjd_ut: f64, iflag: i32, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, serr: [*]u8) callconv(.c) i32 {
    return swe_houses_ex2(h, tjd_ut, iflag, geolat, geolon, hsys, cusps, ascmc, serr);
}

pub export fn swe_houses_armc(h: i32, armc: f64, geolat: f64, eps: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var cs: [37]f64 = [_]f64{0} ** 37;
    var asc: [10]f64 = [_]f64{0} ** 10;
    const ret = swehouse.swe_houses_armc(armc, geolat, eps, hsys, &cs, &asc, &s.house);
    for (0..13) |i| cusps[i] = cs[i];
    for (0..10) |i| ascmc[i] = asc[i];
    return ret;
}

// ---------------------------------------------------------------------------
// vector batch sweep (the 365×10 hot path runs inside WASM)
// ---------------------------------------------------------------------------
/// C layout (frozen — comptime asserts below break the build on drift):
/// f64 start_jd @0, f64 step_days @8, u32 steps @16, u32 body_mask @20,
/// i32 flags @24, u8 use_topo @28, f64 topo[3] @32, u8 use_sidereal @56,
/// sidmode{i32 mode @64, f64 t0 @72, f64 ayan @80}, size 88.
pub const SweepRequest = extern struct {
    start_jd: f64,
    step_days: f64,
    steps: u32,
    body_mask: u32,
    flags: i32,
    use_topo: bool,
    topo: [3]f64,
    use_sidereal: bool,
    sidereal: extern struct {
        mode: i32,
        t0: f64,
        ayan_t0: f64,
    },

    comptime {
        if (@offsetOf(SweepRequest, "start_jd") != 0) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "step_days") != 8) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "steps") != 16) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "body_mask") != 20) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "flags") != 24) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "use_topo") != 28) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "topo") != 32) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "use_sidereal") != 56) @compileError("sweep layout drift");
        if (@offsetOf(SweepRequest, "sidereal") != 64) @compileError("sweep layout drift");
        if (@sizeOf(SweepRequest) != 88) @compileError("sweep layout drift");
    }
};

/// Batch sweep over [steps] JD × masked bodies into out_buf as strided
/// [step][body][6]f64. Session contexts persist across yielded chunks
/// (handles + Chebyshev caches); topo/sidereal apply to the session for
/// this call (documented mutation — one task per session).
/// Returns f64 count on success, -1 bad handle/args or short buffer,
/// -2 engine error (first message in serr[256]).
pub export fn swe_calc_sweep(h: i32, req: *const SweepRequest, out_buf: [*]f64, max_f64: usize, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (req.steps == 0 or req.body_mask == 0) return -1;
    var bodies: [32]i32 = undefined;
    var nbodies: usize = 0;
    for (0..32) |i| {
        if ((req.body_mask & (@as(u32, 1) << @intCast(i))) != 0) {
            bodies[nbodies] = @intCast(i);
            nbodies += 1;
        }
    }
    const need: usize = @as(usize, req.steps) * nbodies * 6;
    if (need > max_f64) return -1;
    if (req.use_topo) {
        sweph.swe_set_topo(req.topo[0], req.topo[1], req.topo[2], &s.swed);
    }
    if (req.use_sidereal) {
        sweph.swe_set_sid_mode(req.sidereal.mode, req.sidereal.t0, req.sidereal.ayan_t0, &s.swed, &s.models);
    }
    var serr_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var out: usize = 0;
    var jd = req.start_jd;
    var step: u32 = 0;
    while (step < req.steps) : (step += 1) {
        for (bodies[0..nbodies]) |ipl| {
            var xx: [6]f64 = undefined;
            const rc = sweph.swe_calc_ut(jd, ipl, req.flags, &xx, &s.swed, s.models, &s.dctx, &serr_buf);
            if (rc < 0) {
                @memcpy(serr[0..AS_MAXCH], &serr_buf);
                return -2;
            }
            @memcpy(out_buf[out .. out + 6], &xx);
            out += 6;
        }
        jd += req.step_days;
    }
    return @intCast(out);
}

// ---------------------------------------------------------------------------
// gauquelin, orbital elements, horizontal coordinates
// ---------------------------------------------------------------------------
pub export fn swe_gauquelin_sector(h: i32, t_ut: f64, ipl: i32, star_ptr: usize, star_len: usize, iflag: i32, imeth: i32, glon: f64, glat: f64, galt: f64, atpress: f64, attemp: f64, dgsect: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var sb: [256]u8 = undefined;
    var star: ?[]u8 = null;
    if (star_ptr != 0 and star_len > 0) {
        const n = @min(star_len, 255);
        const src: [*]const u8 = @ptrFromInt(star_ptr);
        @memcpy(sb[0..n], src[0..n]);
        sb[n] = 0;
        star = sb[0..n];
    }
    var geo: [3]f64 = .{ glon, glat, galt };
    return swecl.swe_gauquelin_sector(t_ut, ipl, star, iflag, imeth, &geo, atpress, attemp, dgsect, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
}

pub export fn swe_get_orbital_elements(h: i32, tjd_et: f64, ipl: i32, iflag: i32, dret: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var buf: [50]f64 = undefined;
    const ret = swecl.swe_get_orbital_elements(tjd_et, ipl, iflag, &buf, serrToZig(serr), &s.swed, s.models, &s.dctx);
    for (0..50) |i| dret[i] = buf[i];
    return ret;
}

pub export fn swe_orbit_max_min_true_distance(h: i32, tjd: f64, ipl: i32, iflag: i32, dmax: *f64, dmin: *f64, dtrue: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    return swecl.swe_orbit_max_min_true_distance(tjd, ipl, iflag, dmax, dmin, dtrue, serrToZig(serr), &s.swed, s.models, &s.dctx);
}

pub export fn swe_azalt(h: i32, tjd_ut: f64, calc_flag: i32, glon: f64, glat: f64, galt: f64, atpress: f64, attemp: f64, xin: [*]f64, xaz: [*]f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var geo: [3]f64 = .{ glon, glat, galt };
    swecl.swe_azalt(tjd_ut, calc_flag, &geo, atpress, attemp, xin[0..3], xaz[0..3], &s.swed, s.models, &s.dctx, &s.cctx);
    return 0;
}

pub export fn swe_azalt_rev(h: i32, tjd_ut: f64, calc_flag: i32, glon: f64, glat: f64, galt: f64, xin: [*]f64, xout: [*]f64) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var geo: [3]f64 = .{ glon, glat, galt };
    swecl.swe_azalt_rev(tjd_ut, calc_flag, &geo, xin[0..3], xout[0..2], &s.swed, s.models, &s.dctx);
    return 0;
}

pub export fn swe_refrac(inalt: f64, atpress: f64, attemp: f64, calc_flag: i32) callconv(.c) f64 {
    return swecl.swe_refrac(inalt, atpress, attemp, calc_flag);
}

pub export fn swe_refrac_extended(inalt: f64, geoalt: f64, atpress: f64, attemp: f64, lapse_rate: f64, calc_flag: i32, dret: [*]f64) callconv(.c) f64 {
    var out: [4]f64 = undefined;
    const ret = swecl.swe_refrac_extended(inalt, geoalt, atpress, attemp, lapse_rate, calc_flag, &out);
    for (0..4) |i| dret[i] = out[i];
    return ret;
}

// ---------------------------------------------------------------------------
// eclipse where/how, occultations
// ---------------------------------------------------------------------------
pub export fn swe_sol_eclipse_where(h: i32, tjd: f64, ifl: i32, geopos: [*]f64, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var g: [2]f64 = undefined;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_where(tjd, ifl, &g, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    geopos[0] = g[0];
    geopos[1] = g[1];
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_sol_eclipse_how(h: i32, tjd: f64, ifl: i32, glon: f64, glat: f64, galt: f64, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var geo: [3]f64 = .{ glon, glat, galt };
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_how(tjd, ifl, &geo, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_lun_occult_where(h: i32, tjd: f64, ipl: i32, star_ptr: usize, star_len: usize, ifl: i32, geopos: [*]f64, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var sb: [256]u8 = undefined;
    var star: ?[]u8 = null;
    if (star_ptr != 0 and star_len > 0) {
        const n = @min(star_len, 255);
        const src: [*]const u8 = @ptrFromInt(star_ptr);
        @memcpy(sb[0..n], src[0..n]);
        sb[n] = 0;
        star = sb[0..n];
    }
    var g: [2]f64 = undefined;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_lun_occult_where(tjd, ipl, star, ifl, &g, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    geopos[0] = g[0];
    geopos[1] = g[1];
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_lun_occult_when_glob(h: i32, tjd: f64, ipl: i32, star_ptr: usize, star_len: usize, ifl: i32, ifltype: i32, tret: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (star_ptr == 0 or star_len == 0) return -1;
    var sb: [256]u8 = undefined;
    const n = @min(star_len, 256);
    const src: [*]const u8 = @ptrFromInt(star_ptr);
    @memcpy(sb[0..n], src[0..n]);
    var tb: [10]f64 = undefined;
    const ret = swecl.swe_lun_occult_when_glob(tjd, ipl, sb[0..n], ifl, ifltype, &tb, backward, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    return ret;
}

pub export fn swe_lun_occult_when_loc(h: i32, tjd: f64, ipl: i32, star_ptr: usize, star_len: usize, ifl: i32, glon: f64, glat: f64, galt: f64, tret: [*]f64, attr: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    if (star_ptr == 0 or star_len == 0) return -1;
    var sb: [256]u8 = undefined;
    const n = @min(star_len, 256);
    const src: [*]const u8 = @ptrFromInt(star_ptr);
    @memcpy(sb[0..n], src[0..n]);
    var geo: [3]f64 = .{ glon, glat, galt };
    var tb: [10]f64 = undefined;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_lun_occult_when_loc(tjd, ipl, sb[0..n], ifl, &geo, &tb, &ab, backward, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_lun_eclipse_how(h: i32, tjd_ut: f64, ifl: i32, has_geo: i32, glon: f64, glat: f64, galt: f64, attr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var geo: [3]f64 = .{ glon, glat, galt };
    const gp: ?*[3]f64 = if (has_geo != 0) &geo else null;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_lun_eclipse_how(tjd_ut, ifl, gp, &ab, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

pub export fn swe_lun_eclipse_when_loc(h: i32, tjd: f64, ifl: i32, glon: f64, glat: f64, galt: f64, tret: [*]f64, attr: [*]f64, backward: i32, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    // swe_abi passes altitude 0 here (geocentric-latitude convention).
    _ = galt;
    var geo: [3]f64 = .{ glon, glat, 0 };
    var tb: [10]f64 = undefined;
    var ab: [20]f64 = undefined;
    const ret = swecl.swe_lun_eclipse_when_loc(tjd, ifl, &geo, &tb, &ab, backward, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx);
    for (0..10) |i| tret[i] = tb[i];
    for (0..20) |i| attr[i] = ab[i];
    return ret;
}

// ---------------------------------------------------------------------------
// heliacal events (object names by ptr+len; fixed buffer layouts)
// ---------------------------------------------------------------------------
fn helObj(obj_ptr: usize, obj_len: usize, buf: *[256]u8) ?[]u8 {
    if (obj_ptr == 0 or obj_len == 0) return null;
    const n = @min(obj_len, 255);
    const src: [*]const u8 = @ptrFromInt(obj_ptr);
    @memcpy(buf[0..n], src[0..n]);
    buf[n] = 0;
    if (buf[0] == 0) return null; // empty name
    return buf[0..n];
}

const HelParams = struct {
    geo: [3]f64,
    datm: [4]f64,
    dobs: [6]f64,
};

fn helParams(glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64) HelParams {
    return .{
        .geo = .{ glon, glat, galt },
        .datm = .{ pr, te, hu, vr },
        .dobs = .{ age, snellen, bino, scope_mag, scope_trans, opt_flag },
    };
}

pub export fn swe_heliacal_ut(h: i32, tjd: f64, glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64, obj_ptr: usize, obj_len: usize, evt: i32, helflag: i32, dret: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ob: [256]u8 = undefined;
    const obj = helObj(obj_ptr, obj_len, &ob) orelse return -1;
    var p = helParams(glon, glat, galt, pr, te, hu, vr, age, snellen, bino, scope_mag, scope_trans, opt_flag);
    var db: [10]f64 = undefined;
    const ret = swehel.swe_heliacal_ut(tjd, &p.geo, &p.datm, &p.dobs, obj, evt, helflag, &db, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx, &s.hctx);
    for (0..10) |i| dret[i] = db[i];
    return ret;
}

pub export fn swe_heliacal_pheno_ut(h: i32, tjd_ut: f64, glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64, obj_ptr: usize, obj_len: usize, evt: i32, helflag: i32, darr: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ob: [256]u8 = undefined;
    const obj = helObj(obj_ptr, obj_len, &ob) orelse return -1;
    var p = helParams(glon, glat, galt, pr, te, hu, vr, age, snellen, bino, scope_mag, scope_trans, opt_flag);
    var db: [40]f64 = undefined;
    const ret = swehel.swe_heliacal_pheno_ut(tjd_ut, &p.geo, &p.datm, &p.dobs, obj, evt, helflag, &db, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx, &s.hctx);
    for (0..40) |i| darr[i] = db[i];
    return ret;
}

pub export fn swe_vis_limit_mag(h: i32, tjd: f64, glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64, obj_ptr: usize, obj_len: usize, helflag: i32, dret: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var ob: [256]u8 = undefined;
    const obj = helObj(obj_ptr, obj_len, &ob) orelse return -1;
    var p = helParams(glon, glat, galt, pr, te, hu, vr, age, snellen, bino, scope_mag, scope_trans, opt_flag);
    var db: [8]f64 = undefined;
    const ret = swehel.swe_vis_limit_mag(tjd, &p.geo, &p.datm, &p.dobs, obj, helflag, &db, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx, &s.hctx);
    for (0..8) |i| dret[i] = db[i];
    return ret;
}

pub export fn swe_heliacal_angle(h: i32, tjd: f64, glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64, helflag: i32, mag: f64, azi_obj: f64, azi_sun: f64, azi_moon: f64, alt_moon: f64, dret: [*]f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var p = helParams(glon, glat, galt, pr, te, hu, vr, age, snellen, bino, scope_mag, scope_trans, opt_flag);
    var db: [3]f64 = undefined;
    const ret = swehel.swe_heliacal_angle(tjd, &p.geo, &p.datm, &p.dobs, helflag, mag, azi_obj, azi_sun, azi_moon, alt_moon, &db, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx, &s.hctx);
    for (0..3) |i| dret[i] = db[i];
    return ret;
}

pub export fn swe_topo_arcus_visionis(h: i32, tjd: f64, glon: f64, glat: f64, galt: f64, pr: f64, te: f64, hu: f64, vr: f64, age: f64, snellen: f64, bino: f64, scope_mag: f64, scope_trans: f64, opt_flag: f64, helflag: i32, mag: f64, a1: f64, a2: f64, a3: f64, a4: f64, am: f64, ret_out: *f64, serr: [*]u8) callconv(.c) i32 {
    const s = sessionOf(h) orelse return -1;
    var p = helParams(glon, glat, galt, pr, te, hu, vr, age, snellen, bino, scope_mag, scope_trans, opt_flag);
    return swehel.swe_topo_arcus_visionis(tjd, &p.geo, &p.datm, &p.dobs, helflag, mag, a1, a2, a3, a4, am, ret_out, serrToZig(serr), &s.swed, s.models, &s.dctx, &s.cctx, &s.hctx);
}

/// Stub: ayanamsha table lives outside the ported subset.
pub export fn swe_get_ayanamsa_name(out_ptr: usize, out_len: usize) callconv(.c) usize {
    const v = "Fagan/Bradley";
    if (out_ptr == 0 or out_len == 0) return 0;
    const n = @min(v.len, out_len - 1);
    const dst: [*]u8 = @ptrFromInt(out_ptr);
    @memcpy(dst[0..n], v[0..n]);
    dst[n] = 0;
    return n;
}
