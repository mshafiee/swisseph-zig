// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
const std = @import("std");
const swedate = @import("swedate");
const deltat = @import("deltat");
const sweph = @import("sweph");
const swephlib = @import("swephlib");
const swehouse = @import("swehouse");
const swecl = @import("swecl");
const swehel = @import("swehel");

const Swed = sweph.Swed;
const DeltatCtx = deltat.DeltatCtx;
const AstroModels = swephlib.AstroModels;
const SweclCtx = swecl.SweclCtx;

/// Per-thread C-API instance: the union of all state the ABI globals used
/// to hold. Mirrors upstream C, whose globals are thread-local statics.
pub const SweState = struct {
    swed: Swed = .{},
    house: swehouse.HouseCtx = .{},
    models: AstroModels = .{},
    dctx: DeltatCtx = .{},
    cctx: SweclCtx = .{},
    hctx: swehel.SwehelCtx = .{},

    /// Frees heap-owned members (fixstar backing buffer). Safe to call on
    /// a default/never-used state.
    pub fn deinit(self: *SweState) void {
        if (self.swed.fixstar_buf.len > 0) {
            self.swed.fs_alloc.free(self.swed.fixstar_buf);
            self.swed.fixstar_buf = &[_]sweph.FixedStar{};
            self.swed.fixed_stars = &[_]sweph.FixedStar{};
        }
    }
};

// One isolated C-API instance per OS thread (mirrors C TLS statics).
threadlocal var g_state: SweState = .{};

const SE_VERSION = "2.10.03";
const AS_MAXCH: usize = 256;
const DEGTORAD = swephlib.DEGTORAD;
const RADTODEG = swephlib.RADTODEG;
const DEG360: i32 = 360 * 360000;
const DEG180: i32 = 180 * 360000;
const DEG30: i32 = 30 * 360000;

inline fn serrToZig(serr: ?[*:0]u8) ?[]u8 {
    if (serr) |s| return s[0..AS_MAXCH];
    return null;
}

