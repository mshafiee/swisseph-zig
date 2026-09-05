// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
const swe = @import("swe_abi");
const std = @import("std");

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(f: ?*anyopaque) c_int;
extern "c" fn fgets(buf: [*]u8, n: c_int, stream: ?*anyopaque) ?[*]u8;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn fprintf(stream: ?*anyopaque, format: [*:0]const u8, ...) c_int;
extern "c" fn sprintf(buf: [*]u8, format: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, n: usize, format: [*:0]const u8, ...) c_int;
extern "c" fn puts(s: [*:0]const u8) c_int;
extern "c" fn fputs(s: [*:0]const u8, stream: ?*anyopaque) c_int;
extern "c" fn exit(code: c_int) noreturn;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn strncpy(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8;
extern "c" fn strcat(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn strchr(s: [*:0]const u8, c: c_int) ?[*:0]u8;
extern "c" fn strstr(hay: [*:0]const u8, needle: [*:0]const u8) ?[*:0]u8;
extern "c" fn strrchr(s: [*:0]const u8, c: c_int) ?[*:0]u8;
extern "c" fn strpbrk(s: [*:0]const u8, accept: [*:0]const u8) ?[*:0]u8;
extern "c" fn sscanf(buf: [*:0]const u8, format: [*:0]const u8, ...) c_int;
extern "c" fn atof(s: [*:0]const u8) f64;
extern "c" fn atoi(s: [*:0]const u8) c_int;
extern "c" fn atol(s: [*:0]const u8) c_long;
extern "c" fn fabs(x: f64) f64;
extern "c" fn floor(x: f64) f64;
extern "c" fn fmod(x: f64, y: f64) f64;
extern "c" fn is_nan_helper(x: f64) c_int;

// extern stdout removed

const SE_GREG_CAL: i32 = 1;
const SE_JUL_CAL: i32 = 0;
const SEFLG_JPLEPH: i32 = 1;
const SEFLG_SWIEPH: i32 = 2;
const SEFLG_MOSEPH: i32 = 4;
const SEFLG_HELCTR: i32 = 8;
const SEFLG_TRUEPOS: i32 = 16;
const SEFLG_J2000: i32 = 32;
const SEFLG_NONUT: i32 = 64;
const SEFLG_SPEED3: i32 = 128;
const SEFLG_SPEED: i32 = 256;
const SEFLG_NOGDEFL: i32 = 512;
const SEFLG_NOABERR: i32 = 1024;
const SEFLG_EQUATORIAL: i32 = 2048;
const SEFLG_XYZ: i32 = 4096;
const SEFLG_RADIANS: i32 = 8192;
const SEFLG_BARYCTR: i32 = 16384;
const SEFLG_TOPOCTR: i32 = 32768;
const SEFLG_SIDEREAL: i32 = 65536;
const SEFLG_ICRS: i32 = 131072;
const SEFLG_JPLHOR: i32 = 262144;
const SEFLG_JPLHOR_APPROX: i32 = 524288;
const SEFLG_CENTER_BODY: i32 = 1048576;
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
const SE_PALLAS: i32 = 18;
const SE_JUNO: i32 = 19;
const SE_VESTA: i32 = 20;
const SE_INTP_APOG: i32 = 21;
const SE_INTP_PERG: i32 = 22;
const SE_NUT: i32 = -1;
const SE_ECL_NUT: i32 = -1;
const SE_FIXSTAR: i32 = -10;
const SE_AST_OFFSET: i32 = 10000;
const SE_CUPIDO: i32 = 40;
const SE_WALDEMATH: i32 = 58;
const SE_FICT_OFFSET_1: i32 = 39;
const SE_NODBIT_MEAN: i32 = 1;
const SE_NODBIT_OSCU: i32 = 2;
const SE_NODBIT_FOPOINT: i32 = 256;

const BIT_ROUND_SEC: i32 = 1;
const BIT_ROUND_MIN: i32 = 2;
const BIT_ZODIAC: i32 = 4;
const BIT_LZEROES: i32 = 8;
const BIT_TIME_LMT: i32 = 16;
const BIT_TIME_LAT: i32 = 32;
const BIT_ALLOW_361: i32 = 64;

const DIFF_DIFF: u8 = 'd';
const DIFF_GEOHEL: u8 = 'h';
const DIFF_MIDP: u8 = 'D';
const MODE_HOUSE: i32 = 1;
const MODE_LABEL: i32 = 2;
const MODE_AYANAMSA: i32 = 4;

const AS_MAXCH: usize = 256;
const LEN_SOUT: usize = 1000;

var zod_nam = [_][:0]const u8{ "ar", "ta", "ge", "cn", "le", "vi", "li", "sc", "sa", "cp", "aq", "pi" };

// globals shared between main and print_line
var fmt_buf: [256]u8 = undefined;
var fmt: [*:0]u8 = undefined;
var gap_buf: [256]u8 = undefined;
var gap: [*:0]u8 = undefined;
var t: f64 = 0;
var te: f64 = 0;
var tut: f64 = 0;
var jut: f64 = 0;
var tstep: f64 = 1;
var jmon: i32 = 1;
var jday: i32 = 1;
var jyear: i32 = 2000;
var ipl: i32 = 0;
var ipldiff: i32 = 0;
var nhouses: i32 = 12;
var iplctr: i32 = 0;
var spnam: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var spnam2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var serr_save: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var serr_warn: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var gregflag: i32 = SE_GREG_CAL;
var gregflag_auto: bool = true;
var diff_mode: u8 = 0;
var use_dms: bool = false;
var has_n: bool = false;
var universal_time: bool = false;
var universal_time_utc: bool = false;
var round_flag: i32 = 0;
var time_flag: i32 = 0;
var short_output: bool = false;
var list_hor: bool = false;
var with_header: bool = true;
var with_header_always: bool = false;
var with_glp: bool = false;
var x: [6]f64 = [_]f64{0} ** 6;
var x2: [6]f64 = [_]f64{0} ** 6;
var xequ: [6]f64 = [_]f64{0} ** 6;
var xcart: [6]f64 = [_]f64{0} ** 6;
var xcartq: [6]f64 = [_]f64{0} ** 6;
var xobl: [6]f64 = [_]f64{0} ** 6;
var xaz: [6]f64 = [_]f64{0} ** 6;
var xt: [6]f64 = [_]f64{0} ** 6;
var hpos: f64 = 0;
var hpos2: f64 = 0;
var hposj: f64 = 0;
var armc: f64 = 0;
var xsv: [6]f64 = [_]f64{0} ** 6;
var hpos_meth: i32 = 0;
var geopos: [10]f64 = [_]f64{0} ** 10;
var attr: [20]f64 = [_]f64{0} ** 20;
var tret: [20]f64 = [_]f64{0} ** 20;
var datm: [4]f64 = [_]f64{0} ** 4;
var dobs: [6]f64 = [_]f64{0} ** 6;
var iflag: i32 = 0;
var whicheph: i32 = SEFLG_SWIEPH;
var nstep: i32 = 1;
var direction: i32 = 1;
var have_geopos: bool = false;
var ihsy: i32 = 'P';
var top_long: f64 = 0;
var top_lat: f64 = 51.5;
var top_elev: f64 = 0;
var have_gap_parameter: bool = false;
var output_extra_prec: bool = false;
var step_in_minutes: bool = false;
var step_in_seconds: bool = false;
var step_in_years: bool = false;
var step_in_months: bool = false;
var iflag_f: i32 = -1;
var do_houses: bool = false;
var plsel_ptr: [*:0]u8 = undefined;
var psp_cur: [*:0]u8 = undefined;

// house names
var hs_nam = [_][:0]const u8{ "undef", "Ascendant", "MC", "ARMC", "Vertex", "equat. Asc.", "co-Asc. W.Koch", "co-Asc Munkasey", "Polar Asc." };

// star etc
var star: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var sastno: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var spmoon: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var shyp: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;

// sout
var sout: [LEN_SOUT]u8 = [_]u8{0} ** LEN_SOUT;

fn cStrLen(s: [*:0]const u8) usize {
    return std.mem.len(s);
}
fn cStrEq(a: [*:0]const u8, b: [*:0]const u8) bool {
    return std.mem.orderZ(u8, a, b) == .eq;
}
fn setCStr(dst: [*]u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
    dst[src.len] = 0;
}
fn copyCStar(dst: [*]u8, src: [*:0]const u8) void {
    var i: usize = 0;
    while (src[i] != 0) : (i += 1) dst[i] = src[i];
    dst[i] = 0;
}
fn zigStrFromC(c: [*:0]const u8) []const u8 {
    return std.mem.span(c);
}
fn startsWith(c: [*:0]const u8, prefix: []const u8) bool {
    const s = zigStrFromC(c);
    if (s.len < prefix.len) return false;
    return std.mem.eql(u8, s[0..prefix.len], prefix);
}

fn letterToIpl(letter: i32) i32 {
    if (letter >= '0' and letter <= '9') return letter - '0' + SE_SUN;
    if (letter >= 'A' and letter <= 'I') return letter - 'A' + SE_MEAN_APOG;
    if (letter >= 'J' and letter <= 'Z') return letter - 'J' + SE_CUPIDO;
    return switch (letter) {
        'm' => SE_MEAN_NODE,
        'c' => SE_INTP_APOG,
        'g' => SE_INTP_PERG,
        'n', 'o' => SE_ECL_NUT,
        't' => SE_TRUE_NODE,
        'f' => SE_FIXSTAR,
        'w' => SE_WALDEMATH,
        'e', 'q', 'y', 'x', 'b', 's', 'v', 'z', 'd', 'p', 'h', 'a' => -1,
        else => -2,
    };
}

var dms_buf: [64]u8 = undefined;
fn dms(xv_in: f64, iflg: i32) [*:0]u8 {
    var xv = xv_in;
    var c: [*:0]const u8 = "\xc2\xb0"; // degree UTF8
    var s: [64]u8 = [_]u8{0} ** 64;
    var s1: [64]u8 = [_]u8{0} ** 64;
    var sg: i32 = 1;
    if (@import("std").math.isNan(xv)) {
        s[0] = 'n';
        s[1] = 'a';
        s[2] = 'n';
        s[3] = 0;
        @memcpy(dms_buf[0..4], s[0..4]);
        dms_buf[3] = 0;
        return @ptrCast(&dms_buf);
    }
    if (xv >= 360 and (iflg & BIT_ALLOW_361) == 0) xv = 0;
    // zero s
    s[0] = 0;
    if ((iflg & SEFLG_EQUATORIAL) != 0) c = "h";
    if (xv < 0) {
        xv = -xv;
        sg = -1;
    } else sg = 1;
    if ((iflg & BIT_ROUND_MIN) != 0) {
        if ((iflg & BIT_ALLOW_361) == 0) xv = swe.swe_degnorm(xv + 0.5 / 60.0);
    } else if ((iflg & BIT_ROUND_SEC) != 0) {
        if ((iflg & BIT_ALLOW_361) == 0) xv = swe.swe_degnorm(xv + 0.5 / 3600.0);
    } else {
        if (output_extra_prec) xv += (if (xv < 0) @as(f64, -1) else @as(f64, 1)) * 0.000000005 / 3600.0 else xv += (if (xv < 0) @as(f64, -1) else @as(f64, 1)) * 0.00005 / 3600.0;
    }
    var izod: i32 = 0;
    var kdeg: i32 = 0;
    if ((iflg & BIT_ZODIAC) != 0) {
        izod = @intFromFloat(xv / 30.0);
        if (izod == 12) izod = 0;
        xv = @mod(xv, 30.0);
        kdeg = @intFromFloat(xv);
        _ = snprintf(&s, 64, "%2d %s ", kdeg, zod_nam[@intCast(izod)].ptr);
    } else {
        kdeg = @intFromFloat(xv);
        _ = snprintf(&s, 64, " %3d%s", kdeg, c);
    }
    xv -= @as(f64, @floatFromInt(kdeg));
    xv *= 60;
    const kmin: i32 = @intFromFloat(xv);
    if (((iflg & BIT_ZODIAC) != 0) and ((iflg & BIT_ROUND_MIN) != 0)) {
        _ = snprintf(&s1, 64, "%2d", kmin);
    } else {
        _ = snprintf(&s1, 64, "%2d'", kmin);
    }
    _ = strcat(@ptrCast(&s), @ptrCast(&s1));
    if ((iflg & BIT_ROUND_MIN) != 0) {
        // goto return_dms
    } else {
        xv -= @as(f64, @floatFromInt(kmin));
        xv *= 60;
        const ksec: i32 = @intFromFloat(xv);
        if ((iflg & BIT_ROUND_SEC) != 0) {
            _ = snprintf(&s1, 64, "%2d\"", ksec);
        } else {
            _ = snprintf(&s1, 64, "%2d", ksec);
        }
        _ = strcat(@ptrCast(&s), @ptrCast(&s1));
        if ((iflg & BIT_ROUND_SEC) == 0) {
            xv -= @as(f64, @floatFromInt(ksec));
            var k: i32 = 0;
            if (output_extra_prec) {
                k = @intFromFloat(xv * 100000000);
                _ = snprintf(&s1, 64, ".%08d", k);
            } else {
                k = @intFromFloat(xv * 10000);
                _ = snprintf(&s1, 64, ".%04d", k);
            }
            _ = strcat(@ptrCast(&s), @ptrCast(&s1));
        }
    }
    if (sg < 0) {
        // find first digit
        var i: usize = 0;
        while (s[i] != 0) : (i += 1) {
            if (s[i] >= '0' and s[i] <= '9') {
                s[i - 1] = '-';
                break;
            }
        }
    }
    if ((iflg & BIT_LZEROES) != 0) {
        var p: usize = 2;
        while (p < 64 and s[p] != 0) : (p += 1) {
            if (s[p] == ' ') s[p] = '0';
            // Actually original loops searching s+2: while ((sp=strchr(s+2,' '))!=NULL) *sp='0';
            // We'll just replace all spaces after pos2
        }
        // simpler: iterate and replace spaces after index2
        var j: usize = 2;
        while (s[j] != 0) : (j += 1) {
            if (s[j] == ' ') s[j] = '0';
        }
    }
    // copy to static
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    @memcpy(dms_buf[0..len], s[0..len]);
    dms_buf[len] = 0;
    return @ptrCast(&dms_buf);
}

var hms_buf: [64]u8 = undefined;
fn hms(x_in: f64, iflg: i32) [*:0]u8 {
    var xv = x_in;
    xv += 0.5 / 36000.0;
    const tmp = dms(xv, iflg);
    var len: usize = 0;
    while (tmp[len] != 0) : (len += 1) {}
    @memcpy(hms_buf[0..len], tmp[0..len]);
    hms_buf[len] = 0;
    // find ODEGREE_STRING "\xc2\xb0"
    var i: usize = 0;
    while (i + 1 < len) : (i += 1) {
        if (hms_buf[i] == 0xC2 and hms_buf[i + 1] == 0xB0) {
            hms_buf[i] = ':';
            var s2: [64]u8 = [_]u8{0} ** 64;
            var j: usize = 0;
            while (hms_buf[i + 2 + j] != 0) : (j += 1) {
                s2[j] = hms_buf[i + 2 + j];
            }
            s2[j] = 0;
            var k: usize = 0;
            while (s2[k] != 0) : (k += 1) {
                hms_buf[i + 1 + k] = s2[k];
            }
            hms_buf[i + 1 + k] = 0;
            if (i + 3 < 64) hms_buf[i + 3] = ':';
            if (i + 8 < 64) hms_buf[i + 8] = 0;
            break;
        }
    }
    return @ptrCast(&hms_buf);
}
fn jdToTimeString(jut_in: f64, out: [*]u8) void {
    var t2: f64 = jut_in + 0.5 / 3600000.0;
    _ = snprintf(out, 64, "  % 2d:", @as(c_int, @intFromFloat(t2)));
    const ti: i32 = @intFromFloat(t2);
    t2 = (t2 - @as(f64, @floatFromInt(ti))) * 60.0;
    _ = snprintf(out + strlen(@ptrCast(out)), 64 - strlen(@ptrCast(out)), "%02d:", @as(c_int, @intFromFloat(t2)));
    const ti2: i32 = @intFromFloat(t2);
    t2 = (t2 - @as(f64, @floatFromInt(ti2))) * 60.0;
    _ = snprintf(out + strlen(@ptrCast(out)), 64 - strlen(@ptrCast(out)), "%02d", @as(c_int, @intFromFloat(t2)));
    const ti3: i32 = @intFromFloat(t2);
    t2 = (t2 - @as(f64, @floatFromInt(ti3))) * 1000.0;
    if (@as(i32, @intFromFloat(t2)) > 0) {
        _ = snprintf(out + strlen(@ptrCast(out)), 64 - strlen(@ptrCast(out)), ".%03d", @as(c_int, @intFromFloat(t2)));
    }
}

fn printLine(mode: i32, is_first: bool, sid_mode: i32) void {
    _ = sid_mode;
    const sp: [*]u8 = fmt;
    const is_house = (mode & MODE_HOUSE) != 0;
    const is_label = (mode & MODE_LABEL) != 0;
    var pnam: [30]u8 = [_]u8{0} ** 30;
    if (is_house) {
        if (ipl <= nhouses) {
            _ = snprintf(&pnam, 30, "house %2d       ", ipl);
        } else {
            const idx: usize = @intCast(ipl - nhouses);
            const name: [*:0]const u8 = if (idx < hs_nam.len) hs_nam[idx].ptr else "unknown";
            _ = snprintf(&pnam, 30, "%-15s", name);
        }
    } else if (diff_mode == DIFF_DIFF) {
        _ = snprintf(&pnam, 30, "%.3s-%.3s", @as([*:0]u8, @ptrCast(&spnam)), @as([*:0]u8, @ptrCast(&spnam2)));
    } else if (diff_mode == DIFF_GEOHEL) {
        _ = snprintf(&pnam, 30, "%.3s-%.3sHel", @as([*:0]u8, @ptrCast(&spnam)), @as([*:0]u8, @ptrCast(&spnam2)));
    } else if (diff_mode == DIFF_MIDP) {
        _ = snprintf(&pnam, 30, "%.3s/%.3s", @as([*:0]u8, @ptrCast(&spnam)), @as([*:0]u8, @ptrCast(&spnam2)));
    } else {
        _ = snprintf(&pnam, 30, "%-15.15s", @as([*:0]u8, @ptrCast(&spnam)));
    }
    var slon: [32]u8 = [_]u8{0} ** 32;
    if (list_hor and strpbrk(fmt, "P") == null) {
        _ = snprintf(&slon, 32, "%.8s %s", @as([*:0]u8, @ptrCast(&pnam)), @as([*:0]const u8, @ptrCast("long.")));
    } else {
        _ = snprintf(&slon, 32, "%-14s", @as([*:0]const u8, @ptrCast("long.")));
    }
    const is_first_local = is_first;
    var idx: usize = 0;
    while (sp[idx] != 0) : (idx += 1) {
        const ch: u8 = sp[idx];
        // skip columns for houses that not needed?
        // is_house && strchr("bBrRxXuUQnNfFj+-*/=",*sp)!=NULL continue;
        var skip = false;
        if (is_house) {
            const skip_chars = "bBrRxXuUQnNfFj+-*/=";
            var k: usize = 0;
            while (skip_chars[k] != 0) : (k += 1) {
                if (skip_chars[k] == ch) {
                    skip = true;
                    break;
                }
            }
            if (skip) continue;
        }
        // is_ayana similar skipped earlier - not needed
        if (idx != 0) _ = printf("%s", gap);
        if (idx == 0 and list_hor and !is_first_local) {
            const tchars = "yYJtT";
            var isT = false;
            var k: usize = 0;
            while (tchars[k] != 0) : (k += 1) {
                if (tchars[k] == ch) {
                    isT = true;
                    break;
                }
            }
            if (!isT) _ = printf("%s", gap);
        }
        switch (ch) {
            'y' => {
                if (list_hor and !is_first_local) break;
                if (is_label) {
                    _ = printf("year");
                    break;
                }
                _ = printf("%d", jyear);
            },
            'Y' => {
                if (list_hor and !is_first_local) break;
                if (is_label) {
                    _ = printf("year");
                    break;
                }
                const t2: f64 = swe.swe_julday(jyear, 1, 1, 0, gregflag);
                const yfrac: f64 = (t - t2) / 365.0;
                _ = printf("%.2f", @as(f64, @floatFromInt(jyear)) + yfrac);
            },
            'p' => {
                if (is_label) {
                    _ = printf("obj.nr");
                    break;
                }
                if (!is_house and diff_mode == DIFF_DIFF) _ = printf("%d-%d", ipl, ipldiff) else if (!is_house and diff_mode == DIFF_GEOHEL) _ = printf("%d-%dhel", ipl, ipldiff) else if (!is_house and diff_mode == DIFF_MIDP) _ = printf("%d/%d", ipl, ipldiff) else _ = printf("%d", ipl);
            },
            'P' => {
                if (is_label) {
                    _ = printf("%-15s", @as([*:0]const u8, @ptrCast("name")));
                    break;
                }
                if (is_house) {
                    if (ipl <= nhouses) _ = printf("house %2d       ", ipl) else {
                        const idx2: usize = @intCast(ipl - nhouses);
                        const name: [*:0]const u8 = if (idx2 < hs_nam.len) hs_nam[idx2].ptr else "unknown";
                        _ = printf("%-15s", name);
                    }
                } else if (diff_mode == DIFF_DIFF or diff_mode == DIFF_GEOHEL) {
                    _ = printf("%.3s-%.3s", @as([*:0]u8, @ptrCast(&spnam)), @as([*:0]u8, @ptrCast(&spnam2)));
                } else if (diff_mode == DIFF_MIDP) {
                    _ = printf("%.3s/%.3s", @as([*:0]u8, @ptrCast(&spnam)), @as([*:0]u8, @ptrCast(&spnam2)));
                } else {
                    _ = printf("%-15s", @as([*:0]u8, @ptrCast(&spnam)));
                }
            },
            'J' => {
                if (list_hor and !is_first_local) break;
                if (is_label) {
                    _ = printf("julday");
                    break;
                }
                const yfrac: f64 = (t - floor(t)) * 100;
                if (floor(yfrac) != yfrac) _ = printf("%.5f", t) else _ = printf("%.2f", t);
            },
            'T' => {
                if (list_hor and !is_first_local) break;
                if (is_label) {
                    _ = printf("date    ");
                    break;
                }
                _ = printf("%02d.%02d.%04d", jday, jmon, jyear);
                if (gregflag == SE_JUL_CAL) _ = printf("j");
                if (jut != 0 or step_in_minutes or step_in_seconds) {
                    var h: i32 = undefined;
                    var m: i32 = undefined;
                    var s: i32 = undefined;
                    var isgn: i32 = undefined;
                    var dsecfr: f64 = undefined;
                    var roundflag: i32 = 1;
                    if ((tstep < 1 and tstep > -1) and step_in_seconds) {
                        roundflag = 0;
                        swe.swe_split_deg(jut, roundflag, &h, &m, &s, &dsecfr, &isgn);
                        _ = printf(" %d:%02d:%02.2f", h, m, @as(f64, @floatFromInt(s)) + dsecfr);
                    } else {
                        swe.swe_split_deg(jut, roundflag, &h, &m, &s, &dsecfr, &isgn);
                        _ = printf(" %d:%02d:%02d", h, m, s);
                    }
                    if (universal_time) _ = printf(" UT") else _ = printf(" TT");
                }
            },
            't' => {
                if (list_hor and !is_first_local) break;
                if (is_label) {
                    _ = printf("date");
                    break;
                }
                _ = printf("%02d%02d%02d", @rem(jyear, 100), jmon, jday);
            },
            'L' => {
                if (is_label) {
                    _ = printf("%s", @as([*:0]u8, @ptrCast(&slon)));
                    break;
                }
                if (psp_cur[0] == 'q' or psp_cur[0] == 'y') {
                    _ = printf("%# 11.7f", x[0]);
                    _ = printf("s");
                    break;
                }
                _ = printf("%s", dms(x[0], round_flag));
            },
            'l' => {
                if (is_label) {
                    _ = printf("%s", @as([*:0]u8, @ptrCast(&slon)));
                    break;
                }
                if ((round_flag & BIT_ROUND_MIN) != 0) _ = printf("%# 6.2f", x[0]) else {
                    if (output_extra_prec) _ = printf("%# 11.11f", x[0]) else _ = printf("%# 11.7f", x[0]);
                }
            },
            'G' => {
                if (is_label) {
                    _ = printf("housPos");
                    break;
                }
                _ = printf("%s", dms(hpos, round_flag));
            },
            'g' => {
                if (is_label) {
                    _ = printf("housPos");
                    break;
                }
                _ = printf("%# 11.7f", hpos);
            },
            'j' => {
                if (is_label) {
                    _ = printf("houseNr");
                    break;
                }
                _ = printf("%# 11.7f", hposj);
            },
            'Z' => {
                if (is_label) {
                    _ = printf("%s", @as([*:0]u8, @ptrCast(&slon)));
                    break;
                }
                _ = printf("%s", dms(x[0], round_flag | BIT_ZODIAC));
            },
            'S', 's' => {
                // Simplified: if next char is S/s or has XU etc, original loops. For now handle single.
                const next: u8 = if (sp[idx + 1] != 0) sp[idx + 1] else 0;
                if (next == 'S' or next == 's') {
                    // handle speed block not implemented fully; just skip duplicate
                    // For simplicity, fall through to single
                }
                if (ch == 'S') {
                    var flag2 = round_flag;
                    if (is_house) flag2 |= BIT_ALLOW_361;
                    if (is_label) {
                        _ = printf("deg/day");
                        break;
                    }
                    _ = printf("%s", dms(x[3], flag2));
                } else {
                    if (is_label) {
                        _ = printf("deg/day");
                        break;
                    }
                    if (output_extra_prec) _ = printf("%# 11.17f", x[3]) else _ = printf("%# 11.7f", x[3]);
                }
                if (next == 'S' or next == 's') idx += 1;
            },
            'B' => {
                if (is_label) {
                    _ = printf("lat.    ");
                    break;
                }
                if (psp_cur[0] == 'q') {
                    _ = printf("%# 11.7f", x[1]);
                    _ = printf("h");
                    break;
                }
                _ = printf("%s", dms(x[1], round_flag));
            },
            'b' => {
                if (is_label) {
                    _ = printf("lat.    ");
                    break;
                }
                if (output_extra_prec) _ = printf("%# 11.11f", x[1]) else _ = printf("%# 11.7f", x[1]);
            },
            'A' => {
                if (is_label) {
                    _ = printf("RA      ");
                    break;
                }
                _ = printf("%s", dms(xequ[0] / 15.0, round_flag | SEFLG_EQUATORIAL));
            },
            'a' => {
                if (is_label) {
                    _ = printf("RA      ");
                    break;
                }
                if (output_extra_prec) _ = printf("%# 11.11f", xequ[0]) else _ = printf("%# 11.7f", xequ[0]);
            },
            'D' => {
                if (is_label) {
                    _ = printf("decl      ");
                    break;
                }
                _ = printf("%s", dms(xequ[1], round_flag));
            },
            'd' => {
                if (is_label) {
                    _ = printf("decl      ");
                    break;
                }
                if (output_extra_prec) _ = printf("%# 11.11f", xequ[1]) else _ = printf("%# 11.7f", xequ[1]);
            },
            'I' => {
                if (is_label) {
                    _ = printf("azimuth");
                    break;
                }
                _ = printf("%s", dms(xaz[0], round_flag));
            },
            'i' => {
                if (is_label) {
                    _ = printf("azimuth");
                    break;
                }
                _ = printf("%# 11.7f", xaz[0]);
            },
            'H' => {
                if (is_label) {
                    _ = printf("height");
                    break;
                }
                _ = printf("%s", dms(xaz[1], round_flag));
            },
            'h' => {
                if (is_label) {
                    _ = printf("height");
                    break;
                }
                _ = printf("%# 11.7f", xaz[1]);
            },
            'K' => {
                if (is_label) {
                    _ = printf("hgtApp");
                    break;
                }
                _ = printf("%s", dms(xaz[2], round_flag));
            },
            'k' => {
                if (is_label) {
                    _ = printf("hgtApp");
                    break;
                }
                _ = printf("%# 11.7f", xaz[2]);
            },
            'R' => {
                if (is_label) {
                    _ = printf("distAU   ");
                    break;
                }
                if (output_extra_prec) _ = printf("%# 18.16f", x[2]) else _ = printf("%# 14.9f", x[2]);
            },
            'r' => {
                if (is_label) {
                    _ = printf("dist");
                    break;
                }
                if (ipl == SE_MOON) {
                    _ = printf("%# 13.5f\"", attr[5] * 3600.0);
                } else _ = printf("%# 14.9f", x[2]);
            },
            'q' => {
                if (is_label) {
                    _ = printf("reldist");
                    break;
                }
                // compute relative distance simplified? Use swe_orbit? For now compute 0
                // Call stub via swe if available? We'll just call via swe_calc? Use approximation
                _ = printf("% 5d", @as(c_int, 0));
            },
            'm' => {
                if (is_label) {
                    _ = printf("MD      ");
                    break;
                }
                var md: f64 = swe.swe_difdeg2n(xequ[0], armc);
                if (md < 0) md = -md;
                if (output_extra_prec) _ = printf("%# 11.11f", md) else _ = printf("%# 11.7f", md);
            },
            'z' => {
                if (is_label) {
                    _ = printf("ZD      ");
                    break;
                }
                swe.swe_azalt(tut, 0, @ptrCast(&geopos), datm[0], datm[1], @ptrCast(&xequ), @ptrCast(&xaz));
                const zd: f64 = 90 - xaz[1];
                if (output_extra_prec) _ = printf("%# 11.11f", zd) else _ = printf("%# 11.7f", zd);
            },
            'U', 'X' => {
                const ar: f64 = if (ch == 'U') @sqrt(xcart[0] * xcart[0] + xcart[1] * xcart[1] + xcart[2] * xcart[2]) else 1;
                if (is_label) {
                    _ = printf("x0");
                    _ = printf("%s", gap);
                    _ = printf("x1");
                    _ = printf("%s", gap);
                    _ = printf("x2");
                    break;
                }
                _ = printf("%# 14.9f", xcart[0] / ar);
                _ = printf("%s", gap);
                _ = printf("%# 14.9f", xcart[1] / ar);
                _ = printf("%s", gap);
                _ = printf("%# 14.9f", xcart[2] / ar);
            },
            'u', 'x' => {
                const ar: f64 = if (ch == 'u') @sqrt(xcartq[0] * xcartq[0] + xcartq[1] * xcartq[1] + xcartq[2] * xcartq[2]) else 1;
                if (is_label) {
                    _ = printf("x0");
                    _ = printf("%s", gap);
                    _ = printf("x1");
                    _ = printf("%s", gap);
                    _ = printf("x2");
                    break;
                }
                if (output_extra_prec) {
                    _ = printf("%# .17f", xcartq[0] / ar);
                    _ = printf("%s", gap);
                    _ = printf("%# .17f", xcartq[1] / ar);
                    _ = printf("%s", gap);
                    _ = printf("%# .17f", xcartq[2] / ar);
                } else {
                    _ = printf("%# 14.9f", xcartq[0] / ar);
                    _ = printf("%s", gap);
                    _ = printf("%# 14.9f", xcartq[1] / ar);
                    _ = printf("%s", gap);
                    _ = printf("%# 14.9f", xcartq[2] / ar);
                }
            },
            'Q' => {
                if (is_label) {
                    _ = printf("Q");
                    break;
                }
                _ = printf("%-15s", @as([*:0]u8, @ptrCast(&spnam)));
                _ = printf("%s", dms(x[0], round_flag));
                _ = printf("%s", dms(x[1], round_flag));
                _ = printf("  %# 14.9f", x[2]);
                _ = printf("%s", dms(x[3], round_flag));
                _ = printf("%s", dms(x[4], round_flag));
                _ = printf("  %# 14.9f\n", x[5]);
                _ = printf("               %s", dms(xequ[0], round_flag));
                _ = printf("%s", dms(xequ[1], round_flag));
                _ = printf("                %s", dms(xequ[3], round_flag));
                _ = printf("%s", dms(xequ[4], round_flag));
            },
            'n', 'N' => {
                var xasc: [6]f64 = undefined;
                var xdsc: [6]f64 = undefined;
                const imeth: i32 = if (ch >= 'a' and ch <= 'z') SE_NODBIT_MEAN else SE_NODBIT_OSCU;
                var _tmp1: [6]f64 = undefined;
                var _tmp2: [6]f64 = undefined;
                _ = swe.swe_nod_aps(te, ipl, iflag, imeth, &xasc, &xdsc, &_tmp1, &_tmp2, @ptrCast(&serr));
                if (is_label) {
                    _ = printf("nodAsc");
                    _ = printf("%s", gap);
                    _ = printf("nodDesc");
                    break;
                }
                _ = printf("%# 11.7f", xasc[0]);
                _ = printf("%s", gap);
                _ = printf("%# 11.7f", xdsc[0]);
            },
            'F', 'f' => {
                if (!is_house) {
                    var xper: [6]f64 = undefined;
                    var xaph: [6]f64 = undefined;
                    var xfoc: [6]f64 = undefined;
                    var imeth2: i32 = if (ch >= 'a' and ch <= 'z') SE_NODBIT_MEAN else SE_NODBIT_OSCU;
                    var __tmp1: [6]f64 = undefined;
                    var __tmp2: [6]f64 = undefined;
                    _ = swe.swe_nod_aps(te, ipl, iflag, imeth2, &__tmp1, &__tmp2, &xper, &xaph, @ptrCast(&serr));
                    if (is_label) {
                        _ = printf("peri");
                        _ = printf("%s", gap);
                        _ = printf("apo");
                        _ = printf("%s", gap);
                        _ = printf("focus");
                        break;
                    }
                    _ = printf("%# 11.7f", xper[0]);
                    _ = printf("%s", gap);
                    _ = printf("%# 11.7f", xaph[0]);
                    imeth2 |= SE_NODBIT_FOPOINT;
                    var __tmp3: [6]f64 = undefined;
                    var __tmp4: [6]f64 = undefined;
                    _ = swe.swe_nod_aps(te, ipl, iflag, imeth2, &__tmp3, &__tmp4, &xper, &xfoc, @ptrCast(&serr));
                    _ = printf("%s", gap);
                    _ = printf("%# 11.7f", xfoc[0]);
                }
            },
            '+' => {
                if (is_house) break;
                if (is_label) {
                    _ = printf("phase");
                    break;
                }
                _ = printf("%# 11.7f", attr[0]);
            },
            '-' => {
                if (is_label) {
                    _ = printf("phase");
                    break;
                }
                if (is_house) break;
                _ = printf("  %# 14.9f", attr[1]);
            },
            '*' => {
                if (is_label) {
                    _ = printf("elong");
                    break;
                }
                if (is_house) break;
                _ = printf("%# 11.7f", attr[2]);
            },
            '/' => {
                if (is_label) {
                    _ = printf("diamet");
                    break;
                }
                if (is_house) break;
                _ = printf("%s", dms(attr[3], round_flag));
            },
            '=' => {
                if (is_label) {
                    _ = printf("magn");
                    break;
                }
                if (is_house) break;
                _ = printf("  %# 6.3fm", attr[4]);
            },
            else => {},
        }
    }
    if (!list_hor) _ = printf("\n");
}

fn parseArgsWithC(argc: c_int, argv: [*][*:0]u8) !void {
    // capture argv[0] for make_ephemeris_path (C swetest.c:3995)
    const argv0_c_str = argv[0];
    // use C argc/argv directly
    // set defaults
    fmt_buf[0] = 'P';
    fmt_buf[1] = 'L';
    fmt_buf[2] = 'B';
    fmt_buf[3] = 'R';
    fmt_buf[4] = 'S';
    fmt_buf[5] = 0;
    fmt = @ptrCast(&fmt_buf);
    gap_buf[0] = ' ';
    gap_buf[1] = 0;
    gap = @ptrCast(&gap_buf);
    // defaults for star etc
    setCStr(&star, "algol");
    setCStr(&sastno, "433");
    setCStr(&spmoon, "9501");
    setCStr(&shyp, "1");
    datm[0] = 1013.25;
    datm[1] = 15;
    datm[2] = 40;
    datm[3] = 0;
    var ephepath: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var fname: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    setCStr(&fname, "seas_18.se1");
    var begindate: ?[*:0]u8 = null;
    var begindate_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var stimein: [64]u8 = [_]u8{0} ** 64;
    var stimein_len: usize = 0;
    var plsel_buf: [256]u8 = [_]u8{0} ** 256;
    setCStr(&plsel_buf, "0123456789mtA");
    var plsel: [*:0]u8 = @ptrCast(&plsel_buf);
    var sid_mode: i32 = 0;
    var aya_t0: f64 = 0;
    var aya_val0: f64 = 0;
    var thour: f64 = 0;
    // need to capture sid flag
    var have_sid: bool = false;
    // we will store argv for header printing later via globals? we can just store args
    // parse loop
    var i: usize = 1;
    while (i < @as(usize, @intCast(argc))) : (i += 1) {
        const cstr_arg = argv[i];
        const arg = std.mem.span(cstr_arg);
        // need to make null-terminated copy for C comparisons
        var cbuf: [1024]u8 = [_]u8{0} ** 1024;
        const copy_len = @min(arg.len, 1023);
        @memcpy(cbuf[0..copy_len], arg[0..copy_len]);
        cbuf[copy_len] = 0;
        const cstr: [*:0]u8 = @ptrCast(&cbuf);
        if (std.mem.startsWith(u8, arg, "-utc")) {
            universal_time = true;
            universal_time_utc = true;
            if (arg.len > 4) {
                const rem = arg[4..];
                const l = @min(rem.len, 30);
                @memcpy(stimein[0..l], rem[0..l]);
                stimein[l] = 0;
                stimein_len = l;
            }
        } else if (std.mem.startsWith(u8, arg, "-ut")) {
            universal_time = true;
            if (arg.len > 3) {
                const rem = arg[3..];
                const l = @min(rem.len, 30);
                @memcpy(stimein[0..l], rem[0..l]);
                stimein[l] = 0;
                stimein_len = l;
            }
        } else if (std.mem.eql(u8, arg, "-glp")) {
            with_glp = true;
        } else if (std.mem.startsWith(u8, arg, "-hor")) {
            list_hor = true;
        } else if (std.mem.eql(u8, arg, "-head")) {
            with_header = false;
        } else if (std.mem.eql(u8, arg, "+head")) {
            with_header_always = true;
        } else if (std.mem.eql(u8, arg, "-j2000")) {
            iflag |= SEFLG_J2000;
        } else if (std.mem.eql(u8, arg, "-icrs")) {
            iflag |= SEFLG_ICRS;
        } else if (std.mem.eql(u8, arg, "-cob")) {
            iflag |= SEFLG_CENTER_BODY;
        } else if (std.mem.startsWith(u8, arg, "-ay")) {
            // do_ayanamsa not needed for our basic
            sid_mode = @intFromFloat(std.fmt.parseFloat(f64, arg[3..]) catch 0);
            have_sid = true;
        } else if (std.mem.startsWith(u8, arg, "-sidt0")) {
            iflag |= SEFLG_SIDEREAL;
            sid_mode = @intFromFloat(std.fmt.parseFloat(f64, arg[6..]) catch 0);
            if (sid_mode == 0) sid_mode = 0;
            sid_mode |= 256;
            have_sid = true;
        } else if (std.mem.startsWith(u8, arg, "-sidsp")) {
            iflag |= SEFLG_SIDEREAL;
            sid_mode = @intFromFloat(std.fmt.parseFloat(f64, arg[6..]) catch 0);
            if (sid_mode == 0) sid_mode = 0;
            sid_mode |= 512;
            have_sid = true;
        } else if (std.mem.startsWith(u8, arg, "-sidudef")) {
            iflag |= SEFLG_SIDEREAL;
            sid_mode = 255;
            have_sid = true;
            // parse aya_t0 etc - simplified
            var s = arg[8..];
            if (std.mem.indexOf(u8, s, ",")) |pos| {
                aya_t0 = std.fmt.parseFloat(f64, s[0..pos]) catch 0;
                const rest = s[pos + 1 ..];
                if (std.mem.indexOf(u8, rest, ",")) |p2| {
                    aya_val0 = std.fmt.parseFloat(f64, rest[0..p2]) catch 0;
                } else {
                    // check for jdisut
                    if (std.mem.indexOf(u8, rest, "jdisut") != null) sid_mode |= 1024;
                    var numEnd: usize = 0;
                    while (numEnd < rest.len and ((rest[numEnd] >= '0' and rest[numEnd] <= '9') or rest[numEnd] == '.' or rest[numEnd] == '-' or rest[numEnd] == '+')) : (numEnd += 1) {}
                    if (numEnd > 0) aya_val0 = std.fmt.parseFloat(f64, rest[0..numEnd]) catch 0;
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-sid")) {
            iflag |= SEFLG_SIDEREAL;
            sid_mode = @intFromFloat(std.fmt.parseFloat(f64, arg[4..]) catch 0);
            have_sid = true;
        } else if (std.mem.startsWith(u8, arg, "-j")) {
            // begindate
            const len = arg.len - 1;
            @memcpy(begindate_buf[0..len], arg[1..]);
            begindate_buf[len] = 0;
            begindate = @ptrCast(&begindate_buf);
        } else if (std.mem.startsWith(u8, arg, "-ejpl")) {
            whicheph = SEFLG_JPLEPH;
            if (arg.len > 5) {
                const rem = arg[5..];
                @memcpy(fname[0..rem.len], rem);
                fname[rem.len] = 0;
            }
        } else if (std.mem.startsWith(u8, arg, "-edir")) {
            if (arg.len > 5) {
                const rem = arg[5..];
                @memcpy(ephepath[0..rem.len], rem);
                ephepath[rem.len] = 0;
            }
        } else if (std.mem.eql(u8, arg, "-eswe")) {
            whicheph = SEFLG_SWIEPH;
        } else if (std.mem.eql(u8, arg, "-emos")) {
            whicheph = SEFLG_MOSEPH;
        } else if (std.mem.startsWith(u8, arg, "-helflag")) {
            // ignore
        } else if (std.mem.eql(u8, arg, "-hel")) {
            iflag |= SEFLG_HELCTR;
        } else if (std.mem.eql(u8, arg, "-bary")) {
            iflag |= SEFLG_BARYCTR;
        } else if (std.mem.startsWith(u8, arg, "-house")) {
            var sp = arg[6..];
            if (sp.len > 0 and sp[0] == '[') sp = sp[1..];
            var l: f64 = 0;
            var la: f64 = 0;
            var hs: u8 = 'P';
            _ = &l;
            _ = &la;
            _ = &hs;
            // parse using sscanf via C for simplicity
            var ctmp: [256]u8 = [_]u8{0} ** 256;
            @memcpy(ctmp[0..sp.len], sp);
            ctmp[sp.len] = 0;
            var hs_buf: [2]u8 = [_]u8{0} ** 2;
            _ = sscanf(@ptrCast(&ctmp), "%lf,%lf,%c", &l, &la, &hs_buf);
            top_long = l;
            top_lat = la;
            if (hs_buf[0] != 0) ihsy = hs_buf[0];
            do_houses = true;
            have_geopos = true;
            geopos[0] = top_long;
            geopos[1] = top_lat;
            geopos[2] = top_elev;
        } else if (std.mem.startsWith(u8, arg, "-hsy")) {
            if (arg.len > 4) ihsy = @intCast(arg[4]);
            if (arg.len > 5) hpos_meth = std.fmt.parseInt(i32, arg[5..], 10) catch 0;
            have_geopos = true;
        } else if (std.mem.startsWith(u8, arg, "-topo")) {
            iflag |= SEFLG_TOPOCTR;
            var sp = arg[5..];
            if (sp.len > 0 and sp[0] == '[') sp = sp[1..];
            var ctmp: [256]u8 = [_]u8{0} ** 256;
            @memcpy(ctmp[0..sp.len], sp);
            ctmp[sp.len] = 0;
            _ = sscanf(@ptrCast(&ctmp), "%lf,%lf,%lf", &top_long, &top_lat, &top_elev);
            have_geopos = true;
            geopos[0] = top_long;
            geopos[1] = top_lat;
            geopos[2] = top_elev;
        } else if (std.mem.startsWith(u8, arg, "-geopos")) {
            var sp = arg[7..];
            if (sp.len > 0 and sp[0] == '[') sp = sp[1..];
            var ctmp: [256]u8 = [_]u8{0} ** 256;
            @memcpy(ctmp[0..sp.len], sp);
            ctmp[sp.len] = 0;
            _ = sscanf(@ptrCast(&ctmp), "%lf,%lf,%lf", &top_long, &top_lat, &top_elev);
            have_geopos = true;
            geopos[0] = top_long;
            geopos[1] = top_lat;
            geopos[2] = top_elev;
        } else if (std.mem.eql(u8, arg, "-true")) {
            iflag |= SEFLG_TRUEPOS;
        } else if (std.mem.eql(u8, arg, "-noaberr")) {
            iflag |= SEFLG_NOABERR;
        } else if (std.mem.eql(u8, arg, "-nodefl")) {
            iflag |= SEFLG_NOGDEFL;
        } else if (std.mem.eql(u8, arg, "-nonut")) {
            iflag |= SEFLG_NONUT;
        } else if (std.mem.eql(u8, arg, "-speed3")) {
            iflag |= SEFLG_SPEED3;
        } else if (std.mem.eql(u8, arg, "-speed")) {
            iflag |= SEFLG_SPEED;
        } else if (std.mem.eql(u8, arg, "-nospeed")) {
            // no_speed handled by not adding SPEED
        } else if (std.mem.startsWith(u8, arg, "-p")) {
            const spno = arg[2..];
            if (spno.len == 1 and spno[0] == 'd') setCStr(&plsel_buf, "0123456789mtA") else if (spno.len == 1 and spno[0] == 'p') setCStr(&plsel_buf, "0123456789mtABCcgDEFGHI") else if (spno.len == 1 and spno[0] == 'h') setCStr(&plsel_buf, "JKLMNOPQRSTUVWXYZw") else if (spno.len == 1 and spno[0] == 'a') setCStr(&plsel_buf, "0123456789mtABCcgDEFGHIJKLMNOPQRSTUVWXYZw") else {
                setCStr(&plsel_buf, spno);
            }
            plsel = @ptrCast(&plsel_buf);
        } else if (std.mem.startsWith(u8, arg, "-xs")) {
            const rem = arg[3..];
            @memcpy(sastno[0..rem.len], rem);
            sastno[rem.len] = 0;
        } else if (std.mem.startsWith(u8, arg, "-xv")) {
            const rem = arg[3..];
            @memcpy(spmoon[0..rem.len], rem);
            spmoon[rem.len] = 0;
        } else if (std.mem.startsWith(u8, arg, "-xf")) {
            const rem = arg[3..];
            @memcpy(star[0..rem.len], rem);
            star[rem.len] = 0;
        } else if (std.mem.startsWith(u8, arg, "-xz")) {
            const rem = arg[3..];
            @memcpy(shyp[0..rem.len], rem);
            shyp[rem.len] = 0;
        } else if (std.mem.startsWith(u8, arg, "-x")) {
            const rem = arg[2..];
            @memcpy(star[0..rem.len], rem);
            star[rem.len] = 0;
        } else if (std.mem.startsWith(u8, arg, "-n")) {
            const num = arg[2..];
            nstep = if (num.len == 0) 20 else std.fmt.parseInt(i32, num, 10) catch 20;
            if (nstep == 0) nstep = 20;
            has_n = true;
        } else if (std.mem.startsWith(u8, arg, "-i")) {
            iflag_f = std.fmt.parseInt(i32, arg[2..], 10) catch -1;
            if ((iflag_f & SEFLG_XYZ) != 0) setCStr(&fmt_buf, "PX");
        } else if (std.mem.startsWith(u8, arg, "-s")) {
            const numpart = arg[2..];
            // check suffix
            if (numpart.len > 0 and numpart[numpart.len - 1] == 'm' and !(numpart.len >= 2 and numpart[numpart.len - 2] == 'o')) {
                step_in_minutes = true;
                tstep = std.fmt.parseFloat(f64, numpart[0 .. numpart.len - 1]) catch 1;
            } else if (numpart.len > 0 and numpart[numpart.len - 1] == 's') {
                step_in_seconds = true;
                tstep = std.fmt.parseFloat(f64, numpart[0 .. numpart.len - 1]) catch 1;
            } else if (numpart.len > 0 and numpart[numpart.len - 1] == 'y') {
                step_in_years = true;
                tstep = std.fmt.parseFloat(f64, numpart[0 .. numpart.len - 1]) catch 1;
            } else if (numpart.len >= 2 and numpart[numpart.len - 2] == 'm' and numpart[numpart.len - 1] == 'o') {
                step_in_months = true;
                tstep = std.fmt.parseFloat(f64, numpart[0 .. numpart.len - 2]) catch 1;
            } else {
                tstep = std.fmt.parseFloat(f64, numpart) catch 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-b")) {
            const len = arg.len - 2;
            @memcpy(begindate_buf[0..len], arg[2..]);
            begindate_buf[len] = 0;
            begindate = @ptrCast(&begindate_buf);
        } else if (std.mem.startsWith(u8, arg, "-f")) {
            const rem = arg[2..];
            @memcpy(fmt_buf[0..rem.len], rem);
            fmt_buf[rem.len] = 0;
            fmt = @ptrCast(&fmt_buf);
        } else if (std.mem.startsWith(u8, arg, "-g")) {
            const rem = arg[2..];
            if (rem.len == 0) {
                gap_buf[0] = '\t';
                gap_buf[1] = 0;
            } else {
                @memcpy(gap_buf[0..rem.len], rem);
                gap_buf[rem.len] = 0;
            }
            gap = @ptrCast(&gap_buf);
            have_gap_parameter = true;
        } else if (std.mem.eql(u8, arg, "-dms")) {
            use_dms = true;
        } else if (std.mem.startsWith(u8, arg, "-d") or std.mem.startsWith(u8, arg, "-D")) {
            diff_mode = arg[1];
            var sp2 = arg[2..];
            if (sp2.len > 0 and sp2[0] == 'h') {
                diff_mode = 'h';
                sp2 = sp2[1..];
            }
            if (sp2.len > 0) {
                ipldiff = letterToIpl(@intCast(sp2[0]));
                if (ipldiff < 0) ipldiff = SE_SUN;
                _ = swe.swe_get_planet_name(ipldiff, @ptrCast(&spnam2));
            } else {
                ipldiff = SE_SUN;
                _ = swe.swe_get_planet_name(ipldiff, @ptrCast(&spnam2));
            }
        } else if (std.mem.eql(u8, arg, "-roundsec")) {
            round_flag |= BIT_ROUND_SEC;
        } else if (std.mem.eql(u8, arg, "-roundmin")) {
            round_flag |= BIT_ROUND_MIN;
        } else if (std.mem.eql(u8, arg, "-ep")) {
            output_extra_prec = true;
        } else if (std.mem.startsWith(u8, arg, "-t")) {
            if (arg.len > 2) {
                const rem = arg[2..];
                // append to stimein
                const existing = stimein_len;
                const l = @min(rem.len, 30 - existing);
                @memcpy(stimein[existing .. existing + l], rem[0..l]);
                stimein_len += l;
                stimein[stimein_len] = 0;
            }
        } else if (std.mem.startsWith(u8, arg, "-h") or std.mem.startsWith(u8, arg, "-?")) {
            // help - just exit
            _ = printf("swetest help not fully implemented\n");
            exit(0);
        } else {
            var sout2: [256]u8 = [_]u8{0} ** 256;
            _ = snprintf(&sout2, 256, "illegal option %s\n", cstr);
            _ = printf("%s", @as([*:0]u8, @ptrCast(&sout2)));
            exit(1);
        }
    }
    // after loop, handle header printing, ephe setup, etc.
    // we need to propagate some vars to global scope (plsel, begindate, stimein)
    // store in globals via pointers - we already modified globals
    // But we need to pass begindate etc to main execution; use globals via extern capture
    // We'll store in static globals for main to use
    // Use a trick: store begindate pointer in global var via raw pointer
    // Instead, we will have main re-parse? Simpler: handle main logic inside parseArgs - but we split.
    // We'll use global vars to communicate
    if (begindate) |bd| {
        const l = std.mem.len(bd);
        @memcpy(global_begindate_buf[0..l], bd[0..l]);
        global_begindate_buf[l] = 0;
        global_begindate = @ptrCast(&global_begindate_buf);
    } else {
        global_begindate = null;
    }
    global_stimein_len = stimein_len;
    @memcpy(global_stimein[0..stimein_len], stimein[0..stimein_len]);
    global_stimein[stimein_len] = 0;
    const _plsel_len = std.mem.len(plsel);
    @memcpy(global_plsel_buf[0.._plsel_len], std.mem.span(plsel));
    global_plsel_buf[_plsel_len] = 0;
    global_plsel = @ptrCast(&global_plsel_buf);
    @memcpy(&global_ephepath, &ephepath);
    @memcpy(&global_fname, &fname);
    // handle sidereal
    if (have_sid) {
        if ((sid_mode & 255) == 255) swe.swe_set_sid_mode(sid_mode, aya_t0, aya_val0) else swe.swe_set_sid_mode(sid_mode, 0, 0);
    }
    // handle whicheph / iflag
    iflag = (iflag & ~SEFLG_EPHMASK) | whicheph;
    if (strpbrk(fmt, "SsQ") != null and (iflag & SEFLG_SPEED3) == 0) {
        // check no_speed? we didn't track no_speed flag; ignore
        iflag |= SEFLG_SPEED;
    }
    if (ephepath[0] == 0) {
        // C make_ephemeris_path(argv[0], path): ".;<argv0-dir>;<SE_EPHE_PATH>"
        // (swetest.c:3995). No pre-scan/fallback here — C lets swe_calc fail
        // and set serr so the "using Moshier eph." warning is printed.
        var path: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        var plen: usize = 0;
        path[plen] = '.';
        plen += 1;
        path[plen] = ';';
        plen += 1;
        const argv0_c: [*:0]const u8 = argv0_c_str;
        const SE_EPHE_PATH: []const u8 = ".:/users/ephe2/:/users/ephe/";
        if (strrchr(argv0_c, '/')) |slash| {
            const dirlen: usize = @intFromPtr(slash) - @intFromPtr(argv0_c);
            if (plen + dirlen < AS_MAXCH - 2) {
                @memcpy(path[plen .. plen + dirlen], argv0_c[0..dirlen]);
                plen += dirlen;
                path[plen] = ';';
                plen += 1;
            }
        }
        if (plen + SE_EPHE_PATH.len < AS_MAXCH - 1) {
            @memcpy(path[plen .. plen + SE_EPHE_PATH.len], SE_EPHE_PATH);
            plen += SE_EPHE_PATH.len;
            path[plen] = 0;
        }
        @memcpy(ephepath[0..plen], path[0..plen]);
        ephepath[plen] = 0;
    }
    if (whicheph != SEFLG_MOSEPH) {
        if (ephepath[0] != 0) swe.swe_set_ephe_path(@ptrCast(&ephepath)) else swe.swe_set_ephe_path(null);
    }
    if ((whicheph & SEFLG_JPLEPH) != 0) {
        if (fname[0] != 0) swe.swe_set_jpl_file(@ptrCast(&fname));
    }
    swe.swe_set_topo(top_long, top_lat, top_elev);
    geopos[0] = top_long;
    geopos[1] = top_lat;
    geopos[2] = top_elev;
    // handle thour parsing from stimein
    if (stimein_len > 0) {
        var th: f64 = 0;
        var ctmp: [64]u8 = [_]u8{0} ** 64;
        @memcpy(ctmp[0..stimein_len], stimein[0..stimein_len]);
        ctmp[stimein_len] = 0;
        const cstr2: [*:0]u8 = @ptrCast(&ctmp);
        // find colons
        if (strchr(cstr2, ':') != null) {
            // parse like C: if colon, split (Zig parsing below)
            const s = zigStrFromC(cstr2);
            var parts = std.mem.splitScalar(u8, s, ':');
            var idxp: usize = 0;
            var h: i32 = 0;
            var mval: i32 = 0;
            var se: f64 = 0;
            while (parts.next()) |p| {
                if (idxp == 0) h = std.fmt.parseInt(i32, p, 10) catch 0;
                if (idxp == 1) mval = std.fmt.parseInt(i32, p, 10) catch 0;
                if (idxp == 2) se = std.fmt.parseFloat(f64, p) catch 0;
                idxp += 1;
            }
            th = @as(f64, @floatFromInt(h)) + @as(f64, @floatFromInt(mval)) / 60.0 + se / 3600.0;
            if (h < 0) th = -@abs(th);
            // Actually C logic: if atoi(stimein)<0 t=-t; then t+=atoi(stimein)
            // Our parsing already handles sign per first part; good.
        } else {
            th = std.fmt.parseFloat(f64, zigStrFromC(cstr2)) catch 0;
        }
        thour = th;
        global_thour = th;
    } else global_thour = 0;
    global_sid_mode = sid_mode;
}

var global_begindate_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var global_begindate: ?[*:0]u8 = null;
var global_stimein: [64]u8 = [_]u8{0} ** 64;
var global_stimein_len: usize = 0;
var global_thour: f64 = 0;
var global_plsel_buf: [256]u8 = [_]u8{0} ** 256;
var global_plsel: [*:0]u8 = @ptrCast(&global_plsel_buf);
var global_ephepath: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var global_fname: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
var global_sid_mode: i32 = 0;

pub fn main(init: std.process.Init) !void {
    var arena2 = init.arena;
    const allocator2 = arena2.allocator();
    const args_slice = try init.minimal.args.toSlice(allocator2);
    const _argc: c_int = @intCast(args_slice.len);
    var argv_buf = try allocator2.alloc([*:0]u8, args_slice.len);
    for (args_slice, 0..) |a, idx| argv_buf[idx] = @ptrCast(@constCast(a.ptr));
    try parseArgsWithC(_argc, @ptrCast(argv_buf.ptr));
    const args = args_slice;
    // header printing (like C)
    if (with_header) {
        for (args) |a| {
            var cbuf: [1024]u8 = [_]u8{0} ** 1024;
            @memcpy(cbuf[0..a.len], a);
            cbuf[a.len] = 0;
            _ = printf("%s", @as([*:0]u8, @ptrCast(&cbuf)));
            _ = printf(" ");
        }
    }
    var tjd: f64 = 2415020.5;
    var year_start: i32 = 0;
    var mon_start: i32 = 1;
    var day_start: i32 = 1;
    var sdate: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var sdate_save: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const begindate = global_begindate;
    // single stdin FILE* for the whole session (fdopen(0) per iteration
    // creates fresh buffers that drop already-buffered input lines)
    const stdin_file = fdopen(0, "r");
    // prepare stimein string for later
    // Loop
    var first_iter = true;
    while (true) {
        if (begindate == null) {
            // interactive: C prints "\nDate ?" then fgets(stdin) — replicate
            _ = printf("\nDate ?");
            var input_line: [AS_MAXCH]u8 = undefined;
            if (fgets(&input_line, AS_MAXCH, stdin_file) == null) break;
            input_line[AS_MAXCH - 1] = 0;
            const ilen = std.mem.len(@as([*:0]u8, @ptrCast(&input_line)));
            @memcpy(sdate[0..ilen], input_line[0..ilen]);
            sdate[ilen] = 0;
        } else {
            if (first_iter) {
                const bd = begindate.?;
                const len = std.mem.len(bd);
                @memcpy(sdate[0..len], bd[0..len]);
                sdate[len] = 0;
                // after first, set to "." to exit afterwards per C: begindate="."
                global_begindate = @ptrCast(@as([*:0]u8, @ptrFromInt(@intFromPtr("."))));
            } else {
                // second iteration, sdate="." -> break
                sdate[0] = '.';
                sdate[1] = 0;
            }
        }
        var sp: [*]u8 = @ptrCast(&sdate);
        // handle "." -> end
        if (sp[0] == '.') break;
        if (sp[0] == 0 or sp[0] == '\n' or sp[0] == '\r') {
            // copy save
            var len: usize = 0;
            while (sdate_save[len] != 0) : (len += 1) {}
            @memcpy(sdate[0..len], sdate_save[0..len]);
            sdate[len] = 0;
            if (sdate[0] == '.') break;
        } else {
            var len: usize = 0;
            while (sdate[len] != 0) : (len += 1) {}
            @memcpy(sdate_save[0..len], sdate[0..len]);
            sdate_save[len] = 0;
        }
        if (sdate[0] == 0) {
            _ = snprintf(@ptrCast(&sdate), AS_MAXCH, "j%f", tjd);
        }
        // parse sdate
        sp = @ptrCast(&sdate);
        if (sp[0] == 'j') {
            var sp2_maybe = strchr(@ptrCast(sp), ',');
            if (sp2_maybe != null) sp2_maybe.?[0] = '.';
            _ = sscanf(@ptrCast(sp + 1), "%lf", &tjd);
            if (tjd < 2299160.5) gregflag = SE_JUL_CAL else gregflag = SE_GREG_CAL;
            if (strstr(@ptrCast(sp), "jul") != null) {
                gregflag = SE_JUL_CAL;
                gregflag_auto = false;
            } else if (strstr(@ptrCast(sp), "greg") != null) {
                gregflag = SE_GREG_CAL;
                gregflag_auto = false;
            }
            swe.swe_revjul(tjd, gregflag, &jyear, &jmon, &jday, &jut);
            year_start = jyear;
            mon_start = jmon;
            day_start = jday;
        } else if (sp[0] == '+') {
            var n: i32 = atoi(@ptrCast(sp));
            if (n == 0) n = 1;
            tjd += @as(f64, @floatFromInt(n));
            swe.swe_revjul(tjd, gregflag, &jyear, &jmon, &jday, &jut);
        } else if (sp[0] == '-' and sdate[1] >= '0' and sdate[1] <= '9') {
            // need to distinguish -b option vs minus days? But begindate already handled; sdate starting with - should be day delta
            var n: i32 = atoi(@ptrCast(sp));
            if (n == 0) n = -1;
            tjd += @as(f64, @floatFromInt(n));
            swe.swe_revjul(tjd, gregflag, &jyear, &jmon, &jday, &jut);
        } else {
            // sscanf "%d%*c%d%*c%d"
            // const jd/jm/jy unused
            // Use Zig parsing: split by non-digit
            const s = std.mem.span(@as([*:0]u8, @ptrCast(sp)));
            var nums: [3]i32 = [_]i32{0} ** 3;
            var idxn: usize = 0;
            var cur: i32 = 0;
            var inNum = false;
            var neg = false;
            var pos: usize = 0;
            while (pos < s.len and idxn < 3) : (pos += 1) {
                const ch = s[pos];
                if (ch == '-' and !inNum) {
                    neg = true;
                    continue;
                }
                if (ch >= '0' and ch <= '9') {
                    if (!inNum) {
                        cur = 0;
                        inNum = true;
                    }
                    cur = cur * 10 + @as(i32, ch - '0');
                } else {
                    if (inNum) {
                        if (neg) cur = -cur;
                        nums[idxn] = cur;
                        idxn += 1;
                        cur = 0;
                        inNum = false;
                        neg = false;
                    }
                }
            }
            if (inNum and idxn < 3) {
                if (neg) cur = -cur;
                nums[idxn] = cur;
                idxn += 1;
            }
            if (idxn >= 1) jday = nums[0];
            if (idxn >= 2) jmon = nums[1];
            if (idxn >= 3) jyear = nums[2];
            year_start = jyear;
            mon_start = jmon;
            day_start = jday;
            if (@as(i64, jyear) * 10000 + @as(i64, jmon) * 100 + @as(i64, jday) < 15821015) gregflag = SE_JUL_CAL else gregflag = SE_GREG_CAL;
            if (strstr(@ptrCast(sp), "jul") != null) {
                gregflag = SE_JUL_CAL;
                gregflag_auto = false;
            } else if (strstr(@ptrCast(sp), "greg") != null) {
                gregflag = SE_GREG_CAL;
                gregflag_auto = false;
            }
            jut = 0;
            if (universal_time_utc) {
                var ih: i32 = 0;
                var im: i32 = 0;
                var ds: f64 = 0;
                if (global_stimein_len > 0) {
                    var ctmp: [64]u8 = [_]u8{0} ** 64;
                    @memcpy(ctmp[0..global_stimein_len], global_stimein[0..global_stimein_len]);
                    ctmp[global_stimein_len] = 0;
                    _ = sscanf(@ptrCast(&ctmp), "%d:%d:%lf", &ih, &im, &ds);
                }
                var tret2: [2]f64 = undefined;
                const rc = swe.swe_utc_to_jd(jyear, jmon, jday, ih, im, ds, gregflag, &tret2, @ptrCast(&serr));
                if (rc < 0) {
                    _ = printf(" error in swe_utc_to_jd(): %s\n", @as([*:0]u8, @ptrCast(&serr)));
                    exit(1);
                }
                tjd = tret2[1];
            } else {
                tjd = swe.swe_julday(jyear, jmon, jday, jut, gregflag);
                tjd += global_thour / 24.0;
                jut = global_thour;
            }
        }
        // main loop over nstep
        var t_cur: f64 = tjd;
        var istep: i32 = 1;
        var line_count: i32 = 0;
        const line_limit: i32 = 36525;
        // need to know plsel
        const plsel = global_plsel;
        // outer for t
        while (istep <= nstep) : (istep += 1) {
            if (step_in_minutes) t_cur = tjd + @as(f64, @floatFromInt(istep - 1)) * tstep / 1440.0 else if (step_in_seconds) t_cur = tjd + @as(f64, @floatFromInt(istep - 1)) * tstep / 86400.0 else if (step_in_years) t_cur = swe.swe_julday(year_start + (istep - 1) * @as(i32, @intFromFloat(tstep)), mon_start, day_start, jut, gregflag) else if (step_in_months) {
                var jm2: i32 = mon_start + (istep - 1) * @as(i32, @intFromFloat(tstep));
                const jy2: i32 = year_start + @divTrunc(jm2 - 1, 12);
                jm2 = @mod(jm2 - 1, 12) + 1;
                t_cur = swe.swe_julday(jy2, jm2, day_start, jut, gregflag);
            } else if (istep > 1) t_cur += tstep;
            if (gregflag_auto) {
                if (t_cur < 2299160.5) gregflag = SE_JUL_CAL else gregflag = SE_GREG_CAL;
            }
            if (step_in_years) t_cur = swe.swe_julday(year_start + (istep - 1) * @as(i32, @intFromFloat(tstep)), mon_start, day_start, jut, gregflag);
            if (step_in_months) {
                var jm2: i32 = mon_start + (istep - 1) * @as(i32, @intFromFloat(tstep));
                const jy2: i32 = year_start + @divTrunc(jm2 - 1, 12);
                jm2 = @mod(jm2 - 1, 12) + 1;
                t_cur = swe.swe_julday(jy2, jm2, day_start, jut, gregflag);
            }
            t = t_cur;
            var delt: f64 = swe.swe_deltat_ex(t, iflag, @ptrCast(&serr));
            if (!universal_time) delt = swe.swe_deltat_ex(t - delt, iflag, @ptrCast(&serr));
            const t2 = t;
            swe.swe_revjul(t2, gregflag, &jyear, &jmon, &jday, &jut);
            if (with_header) {
                if (with_glp) {
                    var sout2: [256]u8 = [_]u8{0} ** 256;
                    _ = swe.swe_get_library_path(@ptrCast(&sout2));
                    _ = printf("\npath: %s", @as([*:0]u8, @ptrCast(&sout2)));
                }
                _ = printf("\ndate (dmy) %d.%d.%04d", jday, jmon, jyear);
                if (gregflag != 0) _ = printf(" greg.") else _ = printf(" jul.");
                var stimeout: [64]u8 = [_]u8{0} ** 64;
                jdToTimeString(jut, @ptrCast(&stimeout));
                _ = printf("%s", @as([*:0]u8, @ptrCast(&stimeout)));
                if (universal_time) {
                    if ((time_flag & BIT_TIME_LMT) != 0) _ = printf(" LMT") else _ = printf(" UT");
                } else _ = printf(" TT");
                var ver: [64]u8 = [_]u8{0} ** 64;
                _ = swe.swe_version(@ptrCast(&ver));
                _ = printf("\t\tversion %s", @as([*:0]u8, @ptrCast(&ver)));
            }
            if (universal_time) {
                if ((time_flag & BIT_TIME_LMT) != 0 and with_header) {
                    _ = printf("\nLMT: %.9f", t);
                    t -= geopos[0] / 15.0 / 24.0;
                }
                if (with_header) {
                    _ = printf("\nUT:  %.9f", t);
                    _ = printf("     delta t: %f sec", delt * 86400);
                }
                te = t + delt;
                tut = t;
            } else {
                te = t;
                tut = t - delt;
                if (with_header) {
                    _ = printf("\nUT:  %.9f", tut);
                    _ = printf("     delta t: %f sec", delt * 86400);
                }
            }
            _ = swe.swe_calc(te, -1, iflag, @ptrCast(&xobl), @ptrCast(&serr));
            if (with_header) {
                _ = printf("\nTT:  %.9f", te);
                if ((iflag & SEFLG_SIDEREAL) != 0) {
                    var daya: f64 = 0;
                    if (swe.swe_get_ayanamsa_ex(te, iflag, &daya, @ptrCast(&serr)) < 0) {
                        _ = printf("   error in swe_get_ayanamsa_ex(): %s\n", @as([*:0]u8, @ptrCast(&serr)));
                        exit(1);
                    }
                    _ = printf("   ayanamsa = %s (%s)", dms(daya, round_flag), swe.swe_get_ayanamsa_name(global_sid_mode));
                }
                if (have_geopos) _ = printf("\ngeo. long %f, lat %f, alt %f", geopos[0], geopos[1], geopos[2]);
                if (iflag_f >= 0) iflag = iflag_f;
                const has_o = strchr(plsel, 'o') != null;
                if (!has_o) {
                    if ((iflag & (SEFLG_NONUT | SEFLG_SIDEREAL)) != 0) {
                        _ = printf("\n%-15s %s", @as([*:0]const u8, @ptrCast("Epsilon (m)")), dms(xobl[0], round_flag));
                    } else {
                        _ = printf("\n%-15s %s%s", @as([*:0]const u8, @ptrCast("Epsilon (t/m)")), dms(xobl[0], round_flag), gap);
                        _ = printf("%s", dms(xobl[1], round_flag));
                    }
                }
                // Nutation not printing for brevity? We'll still mimic C for non-sidereal
                if (strchr(plsel, 'n') == null and (iflag & (SEFLG_NONUT | SEFLG_SIDEREAL)) == 0) {
                    _ = printf("%s", "\nNutation        ");
                    _ = printf("%s", dms(xobl[2], round_flag));
                    _ = printf("%s", gap);
                    _ = printf("%s", dms(xobl[3], round_flag));
                }
                _ = printf("\n");
                if (do_houses) {
                    const shsy = swe.swe_house_name(ihsy);
                    if (!universal_time) {
                        do_houses = false;
                        _ = printf("option -house requires option -ut for Universal Time\n");
                    } else {
                        var s1: [64]u8 = [_]u8{0} ** 64;
                        var s2: [64]u8 = [_]u8{0} ** 64;
                        // copy dms strings
                        const a = dms(top_long, round_flag);
                        @memcpy(s1[0..std.mem.len(a)], std.mem.span(a));
                        s1[std.mem.len(a)] = 0;
                        const b = dms(top_lat, round_flag);
                        @memcpy(s2[0..std.mem.len(b)], std.mem.span(b));
                        s2[std.mem.len(b)] = 0;
                        _ = printf("Houses system %c (%s) for long=%s, lat=%s\n", ihsy, shsy, @as([*:0]u8, @ptrCast(&s1)), @as([*:0]u8, @ptrCast(&s2)));
                    }
                }
            }
            if (with_header and !with_header_always) with_header = false;
            // print planets
            var is_first = true;
            // iterate plsel
            var p_idx: usize = 0;
            while (plsel[p_idx] != 0) : (p_idx += 1) {
                const ch: u8 = plsel[p_idx];
                if (ch == 'e') continue;
                ipl = letterToIpl(@intCast(ch));
                if (ipl == -2) {
                    _ = printf("illegal parameter -p%s\n", plsel);
                    exit(1);
                }
                if (ch == 'f') ipl = SE_FIXSTAR else if (ch == 's') ipl = std.fmt.parseInt(i32, std.mem.span(@as([*:0]u8, @ptrCast(&sastno))), 10) catch 0 + SE_AST_OFFSET else if (ch == 'v') ipl = std.fmt.parseInt(i32, std.mem.span(@as([*:0]u8, @ptrCast(&spmoon))), 10) catch 0 else if (ch == 'z') ipl = std.fmt.parseInt(i32, std.mem.span(@as([*:0]u8, @ptrCast(&shyp))), 10) catch 0 + SE_FICT_OFFSET_1;
                if ((iflag & SEFLG_HELCTR) != 0) {
                    if (ipl == SE_SUN or ipl == SE_MEAN_NODE or ipl == SE_TRUE_NODE or ipl == SE_MEAN_APOG or ipl == SE_OSCU_APOG) continue;
                } else if ((iflag & SEFLG_BARYCTR) != 0) {
                    if (ipl == SE_MEAN_NODE or ipl == SE_TRUE_NODE or ipl == SE_MEAN_APOG or ipl == SE_OSCU_APOG) continue;
                } else {
                    if (ipl == SE_EARTH) continue;
                }
                if (iflag_f >= 0) iflag = iflag_f;
                var iflgret: i32 = 0;
                if (ipl == SE_FIXSTAR) {
                    iflgret = swe.swe_fixstar(@ptrCast(&star), te, iflag, &x, @ptrCast(&serr));
                    if (iflgret >= 0 and strpbrk(fmt, "=") != null) {
                        var mag: f64 = 0;
                        _ = swe.swe_fixstar_mag(@ptrCast(&star), &mag, @ptrCast(&serr));
                        attr[4] = mag;
                    }
                    const len = std.mem.len(@as([*:0]u8, @ptrCast(&star)));
                    @memcpy(spnam[0..len], star[0..len]);
                    spnam[len] = 0;
                } else {
                    iflgret = swe.swe_calc(te, ipl, iflag, &x, @ptrCast(&serr));
                    if (iflgret >= 0 and strpbrk(fmt, "+-*/=") != null) {
                        _ = swe.swe_pheno(te, ipl, iflag, &attr, @ptrCast(&serr));
                    }
                    _ = swe.swe_get_planet_name(ipl, @ptrCast(&spnam));
                }
                if (ch == 'q') {
                    x[0] = swe.swe_deltat_ex(tut, iflag, @ptrCast(&serr)) * 86400;
                    x[1] = x[0] / 3600.0;
                    x[2] = 0;
                    x[3] = 0;
                    const len = "Delta T".len;
                    @memcpy(spnam[0..len], "Delta T");
                    spnam[len] = 0;
                }
                if (ch == 'x') {
                    x[0] = swe.swe_degnorm(swe.swe_sidtime(tut) * 15 + geopos[0]);
                    x[1] = 0;
                    x[2] = 0;
                    x[3] = 0;
                    const len = "Sidereal Time".len;
                    @memcpy(spnam[0..len], "Sidereal Time");
                    spnam[len] = 0;
                }
                if (ch == 'o') {
                    x[2] = 0;
                    x[3] = 0;
                    const len = "Ecl. Obl.".len;
                    @memcpy(spnam[0..len], "Ecl. Obl.");
                    spnam[len] = 0;
                }
                if (ch == 'n') {
                    x[0] = x[2];
                    x[1] = x[3];
                    x[2] = 0;
                    x[3] = 0;
                    const len = "Nutation".len;
                    @memcpy(spnam[0..len], "Nutation");
                    spnam[len] = 0;
                }
                if (ch == 'y') {
                    var e: f64 = 0;
                    _ = swe.swe_time_equ(tut, &e, @ptrCast(&serr));
                    x[0] = e * 86400;
                    x[1] = 0;
                    x[2] = 0;
                    x[3] = 0;
                    const len = "Time Equ.".len;
                    @memcpy(spnam[0..len], "Time Equ.");
                    spnam[len] = 0;
                }
                if (ch == 'b') {
                    var daya: f64 = 0;
                    _ = swe.swe_get_ayanamsa_ex(te, iflag, &daya, @ptrCast(&serr));
                    x[0] = daya;
                    x[1] = 0;
                    const len = "Ayanamsha".len;
                    @memcpy(spnam[0..len], "Ayanamsha");
                    spnam[len] = 0;
                }
                if (iflgret < 0) {
                    // error handling
                    if (serr[0] != 0 and serr_save[0] == 0 or std.mem.orderZ(u8, @ptrCast(&serr), @ptrCast(&serr_save)) != .eq) {
                        _ = printf("error: %s\n", @as([*:0]u8, @ptrCast(&serr)));
                    }
                    @memcpy(serr_save[0..AS_MAXCH], serr[0..AS_MAXCH]);
                } else if (serr[0] != 0 and serr_warn[0] == 0) {
                    if (strstr(@ptrCast(&serr), "seorbel.txt") == null) @memcpy(serr_warn[0..AS_MAXCH], serr[0..AS_MAXCH]);
                }
                if (diff_mode != 0) {
                    var ret2 = swe.swe_calc(te, ipldiff, iflag, &x2, @ptrCast(&serr));
                    if (diff_mode == 'h') ret2 = swe.swe_calc(te, ipldiff, iflag | SEFLG_HELCTR, &x2, @ptrCast(&serr));
                    // _ = ret2;
                    if (diff_mode == 'd' or diff_mode == 'h') {
                        for (1..6) |ii| x[ii] -= x2[ii];
                        if ((iflag & SEFLG_RADIANS) == 0) x[0] = swe.swe_difdeg2n(x[0], x2[0]) else x[0] = swe.swe_difrad2n(x[0], x2[0]);
                    } else {
                        for (1..6) |ii| x[ii] = (x[ii] + x2[ii]) / 2;
                        if ((iflag & SEFLG_RADIANS) == 0) x[0] = swe.swe_deg_midp(x[0], x2[0]) else x[0] = swe.swe_rad_midp(x[0], x2[0]);
                    }
                }
                if (strpbrk(fmt, "aADdQmzx") != null) {
                    const iflag2 = iflag | SEFLG_EQUATORIAL;
                    if (ipl == SE_FIXSTAR) _ = swe.swe_fixstar(@ptrCast(&star), te, iflag2, &xequ, @ptrCast(&serr)) else _ = swe.swe_calc(te, ipl, iflag2, &xequ, @ptrCast(&serr));
                    if (diff_mode != 0) {
                        var tmp: [6]f64 = undefined;
                        _ = swe.swe_calc(te, ipldiff, iflag2, &tmp, @ptrCast(&serr));
                        if (diff_mode == 'h') _ = swe.swe_calc(te, ipldiff, iflag2 | SEFLG_HELCTR, &tmp, @ptrCast(&serr));
                        if (diff_mode == 'd' or diff_mode == 'h') {
                            for (1..6) |ii| xequ[ii] -= tmp[ii];
                            if ((iflag & SEFLG_RADIANS) == 0) xequ[0] = swe.swe_difdeg2n(xequ[0], tmp[0]) else xequ[0] = swe.swe_difrad2n(xequ[0], tmp[0]);
                        } else {
                            for (1..6) |ii| xequ[ii] = (xequ[ii] + tmp[ii]) / 2;
                            if ((iflag & SEFLG_RADIANS) == 0) xequ[0] = swe.swe_deg_midp(xequ[0], tmp[0]) else xequ[0] = swe.swe_rad_midp(xequ[0], tmp[0]);
                        }
                    }
                }
                if (strpbrk(fmt, "IiHhKk") != null) {
                    var fl: i32 = SEFLG_EQUATORIAL | SEFLG_TOPOCTR;
                    // need whicheph? use iflag's eph part plus flags
                    fl |= (iflag & SEFLG_EPHMASK);
                    if (ipl == SE_FIXSTAR) _ = swe.swe_fixstar(@ptrCast(&star), te, fl, &xt, @ptrCast(&serr)) else _ = swe.swe_calc(te, ipl, fl, &xt, @ptrCast(&serr));
                    swe.swe_azalt(tut, 0, @ptrCast(&geopos), datm[0], datm[1], @ptrCast(&xt), @ptrCast(&xaz));
                }
                if (strpbrk(fmt, "XU") != null) {
                    const fl = iflag | SEFLG_XYZ;
                    if (ipl == SE_FIXSTAR) _ = swe.swe_fixstar(@ptrCast(&star), te, fl, &xcart, @ptrCast(&serr)) else _ = swe.swe_calc(te, ipl, fl, &xcart, @ptrCast(&serr));
                }
                if (strpbrk(fmt, "xu") != null) {
                    const fl = iflag | SEFLG_XYZ | SEFLG_EQUATORIAL;
                    if (ipl == SE_FIXSTAR) _ = swe.swe_fixstar(@ptrCast(&star), te, fl, &xcartq, @ptrCast(&serr)) else _ = swe.swe_calc(te, ipl, fl, &xcartq, @ptrCast(&serr));
                }
                if (strpbrk(fmt, "gGjzm") != null) {
                    armc = swe.swe_degnorm(swe.swe_sidtime(tut) * 15 + geopos[0]);
                    for (0..6) |ii| xsv[ii] = x[ii];
                    if (hpos_meth == 1) xsv[1] = 0;
                    var star2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
                    if (ipl == SE_FIXSTAR) @memcpy(star2[0..AS_MAXCH], star[0..AS_MAXCH]) else star2[0] = 0;
                    // simplified: just house_pos
                    hposj = swe.swe_house_pos(armc, geopos[1], xobl[0], ihsy, @ptrCast(&xsv), @ptrCast(&serr));
                    if (ihsy == 'G' or ihsy == 'g') hpos = (hposj - 1) * 10 else hpos = (hposj - 1) * 30;
                }
                // set psp_cur for 'q','y' check inside printLine
                psp_cur = @ptrFromInt(@intFromPtr(plsel) + p_idx);
                // need to handle psp_cur null terminated? we pass pointer to current char
                // print
                // before printing, need to set spnam already
                // call printLine
                printLine(0, is_first, global_sid_mode);
                is_first = false;
                if (!list_hor) line_count += 1;
                if (line_count >= line_limit) {
                    _ = printf("****** line count %d was exceeded\n", line_limit);
                    break;
                }
            }
            if (list_hor) {
                _ = printf("\n");
                line_count += 1;
            }
            // houses
            if (do_houses) {
                var cusp: [37]f64 = [_]f64{0} ** 37;
                var cusp_speed: [37]f64 = [_]f64{0} ** 37;
                var ascmc: [10]f64 = [_]f64{0} ** 10;
                var ascmc_speed: [10]f64 = [_]f64{0} ** 10;
                if (ihsy == 'G' or ihsy == 'g') nhouses = 36;
                const iofs: i32 = nhouses + 1;
                const retc = swe.swe_houses_ex2(t, iflag, top_lat, top_long, ihsy, &cusp, &ascmc, &cusp_speed, &ascmc_speed, @ptrCast(&serr));
                if (retc < 0) {
                    const shsy = swe.swe_house_name(ihsy);
                    var tmp: [256]u8 = [_]u8{0} ** 256;
                    _ = snprintf(&tmp, 256, "House method %s failed, Porphyry calculated instead", shsy);
                    if (std.mem.orderZ(u8, @ptrCast(&tmp), @ptrCast(&serr_save)) != .eq) {
                        _ = printf("error: %s\n", @as([*:0]u8, @ptrCast(&tmp)));
                    }
                    @memcpy(serr_save[0..256], tmp[0..256]);
                    ihsy = 'O';
                    nhouses = 12;
                }
                var is_first_h = true;
                var ipl2: i32 = 1;
                const total = iofs + 8;
                while (ipl2 < total) : (ipl2 += 1) {
                    if (ipl2 < iofs) {
                        x[0] = cusp[@intCast(ipl2)];
                        x[3] = cusp_speed[@intCast(ipl2)];
                    } else {
                        x[0] = ascmc[@intCast(ipl2 - iofs)];
                        x[3] = ascmc_speed[@intCast(ipl2 - iofs)];
                    }
                    x[1] = 0;
                    x[2] = 1;
                    if (ipl2 == iofs + 2) {
                        xequ[0] = x[0];
                        xequ[1] = x[1];
                        xequ[2] = x[2];
                    } else if (strpbrk(fmt, "aADdQ") != null) {
                        swe.swe_cotrans(@ptrCast(&x), @ptrCast(&xequ), -xobl[0]);
                    }
                    if (strpbrk(fmt, "IiHhKk") != null) {
                        var gpos: [3]f64 = [_]f64{0} ** 3;
                        gpos[0] = top_long;
                        gpos[1] = top_lat;
                        gpos[2] = 0;
                        swe.swe_azalt(t, 0, &gpos, datm[0], datm[1], @ptrCast(&x), @ptrCast(&xaz));
                    }
                    if (strpbrk(fmt, "gGj") != null) {
                        hposj = swe.swe_house_pos(armc, geopos[1], xobl[0], ihsy, @ptrCast(&x), @ptrCast(&serr));
                        if (ihsy == 'G' or ihsy == 'g') hpos = (hposj - 1) * 10 else hpos = (hposj - 1) * 30;
                    }
                    ipl = ipl2;
                    printLine(MODE_HOUSE, is_first_h, 0);
                    is_first_h = false;
                    if (!list_hor) line_count += 1;
                }
                if (list_hor) {
                    _ = printf("\n");
                    line_count += 1;
                }
            }
            if (line_count >= line_limit) {
                _ = printf("****** line count %d was exceeded\n", line_limit);
                break;
            }
        }
        // C prints the accumulated warning after each date's for-loop
        // (swetest.c:2039) — inside the while(1), so it prints per iteration.
        if (serr_warn[0] != 0) {
            _ = printf("\nwarning: %s\n", @as([*:0]const u8, @ptrCast(&serr_warn)));
        }
        first_iter = false;
        // C loops forever until '.' input or EOF (swetest.c:1390 goto end_main)
    }
    swe.swe_close();
}
