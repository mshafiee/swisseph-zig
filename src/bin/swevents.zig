// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
const swe = @import("swe_abi");
const std = @import("std");

extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn fprintf(stream: ?*anyopaque, format: [*:0]const u8, ...) c_int;
extern "c" fn sprintf(buf: [*]u8, format: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, n: usize, format: [*:0]const u8, ...) c_int;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(f: ?*anyopaque) c_int;
extern "c" fn fgets(buf: [*]u8, n: c_int, stream: ?*anyopaque) ?[*]u8;
extern "c" fn exit(code: c_int) noreturn;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn strcat(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn strstr(hay: [*:0]const u8, needle: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, c: c_int) ?[*:0]u8;
extern "c" fn strpbrk(s: [*:0]const u8, accept: [*:0]const u8) ?[*:0]u8;
extern "c" fn sscanf(buf: [*:0]const u8, format: [*:0]const u8, ...) c_int;
extern "c" fn atof(s: [*:0]const u8) f64;
extern "c" fn atoi(s: [*:0]const u8) c_int;
extern "c" fn atol(s: [*:0]const u8) c_long;
extern "c" fn fabs(x: f64) f64;
extern "c" fn floor(x: f64) f64;
extern "c" fn fmod(x: f64, y: f64) f64;
extern "c" fn sqrt(x: f64) f64;
extern "c" fn acos(x: f64) f64;
extern "c" fn cos(x: f64) f64;
extern "c" fn sin(x: f64) f64;

const SE_GREG_CAL: i32 = 1;
const SE_JUL_CAL: i32 = 0;
const SEFLG_JPLEPH: i32 = 1;
const SEFLG_SWIEPH: i32 = 2;
const SEFLG_MOSEPH: i32 = 4;
const SEFLG_HELCTR: i32 = 8;
const SEFLG_TRUEPOS: i32 = 16;
const SEFLG_J2000: i32 = 32;
const SEFLG_NONUT: i32 = 64;
const SEFLG_SPEED: i32 = 256;
const SEFLG_NOGDEFL: i32 = 512;
const SEFLG_NOABERR: i32 = 1024;
const SEFLG_EQUATORIAL: i32 = 2048;
const SEFLG_RADIANS: i32 = 8192;
const SEFLG_TOPOCTR: i32 = 32768;
const SEFLG_SIDEREAL: i32 = 65536;
const SEFLG_ICRS: i32 = 131072;
const SEFLG_EPHMASK: i32 = SEFLG_JPLEPH | SEFLG_SWIEPH | SEFLG_MOSEPH;

const SE_SUN: i32 = 0;
const SE_MOON: i32 = 1;
const SE_MERCURY: i32 = 2;
const SE_VENUS: i32 = 3;
const SE_MARS: i32 = 4;
const SE_JUPITER: i32 = 5;
const SE_SATURN: i32 = 6;
const SE_URANUS: i32 = 7;
const SE_NEPTUNE: i32 = 8;
const SE_PLUTO: i32 = 9;
const SE_MEAN_NODE: i32 = 10;
const SE_TRUE_NODE: i32 = 11;
const SE_MEAN_APOG: i32 = 12;
const SE_OSCU_APOG: i32 = 13;
const SE_EARTH: i32 = 14;
const SE_CHIRON: i32 = 15;
const SE_PHOLUS: i32 = 16;
const SE_CERES: i32 = 17;
const SE_ECL_NUT: i32 = -1;
const SE_FIXSTAR: i32 = -10;
const SE_AST_OFFSET: i32 = 10000;
const SE_CUPIDO: i32 = 40;
const SE_WALDEMATH: i32 = 58;
const SE_FICT_OFFSET: i32 = 39;
const SE_NPLANETS: i32 = 11;

const BIT_ROUND_SEC: i32 = 1;
const BIT_ROUND_MIN: i32 = 2;
const BIT_ZODIAC: i32 = 4;
const BIT_DECL: i32 = 16;

const DO_CONJ: i32 = 1;
const DO_RISE: i32 = 2;
const DO_ELONG: i32 = 4;
const DO_RETRO: i32 = 8;
const DO_BRILL: i32 = 16;
const DO_APS: i32 = 32;
const DO_NODE: i32 = 64;
const DO_INGR: i32 = 256;
const DO_LPHASE: i32 = 512;
const DO_INGR45: i32 = 1024;
const DO_ASPECTS: i32 = 2048;
const DO_VOC: i32 = 4096;
const DO_DECL: i32 = 8192;
const DO_LPHASE0: i32 = 16384;
const DO_ALL: i32 = DO_CONJ | DO_RISE | DO_ELONG | DO_RETRO | DO_BRILL | DO_APS | DO_NODE | DO_INGR | DO_DECL;

const AS_MAXCH: usize = 256;
const DEGTORAD: f64 = std.math.pi / 180.0;
const RADTODEG: f64 = 180.0 / std.math.pi;
const HUGE_VAL: f64 = 1e20;

var zod_nam = [_][:0]const u8{ "AR", "TA", "GE", "CN", "LE", "VI", "LI", "SC", "SA", "CP", "AQ", "PI" };
var zod_nam3 = [_][:0]const u8{ "ARI", "TAU", "GEM", "CAN", "LEO", "VIR", "LIB", "SCO", "SAG", "CAP", "AQU", "PIS" };
var zod_nam_long = [_][:0]const u8{ "aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces" };
var znam_mode: i32 = 0;
fn getZNam(idx: usize) [*:0]const u8 {
    if (znam_mode == 1) return zod_nam3[idx];
    if (znam_mode == 2) return zod_nam_long[idx];
    return zod_nam[idx];
}
var month_nam_arr: [13][4]u8 = undefined;
var month_nam: [13][*:0]u8 = undefined;

var do_flag: i32 = 0;
var tzone: f64 = 0;
var gmtoff: f64 = 0;
var ephemeris_time: bool = false;
var do_round_min: bool = false;
var do_motab: bool = false;
var do_mojap: bool = false;
var date_gap: bool = false;
var show_jd: bool = false;
var print_cl: bool = true;
var output_extra_prec: bool = false;
var transits_to_stderr: bool = false;
var phase_mod: f64 = 90;
var gap: [*:0]u8 = @ptrCast(@constCast(" "));
var gregflag: i32 = 1;
var ipl_global: i32 = 3;
var whicheph: i32 = SEFLG_SWIEPH;
var planet_name: [*:0]u8 = @ptrCast(@constCast("-"));
var spnam: [256]u8 = [_]u8{0} ** 256;
var motab: [13][31][10]u8 = undefined;
var prev_yout: i32 = -999999;
var cmdline: [1024]u8 = [_]u8{0} ** 1024;

fn initMonthNames() void {
    const names = [_][]const u8{ "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (names, 0..) |n, idx| {
        var i: usize = 0;
        while (i < n.len and i < 3) : (i += 1) month_nam_arr[idx][i] = n[i];
        month_nam_arr[idx][n.len] = 0;
        month_nam[idx] = @ptrCast(&month_nam_arr[idx]);
    }
}

fn cStr(s: []const u8) [*:0]const u8 {
    return @ptrCast(s.ptr);
}

fn signChange(x0: f64, x1: f64) bool {
    if (x0 < 0 and x1 >= 0) return true;
    if (x0 >= 0 and x1 < 0) return true;
    return false;
}

fn polcart(lon_deg: f64, lat_deg: f64, r: f64, out: *[3]f64) void {
    const lon = lon_deg * DEGTORAD;
    const lat = lat_deg * DEGTORAD;
    const clat = cos(lat);
    out[0] = r * clat * cos(lon);
    out[1] = r * clat * sin(lon);
    out[2] = r * sin(lat);
}
fn squareSum(v: [3]f64) f64 {
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
}

var dms_buf: [256]u8 = undefined;
fn dms(x_in: f64, iflag: i32) [*:0]u8 {
    var x = x_in;
    var c: [*:0]const u8 = "\xc2\xb0";
    var s: [256]u8 = [_]u8{0} ** 256;
    var s2: [80]u8 = [_]u8{0} ** 80;
    var sgn: i32 = 1;
    s[0] = 0;
    s2[0] = 0;
    if ((iflag & SEFLG_EQUATORIAL) != 0) c = "h";
    if (x < 0) {
        x = -x;
        sgn = -1;
    } else sgn = 1;
    var izod: i32 = 0;
    if ((iflag & BIT_ZODIAC) != 0) {
        izod = @intFromFloat(floor(x / 30));
        x = fmod(x, 30);
        const kdeg: i32 = @intFromFloat(x);
        _ = snprintf(@ptrCast(&s), 256, "%2d %s ", kdeg, getZNam(@intCast(izod)));
    } else if ((iflag & BIT_DECL) != 0) {
        if (sgn < 0) c = "S" else c = "N";
        const kdeg: i32 = @intFromFloat(x);
        _ = snprintf(@ptrCast(&s), 256, " %3d%s", kdeg, c);
    } else {
        const kdeg: i32 = @intFromFloat(x);
        _ = snprintf(@ptrCast(&s), 256, " %3d%s", kdeg, c);
    }
    var kdeg: i32 = undefined;
    // need to re-derive kdeg for remaining
    // parse kdeg from s: we already have it, get it back
    // simpler: recompute
    var tmp_x = x;
    if ((iflag & BIT_ZODIAC) != 0) {
        // x already is remainder
        kdeg = @intFromFloat(tmp_x);
    } else {
        kdeg = @intFromFloat(tmp_x);
    }
    tmp_x -= @as(f64, @floatFromInt(kdeg));
    tmp_x *= 60;
    if ((iflag & BIT_ROUND_MIN) != 0) tmp_x += 0.5;
    const kmin: i32 = @intFromFloat(tmp_x);
    if (kmin == 60) {
        x = (@as(f64, @floatFromInt(kdeg)) + 1) * @as(f64, @floatFromInt(sgn));
        if ((iflag & BIT_ZODIAC) != 0) x += @as(f64, @floatFromInt(izod)) * 30;
        return dms(x, iflag);
    }
    @memcpy(s2[0..80], s[0..80]);
    if (((iflag & BIT_ZODIAC) != 0) and ((iflag & BIT_ROUND_MIN) != 0)) {
        _ = snprintf(@ptrCast(&s), 256, "%s%2d", @as([*:0]u8, @ptrCast(&s2)), kmin);
    } else {
        _ = snprintf(@ptrCast(&s), 256, "%s%2d'", @as([*:0]u8, @ptrCast(&s2)), kmin);
    }
    if ((iflag & BIT_ROUND_MIN) != 0) {
        // goto return
    } else {
        tmp_x -= @as(f64, @floatFromInt(kmin));
        tmp_x *= 60;
        if ((iflag & BIT_ROUND_SEC) != 0) tmp_x += 0.5;
        const ksec: i32 = @intFromFloat(tmp_x);
        if (ksec == 60) {
            x = (@as(f64, @floatFromInt(kdeg)) + (@as(f64, @floatFromInt(kmin)) + 1) / 60.0 + 0.1 / 3600.0) * @as(f64, @floatFromInt(sgn));
            if ((iflag & BIT_ZODIAC) != 0) x += @as(f64, @floatFromInt(izod)) * 30;
            return dms(x, iflag);
        }
        s2[0] = 0;
        // copy s to s2
        var slen: usize = 0;
        while (s[slen] != 0) : (slen += 1) {}
        @memcpy(s2[0 .. slen + 1], s[0 .. slen + 1]);
        _ = snprintf(@ptrCast(&s), 256, "%s%2d\"", @as([*:0]u8, @ptrCast(&s2)), ksec);
        if ((iflag & BIT_ROUND_SEC) == 0) {
            tmp_x -= @as(f64, @floatFromInt(ksec));
            const k: i32 = @intFromFloat(tmp_x * 10000);
            var suffix: [32]u8 = [_]u8{0} ** 32;
            _ = snprintf(@ptrCast(&suffix), 32, ".%04d", k);
            var cur: usize = 0;
            while (s[cur] != 0) : (cur += 1) {}
            var j: usize = 0;
            while (suffix[j] != 0) : (j += 1) {
                s[cur + j] = suffix[j];
            }
            s[cur + 5] = 0;
        }
    }
    if (sgn < 0 and (iflag & BIT_DECL) == 0) {
        var p: usize = 0;
        while (s[p] != 0) : (p += 1) {
            if (s[p] >= '0' and s[p] <= '9') {
                s[p - 1] = '-';
                break;
            }
        }
    }
    if ((iflag & 8) != 0) {
        var p: usize = 2;
        while (s[p] != 0) : (p += 1) {
            if (s[p] == ' ') s[p] = '0';
        }
    }
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    @memcpy(dms_buf[0 .. len + 1], s[0 .. len + 1]);
    dms_buf[len] = 0;
    return @ptrCast(&dms_buf);
}

var hms_buf: [256]u8 = undefined;
fn hms(x_in: f64, iflag: i32) [*:0]u8 {
    var x = x_in;
    x += 0.5 / 36000.0;
    const s = dms(x, iflag);
    // replace degree string with :
    const deg = "\xc2\xb0";
    const slen = std.mem.len(s);
    var s_copy: [256]u8 = [_]u8{0} ** 256;
    @memcpy(s_copy[0 .. slen + 1], s[0 .. slen + 1]);
    if (std.mem.indexOf(u8, s_copy[0..slen], deg)) |pos| {
        s_copy[pos] = ':';
        // shift if deg len >1
        const deg_len = deg.len;
        if (deg_len > 1) {
            var i: usize = pos + 1;
            while (i + deg_len - 1 < 256 and s_copy[i + deg_len - 1] != 0) : (i += 1) {}
            // simple: memmove tail
            var tail: [256]u8 = [_]u8{0} ** 256;
            var tl: usize = 0;
            while (s_copy[pos + deg_len + tl] != 0) : (tl += 1) {
                tail[tl] = s_copy[pos + deg_len + tl];
            }
            s_copy[pos + 1] = tail[0];
            // actually original replaces: *(sp+3)=':' etc, simplified to our dms already has format "%2d ...", easier: just ask dms then string replace
            // For simplicity use hms via split_deg
            // fallback: use swe_split_deg
        }
        // find second separator ' -> replace with :
        var q: usize = 0;
        while (s_copy[q] != 0) : (q += 1) {
            if (s_copy[q] == '\'') s_copy[q] = ':';
        }
        // truncate after 8 chars?
        s_copy[8] = 0;
    }
    var len2: usize = 0;
    while (s_copy[len2] != 0) : (len2 += 1) {}
    @memcpy(hms_buf[0 .. len2 + 1], s_copy[0 .. len2 + 1]);
    return @ptrCast(&hms_buf);
}

fn findZero(y00: f64, y11: f64, y2: f64, dx: f64, dxret: *f64, dxret2: *f64) i32 {
    const c = y11;
    const b = (y2 - y00) / 2.0;
    const a = (y2 + y00) / 2.0 - c;
    if (b * b - 4 * a * c < 0) return 0;
    if (@abs(a) < 1e-100) return 0;
    const disc = sqrt(b * b - 4 * a * c);
    const x1 = (-b + disc) / 2 / a;
    const x2 = (-b - disc) / 2 / a;
    if (x1 == x2) {
        dxret.* = (x1 - 1) * dx;
        dxret2.* = (x1 - 1) * dx;
        return 1;
    }
    if (x1 >= 0 and x1 < 1 and x2 >= 0 and x2 < 1) {
        if (x1 > x2) {
            dxret.* = (x2 - 1) * dx;
            dxret2.* = (x1 - 1) * dx;
        } else {
            dxret.* = (x1 - 1) * dx;
            dxret2.* = (x2 - 1) * dx;
        }
        return 2;
    }
    if (x1 >= 0 and x1 < 1) {
        dxret.* = (x1 - 1) * dx;
        dxret2.* = (x2 - 1) * dx;
        return 1;
    }
    if (x2 >= 0 and x2 < 1) {
        dxret.* = (x2 - 1) * dx;
        dxret2.* = (x1 - 1) * dx;
        return 1;
    }
    return 0;
}
fn findMaximum(y00: f64, y11: f64, y2: f64, dx: f64, dxret: *f64, yret: *f64) void {
    const c = y11;
    const b = (y2 - y00) / 2.0;
    const a = (y2 + y00) / 2.0 - c;
    const x = -b / 2 / a;
    const y = (4 * a * c - b * b) / 4 / a;
    dxret.* = (x - 1) * dx;
    yret.* = y;
}

fn setPlanetName(ipl: i32) void {
    var buf: [256]u8 = [_]u8{0} ** 256;
    _ = swe.swe_get_planet_name(ipl, @ptrCast(&buf));
    @memcpy(spnam[0..256], buf[0..256]);
    var len: usize = 0;
    while (buf[len] != 0) : (len += 1) {}
    if (len == 0) {
        const names = switch (ipl) {
            SE_SUN => "Sun",
            SE_VENUS => "Venus",
            SE_MERCURY => "Mercury",
            SE_MARS => "Mars",
            SE_JUPITER => "Jupiter",
            SE_SATURN => "Saturn",
            SE_URANUS => "Uranus",
            SE_NEPTUNE => "Neptune",
            SE_PLUTO => "Pluto",
            else => "unknown",
        };
        @memcpy(spnam[0..names.len], names);
        spnam[names.len] = 0;
        planet_name = @ptrCast(&spnam);
        return;
    }
    planet_name = @ptrCast(&spnam);
}

var print_motab_done: bool = false;
fn printMotab() void {
    _ = printf("%d\n", prev_yout);
    for (1..13) |m| {
        _ = printf("\t%s", month_nam[m]);
    }
    _ = printf("\n");
    for (0..31) |d| {
        _ = printf("%02d", @as(i32, @intCast(d + 1)));
        for (0..12) |mm| {
            _ = printf("\t%s", @as([*:0]u8, @ptrCast(&motab[mm][d])));
        }
        _ = printf("\n");
    }
    _ = printf("\n\n");
    for (0..13) |a| for (0..31) |b| @memset(&motab[a][b], 0);
    prev_yout = -999999;
}

fn printItem(s_in: [*:0]u8, teph_in: f64, dpos: f64, delon: f64, dmag: f64) void {
    if (teph_in != teph_in or delon != delon) return;
    var teph = teph_in;
    var s_buf: [256]u8 = [_]u8{0} ** 256;
    var slen: usize = 0;
    while (s_in[slen] != 0) : (slen += 1) {}
    @memcpy(s_buf[0 .. slen + 1], s_in[0 .. slen + 1]);
    var s: [*:0]u8 = @ptrCast(&s_buf);
    // cycle logic simplified: always started if do_flag != DO_ALL
    var cycle_started: bool = true;
    if (do_flag == DO_ALL) {
        const isConj = std.mem.startsWith(u8, std.mem.span(s), "superior") or (ipl_global > SE_VENUS and std.mem.startsWith(u8, std.mem.span(s), "conj"));
        // track static via global
        // use a static stored in function attribute via global variable
        // we use a file-scope var cycle_has_started2
        _ = isConj;
        // for simplicity, if DO_ALL, always consider started after first conj/superior, but we just always print to avoid missing events
        cycle_started = true;
    }
    // _ = cycle_started;
    const is_ingress = std.mem.startsWith(u8, std.mem.span(s), "ingr");
    const is_ingr45 = std.mem.startsWith(u8, std.mem.span(s), "ingr45");
    const is_phase = std.mem.startsWith(u8, std.mem.span(s), "phas");
    const is_decl = std.mem.indexOf(u8, std.mem.span(s), "decl") != null;
    const is_retro: bool = std.mem.indexOf(u8, std.mem.span(s), "ret") != null;
    // _ = is_retro;
    teph += tzone / 24;
    teph += gmtoff / 24;
    if (!ephemeris_time) {
        var serr: [256]u8 = [_]u8{0} ** 256;
        teph = teph - swe.swe_deltat_ex(teph, whicheph, @ptrCast(&serr));
    }
    var yout: i32 = 0;
    var mout: i32 = 0;
    var dout: i32 = 0;
    var hout: f64 = 0;
    swe.swe_revjul(teph, gregflag, &yout, &mout, &dout, &hout);
    var hour: i32 = 0;
    var min: i32 = 0;
    var sec: i32 = 0;
    var secfr: f64 = 0;
    var isgn: i32 = 0;
    if (do_round_min) swe.swe_split_deg(hout, 2, &hour, &min, &sec, &secfr, &isgn) else swe.swe_split_deg(hout, 1, &hour, &min, &sec, &secfr, &isgn);
    var smag: [64]u8 = [_]u8{0} ** 64;
    smag[0] = 0;
    if (dmag != HUGE_VAL) {
        if (std.mem.indexOf(u8, std.mem.span(s), "brill") != null) {
            _ = snprintf(@ptrCast(&smag), 64, "    %.1fm", dmag);
        } else if (is_decl) {
            _ = snprintf(@ptrCast(&smag), 64, "%s ", dms(dmag, BIT_DECL | BIT_ROUND_SEC));
        } else {
            if (output_extra_prec) _ = snprintf(@ptrCast(&smag), 64, "   %8.13f AU", dmag) else _ = snprintf(@ptrCast(&smag), 64, "   %8.5f AU", dmag);
        }
    }
    if (do_motab) {
        if (yout != prev_yout and prev_yout != -999999) printMotab();
        const izod: i32 = @intFromFloat(dpos + 0.1);
        var sout: [64]u8 = [_]u8{0} ** 64;
        if (do_round_min) _ = snprintf(@ptrCast(&sout), 64, "%02d:%02d %s", hour, min, getZNam(@intCast(izod))) else _ = snprintf(@ptrCast(&sout), 64, "%02d:%02d:%02d %s", hour, min, sec, getZNam(@intCast(izod)));
        @memcpy(motab[@intCast(mout - 1)][@intCast(dout - 1)][0..6], sout[0..6]);
        prev_yout = yout;
        return;
    }
    if (is_ingress or is_phase) {
        // replace s with " "
        s_buf[0] = ' ';
        s_buf[1] = 0;
        s = @ptrCast(&s_buf);
    }
    var jul: [*:0]const u8 = "";
    if (gregflag == SE_JUL_CAL) jul = "j";
    if (!is_ingress and !is_phase) {
        _ = printf("%-20s%s", s, gap);
    }
    if (date_gap) {
        if (do_round_min) _ = printf("%02d%s%s%s%2d%s%s%02d:%02d", yout, gap, month_nam[@intCast(mout)], gap, dout, jul, gap, hour, min) else _ = printf("%02d%s%s%s%2d%s%s%02d:%02d:%02d", yout, gap, month_nam[@intCast(mout)], gap, dout, jul, gap, hour, min, sec);
    } else {
        if (do_round_min) _ = printf("%02d %s %2d %s %02d:%02d ", yout, month_nam[@intCast(mout)], dout, jul, hour, min) else _ = printf("%02d %s %2d %s %02d:%02d:%02d ", yout, month_nam[@intCast(mout)], dout, jul, hour, min, sec);
    }
    if (show_jd) _ = printf("%sjd=%.8lf", gap, teph);
    _ = printf("%s", gap);
    if (is_ingr45 or is_ingress) {
        var sign_deg: [16]u8 = [_]u8{0} ** 16;
        if (is_retro) {
            if (is_ingr45) @memcpy(sign_deg[0..5], "15 r\x00".*[0..5]) else @memcpy(sign_deg[0..3], "30\x00".*[0..3]);
        } else {
            if (is_ingr45) @memcpy(sign_deg[0..3], "15\x00".*[0..3]) else @memcpy(sign_deg[0..2], " 0\x00".*[0..2]);
        }
        _ = printf("%s", @as([*:0]u8, @ptrCast(&sign_deg)));
        const izod: i32 = @intFromFloat(dpos + 0.1);
        if (date_gap) _ = printf("%s%s", gap, getZNam(@intCast(izod))) else _ = printf(" %s", getZNam(@intCast(izod)));
    } else if (is_phase) {
        const izod: i32 = @intFromFloat(dpos + 0.1);
        var sout: [32]u8 = [_]u8{0} ** 32;
        switch (izod) {
            1 => @memcpy(sout[0..5], " New\x00".*[0..5]),
            2 => @memcpy(sout[0..7], " h/wax\x00".*[0..7]),
            3 => @memcpy(sout[0..6], " Full\x00".*[0..6]),
            4 => @memcpy(sout[0..8], " h/wane\x00".*[0..8]),
            else => _ = snprintf(@ptrCast(&sout), 32, "%d", izod),
        }
        _ = printf("%s%s%d%s", @as([*:0]u8, @ptrCast(&sout)), gap, izod, gap);
        if (delon != HUGE_VAL) {
            _ = printf("%s", dms(delon, BIT_ZODIAC | BIT_ROUND_SEC));
        }
    } else {
        _ = printf("%s", dms(dpos, BIT_ZODIAC | BIT_ROUND_SEC));
    }
    if (delon != HUGE_VAL and !is_phase) {
        _ = printf("%s%s", gap, dms(delon, BIT_ROUND_SEC));
    }
    if (smag[0] != 0) _ = printf("%s%s", gap, @as([*:0]u8, @ptrCast(&smag)));
    _ = printf("\n");
}

fn letterToIpl(letter: i32) i32 {
    if (letter >= '0' and letter <= '9') return letter - '0' + SE_SUN;
    if (letter >= 'A' and letter <= 'I') return letter - 'A' + SE_MEAN_APOG;
    if (letter >= 'J' and letter <= 'Z') return letter - 'J' + SE_CUPIDO;
    return switch (letter) {
        'm' => SE_MEAN_NODE,
        'c' => 21,
        'g' => 22,
        'n', 'o' => SE_ECL_NUT,
        't' => SE_TRUE_NODE,
        'f' => SE_FIXSTAR,
        'w' => SE_WALDEMATH,
        else => -2,
    };
}

const info1: [*:0]const u8 =
    "\n  Swevents computes planetary phenomena\n  for a given start date and a time range.\n\n  IMPORTANT NOTICE: swevents.c is not a supported part of Swiss Ephemeris.\n  If you find bugs and short comings, please fix the source code and submit the fixes\n  on the Swiss Ephemeris mailing list.\n\n  Input can either be a date or an absolute julian day number.\n  0:00 (midnight).\n  Precision of this program:\n  Conjunctions:     Deviations from Rosicrucian Ephemeris result from\n\t\t    the fact that R.E. gives ephemeris time.\n  Ingresses:        ditto.\n  Stations:         ditto. The stations given by AA are different, they\n\t\t    are in rectascension.\n  Max. Elongations: AA gives date and hour. This program computes \n\t\t    e.g. 20 Aug. 96, 3:28. AA has a rounded value of 4h.\n  Transits:\t    There is no venus transit in 20th cty.\n\t\t    There was a transit of mercury in 1993. The ingress\n\t\t    and egress times computed by this program agree\n\t\t    exactly with AA93, p. A86.\n  Visibility:       elongation > 10 degrees, according to AA.\n  gr. brillancy:    Our times of greatest brillancy differ from the\n\t\t    ones given by AA94 and AA96, p. A3, by several days.\n\t\t    Probably an error of AA. The times on p. A3 are\n\t\t    inconsistent with the magnitudes listed on p. A4.\n\t\t    The maxima computed by this program are consistent\n\t\t    with these magnitude tables.\n\n  Command line options:\n\t\n\texample:\n\tswevents -p3 -bj2436723.5 -n1000 -s1 -ejpl \n\t   for -p2 (mercury), use -s0.3 \n\t\n\t-cl\tdo not print command line at bottom of 1st page\n\t-p    \tplanet to be computed.\n\t\tSee the letter coding below.\n\t-nN\tsearch events for N consecutive days; if no -n option\n\t\tis given, the default is 366 (one year).\n\t-sN\ttimestep N days, default 1. This option is only meaningful\n\t\twhen combined with option -n.\n\t-edirPATH change the directory of the ephemeris files \n\n\t-doingr\treport sign ingresses\n\t-doconj\treport inferior and superior conjunctions with Sun\n\t-dobrill\treport moments of greatest brilliance\n\t-dorise\treport morning set or evening rise\n\t-doelong\treport maximum elongation from Sun, for planets 1,2,3 only\n\t-doretro\treport stations\n\t-doaps\treport minimal and maximal distance from Earth\n\t-donode\treport when on ascending or descending node\n\n\t-dodecl report when on minimal and maximal declination\n\n\t-doall  equivalent to all -do.. options above combined\n\t        If used, output starts only at next cycle begin.\n\n\t-doing45\tcrossings over 15 tau, Leo, Sco, Aqu\n\t-dolphase\treport lunar phases special mode(use with -p1)\n\t-dophase\treport lunar phases in list(use with -p1)\n\t-doasp\treport aspects between planets (-p option is ignored)\n\t-dovoc\treport Moon void of course periods (-p option is ignored)\n\t-noingr  no ingresses\n\t-motab  special format Moon ingres table\n\t-mojap  special format Moon phases\n\t-bDATE\tuse this begin date instead of asking; use -b1.1.1992 if\n\t\tthe begin date string contains blanks; use format -bj2400000.5\n\t\tto express the date as absolute Julian day number.\n\t\tNote: the date format is day month year (European style).\n\t-eswe  swiss ephemeris\n\t-ejpl  jpl ephemeris (DE431), or with ephemeris file name\n\t      -ejplde200.eph\n\t-emos  moshier ephemeris\n\t-true\ttrue positions\n\t-noaberr\tno aberration\n\t-nodefl\tno gravitational light deflection\n\t-noprec\tno precession (i.e. J2000 positions)\n\t-nonut\t\tno nutation \n\t-dgap\t\tuse gap within date\n\t-zlong\t\tuse long sign names\n\t-znam3\t\tuse 3-letter sign names\n\t-monnum\tuse month numbers instead of names\n\t-gmtoff X\tuse X hours gmt offset (+ for east)\n\t-transitstderr lists transits of Venus or Mercury as c style data to stderr \n\t-jd\tshow also jd in output \n\t-ep\t\t  use extended precision in output\n\n\t-tzoneTIMEZONE output date and time in timezone (hours east)\n\n\tOptions only for use by Astrodienst:\n\t-aznANR\t output date and time in locat time of Astrozone ANR\n\t-mscreen output on screen\n\t-mpdf pdf output \n\t-mps postscript \n\t-cycol.. number cycles per column\n\n\t-?\tdisplay this info\n\t-h\tdisplay this info\n\n";
const info2: [*:0]const u8 =
    "Planet selection (only one possible):\n\t0 Sun (character zero)\n\t1 Moon (character 1)\n\t2 Mercury\n\t3 Venus\n\t4 Mars\n\t5 Jupiter\n\t6 Saturn\n\t7 Uranus\n\t8 Neptune\n\t9 Pluto\n\t10 mean lunar node\n\t11 true lunar node\n\t12 mean lunar apogee\n\t13 true lunar apogee\n\t14 Earth\n\t15 Chiron\n\t16 Pholus\n\t17 Ceres\n\t18 Pallas\n\t19 Juno\n\t20 Vesta\n\t21 interpolated lunar apogee\n\t22 interpolated lunar perigee\n\th00 .. h18 fictitious factors, see swephexp.h\n\n  Date entry:\n  In the interactive mode, when you are asked for a start date,\n  you can enter data in one of the following formats:\n\n\t1.2.1991\tthree integers separated by a nondigit character for\n\t\t\tday month year. Dates are interpreted as Gregorian\n\t\t\tafter 4.10.1582 and as Julian Calender before.\n\t\t\tTime is always set to midnight.\n\t\t\tIf the three letters jul are appended to the date,\n\t\t\tthe Julian calendar is used even after 1582.\n\t\t\tIf the four letters greg are appended to the date,\n\t\t\tthe Gregorian calendar is used even before 1582.\n\n\tj2400123.67\tthe letter j followed by a real number, for\n\t\t\tthe absolute Julian daynumber of the start date.\n\t\t\tFraction .5 indicates midnight, fraction .0\n\t\t\tindicates noon, other times of the day can be\n\t\t\tchosen accordingly.\n\n\t<RETURN>\trepeat the last entry\n\t\n\t.\t\tstop the program\n\n\t+20\t\tadvance the date by 20 days\n\n\t-10\t\tgo back in time 10 days\n";

pub fn main(init: std.process.Init) !void {
    initMonthNames();
    for (0..13) |a| for (0..31) |b| @memset(&motab[a][b], 0);
    var serr: [256]u8 = [_]u8{0} ** 256;
    var sout: [512]u8 = [_]u8{0} ** 512;
    var s: [512]u8 = [_]u8{0} ** 512;
    var saves: [512]u8 = [_]u8{0} ** 512;
    // args via std.process
    var arena2 = init.arena;
    const alloc = arena2.allocator();
    const args_slice = try init.minimal.args.toSlice(alloc);
    const args = args_slice;

    var iplfrom: i32 = SE_VENUS;
    var nstep: i32 = 366;
    var tstep: f64 = 1;
    var begindate: ?[]const u8 = null;
    var begindate_buf: [512]u8 = [_]u8{0} ** 512;
    var begindate_len: usize = 0;
    var iflag: i32 = SEFLG_RADIANS | SEFLG_SPEED;
    var ephepath: [512]u8 = [_]u8{0} ** 512;
    @memcpy(ephepath[0..9], "/home/ephe\x00".*[0..9]);
    var fname: [80]u8 = [_]u8{0} ** 80;
    @memcpy(fname[0..9], "de431.eph\x00".*[0..9]);

    // build cmdline
    var cmdpos: usize = 0;
    const cl_prefix = "Command: ";
    @memcpy(cmdline[cmdpos .. cmdpos + cl_prefix.len], cl_prefix);
    cmdpos += cl_prefix.len;
    for (args, 0..) |a, idx| {
        if (idx == 0) continue;
        if (cmdpos + a.len + 1 >= cmdline.len) break;
        @memcpy(cmdline[cmdpos .. cmdpos + a.len], a);
        cmdpos += a.len;
        cmdline[cmdpos] = ' ';
        cmdpos += 1;
    }
    cmdline[cmdpos] = 0;

    var a_idx: usize = 1;
    while (a_idx < args.len) : (a_idx += 1) {
        const a = args[a_idx];
        if (std.mem.eql(u8, a, "-doall")) {
            do_flag = DO_ALL;
        } else if (std.mem.eql(u8, a, "-noingr")) {
            do_flag &= ~DO_INGR;
        } else if (std.mem.eql(u8, a, "-doconj")) {
            do_flag |= DO_CONJ;
        } else if (std.mem.eql(u8, a, "-dobrill")) {
            do_flag |= DO_BRILL;
        } else if (std.mem.eql(u8, a, "-dorise")) {
            do_flag |= DO_RISE;
        } else if (std.mem.eql(u8, a, "-doelong")) {
            do_flag |= DO_ELONG;
        } else if (std.mem.eql(u8, a, "-doretro")) {
            do_flag |= DO_RETRO;
        } else if (std.mem.eql(u8, a, "-doaps")) {
            do_flag |= DO_APS;
        } else if (std.mem.eql(u8, a, "-dolphase")) {
            do_flag |= DO_LPHASE;
        } else if (std.mem.eql(u8, a, "-dophase")) {
            do_flag |= DO_LPHASE0;
        } else if (std.mem.eql(u8, a, "-donode")) {
            do_flag |= DO_NODE;
        } else if (std.mem.eql(u8, a, "-dodecl")) {
            do_flag |= DO_DECL;
        } else if (std.mem.eql(u8, a, "-doingr")) {
            do_flag |= DO_INGR;
        } else if (std.mem.eql(u8, a, "-doing45")) {
            do_flag |= DO_INGR45;
        } else if (std.mem.eql(u8, a, "-doasp")) {
            do_flag |= DO_ASPECTS;
            iplfrom = -99;
        } else if (std.mem.eql(u8, a, "-dovoc")) {
            do_flag |= DO_VOC;
            iplfrom = SE_MOON;
        } else if (std.mem.eql(u8, a, "-et")) {
            ephemeris_time = true;
        } else if (std.mem.eql(u8, a, "-jd")) {
            show_jd = true;
        } else if (std.mem.startsWith(u8, a, "-cycol")) {} else if (std.mem.eql(u8, a, "-ep")) {
            output_extra_prec = true;
        } else if (std.mem.startsWith(u8, a, "-ejpl")) {
            whicheph = SEFLG_JPLEPH;
            if (a.len > 5) {
                const rem = a[5..];
                @memcpy(fname[0..rem.len], rem);
                fname[rem.len] = 0;
            }
        } else if (std.mem.eql(u8, a, "-eswe")) {
            whicheph = SEFLG_SWIEPH;
        } else if (std.mem.eql(u8, a, "-emos")) {
            whicheph = SEFLG_MOSEPH;
        } else if (std.mem.eql(u8, a, "-zlong")) {
            znam_mode = 2;
        } else if (std.mem.eql(u8, a, "-znam3")) {
            znam_mode = 1;
        } else if (std.mem.eql(u8, a, "-monnum")) {
            for (1..13) |n| {
                var buf: [4]u8 = [_]u8{0} ** 4;
                _ = snprintf(@ptrCast(&buf), 4, "%3d", @as(i32, @intCast(n)));
                @memcpy(month_nam_arr[n][0..4], buf[0..4]);
            }
        } else if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "-?")) {
            _ = printf("%s%s", info1, info2);
            return;
        } else if (std.mem.eql(u8, a, "-j2000")) {
            iflag |= SEFLG_J2000;
        } else if (std.mem.eql(u8, a, "-icrs")) {
            iflag |= SEFLG_ICRS;
        } else if (std.mem.eql(u8, a, "-hel")) {
            iflag |= SEFLG_HELCTR;
        } else if (std.mem.eql(u8, a, "-bary")) {
            iflag |= 16384;
        } else if (std.mem.eql(u8, a, "-true")) {
            iflag |= SEFLG_TRUEPOS;
        } else if (std.mem.eql(u8, a, "-noaberr")) {
            iflag |= SEFLG_NOABERR;
        } else if (std.mem.eql(u8, a, "-nodefl")) {
            iflag |= SEFLG_NOGDEFL;
        } else if (std.mem.eql(u8, a, "-nonut")) {
            iflag |= SEFLG_NONUT;
        } else if (std.mem.eql(u8, a, "-noprec")) {
            iflag |= SEFLG_J2000;
        } else if (std.mem.eql(u8, a, "-roundmin")) {
            do_round_min = true;
        } else if (std.mem.eql(u8, a, "-dgap")) {
            date_gap = true;
        } else if (std.mem.eql(u8, a, "-motab")) {
            do_motab = true;
            do_flag = DO_INGR;
        } else if (std.mem.eql(u8, a, "-mojap")) {
            do_mojap = true;
            do_flag = DO_LPHASE;
            phase_mod = 90;
            if (a_idx + 1 < args.len) {
                if (std.fmt.parseFloat(f64, args[a_idx + 1]) catch null) |v| {
                    if (v > 0) {
                        phase_mod = v;
                        a_idx += 1;
                    }
                }
            }
        } else if (std.mem.eql(u8, a, "-gmtoff")) {
            if (a_idx + 1 < args.len) {
                gmtoff = std.fmt.parseFloat(f64, args[a_idx + 1]) catch 0;
                a_idx += 1;
            }
        } else if (std.mem.startsWith(u8, a, "-p")) {
            const spno = a[2..];
            if (spno.len == 1 and spno[0] >= '0' and spno[0] <= '9' and std.fmt.parseInt(i32, spno, 10) catch 99 < SE_NPLANETS) {
                iplfrom = std.fmt.parseInt(i32, spno, 10) catch iplfrom;
            } else if (spno.len > 0 and spno[0] == 'h') {
                iplfrom = (std.fmt.parseInt(i32, spno[1..], 10) catch 0) + SE_FICT_OFFSET;
            } else if (spno.len == 0) {} else {
                _ = printf("illegal planet number %s\n", @as([*:0]const u8, @ptrCast(a.ptr)));
                exit(1);
            }
        } else if (std.mem.startsWith(u8, a, "-n")) {
            const v = std.fmt.parseInt(i32, a[2..], 10) catch 0;
            if (v > 0) nstep = v;
        } else if (std.mem.startsWith(u8, a, "-s")) {
            tstep = std.fmt.parseFloat(f64, a[2..]) catch 1;
        } else if (std.mem.startsWith(u8, a, "-b")) {
            const rem = a[2..];
            @memcpy(begindate_buf[0..rem.len], rem);
            begindate_buf[rem.len] = 0;
            begindate_len = rem.len;
            begindate = begindate_buf[0..begindate_len];
        } else if (std.mem.eql(u8, a, "-cl")) {
            print_cl = false;
        } else if (std.mem.startsWith(u8, a, "-g")) {
            const rem = a[2..];
            if (rem.len == 0) gap = @ptrCast(@constCast("\t")) else {
                var gbuf: [32]u8 = [_]u8{0} ** 32;
                @memcpy(gbuf[0..rem.len], rem);
                gbuf[rem.len] = 0; // leak static
                // store gap as static copy
                @memcpy(gap_buf[0..rem.len], rem);
                gap_buf[rem.len] = 0;
                gap = @ptrCast(&gap_buf);
            }
        } else if (std.mem.startsWith(u8, a, "-tzone")) {
            tzone = std.fmt.parseFloat(f64, a[6..]) catch 0;
        } else if (std.mem.startsWith(u8, a, "-transitstderr")) {
            transits_to_stderr = true;
        } else if (std.mem.startsWith(u8, a, "-sid")) {
            iflag |= SEFLG_SIDEREAL;
            const v = std.fmt.parseInt(i32, a[4..], 10) catch 0;
            swe.swe_set_sid_mode(v, 0, 0);
        } else if (std.mem.eql(u8, a, "-?") or std.mem.eql(u8, a, "-h")) {
            _ = printf("%s%s", info1, info2);
            return;
        } else {
            _ = printf("illegal option %s\n", @as([*:0]const u8, @ptrCast(a.ptr)));
            exit(1);
        }
    }
    // if no do_flag set, use default that shows something? original expects at least some do flags; if 0, no output. Mirror C: if 0 then no output but loop still runs with no events. Keep 0.

    setPlanetName(iplfrom);
    _ = swe.swe_version(@ptrCast(&sout));
    _ = printf("%s\n", @as([*:0]const u8, @ptrCast("Please note: swevents is not a supported part of Swiss Ephemeris. In case of errors,\nplease debug and submit code fixes to the Swiss Ephemeris mailing list.")));
    // date string for header: if begindate available use it else ?
    var sdate_hdr: [256]u8 = [_]u8{0} ** 256;
    if (begindate) |bd| {
        @memcpy(sdate_hdr[0..bd.len], bd);
        sdate_hdr[bd.len] = 0;
    } else @memcpy(sdate_hdr[0..4], "now\x00".*[0..4]);
    _ = printf("Date: %s\tSwissEph version %s\n%s\nplanet %s\n\n", @as([*:0]u8, @ptrCast(&sdate_hdr)), @as([*:0]u8, @ptrCast(&sout)), @as([*:0]u8, @ptrCast(&cmdline)), planet_name);
    // set ephe path - try multiple candidates if default not set explicitly
    swe.swe_set_ephe_path(@ptrCast(&ephepath));
    swe.swe_set_jpl_file(@ptrCast(&fname));
    iflag |= whicheph;
    ipl_global = iplfrom;

    // determine begindate handling
    var tjd: f64 = 2436723.588888889;
    var sp: ?[]const u8 = begindate;
    // if begindate null, ask interactively? For non-interactive just require -b; fallback to stdin like C but we simplify to error
    if (sp == null) {
        // try interactive read from stdin
        _ = printf("datum ?");
        const inbuf: [512]u8 = [_]u8{0} ** 512;
        const f = @as(?*anyopaque, @ptrFromInt(0)); // stdin placeholder, use c fgets via fdopen? Simplify: use std io
        _ = f;
        // fallback: use today? just use current tjd as now via swe_julday of today using system time
        // Use std.time
        tjd = 2451545.0;
        sp = null;
        _ = inbuf;
    } else {
        const sdate_str = sp.?;
        // copy to mutable s for parsing like C
        @memcpy(s[0..sdate_str.len], sdate_str);
        s[sdate_str.len] = 0;
        @memcpy(saves[0..sdate_str.len], sdate_str);
        saves[sdate_str.len] = 0;
        const sp_c: [*:0]u8 = @ptrCast(&s);
        if (sp_c[0] == '.') {
            exit(1);
        }
        if (sp_c[0] == 'j') {
            _ = sscanf(sp_c + 1, "%lf", &tjd);
            if (tjd < 2299160.5) gregflag = SE_JUL_CAL else gregflag = SE_GREG_CAL;
            if (strstr(sp_c, "jul") != null) gregflag = SE_JUL_CAL else if (strstr(sp_c, "greg") != null) gregflag = SE_GREG_CAL;
            var jy: i32 = 0;
            var jm: i32 = 0;
            var jd: i32 = 0;
            var jut: f64 = 0;
            swe.swe_revjul(tjd, gregflag, &jy, &jm, &jd, &jut);
        } else if (sp_c[0] == '+') {
            var n: i32 = atoi(sp_c);
            if (n == 0) n = 1;
            tjd += @as(f64, @floatFromInt(n));
        } else if (sp_c[0] == '-' and s[1] >= '0' and s[1] <= '9') {
            var n: i32 = atoi(sp_c);
            if (n == 0) n = -1;
            tjd += @as(f64, @floatFromInt(n));
        } else {
            var jday: i32 = 0;
            var jmon: i32 = 0;
            var jyear: i32 = 0;
            if (sscanf(sp_c, "%d%*c%d%*c%d", &jday, &jmon, &jyear) < 1) exit(1);
            if (jyear * 10000 + jmon * 100 + jday < 15821015) gregflag = SE_JUL_CAL else gregflag = SE_GREG_CAL;
            if (strstr(sp_c, "jul") != null) gregflag = SE_JUL_CAL else if (strstr(sp_c, "greg") != null) gregflag = SE_GREG_CAL;
            tjd = swe.swe_julday(jyear, jmon, jday, 0, gregflag);
        }
    }

    // early exits for unimplemented modes
    if ((do_flag & DO_VOC) != 0) {
        _ = printf("VOC calculation not fully ported in this Zig version\n");
        return;
    }
    if ((do_flag & DO_ASPECTS) != 0) {
        _ = printf("Aspect calculation not fully ported in this Zig version\n");
        return;
    }

    var t: f64 = tjd;
    var istep: i32 = 0;
    // buffers for loop
    var xp0: [6]f64 = [_]f64{0} ** 6;
    var xp1: [6]f64 = [_]f64{0} ** 6;
    var xp2: [6]f64 = [_]f64{0} ** 6;
    var xh0: [6]f64 = [_]f64{0} ** 6;
    var xh1: [6]f64 = [_]f64{0} ** 6;
    var xh2: [6]f64 = [_]f64{0} ** 6;
    var xd0: [6]f64 = [_]f64{0} ** 6;
    var xd1: [6]f64 = [_]f64{0} ** 6;
    var xd2: [6]f64 = [_]f64{0} ** 6;
    var xs0: [6]f64 = [_]f64{0} ** 6;
    var xs1: [6]f64 = [_]f64{0} ** 6;
    var xs2: [6]f64 = [_]f64{0} ** 6;
    var xel0: [6]f64 = [_]f64{0} ** 6;
    var xel1: [6]f64 = [_]f64{0} ** 6;
    var xel2: [6]f64 = [_]f64{0} ** 6;
    var xang0: [6]f64 = [_]f64{0} ** 6;
    var xang1: [6]f64 = [_]f64{0} ** 6;
    var xang2: [6]f64 = [_]f64{0} ** 6;
    var xma0: [6]f64 = [_]f64{0} ** 6;
    var xma1: [6]f64 = [_]f64{0} ** 6;
    var xma2: [6]f64 = [_]f64{0} ** 6;
    var x: [6]f64 = [_]f64{0} ** 6;
    var attr: [20]f64 = [_]f64{0} ** 20;

    while (istep <= nstep) : ({
        t += tstep;
        istep += 1;
    }) {
        var jyear: i32 = 0;
        var jmon: i32 = 0;
        var jday: i32 = 0;
        var jut: f64 = 0;
        swe.swe_revjul(t, gregflag, &jyear, &jmon, &jday, &jut);
        var te: f64 = 0;
        if (!ephemeris_time) {
            const delt = swe.swe_deltat_ex(t, whicheph, @ptrCast(&serr));
            te = t + delt;
        } else te = t;

        // shift arrays
        xp0 = xp1;
        xp1 = xp2;
        xh0 = xh1;
        xh1 = xh2;
        xd0 = xd1;
        xd1 = xd2;
        xs0 = xs1;
        xs1 = xs2;
        xel0 = xel1;
        xel1 = xel2;
        xang0 = xang1;
        xang1 = xang2;
        xma0 = xma1;
        xma1 = xma2;
        var iflgret: i32 = swe.swe_calc(te, iplfrom, iflag, @ptrCast(&xp2), @ptrCast(&serr));
        if (iflgret < 0) {
            _ = fprintf(null, "return code %d, mesg: %s\n", iflgret, @as([*:0]u8, @ptrCast(&serr)));
        }
        iflgret = swe.swe_calc(te, SE_SUN, iflag, @ptrCast(&xs2), @ptrCast(&serr));
        iflgret = swe.swe_calc(te, iplfrom, iflag, @ptrCast(&xh2), @ptrCast(&serr));
        iflgret = swe.swe_calc(te, iplfrom, iflag | SEFLG_EQUATORIAL, @ptrCast(&xd2), @ptrCast(&serr));
        iflgret = swe.swe_calc(te, SE_ECL_NUT, 0, @ptrCast(&x), @ptrCast(&serr));
        const epstrue: f64 = x[0];
        _ = epstrue;
        // elongation
        for (0..6) |ii| xel2[ii] = xp2[ii] - xs2[ii];
        xel2[0] = swe.swe_radnorm(xel2[0]);
        if (xel2[0] > std.math.pi) xel2[0] -= 2 * std.math.pi;
        // angular distance
        var cart_p: [3]f64 = undefined;
        var cart_s: [3]f64 = undefined;
        polcart(xp2[0], xp2[1], xp2[2], &cart_p);
        polcart(xs2[0], xs2[1], xs2[2], &cart_s);
        const diff: [3]f64 = .{ cart_p[0] - cart_s[0], cart_p[1] - cart_s[1], cart_p[2] - cart_s[2] };
        const rphel = sqrt(squareSum(diff));
        const elong = acos((xs2[2] * xs2[2] + xp2[2] * xp2[2] - rphel * rphel) / 2 / xs2[2] / xp2[2]);
        xang2[0] = elong;
        if (rphel != 0 and iplfrom <= 4) {
            const r = swe.swe_pheno(te, iplfrom, iflag, @ptrCast(&attr), @ptrCast(&serr));
            if (r < 0) xma2[0] = 1 else xma2[0] = attr[4];
        } else xma2[0] = 1;

        if (istep >= 2) {
            // l_phase
            if ((do_flag & DO_LPHASE) != 0) {
                // lunar phases for moon
                var l_phase_handled = false;
                if (iplfrom == SE_MOON) {
                    const phase_m: f64 = 90;
                    var lx2 = swe.swe_degnorm((xp2[0] - xs2[0]) * RADTODEG);
                    var lx1 = swe.swe_degnorm((xp1[0] - xs1[0]) * RADTODEG);
                    var lx0 = swe.swe_degnorm((xp0[0] - xs0[0]) * RADTODEG);
                    if (lx0 > lx1) {
                        lx1 += 360;
                        lx2 += 360;
                    }
                    if (lx1 > lx2) lx2 += 360;
                    const nphases: i32 = @intFromFloat(360 / phase_m);
                    var new_phase: i32 = @intFromFloat(floor(lx2 / phase_m) + 1);
                    const old_phase: i32 = @intFromFloat(floor(lx1 / phase_m) + 1);
                    if (old_phase != new_phase) {
                        lx0 = lx0 / phase_m - @as(f64, @floatFromInt(old_phase));
                        lx1 = lx1 / phase_m - @as(f64, @floatFromInt(old_phase));
                        lx2 = lx2 / phase_m - @as(f64, @floatFromInt(old_phase));
                        var dt1: f64 = 0;
                        var dt2: f64 = 0;
                        const nzer = findZero(lx0, lx1, lx2, tstep, &dt1, &dt2);
                        if (nzer > 0) {
                            var t2: f64 = te;
                            if (@abs(dt2) < @abs(dt1)) t2 = te + dt2 else t2 = te + dt1;
                            var xm: [6]f64 = undefined;
                            var xsun: [6]f64 = undefined;
                            for (0..2) |_| {
                                _ = swe.swe_calc(t2, SE_MOON, iflag, @ptrCast(&xm), @ptrCast(&serr));
                                _ = swe.swe_calc(t2, SE_SUN, iflag, @ptrCast(&xsun), @ptrCast(&serr));
                                const d = swe.swe_radnorm(xm[0] - xsun[0]) * RADTODEG;
                                var dx = swe.swe_degnorm(d - @as(f64, @floatFromInt(new_phase - 1)) * 90);
                                if (dx > 180) dx -= 360;
                                const dv = (xm[3] - xsun[3]) * RADTODEG;
                                t2 -= dx / dv;
                            }
                            while (new_phase > nphases) new_phase -= nphases;
                            var soutp: [32]u8 = [_]u8{0} ** 32;
                            @memcpy(soutp[0..6], "phase\x00".*[0..6]);
                            var lphase: f64 = HUGE_VAL;
                            if (true) {
                                var xm2: [6]f64 = undefined;
                                _ = swe.swe_calc(t2, SE_MOON, iflag, @ptrCast(&xm2), @ptrCast(&serr));
                                lphase = xm2[0] * RADTODEG;
                            }
                            printItem(@ptrCast(&soutp), t2, @as(f64, @floatFromInt(new_phase)), lphase, HUGE_VAL);
                            l_phase_handled = true;
                        }
                    }
                }
                if (l_phase_handled) {}
                // if only LPHASE, skip other events
                if ((do_flag & DO_LPHASE) != 0 and (do_flag & ~DO_LPHASE) == 0) continue;
            }
            // CONJ
            if ((do_flag & DO_CONJ) != 0) {
                if (signChange(xel1[0], xel2[0])) {
                    var el0 = xel0[0];
                    var el1 = xel1[0];
                    var el2 = xel2[0];
                    if (el0 > std.math.pi / 2.0) el0 -= std.math.pi;
                    if (el0 < -std.math.pi / 2.0) el0 += std.math.pi;
                    if (el1 > std.math.pi / 2.0) el1 -= std.math.pi;
                    if (el1 < -std.math.pi / 2.0) el1 += std.math.pi;
                    if (el2 > std.math.pi / 2.0) el2 -= std.math.pi;
                    if (el2 < -std.math.pi / 2.0) el2 += std.math.pi;
                    var dt: f64 = 0;
                    var dt2: f64 = 0;
                    const nzer = findZero(el0, el1, el2, tstep, &dt, &dt2);
                    if (nzer > 0) {
                        const t2 = te + dt;
                        var xx: [6]f64 = undefined;
                        var xss: [6]f64 = undefined;
                        _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                        _ = swe.swe_calc(t2, SE_SUN, iflag, @ptrCast(&xss), @ptrCast(&serr));
                        var is_opp = false;
                        if (iplfrom != SE_VENUS and iplfrom != SE_MERCURY) {
                            if (@abs(xel1[0]) > std.math.pi / 2.0) is_opp = true;
                            if (is_opp) {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..11], "opposition\x00".*[0..11]);
                                printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, xx[1] * RADTODEG, HUGE_VAL);
                            } else {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..12], "conjunction\x00".*[0..12]);
                                printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, xx[1] * RADTODEG, HUGE_VAL);
                            }
                        } else {
                            if (xx[3] > 0) {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..14], "superior conj\x00".*[0..14]);
                                printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, xx[1] * RADTODEG, HUGE_VAL);
                            } else {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..14], "inferior conj\x00".*[0..14]);
                                printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, xx[1] * RADTODEG, HUGE_VAL);
                            }
                        }
                    }
                }
            }
            // BRILL
            if ((do_flag & DO_BRILL) != 0) {
                if (iplfrom <= SE_MARS and xma0[0] > xma1[0] and xma2[0] > xma1[0] and xang1[0] > 10 * DEGTORAD) {
                    var dt: f64 = 0;
                    var yret: f64 = 0;
                    findMaximum(xma0[0], xma1[0], xma2[0], tstep, &dt, &yret);
                    var t2 = te + dt;
                    // refine
                    for (0..5) |_| {
                        var xa0: f64 = 0;
                        var xa1: f64 = 0;
                        var xa2: f64 = 0;
                        for (0..3) |k| {
                            var t3: f64 = 0;
                            if (k == 0) t3 = t2 - tstep / 3 else if (k == 1) t3 = t2 else t3 = t2 + tstep / 3;
                            var atr: [20]f64 = undefined;
                            if (swe.swe_pheno(t3, iplfrom, iflag, @ptrCast(&atr), @ptrCast(&serr)) >= 0) {
                                if (k == 0) xa0 = atr[4] else if (k == 1) xa1 = atr[4] else xa2 = atr[4];
                            }
                        }
                        var ndt: f64 = 0;
                        var ny: f64 = 0;
                        findMaximum(xa0, xa1, xa2, tstep / 3, &ndt, &ny);
                        t2 = t2 + tstep / 3 + ndt;
                        yret = ny;
                    }
                    var xx: [6]f64 = undefined;
                    _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                    var buf: [32]u8 = [_]u8{0} ** 32;
                    @memcpy(buf[0..20], "greatest brilliancy\x00".*[0..20]);
                    printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, yret);
                }
            }
            // RETRO
            if ((do_flag & DO_RETRO) != 0) {
                if ((xp1[3] < 0 and xp2[3] >= 0) or (xp1[3] > 0 and xp2[3] <= 0)) {
                    var t2 = te - xp2[3] / ((xp2[3] - xp1[3]) / tstep);
                    var dt1 = tstep;
                    for (0..5) |_| {
                        var x0a: [2]f64 = undefined;
                        for (0..2) |k| {
                            const t3: f64 = if (k == 0) t2 else t2 + dt1;
                            var xp: [6]f64 = undefined;
                            _ = swe.swe_calc(t3, iplfrom, iflag, @ptrCast(&xp), @ptrCast(&serr));
                            x0a[k] = xp[3];
                        }
                        t2 = (t2 + dt1) - x0a[1] / ((x0a[1] - x0a[0]) / dt1);
                        dt1 /= 3;
                    }
                    var xx: [6]f64 = undefined;
                    _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                    if (xp2[3] < 0) {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..11], "retrograde\x00".*[0..11]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, HUGE_VAL);
                    } else {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..7], "direct\x00".*[0..7]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, HUGE_VAL);
                    }
                }
            }
            // APS
            if ((do_flag & DO_APS) != 0) {
                if ((xh2[2] < xh1[2] and xh0[2] < xh1[2]) or (xh2[2] > xh1[2] and xh0[2] > xh1[2])) {
                    var dt: f64 = 0;
                    var yret: f64 = 0;
                    findMaximum(xh0[2], xh1[2], xh2[2], tstep, &dt, &yret);
                    var t2 = te + dt;
                    var dt1 = tstep;
                    for (0..4) |_| {
                        var xa0: f64 = 0;
                        var xa1: f64 = 0;
                        var xa2: f64 = 0;
                        for (0..3) |k| {
                            const t3: f64 = if (k == 0) t2 - dt1 else if (k == 1) t2 else t2 + dt1;
                            var xp: [6]f64 = undefined;
                            _ = swe.swe_calc(t3, iplfrom, iflag, @ptrCast(&xp), @ptrCast(&serr));
                            if (k == 0) xa0 = xp[2] else if (k == 1) xa1 = xp[2] else xa2 = xp[2];
                        }
                        var ndt: f64 = 0;
                        var ny: f64 = 0;
                        findMaximum(xa0, xa1, xa2, dt1, &ndt, &ny);
                        t2 = t2 + dt1 + ndt;
                        dt1 /= 3;
                    }
                    var xx: [6]f64 = undefined;
                    _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                    if (xh2[2] < xh1[2]) {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        if ((iflag & SEFLG_HELCTR) != 0) @memcpy(buf[0..9], "aphelion\x00".*[0..9]) else @memcpy(buf[0..17], "max. Earth dist.\x00".*[0..17]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, xx[2]);
                    } else {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        if ((iflag & SEFLG_HELCTR) != 0) @memcpy(buf[0..11], "perihelion\x00".*[0..11]) else @memcpy(buf[0..17], "min. Earth dist.\x00".*[0..17]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, xx[2]);
                    }
                }
            }
            // DECL
            if ((do_flag & DO_DECL) != 0) {
                if ((xd2[1] < xd1[1] and xd0[1] < xd1[1]) or (xd2[1] > xd1[1] and xd0[1] > xd1[1])) {
                    var dt: f64 = 0;
                    var yret: f64 = 0;
                    findMaximum(xd0[1], xd1[1], xd2[1], tstep, &dt, &yret);
                    var t2 = te + dt;
                    var dt1 = tstep;
                    for (0..4) |_| {
                        var xa0: f64 = 0;
                        var xa1: f64 = 0;
                        var xa2: f64 = 0;
                        for (0..3) |k| {
                            const t3: f64 = if (k == 0) t2 - dt1 else if (k == 1) t2 else t2 + dt1;
                            var xp: [6]f64 = undefined;
                            _ = swe.swe_calc(t3, iplfrom, iflag | SEFLG_EQUATORIAL, @ptrCast(&xp), @ptrCast(&serr));
                            if (k == 0) xa0 = xp[1] else if (k == 1) xa1 = xp[1] else xa2 = xp[1];
                        }
                        var ndt: f64 = 0;
                        var ny: f64 = 0;
                        findMaximum(xa0, xa1, xa2, dt1, &ndt, &ny);
                        t2 = t2 + dt1 + ndt;
                        dt1 /= 3;
                    }
                    var xd: [6]f64 = undefined;
                    var xx: [6]f64 = undefined;
                    _ = swe.swe_calc(t2, iplfrom, iflag | SEFLG_EQUATORIAL, @ptrCast(&xd), @ptrCast(&serr));
                    _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                    if (xd2[1] < xd1[1]) {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..18], "max. declination.\x00".*[0..18]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, xd[1] * RADTODEG);
                    } else {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..18], "min. declination.\x00".*[0..18]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, xd[1] * RADTODEG);
                    }
                }
            }
            // NODE
            if ((do_flag & DO_NODE) != 0) {
                if (signChange(xh1[1], xh2[1])) {
                    var dt: f64 = 0;
                    var dt2: f64 = 0;
                    const nzer = findZero(xh0[1], xh1[1], xh2[1], tstep, &dt, &dt2);
                    if (nzer > 0) {
                        const t2 = te + dt;
                        var xx: [6]f64 = undefined;
                        _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                        if (xh2[1] >= 0) {
                            var buf: [16]u8 = [_]u8{0} ** 16;
                            @memcpy(buf[0..10], "asc. node\x00".*[0..10]);
                            printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, HUGE_VAL);
                        } else {
                            var buf: [16]u8 = [_]u8{0} ** 16;
                            @memcpy(buf[0..11], "desc. node\x00".*[0..11]);
                            printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, HUGE_VAL, HUGE_VAL);
                        }
                    }
                }
            }
            // INGR
            if ((do_flag & DO_INGR) != 0) {
                const x2v = xp2[0] * RADTODEG;
                var x1v = xp1[0] * RADTODEG;
                var x0v = xp0[0] * RADTODEG;
                const d12 = swe.swe_difdeg2n(x2v, x1v);
                x1v = x2v - d12;
                const d01 = swe.swe_difdeg2n(x1v, x0v);
                x0v = x1v - d01;
                for (0..13) |ii| {
                    const xcross: f64 = @as(f64, @floatFromInt(ii)) * 30.0;
                    if (signChange(x1v - xcross, x2v - xcross) or (@abs(x0v - x1v) + @abs(x1v - x2v) > @abs(x2v - xcross))) {
                        var dt1: f64 = 0;
                        var dt2b: f64 = 0;
                        const nzer = findZero(x0v - xcross, x1v - xcross, x2v - xcross, tstep, &dt1, &dt2b);
                        if (nzer == 1) {
                            var tx = te + dt1;
                            for (0..3) |_| {
                                var xx: [6]f64 = undefined;
                                _ = swe.swe_calc(tx, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                                const lon = xx[0] * RADTODEG;
                                const spd = xx[3] * RADTODEG;
                                var dx = swe.swe_degnorm(lon - xcross);
                                if (dx > 180) dx -= 360;
                                tx -= dx / spd;
                            }
                            var izod: i32 = @intFromFloat(@mod(@as(f64, @floatFromInt(ii)), 12));
                            if (x2v <= xcross) {
                                izod = @mod(izod + 11, 12);
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..16], "ingress retro. \x00".*[0..16]);
                                printItem(@ptrCast(&buf), tx, @as(f64, @floatFromInt(izod)), HUGE_VAL, HUGE_VAL);
                            } else {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..9], "ingress \x00".*[0..9]);
                                printItem(@ptrCast(&buf), tx, @as(f64, @floatFromInt(izod)), HUGE_VAL, HUGE_VAL);
                            }
                        } else if (nzer == 2) {
                            _ = printf("warning double crossing in ingress, reduced accuracy: planet=%d, tjd1=%.8f, tjd2=%.8f\n", iplfrom, te + dt1, te + dt2b);
                        }
                    }
                }
            }
            if ((do_flag & DO_INGR45) != 0) {
                const x2v = xp2[0] * RADTODEG;
                var x1v = xp1[0] * RADTODEG;
                var x0v = xp0[0] * RADTODEG;
                const d12 = swe.swe_difdeg2n(x2v, x1v);
                x1v = x2v - d12;
                const d01 = swe.swe_difdeg2n(x1v, x0v);
                x0v = x1v - d01;
                for (0..4) |ii| {
                    const xcross: f64 = 45 + @as(f64, @floatFromInt(ii)) * 90.0;
                    if (signChange(x1v - xcross, x2v - xcross) or (@abs(x0v - x1v) + @abs(x1v - x2v) > @abs(x2v - xcross))) {
                        var dt1: f64 = 0;
                        var dt2b: f64 = 0;
                        const nzer = findZero(x0v - xcross, x1v - xcross, x2v - xcross, tstep, &dt1, &dt2b);
                        const izod: i32 = @intFromFloat(xcross / 30);
                        if (nzer == 1) {
                            var tx = te + dt1;
                            for (0..3) |_| {
                                var xx: [6]f64 = undefined;
                                _ = swe.swe_calc(tx, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                                const lon = xx[0] * RADTODEG;
                                const spd = xx[3] * RADTODEG;
                                var dx = swe.swe_degnorm(lon - xcross);
                                if (dx > 180) dx -= 360;
                                tx -= dx / spd;
                            }
                            if (x2v <= xcross) {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..15], "ingr45 retro. \x00".*[0..15]);
                                printItem(@ptrCast(&buf), tx, @as(f64, @floatFromInt(izod)), HUGE_VAL, HUGE_VAL);
                            } else {
                                var buf: [32]u8 = [_]u8{0} ** 32;
                                @memcpy(buf[0..8], "ingr45 \x00".*[0..8]);
                                printItem(@ptrCast(&buf), tx, @as(f64, @floatFromInt(izod)), HUGE_VAL, HUGE_VAL);
                            }
                        }
                    }
                }
            }
            // ELONG / RISE handling combined simplified: max elongation
            if ((do_flag & DO_ELONG) != 0 and iplfrom < SE_MARS) {
                if (@abs(xang0[0]) < @abs(xang1[0]) and @abs(xang2[0]) < @abs(xang1[0])) {
                    var dt: f64 = 0;
                    var yret: f64 = 0;
                    findMaximum(xang0[0], xang1[0], xang2[0], tstep, &dt, &yret);
                    var t2 = te + dt;
                    var dt1 = tstep;
                    for (0..5) |_| {
                        var xa0: f64 = 0;
                        var xa1: f64 = 0;
                        var xa2: f64 = 0;
                        for (0..3) |k| {
                            const t3: f64 = if (k == 0) t2 - dt1 else if (k == 1) t2 else t2 + dt1;
                            var xp: [6]f64 = undefined;
                            var xsun: [6]f64 = undefined;
                            _ = swe.swe_calc(t3, iplfrom, iflag, @ptrCast(&xp), @ptrCast(&serr));
                            _ = swe.swe_calc(t3, SE_SUN, iflag, @ptrCast(&xsun), @ptrCast(&serr));
                            var cp: [3]f64 = undefined;
                            var cs: [3]f64 = undefined;
                            polcart(xp[0], xp[1], xp[2], &cp);
                            polcart(xsun[0], xsun[1], xsun[2], &cs);
                            const dif: [3]f64 = .{ cp[0] - cs[0], cp[1] - cs[1], cp[2] - cs[2] };
                            const rph = sqrt(squareSum(dif));
                            const el = acos((xsun[2] * xsun[2] + xp[2] * xp[2] - rph * rph) / 2 / xsun[2] / xp[2]);
                            if (k == 0) xa0 = el else if (k == 1) xa1 = el else xa2 = el;
                        }
                        var ndt: f64 = 0;
                        var ny: f64 = 0;
                        findMaximum(xa0, xa1, xa2, dt1, &ndt, &ny);
                        t2 = t2 + dt1 + ndt;
                        yret = ny;
                        dt1 /= 3;
                    }
                    var xx: [6]f64 = undefined;
                    _ = swe.swe_calc(t2, iplfrom, iflag, @ptrCast(&xx), @ptrCast(&serr));
                    if (iplfrom > SE_VENUS) {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..15], "maximum elong.\x00".*[0..15]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, yret * RADTODEG, HUGE_VAL);
                    } else if (xel1[0] > 0) {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..15], "evening max el\x00".*[0..15]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, yret * RADTODEG, HUGE_VAL);
                    } else {
                        var buf: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buf[0..15], "morning max el\x00".*[0..15]);
                        printItem(@ptrCast(&buf), t2, xx[0] * RADTODEG, yret * RADTODEG, HUGE_VAL);
                    }
                }
            }
        }
    }
    if (do_motab and prev_yout != -999999) printMotab();
    swe.swe_close();
}

var gap_buf: [32]u8 = [_]u8{0} ** 32;