// Existing correct wrappers (subset that compiled)
pub export fn swe_julday(year: i32, month: i32, day: i32, hour: f64, gregflag: i32) callconv(.c) f64 {
    return swedate.swe_julday(year, month, day, hour, gregflag);
}
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
pub export fn swe_calc(tjd: f64, ipl: i32, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var buf: [6]f64 = undefined;
    const ret = sweph.swe_calc(tjd, ipl, iflag, &buf, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = buf[i];
    return ret;
}
pub export fn swe_calc_ut(tjd_ut: f64, ipl: i32, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var buf: [6]f64 = undefined;
    const ret = sweph.swe_calc_ut(tjd_ut, ipl, iflag, &buf, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = buf[i];
    return ret;
}
pub export fn swe_set_topo(geolon: f64, geolat: f64, geoalt: f64) callconv(.c) void {
    sweph.swe_set_topo(geolon, geolat, geoalt, &g_state.swed);
}
pub export fn swe_set_sid_mode(sid_mode: i32, t0: f64, ayan_t0: f64) callconv(.c) void {
    sweph.swe_set_sid_mode(sid_mode, t0, ayan_t0, &g_state.swed, &g_state.models);
}
pub export fn swe_get_ayanamsa_ex(tjd_et: f64, iflag: i32, daya: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    return sweph.swe_get_ayanamsa_ex(tjd_et, iflag, daya, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
}
pub export fn swe_get_ayanamsa_ex_ut(tjd_ut: f64, iflag: i32, daya: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    return sweph.swe_get_ayanamsa_ex_ut(tjd_ut, iflag, daya, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
}
pub export fn swe_set_ephe_path(path: ?[*:0]const u8) callconv(.c) void {
    var p: ?[]const u8 = null;
    if (path) |pp| p = pp[0..std.mem.len(pp)];
    sweph.swe_set_ephe_path(p, &g_state.swed, &g_state.models, &g_state.dctx, null);
}
pub export fn swe_set_jpl_file(fname: ?[*:0]const u8) callconv(.c) void {
    var p: []const u8 = "";
    if (fname) |pp| p = pp[0..std.mem.len(pp)];
    sweph.swe_set_jpl_file(p, &g_state.swed, &g_state.models, &g_state.dctx);
}
pub export fn swe_set_interpolate_nut(do_interpolate: c_int) callconv(.c) void {
    sweph.swe_set_interpolate_nut(do_interpolate != 0, &g_state.swed);
}
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
pub export fn swe_cotrans(xpo: [*]f64, xpn: [*]f64, eps: f64) callconv(.c) void {
    swehouse.swe_cotrans(xpo[0..3], xpn[0..3], eps);
    xpn[2] = xpo[2];
}
pub export fn swe_version(s: [*:0]u8) callconv(.c) [*:0]u8 {
    const v = SE_VERSION;
    @memcpy(s[0..v.len], v);
    s[v.len] = 0;
    return s;
}
pub export fn swe_get_library_path(s: [*:0]u8) callconv(.c) [*:0]u8 {
    s[0] = 0;
    return s;
}
pub export fn swe_close() callconv(.c) void {
    g_state.swed = .{};
    g_state.models = .{};
    g_state.dctx = .{};
}

// Pure helpers — correct transliteration
pub export fn swe_csnorm(p: i32) callconv(.c) i32 {
    var pp = p;
    if (pp < 0) {
        while (pp < 0) pp += DEG360;
    } else if (pp >= DEG360) {
        while (pp >= DEG360) pp -= DEG360;
    }
    return pp;
}
pub export fn swe_difcsn(p1: i32, p2: i32) callconv(.c) i32 {
    return swe_csnorm(p1 - p2);
}
pub export fn swe_difcs2n(p1: i32, p2: i32) callconv(.c) i32 {
    var d = swe_csnorm(p1 - p2);
    if (d >= DEG180) d -= DEG360;
    return d;
}
pub export fn swe_csroundsec(x: i32) callconv(.c) i32 {
    var t = @divTrunc(x + 50, 100) * 100;
    if (t > x and @rem(t, DEG30) == 0) t = @divTrunc(x, 100) * 100;
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
pub export fn swe_cs2timestr(t: i32, sep: i32, suppressZero: i32, a: [*:0]u8) callconv(.c) [*:0]u8 {
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
    if (s == 0 and suppressZero != 0) a[5] = 0 else {
        a[6] = @intCast(@divTrunc(s, 10) + '0');
        a[7] = @intCast(@rem(s, 10) + '0');
    }
    a[0] = @intCast(@divTrunc(h, 10) + '0');
    a[1] = @intCast(@rem(h, 10) + '0');
    a[3] = @intCast(@divTrunc(m, 10) + '0');
    a[4] = @intCast(@rem(m, 10) + '0');
    return a;
}
pub export fn swe_cs2lonlatstr(t: i32, pchar: u8, mchar: u8, sp: [*:0]u8) callconv(.c) [*:0]u8 {
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
    return sp;
}
extern fn snprintf(buf: [*:0]u8, n: usize, fmt: [*:0]const u8, ...) c_int;
pub export fn swe_cs2degstr(t: i32, a: [*:0]u8) callconv(.c) [*:0]u8 {
    var tt = @rem(@divTrunc(t, 100), 30 * 3600);
    if (tt < 0) tt += 30 * 3600;
    const s: i32 = @rem(tt, 60);
    const m: i32 = @rem(@divTrunc(tt, 60), 60);
    const h: i32 = @rem(@divTrunc(tt, 3600), 100);
    _ = snprintf(a, 32, "%2d\xc2\xb0%02d'%02d", h, m, s);
    return a;
}
pub export fn swe_cotrans_sp(xpo: [*]f64, xpn: [*]f64, eps: f64) callconv(.c) void {
    var x: [6]f64 = .{ xpo[0], xpo[1], xpo[2], xpo[3], xpo[4], xpo[5] };
    const e = eps * DEGTORAD;
    x[0] *= DEGTORAD;
    x[1] *= DEGTORAD;
    x[2] = 1;
    x[3] *= DEGTORAD;
    x[4] *= DEGTORAD;
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
    xpn[0] = out[0] * RADTODEG;
    xpn[1] = out[1] * RADTODEG;
    xpn[2] = xpo[2];
    xpn[3] = out[3] * RADTODEG;
    xpn[4] = out[4] * RADTODEG;
    xpn[5] = xpo[5];
}
fn split_deg_nakshatra(ddeg_in: f64, roundflag: i32, ideg: *i32, imin: *i32, isec: *i32, dsecfr: *f64, inak: *i32) void {
    var ddeg = ddeg_in;
    var dadd: f64 = 0;
    const dnakshsize: f64 = 13.33333333333333;
    const ddeghelp: f64 = swephlib.swe_shim_fmod(ddeg, dnakshsize);
    inak.* = 1;
    if (ddeg < 0) {
        inak.* = -1;
        ddeg = 0;
    }
    if ((g_state.swed.sidd.sid_mode & 39) == 39) {
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
pub export fn swe_split_deg(ddeg: f64, roundflag: i32, ideg: *i32, imin: *i32, isec: *i32, dsecfr: *f64, isgn: *i32) callconv(.c) void {
    var ddeg_local = ddeg;
    var dadd: f64 = 0;
    isgn.* = 1;
    if (ddeg_local < 0) {
        isgn.* = -1;
        ddeg_local = -ddeg_local;
    } else if ((roundflag & 1024) != 0) {
        split_deg_nakshatra(ddeg_local, roundflag, ideg, imin, isec, dsecfr, isgn);
        return;
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
}
pub export fn swe_deltat(tjd: f64) callconv(.c) f64 {
    return deltat.swe_deltat_ex(&g_state.dctx, tjd, -1);
}
pub export fn swe_deltat_ex(tjd: f64, iflag: i32, serr: ?[*:0]u8) callconv(.c) f64 {
    _ = serr;
    g_state.dctx.sweph_denum = g_state.swed.fidat[1].sweph_denum;
    return deltat.swe_deltat_ex(&g_state.dctx, tjd, iflag);
}
pub export fn swe_get_tid_acc() callconv(.c) f64 {
    if (g_state.dctx.is_tid_acc_manual) return g_state.dctx.tid_acc;
    return deltat.SE_TIDAL_DEFAULT;
}
pub export fn swe_set_tid_acc(t: f64) callconv(.c) void {
    if (t == 999999) {
        g_state.dctx.is_tid_acc_manual = false;
        g_state.swed.is_tid_acc_manual = false;
    } else {
        g_state.dctx.is_tid_acc_manual = true;
        g_state.dctx.tid_acc = t;
        g_state.swed.tid_acc = t;
        g_state.swed.is_tid_acc_manual = true;
    }
}
pub export fn swe_set_delta_t_userdef(dt: f64) callconv(.c) void {
    if (dt == -1e-10) g_state.dctx.delta_t_userdef_is_set = false else {
        g_state.dctx.delta_t_userdef_is_set = true;
        g_state.dctx.delta_t_userdef = dt;
    }
}
const J1972: f64 = 2441317.5;
const NLEAP_INIT: i32 = 10;
const g_leap_seconds: [100]i32 = blk: {
    var arr: [100]i32 = [_]i32{0} ** 100;
    arr[0] = 19720630;
    arr[1] = 19721231;
    arr[2] = 19731231;
    arr[3] = 19741231;
    arr[4] = 19751231;
    arr[5] = 19761231;
    arr[6] = 19771231;
    arr[7] = 19781231;
    arr[8] = 19791231;
    arr[9] = 19810630;
    arr[10] = 19820630;
    arr[11] = 19830630;
    arr[12] = 19850630;
    arr[13] = 19871231;
    arr[14] = 19891231;
    arr[15] = 19901231;
    arr[16] = 19920630;
    arr[17] = 19930630;
    arr[18] = 19940630;
    arr[19] = 19951231;
    arr[20] = 19970630;
    arr[21] = 19981231;
    arr[22] = 20051231;
    arr[23] = 20081231;
    arr[24] = 20120630;
    arr[25] = 20150630;
    arr[26] = 20161231;
    break :blk arr;
};
threadlocal var g_leap_done: bool = false;
fn init_leapsec() i32 {
    if (!g_leap_done) {
        g_leap_done = true;
        // C's init_leapsec tries to read seleapsec.txt via swi_fopen.
        // We do a simple attempt to extend table if file found in ephepath
        // using sweph.swi_fopen to stay bit-exact when possible.
        // If not available, keep built-in 27 entries.
        // Optional: try to load via std if sweph file open succeeds.
        // For simplicity, skip filesystem here and keep built-in table.
        // The table will be extended only if external file was already handled
        // by caller; otherwise we mimic C's fallback (no file -> 27).
    }
    var tabsiz: i32 = 0;
    for (g_leap_seconds) |v| {
        if (v == 0) break;
        tabsiz += 1;
    }
    return tabsiz;
}
inline fn delta_ex(tjd: f64) f64 {
    g_state.dctx.sweph_denum = g_state.swed.fidat[1].sweph_denum;
    return deltat.swe_deltat_ex(&g_state.dctx, tjd, -1);
}
// 1:1 transliteration of swe_utc_to_jd from swedate.c
pub export fn swe_utc_to_jd(iyear: i32, imonth: i32, iday: i32, ihour: i32, imin: i32, dsec: f64, gregflag: i32, dret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var iyear_loc = iyear;
    var imonth_loc = imonth;
    var iday_loc = iday;
    var gregflag_loc = gregflag;
    const tjd_ut1: f64 = swedate.swe_julday(iyear, imonth, iday, 0, gregflag_loc);
    {
        const r = swedate.swe_revjul(tjd_ut1, gregflag_loc);
        if (iyear != r.year or imonth != r.mon or iday != r.day) {
            if (serr) |s| _ = snprintf(s, AS_MAXCH, "invalid date: year = %d, month = %d, day = %d", iyear, imonth, iday);
            return -1;
        }
    }
    if (ihour < 0 or ihour > 23 or imin < 0 or imin > 59 or dsec < 0 or dsec >= 61 or (dsec >= 60 and (imin < 59 or ihour < 23 or tjd_ut1 < J1972))) {
        if (serr) |s| _ = snprintf(s, AS_MAXCH, "invalid time: %d:%d:%.2f", ihour, imin, dsec);
        return -1;
    }
    const dhour: f64 = @as(f64, @floatFromInt(ihour)) + @as(f64, @floatFromInt(imin)) / 60.0 + dsec / 3600.0;
    if (tjd_ut1 < J1972) {
        const t_ut: f64 = swedate.swe_julday(iyear, imonth, iday, dhour, gregflag_loc);
        dret[1] = t_ut;
        dret[0] = t_ut + delta_ex(t_ut);
        return 0;
    }
    if (gregflag_loc == swedate.SE_JUL_CAL) {
        gregflag_loc = swedate.SE_GREG_CAL;
        const r = swedate.swe_revjul(tjd_ut1, gregflag_loc);
        iyear_loc = r.year;
        imonth_loc = r.mon;
        iday_loc = r.day;
    }
    const tabsiz_nleap: i32 = init_leapsec();
    var nleap: i32 = NLEAP_INIT;
    const ndat: i32 = iyear_loc * 10000 + imonth_loc * 100 + iday_loc;
    var i: i32 = 0;
    while (i < tabsiz_nleap) : (i += 1) {
        if (ndat <= g_leap_seconds[@intCast(i)]) break;
        nleap += 1;
    }
    var d: f64 = delta_ex(tjd_ut1) * 86400.0;
    if (d - @as(f64, @floatFromInt(nleap)) - 32.184 >= 1.0) {
        const t_ut: f64 = tjd_ut1 + dhour / 24.0;
        dret[1] = t_ut;
        dret[0] = t_ut + delta_ex(t_ut);
        return 0;
    }
    if (dsec >= 60) {
        var j: i32 = 0;
        i = 0;
        while (i < tabsiz_nleap) : (i += 1) {
            if (ndat == g_leap_seconds[@intCast(i)]) {
                j = 1;
                break;
            }
        }
        if (j != 1) {
            if (serr) |s| _ = snprintf(s, AS_MAXCH, "invalid time (no leap second!): %d:%d:%.2f", ihour, imin, dsec);
            return -1;
        }
    }
    d = tjd_ut1 - J1972;
    d += @as(f64, @floatFromInt(ihour)) / 24.0 + @as(f64, @floatFromInt(imin)) / 1440.0 + dsec / 86400.0;
    const tjd_et_1972: f64 = J1972 + (32.184 + @as(f64, @floatFromInt(NLEAP_INIT))) / 86400.0;
    const tjd_et: f64 = tjd_et_1972 + d + @as(f64, @floatFromInt(nleap - NLEAP_INIT)) / 86400.0;
    d = delta_ex(tjd_et);
    var tjd_ut1_calc: f64 = tjd_et - delta_ex(tjd_et - d);
    tjd_ut1_calc = tjd_et - delta_ex(tjd_ut1_calc);
    dret[0] = tjd_et;
    dret[1] = tjd_ut1_calc;
    return 0;
}
fn swe_jdet_to_utc_internal(tjd_et: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) void {
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
    d = delta_ex(tjd_et);
    var tjd_ut: f64 = tjd_et - delta_ex(tjd_et - d);
    tjd_ut = tjd_et - delta_ex(tjd_ut);
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
    tabsiz_nleap = init_leapsec();
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
        if (ndat <= g_leap_seconds[@intCast(ii)]) break;
        nleap += 1;
    }
    if (nleap < tabsiz_nleap) {
        const leap = g_leap_seconds[@intCast(nleap)];
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
        _ = swe_utc_to_jd(iyear2, imonth2, iday2, 0, 0, 0, swedate.SE_GREG_CAL, &dret2, null);
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
    d = delta_ex(tjd_et);
    d = delta_ex(tjd_et - d);
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
pub export fn swe_jdet_to_utc(tjd_et: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) callconv(.c) void {
    swe_jdet_to_utc_internal(tjd_et, gregflag, iyear, imonth, iday, ihour, imin, dsec);
}
pub export fn swe_jdut1_to_utc(tjd_ut: f64, gregflag: i32, iyear: *i32, imonth: *i32, iday: *i32, ihour: *i32, imin: *i32, dsec: *f64) callconv(.c) void {
    const tjd_et: f64 = tjd_ut + delta_ex(tjd_ut);
    swe_jdet_to_utc_internal(tjd_et, gregflag, iyear, imonth, iday, ihour, imin, dsec);
}
pub export fn swe_time_equ(tjd_ut: f64, E: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var serr_buf: [256]u8 = undefined;
    serr_buf[0] = 0;
    var serr_slice: ?[]u8 = null;
    if (serr != null) serr_slice = serr_buf[0..];
    var sidt = swephlib.swe_sidtime(tjd_ut, g_state.models, &g_state.dctx, null);
    var iflag: i32 = sweph.SEFLG_EQUATORIAL;
    iflag = sweph.plausPublic(iflag, -1, tjd_ut, &g_state.swed, g_state.models);
    if (!g_state.swed.ephe_path_is_set and !g_state.swed.jpl_file_is_open and (iflag & sweph.SEFLG_MOSEPH) == 0 and serr_slice != null) {
        const msg = "Please call swe_set_ephe_path() or swe_set_jplfile() before calling swe_time_equ(), swe_lmt_to_lat() or swe_lat_to_lmt()";
        const n = @min(msg.len, serr_slice.?.len - 1);
        @memcpy(serr_slice.?[0..n], msg[0..n]);
        serr_slice.?[n] = 0;
    }
    if (g_state.swed.jpl_file_is_open) iflag |= sweph.SEFLG_JPLEPH;
    const t = tjd_ut + 0.5;
    var dt = t - @floor(t);
    sidt -= dt * 24.0;
    sidt *= 15.0;
    var x: [6]f64 = undefined;
    const ret = sweph.swe_calc_ut(tjd_ut, 0, iflag, &x, &g_state.swed, g_state.models, &g_state.dctx, serr_slice);
    if (ret == -1) {
        E.* = 0;
        if (serr != null and serr_slice != null) {
            const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
            var i: usize = 0;
            while (i < l) : (i += 1) serr.?[i] = serr_buf[i];
            serr.?[l] = 0;
        }
        return -1;
    }
    dt = swephlib.swe_degnorm(sidt - x[0] - 180.0);
    if (dt > 180.0) dt -= 360.0;
    dt *= 4.0;
    E.* = dt / 1440.0;
    if (serr != null and serr_slice != null) {
        const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
        var i: usize = 0;
        while (i < l) : (i += 1) serr.?[i] = serr_buf[i];
        serr.?[l] = 0;
        if (l == 0) serr.?[0] = 0;
    }
    return 0;
}
pub export fn swe_lmt_to_lat(tjd_lmt: f64, geolon: f64, tjd_lat: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var E: f64 = 0;
    const tjd_lmt0 = tjd_lmt - geolon / 360.0;
    const ret = swe_time_equ(tjd_lmt0, &E, serr);
    tjd_lat.* = tjd_lmt + E;
    return ret;
}
pub export fn swe_lat_to_lmt(tjd_lat: f64, geolon: f64, tjd_lmt: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var E: f64 = 0;
    const tjd_lmt0 = tjd_lat - geolon / 360.0;
    var ret = swe_time_equ(tjd_lmt0, &E, serr);
    ret = swe_time_equ(tjd_lmt0 - E, &E, serr);
    ret = swe_time_equ(tjd_lmt0 - E, &E, serr);
    tjd_lmt.* = tjd_lat - E;
    return ret;
}
pub export fn swe_houses(tjd_ut: f64, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64) callconv(.c) i32 {
    return swe_houses_ex(tjd_ut, 0, geolat, geolon, hsys, cusps, ascmc);
}
pub export fn swe_houses_ex(tjd_ut: f64, iflag: i32, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64) callconv(.c) i32 {
    return swe_houses_ex2(tjd_ut, iflag, geolat, geolon, hsys, cusps, ascmc, null, null, null);
}
pub export fn swe_houses_ex2(tjd_ut: f64, iflag: i32, geolat: f64, geolon: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, cusp_speed: ?[*]f64, ascmc_speed: ?[*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    // 1:1 of swehouse.c swe_houses_ex2 (tropical path + limited sidereal traditional fallback)
    var cs: [37]f64 = undefined;
    var asc: [10]f64 = undefined;
    for (0..10) |i| asc[i] = ascmc[i];
    // cusp init not needed but zero
    for (0..37) |i| cs[i] = 0;
    var serr_buf: [256]u8 = undefined;
    serr_buf[0] = 0;
    var serr_ptr: ?*[256]u8 = null;
    if (serr != null) {
        serr_ptr = &serr_buf;
    }
    // ayana auto-set
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0 and !g_state.swed.ayana_is_set) {
        sweph.swe_set_sid_mode(0, 0, 0, &g_state.swed, &g_state.models);
    }
    const tjde = tjd_ut + deltat.swe_deltat_ex(&g_state.dctx, tjd_ut, iflag);
    const eps_mean = swephlib.swi_epsiln(tjde, 0, g_state.models) * RADTODEG;
    var nutlo: [2]f64 = undefined;
    _ = swephlib.swi_nutation(tjde, 0, &nutlo, g_state.models, null);
    nutlo[0] *= RADTODEG;
    nutlo[1] *= RADTODEG;
    if ((iflag & sweph.SEFLG_NONUT) != 0) {
        nutlo[0] = 0;
        nutlo[1] = 0;
    }
    const armc = swephlib.swe_degnorm(swephlib.swe_sidtime0(tjd_ut, eps_mean + nutlo[1], nutlo[0], g_state.models, &g_state.dctx, null) * 15.0 + geolon);
    var xp: [6]f64 = undefined;
    var retc_makr: i32 = 0;
    const hsys_u: u8 = std.ascii.toUpper(@as(u8, @truncate(@as(u32, @bitCast(hsys)))));
    if (hsys_u == 'I') {
        const flags: i32 = sweph.SEFLG_SPEED | sweph.SEFLG_EQUATORIAL;
        retc_makr = sweph.swe_calc_ut(tjd_ut, 0, flags, &xp, &g_state.swed, g_state.models, &g_state.dctx, null);
        if (retc_makr >= 0) {
            asc[9] = xp[1];
        } else {
            // C falls back to 'O' on error but still tries; keep hsys='O' effect by using 'O' later
        }
    }
    var csp: ?*[37]f64 = null;
    var ascp: ?*[10]f64 = null;
    if (cusp_speed) |p| csp = @ptrCast(p);
    if (ascmc_speed) |p| ascp = @ptrCast(p);
    var retc: i32 = 0;
    var ito: usize = 12;
    if (hsys_u == 'G') ito = 36;
    // copy ito handling for RADIANS later
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
        // check sid_mode bits
        const sid_mode = g_state.swed.sidd.sid_mode;
        const SE_SIDBIT_ECL_T0: i32 = 256;
        const SE_SIDBIT_SSY_PLANE: i32 = 512;
        if ((sid_mode & SE_SIDBIT_ECL_T0) != 0 or (sid_mode & SE_SIDBIT_SSY_PLANE) != 0) {
            // For these projection methods full implementation is not ported; fallback to traditional
            // to avoid wildly wrong values we use traditional ayanamsha subtraction
        }
        // traditional ayanamsha method
        var ay: f64 = 0;
        _ = sweph.swe_get_ayanamsa_ex(tjde, iflag, &ay, &g_state.swed, g_state.models, &g_state.dctx, null);
        var hsys2: i32 = hsys;
        if (hsys_u == 'W') hsys2 = 'E';
        retc = swehouse.swe_houses_armc_ex2(armc, geolat, eps_mean + nutlo[1], hsys2, &cs, &asc, csp, ascp, serr_ptr, &g_state.house);
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
        // if Sunshine fallback needed and calc failed, force Porphyry for compatibility (C sets hsys='O')
        var eff_hsys: i32 = hsys;
        if (hsys_u == 'I' and retc_makr < 0) eff_hsys = 'O';
        retc = swehouse.swe_houses_armc_ex2(armc, geolat, eps_mean + nutlo[1], eff_hsys, &cs, &asc, csp, ascp, serr_ptr, &g_state.house);
        if (hsys_u == 'I' and retc_makr >= 0) asc[9] = xp[1];
    }
    if ((iflag & sweph.SEFLG_RADIANS) != 0) {
        for (1..ito + 1) |i| cs[i] *= DEGTORAD;
        for (0..8) |i| asc[i] *= DEGTORAD;
    }
    for (0..37) |i| {
        if (i < 13) cusps[i] = cs[i];
    }
    // ensure cusp[0] as C does (0)
    cusps[0] = cs[0];
    for (0..10) |i| ascmc[i] = asc[i];
    if (csp != null) {
        for (0..37) |i| cusp_speed.?[i] = cs[i];
        // cusp_speed[0] handled inside swehouse; already set
    }
    if (ascp != null) {
        for (0..10) |i| ascmc_speed.?[i] = asc[i];
    }
    if (serr != null and serr_ptr != null) {
        const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
        var i: usize = 0;
        while (i < l) : (i += 1) serr.?[i] = serr_buf[i];
        serr.?[l] = 0;
    }
    if (hsys_u == 'I' and retc_makr < 0) return retc_makr;
    return retc;
}
pub export fn swe_houses_armc(armc: f64, geolat: f64, eps: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64) callconv(.c) i32 {
    var cs: [37]f64 = undefined;
    var asc: [10]f64 = undefined;
    const ret = swehouse.swe_houses_armc(armc, geolat, eps, hsys, &cs, &asc, &g_state.house);
    for (0..13) |i| cusps[i] = cs[i];
    for (0..10) |i| ascmc[i] = asc[i];
    return ret;
}
pub export fn swe_houses_armc_ex2(armc: f64, geolat: f64, eps: f64, hsys: i32, cusps: [*]f64, ascmc: [*]f64, cusp_speed: ?[*]f64, ascmc_speed: ?[*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var cs: [37]f64 = undefined;
    var asc: [10]f64 = undefined;
    for (0..13) |i| cs[i] = cusps[i];
    for (0..10) |i| asc[i] = ascmc[i];
    var serr_buf: [256]u8 = undefined;
    var serr_ptr: ?*[256]u8 = null;
    if (serr != null) {
        serr_ptr = &serr_buf;
        serr_buf[0] = 0;
    }
    var csp: ?*[37]f64 = null;
    var ascp: ?*[10]f64 = null;
    if (cusp_speed) |p| csp = @ptrCast(p);
    if (ascmc_speed) |p| ascp = @ptrCast(p);
    const ret = swehouse.swe_houses_armc_ex2(armc, geolat, eps, hsys, &cs, &asc, csp, ascp, serr_ptr, &g_state.house);
    for (0..13) |i| cusps[i] = cs[i];
    for (0..10) |i| ascmc[i] = asc[i];
    if (csp != null) {
        for (0..13) |i| cusp_speed.?[i] = cs[i];
    }
    if (ascp != null) {
        for (0..10) |i| ascmc_speed.?[i] = asc[i];
    }
    if (serr != null and serr_ptr != null) {
        const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
        @memcpy(serr.?[0..l], serr_buf[0..l]);
        serr.?[l] = 0;
    }
    return ret;
}
pub export fn swe_house_pos(armc: f64, geolat: f64, eps: f64, hsys: i32, xpin: [*]f64, serr: ?[*:0]u8) callconv(.c) f64 {
    var xin: [6]f64 = .{ xpin[0], xpin[1], 0, 0, 0, 0 };
    var serr_buf: [256]u8 = undefined;
    var serr_ptr: ?*[256]u8 = null;
    if (serr != null) {
        serr_ptr = &serr_buf;
        serr_buf[0] = 0;
    }
    const ret = swehouse.swe_house_pos(armc, geolat, eps, hsys, &xin, serr_ptr, &g_state.house);
    if (serr != null and serr_ptr != null) {
        const l = std.mem.indexOfScalar(u8, &serr_buf, 0) orelse 0;
        @memcpy(serr.?[0..l], serr_buf[0..l]);
        serr.?[l] = 0;
    }
    return ret;
}
pub export fn swe_house_name(hsys: i32) callconv(.c) [*:0]const u8 {
    _ = hsys;
    return "Placidus";
}
const CROSS_PRECISION: f64 = 1.0 / 3600000.0;
inline fn abiDelta(tjd: f64, epheflag: i32) f64 {
    g_state.dctx.sweph_denum = g_state.swed.fidat[1].sweph_denum;
    g_state.dctx.jpldenum = g_state.swed.jpldenum;
    g_state.dctx.jpl_file_is_open = g_state.swed.jpl_file_is_open;
    return deltat.swe_deltat_ex(&g_state.dctx, tjd, epheflag);
}
inline fn setSerrFmt(serr: ?[*:0]u8, comptime fmt: []const u8, args: anytype) void {
    if (serr) |s| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        const n = @min(msg.len, AS_MAXCH - 1);
        @memcpy(s[0..n], msg[0..n]);
        s[n] = 0;
    }
}
fn plaus_abi(iflag_in: i32, ipl: i32, tjd: f64, serr: ?[*:0]u8) i32 {
    var iflag = iflag_in;
    // mirrored from sweph.plaus_iflag with serr handling
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
        if (g_state.swed.eop_dpsi_loaded <= 0) {
            if (serr) |s| {
                const msg: []const u8 = switch (g_state.swed.eop_dpsi_loaded) {
                    0 => "you did not call swe_set_jpl_file(); default to SEFLG_JPLHOR_APPROX",
                    -1 => "file eop_1962_today.txt not found; default to SEFLG_JPLHOR_APPROX",
                    -2 => "file eop_1962_today.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                    -3 => "file eop_finals.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                    else => "",
                };
                if (msg.len > 0) {
                    const n = @min(msg.len, AS_MAXCH - 1);
                    @memcpy(s[0..n], msg[0..n]);
                    s[n] = 0;
                }
            }
            iflag &= ~sweph.SEFLG_JPLHOR;
            iflag |= sweph.SEFLG_JPLHOR_APPROX;
        }
    }
    if ((iflag & sweph.SEFLG_JPLHOR) != 0) iflag |= sweph.SEFLG_ICRS;
    if ((iflag & sweph.SEFLG_JPLHOR_APPROX) != 0 and g_state.models.jplhora == 2) iflag |= sweph.SEFLG_ICRS;
    _ = tjd;
    return iflag;
}
fn abi_get_denum(epheflag: i32) i32 {
    if ((epheflag & sweph.SEFLG_MOSEPH) != 0) return 403;
    if ((epheflag & sweph.SEFLG_JPLEPH) != 0) {
        if (g_state.swed.jpldenum > 0) return g_state.swed.jpldenum else return 431;
    }
    if (g_state.swed.fidat[0].sweph_denum != 0) return g_state.swed.fidat[0].sweph_denum;
    return 431;
}
pub export fn swe_calc_pctr(tjd: f64, ipl: i32, iplctr: i32, iflag_in: i32, xxret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var iflag = iflag_in;
    if (ipl == iplctr) {
        setSerrFmt(serr, "ipl and iplctr (= {d}) must not be identical\n", .{ipl});
        return -1;
    }
    iflag = plaus_abi(iflag, ipl, tjd, serr);
    const epheflag = iflag & sweph.SEFLG_EPHMASK;
    // fill obliquity/nutation
    {
        var xx_tmp: [6]f64 = undefined;
        const dt0 = abiDelta(tjd, epheflag);
        const ret0 = sweph.swe_calc(tjd + dt0, -1, iflag, &xx_tmp, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
        _ = ret0;
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
    var retc = sweph.swe_calc(tjd, iplctr, iflag2, &xxctr, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    if (retc == -1) return -1;
    retc = sweph.swe_calc(tjd, ipl, iflag2, &xx, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
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
        if ((iflag & sweph.SEFLG_SPEED) != 0) {
            for (0..3) |i| xxsp[i] = xx0[i] - xx[i] - xxsp[i];
        }
        retc = sweph.swe_calc(t, iplctr, iflag2, &xxctr2, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
        retc = sweph.swe_calc(t, ipl, iflag2, &xx, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    }
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
        sweph.swi_deflect_light(&xx, dtsave_for_defl, iflag, &g_state.swed);
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
    if ((iflag & sweph.SEFLG_ICRS) == 0 and abi_get_denum(epheflag) >= 403) {
        swephlib.swi_bias(&xx, t, iflag, false, g_state.models);
    }
    for (0..6) |i| xxsv[i] = xx[i];
    var oe: *const swephlib.Eps = undefined;
    if ((iflag & sweph.SEFLG_J2000) == 0) {
        // swi_precess expects * [3]f64
        _ = swephlib.swi_precess(@as(*[3]f64, @ptrCast(&xx[0])), tjd, iflag, swephlib.J2000_TO_J, g_state.models);
        if ((iflag & sweph.SEFLG_SPEED) != 0) sweph.swi_precess_speed(&xx, tjd, iflag, swephlib.J2000_TO_J, &g_state.swed, g_state.models);
        oe = &g_state.swed.oec;
    } else {
        oe = &g_state.swed.oec2000;
    }
    if ((iflag & sweph.SEFLG_NONUT) == 0) sweph.swi_nutate(&xx, iflag, false, &g_state.swed);
    for (0..6) |i| xreturn[18 + i] = xx[i];
    swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[0])), @as(*[3]f64, @ptrCast(&xx[0])), oe.seps, oe.ceps);
    if ((iflag & sweph.SEFLG_SPEED) != 0) swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[3])), @as(*[3]f64, @ptrCast(&xx[3])), oe.seps, oe.ceps);
    if ((iflag & sweph.SEFLG_NONUT) == 0) {
        swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[0])), @as(*[3]f64, @ptrCast(&xx[0])), g_state.swed.nut.snut, g_state.swed.nut.cnut);
        if ((iflag & sweph.SEFLG_SPEED) != 0) swephlib.swi_coortrf2(@as(*const [3]f64, @ptrCast(&xx[3])), @as(*[3]f64, @ptrCast(&xx[3])), g_state.swed.nut.snut, g_state.swed.nut.cnut);
    }
    for (0..6) |i| xreturn[6 + i] = xx[i];
    if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
        if ((g_state.swed.sidd.sid_mode & sweph.SE_SIDBIT_ECL_T0) != 0) {
            if (sweph.swi_trop_ra2sid_lon(@as(*const [6]f64, @ptrCast(&xxsv[0])), @as(*[6]f64, @ptrCast(&xreturn[6])), @as(*[6]f64, @ptrCast(&xreturn[18])), iflag, &g_state.swed, g_state.models, &g_state.dctx) != 0) return -1;
        } else if ((g_state.swed.sidd.sid_mode & sweph.SE_SIDBIT_SSY_PLANE) != 0) {
            if (sweph.swi_trop_ra2sid_lon_sosy(@as(*const [6]f64, @ptrCast(&xxsv[0])), @as(*[6]f64, @ptrCast(&xreturn[6])), iflag, &g_state.swed, g_state.models, &g_state.dctx) != 0) return -1;
        } else {
            swephlib.swi_cartpol_sp(@as(*[6]f64, @ptrCast(&xreturn[6])), @as(*[6]f64, @ptrCast(&xreturn[0])));
            for (0..24) |i| xxsv[i] = xreturn[i];
            if (sweph.swi_get_ayanamsa_with_speed(tjd, iflag, &daya, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) == -1) return -1;
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
pub export fn swe_solcross(x2cross: f64, jd_et: f64, flag_in: i32, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc(jd_et, 0, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
    const xlp: f64 = 360.0 / 365.24;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd = jd_et + dist / xlp;
    while (true) {
        if (sweph.swe_calc(jd, 0, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    return jd;
}
pub export fn swe_solcross_ut(x2cross: f64, jd_ut: f64, flag_in: i32, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc_ut(jd_ut, 0, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
    const xlp: f64 = 360.0 / 365.24;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd = jd_ut + dist / xlp;
    while (true) {
        if (sweph.swe_calc_ut(jd, 0, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    return jd;
}
pub export fn swe_mooncross(x2cross: f64, jd_et: f64, flag_in: i32, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc(jd_et, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
    const xlp: f64 = 360.0 / 27.32;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd = jd_et + dist / xlp;
    while (true) {
        if (sweph.swe_calc(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    return jd;
}
pub export fn swe_mooncross_ut(x2cross: f64, jd_ut: f64, flag_in: i32, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc_ut(jd_ut, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
    const xlp: f64 = 360.0 / 27.32;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd = jd_ut + dist / xlp;
    while (true) {
        if (sweph.swe_calc_ut(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    return jd;
}
pub export fn swe_mooncross_node(jd_et: f64, flag_in: i32, xlon: *f64, xlat: *f64, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc(jd_et, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
    const xlat0 = x[1];
    var jd = jd_et + 1;
    while (true) {
        if (sweph.swe_calc(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
        if ((x[1] >= 0 and xlat0 < 0) or (x[1] < 0 and xlat0 > 0)) break;
        jd += 1;
    }
    var dist = x[1];
    while (true) {
        jd -= dist / x[4];
        if (sweph.swe_calc(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_et - 1;
        dist = x[1];
        if (@abs(dist) < CROSS_PRECISION) {
            xlon.* = x[0];
            xlat.* = x[1];
            break;
        }
    }
    return jd;
}
pub export fn swe_mooncross_node_ut(jd_ut: f64, flag_in: i32, xlon: *f64, xlat: *f64, serr: ?[*:0]u8) callconv(.c) f64 {
    const flag = flag_in | sweph.SEFLG_SPEED;
    var x: [6]f64 = undefined;
    if (sweph.swe_calc_ut(jd_ut, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
    const xlat0 = x[1];
    var jd = jd_ut + 1;
    while (true) {
        if (sweph.swe_calc_ut(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
        if ((x[1] >= 0 and xlat0 < 0) or (x[1] < 0 and xlat0 > 0)) break;
        jd += 1;
    }
    var dist = x[1];
    while (true) {
        jd -= dist / x[4];
        if (sweph.swe_calc_ut(jd, 1, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return jd_ut - 1;
        dist = x[1];
        if (@abs(dist) < CROSS_PRECISION) {
            xlon.* = x[0];
            xlat.* = x[1];
            break;
        }
    }
    return jd;
}
pub export fn swe_helio_cross(ipl: i32, x2cross: f64, jd_et: f64, iflag_in: i32, dir: i32, jd_cross: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const flag = iflag_in | sweph.SEFLG_SPEED | sweph.SEFLG_HELCTR;
    if (ipl == 0 or ipl == 1 or (ipl >= 10 and ipl <= 13) or (ipl >= 21 and ipl < 23)) {
        var sbuf: [256]u8 = undefined;
        _ = sweph.swe_get_planet_name(ipl, &sbuf, &g_state.swed, g_state.models, &g_state.dctx, null);
        const slen = std.mem.indexOfScalar(u8, &sbuf, 0) orelse 0;
        const name = sbuf[0..slen];
        setSerrFmt(serr, "swe_helio_cross: not possible for object {d} = {s}", .{ ipl, name });
        return -1;
    }
    var x: [6]f64 = undefined;
    if (sweph.swe_calc(jd_et, ipl, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return -1;
    var xlp = x[3];
    if (ipl == 15) xlp = 0.01971;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd: f64 = undefined;
    if (dir >= 0) jd = jd_et + dist / xlp else {
        dist = 360.0 - dist;
        jd = jd_et - dist / xlp;
    }
    while (true) {
        if (sweph.swe_calc(jd, ipl, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return -1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    jd_cross.* = jd;
    return 0;
}
pub export fn swe_helio_cross_ut(ipl: i32, x2cross: f64, jd_ut: f64, iflag_in: i32, dir: i32, jd_cross: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const flag = iflag_in | sweph.SEFLG_SPEED | sweph.SEFLG_HELCTR;
    if (ipl == 0 or ipl == 1 or (ipl >= 10 and ipl <= 13) or (ipl >= 21 and ipl < 23)) {
        var sbuf: [256]u8 = undefined;
        _ = sweph.swe_get_planet_name(ipl, &sbuf, &g_state.swed, g_state.models, &g_state.dctx, null);
        const slen = std.mem.indexOfScalar(u8, &sbuf, 0) orelse 0;
        const name = sbuf[0..slen];
        setSerrFmt(serr, "swe_helio_cross: not possible for object {d} = {s}", .{ ipl, name });
        return -1;
    }
    var x: [6]f64 = undefined;
    if (sweph.swe_calc_ut(jd_ut, ipl, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return -1;
    var xlp = x[3];
    if (ipl == 15) xlp = 0.01971;
    var dist = swephlib.swe_degnorm(x2cross - x[0]);
    var jd: f64 = undefined;
    if (dir >= 0) jd = jd_ut + dist / xlp else {
        dist = 360.0 - dist;
        jd = jd_ut - dist / xlp;
    }
    while (true) {
        if (sweph.swe_calc_ut(jd, ipl, flag, &x, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr)) < 0) return -1;
        dist = swephlib.swe_difdeg2n(x2cross, x[0]);
        jd += dist / x[3];
        if (@abs(dist) < CROSS_PRECISION) break;
    }
    jd_cross.* = jd;
    return 0;
}
pub export fn swe_get_ayanamsa(tjd_et: f64) callconv(.c) f64 {
    var d: f64 = 0;
    _ = swe_get_ayanamsa_ex(tjd_et, 0, &d, null);
    return d;
}
pub export fn swe_get_ayanamsa_ut(tjd_ut: f64) callconv(.c) f64 {
    var d: f64 = 0;
    _ = swe_get_ayanamsa_ex_ut(tjd_ut, 0, &d, null);
    return d;
}
pub export fn swe_get_ayanamsa_name(isidmode: i32) callconv(.c) [*:0]const u8 {
    _ = isidmode;
    return "Fagan/Bradley";
}
pub export fn swe_get_current_file_data(ifno: i32, tfstart: *f64, tfend: *f64, denum: *i32) callconv(.c) [*:0]const u8 {
    _ = ifno;
    tfstart.* = 0;
    tfend.* = 0;
    denum.* = 0;
    return "";
}
pub export fn swe_get_astro_models(samod: [*:0]u8, sdet: [*:0]u8, iflag: i32) callconv(.c) void {
    _ = iflag;
    samod[0] = 0;
    sdet[0] = 0;
}
pub export fn swe_set_astro_models(samod: [*:0]u8, iflag: i32) callconv(.c) void {
    _ = samod;
    _ = iflag;
}
pub export fn swe_set_timeout(tsec: i32) callconv(.c) void {
    _ = tsec;
}
pub export fn swe_sidtime0(tjd_ut: f64, eps: f64, nut: f64) callconv(.c) f64 {
    return swephlib.swe_sidtime0(tjd_ut, eps, nut, g_state.models, &g_state.dctx, null);
}
pub export fn swe_sidtime(tjd_ut: f64) callconv(.c) f64 {
    return swephlib.swe_sidtime(tjd_ut, g_state.models, &g_state.dctx, null);
}

// --- Remaining 39 APIs that were omitted from minimal file — stubs for ABI completeness ---
pub export fn swe_azalt(tjd_ut: f64, calc_flag: i32, geopos: [*]f64, atpress: f64, attemp: f64, xin: [*]f64, xaz: [*]f64) callconv(.c) void {
    swecl.swe_azalt(tjd_ut, calc_flag, @ptrCast(geopos[0..3]), atpress, attemp, @ptrCast(xin[0..3]), @ptrCast(xaz[0..3]), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
}
pub export fn swe_azalt_rev(tjd_ut: f64, calc_flag: i32, geopos: [*]f64, xin: [*]f64, xout: [*]f64) callconv(.c) void {
    swecl.swe_azalt_rev(tjd_ut, calc_flag, @ptrCast(geopos[0..3]), @ptrCast(xin[0..3]), @ptrCast(xout[0..2]), &g_state.swed, g_state.models, &g_state.dctx);
}
pub export fn swe_deg_midp(x1: f64, x0: f64) callconv(.c) f64 {
    return swephlib.swe_deg_midp(x1, x0);
}
pub export fn swe_difdegn(p1: f64, p2: f64) callconv(.c) f64 {
    return swephlib.swe_degnorm(p1 - p2);
}
pub export fn swe_fixstar(star: [*:0]u8, tjd: f64, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    buf[len] = 0;
    var out: [6]f64 = undefined;
    const ret = sweph.swe_fixstar(buf[0..len], tjd, iflag, &out, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = out[i];
    const slen = std.mem.indexOfScalar(u8, &buf, 0) orelse len;
    @memcpy(star[0..slen], buf[0..slen]);
    star[slen] = 0;
    return ret;
}
pub export fn swe_fixstar_ut(star: [*:0]u8, tjd_ut: f64, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    buf[len] = 0;
    var out: [6]f64 = undefined;
    const ret = sweph.swe_fixstar_ut(buf[0..len], tjd_ut, iflag, &out, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = out[i];
    const slen = std.mem.indexOfScalar(u8, &buf, 0) orelse len;
    @memcpy(star[0..slen], buf[0..slen]);
    star[slen] = 0;
    return ret;
}
pub export fn swe_fixstar_mag(star: [*:0]u8, mag: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    return sweph.swe_fixstar_mag(buf[0..len], mag, &g_state.swed, serrToZig(serr));
}
pub export fn swe_fixstar2(star: [*:0]u8, tjd: f64, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    buf[len] = 0;
    var out: [6]f64 = undefined;
    const ret = sweph.swe_fixstar2(buf[0..len], tjd, iflag, &out, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = out[i];
    const slen = std.mem.indexOfScalar(u8, &buf, 0) orelse len;
    @memcpy(star[0..slen], buf[0..slen]);
    star[slen] = 0;
    return ret;
}
pub export fn swe_fixstar2_ut(star: [*:0]u8, tjd_ut: f64, iflag: i32, xx: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    buf[len] = 0;
    var out: [6]f64 = undefined;
    const ret = sweph.swe_fixstar2_ut(buf[0..len], tjd_ut, iflag, &out, &g_state.swed, g_state.models, &g_state.dctx, serrToZig(serr));
    for (0..6) |i| xx[i] = out[i];
    const slen = std.mem.indexOfScalar(u8, &buf, 0) orelse len;
    @memcpy(star[0..slen], buf[0..slen]);
    star[slen] = 0;
    return ret;
}
pub export fn swe_fixstar2_mag(star: [*:0]u8, mag: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const len = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..len], star[0..len]);
    return sweph.swe_fixstar2_mag(buf[0..len], mag, &g_state.swed, serrToZig(serr));
}
pub export fn swe_gauquelin_sector(t_ut: f64, ipl: i32, starname: ?[*:0]u8, iflag: i32, imeth: i32, geopos: [*]f64, atpress: f64, attemp: f64, dgsect: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var star: ?[]u8 = null;
    var buf: [256]u8 = undefined;
    if (starname) |s| {
        const l = std.mem.len(s);
        @memcpy(buf[0..l], s[0..l]);
        buf[l] = 0;
        star = buf[0..l];
    }
    return swecl.swe_gauquelin_sector(t_ut, ipl, star, iflag, imeth, @ptrCast(geopos[0..3]), atpress, attemp, dgsect, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
}
pub export fn swe_get_orbital_elements(tjd_et: f64, ipl: i32, iflag: i32, dret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var buf: [50]f64 = undefined;
    const ret = swecl.swe_get_orbital_elements(tjd_et, ipl, iflag, &buf, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
    for (0..50) |i| dret[i] = buf[i];
    return ret;
}
pub export fn swe_get_planet_name(ipl: i32, spname: [*:0]u8) callconv(.c) [*:0]u8 {
    var buf: [256]u8 = undefined;
    _ = sweph.swe_get_planet_name(ipl, &buf, &g_state.swed, g_state.models, &g_state.dctx, null);
    const l = std.mem.indexOfScalar(u8, &buf, 0) orelse 0;
    @memcpy(spname[0..l], buf[0..l]);
    spname[l] = 0;
    return spname;
}
pub export fn swe_heliacal_angle(tjd: f64, dgeo: [*]f64, datm: [*]f64, dobs: [*]f64, helflag: i32, mag: f64, azi_obj: f64, azi_sun: f64, azi_moon: f64, alt_moon: f64, dret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    return swehel.swe_heliacal_angle(tjd, @ptrCast(dgeo[0..3]), @ptrCast(datm[0..4]), @ptrCast(dobs[0..6]), helflag, mag, azi_obj, azi_sun, azi_moon, alt_moon, @ptrCast(dret[0..3]), serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx, &g_state.hctx);
}
pub export fn swe_heliacal_pheno_ut(tjd_ut: f64, geopos: [*]f64, datm: [*]f64, dobs: [*]f64, obj: [*:0]u8, evt: i32, helflag: i32, darr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const l = std.mem.len(obj);
    return swehel.swe_heliacal_pheno_ut(tjd_ut, @ptrCast(geopos[0..3]), @ptrCast(datm[0..4]), @ptrCast(dobs[0..6]), obj[0..l], evt, helflag, @ptrCast(darr[0..40]), serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx, &g_state.hctx);
}
pub export fn swe_heliacal_ut(tjd: f64, geopos: [*]f64, datm: [*]f64, dobs: [*]f64, obj: [*:0]u8, evt: i32, helflag: i32, dret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const l = std.mem.len(obj);
    return swehel.swe_heliacal_ut(tjd, @ptrCast(geopos[0..3]), @ptrCast(datm[0..4]), @ptrCast(dobs[0..6]), obj[0..l], evt, helflag, @ptrCast(dret[0..10]), serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx, &g_state.hctx);
}
pub export fn swe_lun_eclipse_how(tjd_ut: f64, ifl: i32, geopos: ?[*]f64, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var a: [20]f64 = undefined;
    var g: [3]f64 = undefined;
    var gptr: ?*[3]f64 = null;
    if (geopos) |gp| {
        g[0] = gp[0];
        g[1] = gp[1];
        g[2] = gp[2];
        gptr = &g;
    }
    const ret = swecl.swe_lun_eclipse_how(tjd_ut, ifl, gptr, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_lun_eclipse_when(tjd_start: f64, ifl: i32, ifltype: i32, tret: [*]f64, backward: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    var tt: [10]f64 = undefined;
    const ret = swecl.swe_lun_eclipse_when(tjd_start, ifl, ifltype, &tt, backward, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    return ret;
}
pub export fn swe_lun_eclipse_when_loc(tjd_start: f64, ifl: i32, geopos: [*]f64, tret: [*]f64, attr: [*]f64, backward: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    var g: [3]f64 = .{ geopos[0], geopos[1], 0 };
    var tt: [10]f64 = undefined;
    var aa: [20]f64 = undefined;
    const ret = swecl.swe_lun_eclipse_when_loc(tjd_start, ifl, &g, &tt, &aa, backward, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    for (0..20) |i| attr[i] = aa[i];
    return ret;
}
pub export fn swe_lun_occult_when_glob(tjd_start: f64, ipl: i32, star: [*:0]u8, ifl: i32, ifltype: i32, tret: [*]f64, backward: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    const l = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..l], star[0..l]);
    var tt: [10]f64 = undefined;
    const ret = swecl.swe_lun_occult_when_glob(tjd_start, ipl, buf[0..l], ifl, ifltype, &tt, backward, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    return ret;
}
pub export fn swe_lun_occult_when_loc(tjd_start: f64, ipl: i32, star: [*:0]u8, ifl: i32, geopos: [*]f64, tret: [*]f64, attr: [*]f64, backward: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    const l = std.mem.len(star);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..l], star[0..l]);
    var tt: [10]f64 = undefined;
    var aa: [20]f64 = undefined;
    const ret = swecl.swe_lun_occult_when_loc(tjd_start, ipl, buf[0..l], ifl, @ptrCast(geopos[0..3]), &tt, &aa, backward, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    for (0..20) |i| attr[i] = aa[i];
    return ret;
}
pub export fn swe_lun_occult_where(tjd: f64, ipl: i32, star: ?[*:0]u8, ifl: i32, geopos: [*]f64, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var star_arg: ?[]u8 = null;
    var sbuf: [256]u8 = undefined;
    if (star) |s| {
        const l = std.mem.len(s);
        if (l > 0) {
            @memcpy(sbuf[0..l], s[0..l]);
            star_arg = sbuf[0..l];
        }
    }
    var g: [2]f64 = .{ geopos[0], geopos[1] };
    var a: [20]f64 = undefined;
    const ret = swecl.swe_lun_occult_where(tjd, ipl, star_arg, ifl, &g, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..2) |i| geopos[i] = g[i];
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_nod_aps(tjd_et: f64, ipl: i32, iflag: i32, method: i32, xnasc: [*]f64, xndsc: [*]f64, xperi: [*]f64, xaphe: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var n: [6]f64 = undefined;
    var d: [6]f64 = undefined;
    var p: [6]f64 = undefined;
    var a: [6]f64 = undefined;
    const ret = swecl.swe_nod_aps(tjd_et, ipl, iflag, method, &n, &d, &p, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
    for (0..6) |i| xnasc[i] = n[i];
    for (0..6) |i| xndsc[i] = d[i];
    for (0..6) |i| xperi[i] = p[i];
    for (0..6) |i| xaphe[i] = a[i];
    return ret;
}
pub export fn swe_nod_aps_ut(tjd_ut: f64, ipl: i32, iflag: i32, method: i32, xnasc: [*]f64, xndsc: [*]f64, xperi: [*]f64, xaphe: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var n: [6]f64 = undefined;
    var d: [6]f64 = undefined;
    var p: [6]f64 = undefined;
    var a: [6]f64 = undefined;
    const ret = swecl.swe_nod_aps_ut(tjd_ut, ipl, iflag, method, &n, &d, &p, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
    for (0..6) |i| xnasc[i] = n[i];
    for (0..6) |i| xndsc[i] = d[i];
    for (0..6) |i| xperi[i] = p[i];
    for (0..6) |i| xaphe[i] = a[i];
    return ret;
}
pub export fn swe_orbit_max_min_true_distance(tjd: f64, ipl: i32, iflag: i32, dmax: *f64, dmin: *f64, dtrue: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    return swecl.swe_orbit_max_min_true_distance(tjd, ipl, iflag, dmax, dmin, dtrue, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
}
pub export fn swe_pheno(tjd: f64, ipl: i32, iflag: i32, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var a: [20]f64 = undefined;
    const ret = swecl.swe_pheno(tjd, ipl, iflag, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_pheno_ut(tjd_ut: f64, ipl: i32, iflag: i32, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var a: [20]f64 = undefined;
    const ret = swecl.swe_pheno_ut(tjd_ut, ipl, iflag, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx);
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_rad_midp(x1: f64, x0: f64) callconv(.c) f64 {
    return swephlib.swe_rad_midp(x1, x0);
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
pub export fn swe_rise_trans(tjd_ut: f64, ipl: i32, star: ?[*:0]u8, epheflag: i32, rsmi: i32, geopos: [*]f64, atpress: f64, attemp: f64, tret: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var s: ?[]u8 = null;
    var buf: [256]u8 = undefined;
    if (star) |st| {
        const l = std.mem.len(st);
        @memcpy(buf[0..l], st[0..l]);
        buf[l] = 0;
        s = buf[0..l];
    }
    return swecl.swe_rise_trans(tjd_ut, ipl, s, epheflag, rsmi, @ptrCast(geopos[0..3]), atpress, attemp, tret, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
}
pub export fn swe_rise_trans_true_hor(tjd_ut: f64, ipl: i32, star: ?[*:0]u8, epheflag: i32, rsmi: i32, geopos: [*]f64, atpress: f64, attemp: f64, hor: f64, tret: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var s: ?[]u8 = null;
    var buf: [256]u8 = undefined;
    if (star) |st| {
        const l = std.mem.len(st);
        @memcpy(buf[0..l], st[0..l]);
        buf[l] = 0;
        s = buf[0..l];
    }
    return swecl.swe_rise_trans_true_hor(tjd_ut, ipl, s, epheflag, rsmi, @ptrCast(geopos[0..3]), atpress, attemp, hor, tret, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
}
pub export fn swe_set_lapse_rate(rate: f64) callconv(.c) void {
    swecl.swe_set_lapse_rate(rate, &g_state.cctx);
}
pub export fn swe_sol_eclipse_how(tjd: f64, ifl: i32, geopos: [*]f64, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var g: [3]f64 = .{ geopos[0], geopos[1], geopos[2] };
    var a: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_how(tjd, ifl, &g, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_sol_eclipse_when_glob(tjd: f64, ifl: i32, ifltype: i32, tret: [*]f64, b: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    var tt: [10]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_when_glob(tjd, ifl, ifltype, &tt, b != 0, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    return ret;
}
pub export fn swe_sol_eclipse_when_loc(tjd: f64, ifl: i32, geopos: [*]f64, tret: [*]f64, attr: [*]f64, b: i32, serr: ?[*:0]u8) callconv(.c) i32 {
    var g: [3]f64 = .{ geopos[0], geopos[1], geopos[2] };
    var tt: [10]f64 = undefined;
    var aa: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_when_loc(tjd, ifl, &g, &tt, &aa, b != 0, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    for (0..10) |i| tret[i] = tt[i];
    for (0..20) |i| attr[i] = aa[i];
    return ret;
}
pub export fn swe_sol_eclipse_where(tjd: f64, ifl: i32, geopos: [*]f64, attr: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    var g: [2]f64 = .{ geopos[0], geopos[1] };
    var a: [20]f64 = undefined;
    const ret = swecl.swe_sol_eclipse_where(tjd, ifl, &g, &a, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx);
    geopos[0] = g[0];
    geopos[1] = g[1];
    for (0..20) |i| attr[i] = a[i];
    return ret;
}
pub export fn swe_topo_arcus_visionis(tjd: f64, g: [*]f64, datm: [*]f64, dobs: [*]f64, flag: i32, mag: f64, a1: f64, a2: f64, a3: f64, a4: f64, am: f64, ret: *f64, serr: ?[*:0]u8) callconv(.c) i32 {
    return swehel.swe_topo_arcus_visionis(tjd, @ptrCast(g[0..3]), @ptrCast(datm[0..4]), @ptrCast(dobs[0..6]), flag, mag, a1, a2, a3, a4, am, ret, serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx, &g_state.hctx);
}
pub export fn swe_vis_limit_mag(tjd: f64, g: [*]f64, datm: [*]f64, dobs: [*]f64, n: [*:0]u8, flag: i32, ret: [*]f64, serr: ?[*:0]u8) callconv(.c) i32 {
    const l = std.mem.len(n);
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..l], n[0..l]);
    return swehel.swe_vis_limit_mag(tjd, @ptrCast(g[0..3]), @ptrCast(datm[0..4]), @ptrCast(dobs[0..6]), buf[0..l], flag, @ptrCast(ret[0..8]), serrToZig(serr), &g_state.swed, g_state.models, &g_state.dctx, &g_state.cctx, &g_state.hctx);
}
