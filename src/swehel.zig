// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port — swehel module (heliacal events).
// Port of swehel.c; see docs/parity.md for the bit-parity contract.
// C function-local statics live in SwehelCtx (order-dependent, like C).
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");
const sweph = @import("sweph");
const swecl = @import("swecl");

const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;
const swe_shim_tan = lib.swe_shim_tan;
const swe_shim_asin = lib.swe_shim_asin;
const swe_shim_acos = lib.swe_shim_acos;
const swe_shim_atan2 = lib.swe_shim_atan2;
const swe_shim_pow = lib.swe_shim_pow;
const swe_shim_log = lib.swe_shim_log;
const swe_shim_log10 = lib.swe_shim_log10;
const swe_shim_exp = lib.swe_shim_exp;

const AstroModels = lib.AstroModels;
const DeltatCtx = deltat.DeltatCtx;
const Swed = sweph.Swed;
const SweclCtx = swecl.SweclCtx;
const AS_MAXCH = 256;

const DEGTORAD = lib.DEGTORAD;
const RADTODEG = lib.RADTODEG;
const PI = lib.PI;
const AUNIT = lib.AUNIT;
const CLIGHT = lib.CLIGHT;
const J2000 = lib.J2000;

const OK = lib.OK;
const ERR = lib.ERR;
const NOT_AVAILABLE = sweph.NOT_AVAILABLE;

const SE_SUN = swecl.SE_SUN;
const SE_MOON = swecl.SE_MOON;
const SE_MERCURY = swecl.SE_MERCURY;
const SE_VENUS = swecl.SE_VENUS;
const SE_MARS = swecl.SE_MARS;
const SE_JUPITER = swecl.SE_JUPITER;
const SE_SATURN = swecl.SE_SATURN;
const SE_URANUS = swecl.SE_URANUS;
const SE_NEPTUNE = swecl.SE_NEPTUNE;
const SE_PLUTO = swecl.SE_PLUTO;
const SE_TRUE_NODE = swecl.SE_TRUE_NODE;
const SE_EARTH = swecl.SE_EARTH;
const SE_AST_OFFSET = swecl.SE_AST_OFFSET;

const SEFLG_JPLEPH: i32 = 1;
const SEFLG_SWIEPH: i32 = 2;
const SEFLG_MOSEPH: i32 = 4;
const SEFLG_TRUEPOS: i32 = 16;
const SEFLG_NONUT: i32 = 64;
const SEFLG_SPEED: i32 = 256;
const SEFLG_EQUATORIAL: i32 = 2 * 1024;
const SEFLG_XYZ: i32 = 4 * 1024;
const SEFLG_TOPOCTR: i32 = 32 * 1024;
const SEFLG_EPHMASK: i32 = 1 | 2 | 4;

pub const SE_HELIACAL_RISING: i32 = 1;
pub const SE_HELIACAL_SETTING: i32 = 2;
pub const SE_MORNING_FIRST: i32 = SE_HELIACAL_RISING;
pub const SE_EVENING_LAST: i32 = SE_HELIACAL_SETTING;
pub const SE_EVENING_FIRST: i32 = 3;
pub const SE_MORNING_LAST: i32 = 4;
pub const SE_ACRONYCHAL_RISING: i32 = 5;
pub const SE_ACRONYCHAL_SETTING: i32 = 6;

// swehel.c defines
const PLSV: i32 = 0; // if Planet, Lunar and Stellar Visibility formula is needed PLSV=1
const criticalangle: f64 = 0.0; // [deg]
const BNIGHT: f64 = 1479.0; // [nL]
const BNIGHT_FACTOR: f64 = 1.0;
const Min2Deg: f64 = 1.0 / 60.0;
const MaxTryHours: f64 = 4;
const TimeStepDefault: f64 = 1;
const LocalMinStep: f64 = 8;
const MAX_COUNT_SYNPER: i32 = 5; // search within 10 synodic periods
const MAX_COUNT_SYNPER_MAX: i32 = 1000000; // high, so there is not max count
const AvgRadiusMoon: f64 = 15.541 / 60.0; // [Deg] at 2007 CE or BCE
const Ra: f64 = 6378136.6; // [m]
const Rb: f64 = 6356752.314; // [m]
const nL2erg: f64 = 1.02E-15;
const erg2nL: f64 = 1 / nL2erg; // erg2nL to nLambert
const MoonDistance: f64 = 384410.4978; // [km]
const scaleHwater: f64 = 3000.0; // [m] Ricchiazzi [1997] 8200 Schaefer [2000]
const scaleHrayleigh: f64 = 8515.0; // [m] Su [2003] 8200 Schaefer [2000]
const scaleHaerosol: f64 = 3745.0; // m Su [2003] 1500 Schaefer [2000]
const scaleHozone: f64 = 20000.0; // [m] Schaefer [2000]
const astr2tau: f64 = 0.921034037197618; // LN(10 ^ 0.4)
// C: #define tau2astr 1 / astr2tau — UNPARENTHESIZED. Every use expands to
// `* 1 / astr2astr`, i.e. a DIVISION; do not fold into a reciprocal const.

const C2K: f64 = 273.15; // [K]
const LapseSA: f64 = 0.0065; // [K/m] standard atmosphere
const LowestAppAlt: f64 = -3.5; // [Deg]
const epsilon: f64 = 0.001;
const staticAirmass: i32 = 0; // use staticAirmass=1 instead depending on difference k's
const TJD_INVALID: f64 = 99999999.0;
const SE_SCOTOPIC_FLAG: i32 = 1;
const SE_MIXEDOPIC_FLAG: i32 = 2;

pub const SE_HELFLAG_LONG_SEARCH: i32 = 128;
pub const SE_HELFLAG_HIGH_PRECISION: i32 = 256;
pub const SE_HELFLAG_OPTICAL_PARAMS: i32 = 512;
pub const SE_HELFLAG_NO_DETAILS: i32 = 1024;
pub const SE_HELFLAG_SEARCH_1_PERIOD: i32 = 1 << 11; // 2048
pub const SE_HELFLAG_VISLIM_DARK: i32 = 1 << 12; // 4096
pub const SE_HELFLAG_VISLIM_NOMOON: i32 = 1 << 13; // 8192
pub const SE_HELFLAG_VISLIM_PHOTOPIC: i32 = 1 << 14; // 16384
pub const SE_HELFLAG_VISLIM_SCOTOPIC: i32 = 1 << 15; // 32768
pub const SE_HELFLAG_AV: i32 = 1 << 16; // 65536
pub const SE_HELFLAG_AVKIND_VR: i32 = 1 << 16; // 65536
pub const SE_HELFLAG_AVKIND_PTO: i32 = 1 << 17;
pub const SE_HELFLAG_AVKIND_MIN7: i32 = 1 << 18;
pub const SE_HELFLAG_AVKIND_MIN9: i32 = 1 << 19;
pub const SE_HELFLAG_AVKIND: i32 = SE_HELFLAG_AVKIND_VR | SE_HELFLAG_AVKIND_PTO | SE_HELFLAG_AVKIND_MIN7 | SE_HELFLAG_AVKIND_MIN9;

const SEI_ECL_GEOALT_MIN: f64 = -500.0;
const SEI_ECL_GEOALT_MAX: f64 = 25000.0;

pub const SE_GREG_CAL: i32 = 1;

/// swehel.c function-local caches, order-dependent. Threaded
/// through the swehel API (single-threaded contract).
pub const SwehelCtx = struct {
    // SunRA
    sunra_tjdlast: f64 = 0,
    sunra_ralast: f64 = 0,
    // kOZ
    koz_last: f64 = 0,
    koz_alts_last: f64 = 0,
    koz_sunra_last: f64 = 0,
    // ka
    ka_alts_last: f64 = 0,
    ka_sunra_last: f64 = 0,
    ka_last: f64 = 0,
    // Deltam
    dm_alts_last: f64 = 0,
    dm_alto_last: f64 = 0,
    dm_sunra_last: f64 = 0,
    dm_deltam_last: f64 = 0,
    // call_swe_fixstar_mag
    fsm_dmag: f64 = 0,
    fsm_star_save: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH,
};

fn mymin(a: f64, b: f64) f64 {
    if (a <= b)
        return a;
    return b;
}

fn mymax(a: f64, b: f64) f64 {
    if (a >= b)
        return a;
    return b;
}

/// swehel.c Tanh()
fn Tanh(x: f64) f64 {
    return (swe_shim_exp(x) - swe_shim_exp(-x)) / (swe_shim_exp(x) + swe_shim_exp(-x));
}

/// swehel.c CVA() — Schaefer 1993
fn CVA(B: f64, SN: f64, helflag: i32) f64 {
    var is_scotopic = false;
    // if (B < BNIGHT)
    if (B < 1394) // use this value for BNIGHT to make the function continous
        is_scotopic = true;
    if ((helflag & SE_HELFLAG_VISLIM_PHOTOPIC) != 0)
        is_scotopic = false;
    if ((helflag & SE_HELFLAG_VISLIM_SCOTOPIC) != 0)
        is_scotopic = true;
    if (is_scotopic)
        return mymin(900, 380 / SN * swe_shim_pow(10, (0.3 * swe_shim_pow(B, (-0.29))))) / 60.0 / 60.0
    else
        return (40.0 / SN) * swe_shim_pow(10, (8.28 * swe_shim_pow(B, (-0.29)))) / 60.0 / 60.0;
}

/// swehel.c PupilDia() — age dependency from Garstang [2000]
fn PupilDia(Age: f64, B: f64) f64 {
    return (0.534 - 0.00211 * Age - (0.236 - 0.00127 * Age) * Tanh(0.4 * swe_shim_log(B) / swe_shim_log(10) - 2.2)) * 10;
}

/// swehel.c OpticFactor() — Schaefer 1993
fn OpticFactor(Bback: f64, kX: f64, dobs: *const [6]f64, JDNDaysUT: f64, ObjectName: []const u8, TypeFactor: i32, helflag: i32) f64 {
    var Fsc: f64 = undefined;
    var Age = dobs[0];
    var SN = dobs[1];
    const SNi: f64 = if (SN <= 0.00000001) 0.00000001 else SN;
    _ = &Age;
    _ = &SN;
    _ = JDNDaysUT; // unused
    const Binocular = dobs[2];
    const OpticMag = dobs[3];
    var OpticDia = dobs[4];
    var OpticTrans = dobs[5];
    var is_scotopic = false;
    // 23 years as standard from Garstang
    const Pst = PupilDia(23, Bback);
    if (OpticMag == 1) { // 1 means using eye
        OpticTrans = 1;
        OpticDia = Pst;
    }
    // Schaefer, Astronomy and the limits of vision, Archaeoastronomy, 1993
    const CIb: f64 = 0.7; // background color index
    const CIi: f64 = 0.5; // white color index
    const ObjectSize: f64 = 0;
    if (std.mem.eql(u8, ObjectName, "moon")) {
        // TODO: determine ObjectSize and CI from JDNDaysUT
    }
    var Fb: f64 = 1;
    if (Binocular == 0) Fb = 1.41;
    // if (Bback < BNIGHT)
    if (Bback < 1645) // use this value for BNIGHT to make the function continuous
        is_scotopic = true;
    if ((helflag & SE_HELFLAG_VISLIM_PHOTOPIC) != 0)
        is_scotopic = false;
    if ((helflag & SE_HELFLAG_VISLIM_SCOTOPIC) != 0)
        is_scotopic = true;
    var Fe: f64 = undefined;
    var Fci: f64 = undefined;
    var Fcb: f64 = undefined;
    if (is_scotopic) {
        Fe = swe_shim_pow(10, (0.48 * kX));
        Fsc = mymin(1, (1 - swe_shim_pow(Pst / 124.4, 4)) / (1 - swe_shim_pow((OpticDia / OpticMag / 124.4), 4)));
        Fci = swe_shim_pow(10, (-0.4 * (1 - CIi / 2.0)));
        Fcb = swe_shim_pow(10, (-0.4 * (1 - CIb / 2.0)));
    } else {
        Fe = swe_shim_pow(10, (0.4 * kX));
        Fsc = mymin(1, swe_shim_pow((OpticDia / OpticMag / Pst), 2) * (1 - swe_shim_exp(-swe_shim_pow((Pst / 6.2), 2))) / (1 - swe_shim_exp(-swe_shim_pow((OpticDia / OpticMag / 6.2), 2))));
        Fci = 1;
        Fcb = 1;
    }
    const Ft = 1 / OpticTrans;
    const Fp = mymax(1, swe_shim_pow((Pst / (OpticMag * PupilDia(Age, Bback))), 2));
    const Fa = swe_shim_pow((Pst / OpticDia), 2);
    const Fr = (1 + 0.03 * swe_shim_pow((OpticMag * ObjectSize / CVA(Bback, SNi, helflag)), 2)) / swe_shim_pow(SNi, 2);
    const Fm = swe_shim_pow(OpticMag, 2);
    if (TypeFactor == 0)
        return Fb * Fe * Ft * Fp * Fa * Fr * Fsc * Fci
    else
        return Fb * Ft * Fp * Fa * Fm * Fsc * Fcb;
}

/// C atoi() semantics: skip whitespace, optional sign, digits; 0 otherwise.
fn cAtoi(s: []const u8) i32 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r' or s[i] == 11 or s[i] == 12)) : (i += 1) {}
    var sign: i32 = 1;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        if (s[i] == '-') sign = -1;
        i += 1;
    }
    var val: i64 = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        val = val * 10 + (s[i] - '0');
        if (val > 2147483647) val = 2147483647;
    }
    return sign * @as(i32, @intCast(val));
}

/// swehel.c DeterObject()
fn DeterObject(ObjectName: []const u8) i32 {
    var s: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const n = @min(ObjectName.len, AS_MAXCH - 1);
    @memcpy(s[0..n], ObjectName[0..n]);
    for (s[0..n]) |*c|
        c.* = std.ascii.toLower(c.*);
    const sv = std.mem.sliceTo(&s, 0);
    if (std.mem.startsWith(u8, sv, "sun"))
        return SE_SUN;
    if (std.mem.startsWith(u8, sv, "venus"))
        return SE_VENUS;
    if (std.mem.startsWith(u8, sv, "mars"))
        return SE_MARS;
    if (std.mem.startsWith(u8, sv, "mercur"))
        return SE_MERCURY;
    if (std.mem.startsWith(u8, sv, "jupiter"))
        return SE_JUPITER;
    if (std.mem.startsWith(u8, sv, "saturn"))
        return SE_SATURN;
    if (std.mem.startsWith(u8, sv, "uranus"))
        return SE_URANUS;
    if (std.mem.startsWith(u8, sv, "neptun"))
        return SE_NEPTUNE;
    if (std.mem.startsWith(u8, sv, "moon"))
        return SE_MOON;
    const ipl = cAtoi(sv);
    if (ipl > 0) {
        return ipl + SE_AST_OFFSET;
    }
    return -1;
}

/// swehel.c call_swe_fixstar() — copies the star name so swe_fixstar's
/// in-place rewrite cannot corrupt the caller's buffer
fn call_swe_fixstar(star: []const u8, tjd: f64, iflag: i32, xx: *[6]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var star2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const n = @min(star.len, AS_MAXCH - 1);
    @memcpy(star2[0..n], star[0..n]);
    return sweph.swe_fixstar(star2[0..n], tjd, iflag, xx, swed, models, dctx, serr);
}

/// swehel.c call_swe_fixstar_mag() — memoized in ctx by star name
fn call_swe_fixstar_mag(star: []const u8, mag: *f64, serr: ?[]u8, swed: *Swed, hctx: *SwehelCtx) i32 {
    const saved = std.mem.sliceTo(&hctx.fsm_star_save, 0);
    if (std.mem.eql(u8, star, saved)) {
        mag.* = hctx.fsm_dmag;
        return OK;
    }
    const n = @min(star.len, AS_MAXCH - 1);
    @memcpy(hctx.fsm_star_save[0..n], star[0..n]);
    hctx.fsm_star_save[n] = 0;
    var star2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    @memcpy(star2[0..n], star[0..n]);
    const retval = sweph.swe_fixstar_mag(star2[0..n], &hctx.fsm_dmag, swed, serr);
    mag.* = hctx.fsm_dmag;
    return retval;
}

/// swehel.c call_swe_rise_trans()
fn call_swe_rise_trans(tjd: f64, ipl: i32, star: []const u8, helflag: i32, eventtype: i32, dgeo: *const [3]f64, atpress: f64, attemp: f64, tret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx) i32 {
    const iflag = helflag & (SEFLG_JPLEPH | SEFLG_SWIEPH | SEFLG_MOSEPH);
    var star2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const n = @min(star.len, AS_MAXCH - 1);
    @memcpy(star2[0..n], star[0..n]);
    return swecl.swe_rise_trans(tjd, ipl, star2[0..n], iflag, eventtype, dgeo, atpress, attemp, tret, serr, swed, models, dctx, cctx);
}

/// swehel.c SunRA() — memoized in ctx by tjd
pub fn sunraTest(JDNDaysUT: f64, helflag: i32, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, hctx: *SwehelCtx) f64 {
    return SunRA(JDNDaysUT, helflag, serr, swed, models, dctx, hctx);
}

fn SunRA(JDNDaysUT: f64, helflag: i32, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, hctx: *SwehelCtx) f64 {
    _ = helflag; // unused
    _ = swed;
    _ = models;
    _ = dctx;
    if (serr) |sr| sr[0] = 0;
    if (JDNDaysUT == hctx.sunra_tjdlast)
        return hctx.sunra_ralast;
    // Always uses the revjul approximation (C builds with SIMULATE_VICTORVB=1).
    const rv = swedate_mod.swe_revjul(JDNDaysUT, SE_GREG_CAL);
    hctx.sunra_tjdlast = JDNDaysUT;
    hctx.sunra_ralast = lib.swe_degnorm((@as(f64, @floatFromInt(rv.mon)) + (@as(f64, @floatFromInt(rv.day)) - 1) / 30.4 - 3.69) * 30);
    return hctx.sunra_ralast;
}

const swedate_mod = @import("swedate");

/// helflag & (SEFLG_JPLEPH|SEFLG_SWIEPH|SEFLG_MOSEPH)
fn ephemFlag(helflag: i32) i32 {
    return helflag & (SEFLG_JPLEPH | SEFLG_SWIEPH | SEFLG_MOSEPH);
}

/// swehel.c Kelvin()
fn Kelvin(Temp: f64) f64 {
    return Temp + C2K;
}

/// swehel.c TopoAltfromAppAlt()
fn TopoAltfromAppAlt(AppAlt: f64, TempE: f64, PresE: f64) f64 {
    var R: f64 = 0;
    var retalt: f64 = 0;
    if (AppAlt >= LowestAppAlt) {
        if (AppAlt > 17.904104638432)
            R = 0.97 / swe_shim_tan(AppAlt * DEGTORAD)
        else
            R = (34.46 + 4.23 * AppAlt + 0.004 * AppAlt * AppAlt) / (1 + 0.505 * AppAlt + 0.0845 * AppAlt * AppAlt);
        R = (PresE - 80) / 930 / (1 + 0.00008 * (R + 39) * (TempE - 10)) * R;
        retalt = AppAlt - R * Min2Deg;
    } else {
        retalt = AppAlt;
    }
    return retalt;
}

/// swehel.c AppAltfromTopoAlt() — Newton-derivative iteration
fn AppAltfromTopoAlt(TopoAlt: f64, TempE: f64, PresE: f64, helflag: i32) f64 {
    var nloop: i32 = 2;
    const newAppAlt_init = TopoAlt;
    const newTopoAlt_init: f64 = 0.0;
    var newAppAlt = newAppAlt_init;
    var newTopoAlt = newTopoAlt_init;
    var oudAppAlt = newAppAlt;
    var oudTopoAlt = newTopoAlt;
    var verschil: f64 = undefined;
    var retalt: f64 = undefined;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) != 0)
        nloop = 5;
    var i: i32 = 0;
    while (i <= nloop) : (i += 1) {
        newTopoAlt = newAppAlt - TopoAltfromAppAlt(newAppAlt, TempE, PresE);
        verschil = newAppAlt - oudAppAlt;
        oudAppAlt = newTopoAlt - oudTopoAlt - verschil;
        if ((verschil != 0) and (oudAppAlt != 0))
            verschil = newAppAlt - verschil * (TopoAlt + newTopoAlt - newAppAlt) / oudAppAlt
        else
            verschil = TopoAlt + newTopoAlt;
        oudAppAlt = newAppAlt;
        oudTopoAlt = newTopoAlt;
        newAppAlt = verschil;
    }
    retalt = TopoAlt + newTopoAlt;
    if (retalt < LowestAppAlt)
        retalt = TopoAlt;
    return retalt;
}

/// swehel.c HourAngle()
fn HourAngle(TopoAlt: f64, TopoDecl: f64, Lat: f64) f64 {
    const Alti = TopoAlt * DEGTORAD;
    const decli = TopoDecl * DEGTORAD;
    const Lati = Lat * DEGTORAD;
    var ha = (swe_shim_sin(Alti) - swe_shim_sin(Lati) * swe_shim_sin(decli)) / swe_shim_cos(Lati) / swe_shim_cos(decli);
    if (ha < -1) ha = -1;
    if (ha > 1) ha = 1;
    // from http://star-www.st-and.ac.uk/~fv/webnotes/chapt12.htm
    return swe_shim_acos(ha) / DEGTORAD / 15.0;
}

/// swehel.c ObjectLoc() — Angle: 0=TopoAlt, 1=Azi, 2=TopoDecl, 3=TopoRA,
/// 4=AppAlt, 5=GeoDecl, 6=GeoRA, 7 (=0) geoalt via ecl. coords
pub fn objectLocTest(JDNDaysUT: f64, dgeo: *const [3]f64, datm: *const [4]f64, ObjectName: []const u8, Angle_in: i32, helflag: i32, dret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx) i32 {
    return ObjectLoc(JDNDaysUT, dgeo, datm, ObjectName, Angle_in, helflag, dret, serr, swed, models, dctx, cctx);
}

fn ObjectLoc(JDNDaysUT: f64, dgeo: *const [3]f64, datm: *const [4]f64, ObjectName: []const u8, Angle_in: i32, helflag: i32, dret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx) i32 {
    var x: [6]f64 = undefined;
    var xin: [3]f64 = undefined;
    var xaz: [3]f64 = undefined;
    var Angle = Angle_in;
    const epheflag = ephemFlag(helflag);
    var iflag: i32 = SEFLG_EQUATORIAL;
    iflag |= epheflag;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    if (Angle < 5) iflag = iflag | SEFLG_TOPOCTR;
    if (Angle == 7) Angle = 0;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    const tjd_tt = JDNDaysUT + deltat.swe_deltat_ex(dctx, JDNDaysUT, epheflag);
    const Planet = DeterObject(ObjectName);
    if (Planet != -1) {
        if (sweph.swe_calc(tjd_tt, Planet, iflag, &x, swed, models, dctx, serr) == ERR)
            return ERR;
    } else {
        if (call_swe_fixstar(ObjectName, tjd_tt, iflag, &x, serr, swed, models, dctx) == ERR)
            return ERR;
    }
    if (Angle == 2 or Angle == 5) {
        dret.* = x[1];
    } else {
        if (Angle == 3 or Angle == 6) {
            dret.* = x[0];
        } else {
            xin[0] = x[0];
            xin[1] = x[1];
            swecl.swe_azalt(JDNDaysUT, swecl.SE_EQU2HOR, dgeo, datm[0], datm[1], &xin, &xaz, swed, models, dctx, cctx);
            if (Angle == 0)
                dret.* = xaz[1];
            if (Angle == 4)
                dret.* = AppAltfromTopoAlt(xaz[1], datm[0], datm[1], helflag);
            if (Angle == 1) {
                xaz[0] += 180;
                if (xaz[0] >= 360)
                    xaz[0] -= 360;
                dret.* = xaz[0];
            }
        }
    }
    return OK;
}

/// swehel.c azalt_cart()
fn azalt_cart(JDNDaysUT: f64, dgeo: *const [3]f64, datm: *const [4]f64, ObjectName: []const u8, helflag: i32, dret: *[6]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx) i32 {
    var x: [6]f64 = undefined;
    var xin: [3]f64 = undefined;
    var xaz: [3]f64 = undefined;
    const epheflag = ephemFlag(helflag);
    var iflag: i32 = SEFLG_EQUATORIAL;
    iflag |= epheflag;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    iflag = iflag | SEFLG_TOPOCTR;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    const tjd_tt = JDNDaysUT + deltat.swe_deltat_ex(dctx, JDNDaysUT, epheflag);
    const Planet = DeterObject(ObjectName);
    if (Planet != -1) {
        if (sweph.swe_calc(tjd_tt, Planet, iflag, &x, swed, models, dctx, serr) == ERR)
            return ERR;
    } else {
        if (call_swe_fixstar(ObjectName, tjd_tt, iflag, &x, serr, swed, models, dctx) == ERR)
            return ERR;
    }
    xin[0] = x[0];
    xin[1] = x[1];
    swecl.swe_azalt(JDNDaysUT, swecl.SE_EQU2HOR, dgeo, datm[0], datm[1], &xin, &xaz, swed, models, dctx, cctx);
    dret[0] = xaz[0];
    dret[1] = xaz[1]; // true altitude
    dret[2] = xaz[2]; // apparent altitude
    // also return cartesian coordinates, for apparent altitude
    xaz[1] = xaz[2];
    xaz[2] = 1;
    lib.swi_polcart(xaz[0..3], xaz[0..3]);
    dret[3] = xaz[0];
    dret[4] = xaz[1];
    dret[5] = xaz[2];
    return OK;
}

/// swehel.c DistanceAngle() — Haversine
fn DistanceAngle(LatA: f64, LongA: f64, LatB: f64, LongB: f64) f64 {
    const dlon = LongB - LongA;
    const dlat = LatB - LatA;
    const sindlat2 = swe_shim_sin(dlat / 2);
    const sindlon2 = swe_shim_sin(dlon / 2);
    var corde = sindlat2 * sindlat2 + swe_shim_cos(LatA) * swe_shim_cos(LatB) * sindlon2 * sindlon2;
    if (corde > 1) corde = 1;
    return 2 * swe_shim_asin(@sqrt(corde));
}

/// swehel.c kW() — Schaefer 2000 p.128
fn kW(HeightEye: f64, TempS: f64, RH: f64) f64 {
    var WT: f64 = 0.031;
    WT *= 0.94 * (RH / 100.0) * swe_shim_exp(TempS / 15) * swe_shim_exp(-1 * HeightEye / scaleHwater);
    return WT;
}

/// swehel.c kOZ() — memoized in ctx
fn kOZ(AltS: f64, sunra: f64, Lat: f64, hctx: *SwehelCtx) f64 {
    var altslim: f64 = 0;
    if (AltS == hctx.koz_alts_last and sunra == hctx.koz_sunra_last)
        return hctx.koz_last;
    hctx.koz_alts_last = AltS;
    hctx.koz_sunra_last = sunra;
    const OZ: f64 = 0.031;
    const LT = Lat * DEGTORAD;
    // From Schaefer, Archaeoastronomy, XV, 2000, page 128
    const kOZret = OZ * (3.0 + 0.4 * (LT * swe_shim_cos(sunra * DEGTORAD) - swe_shim_cos(3 * LT))) / 3.0;
    // depending on day/night vision, KO changes from 100% to 30%
    altslim = -AltS - 12;
    if (altslim < 0)
        altslim = 0;
    const CHANGEKO = (100 - 11.6 * mymin(6, altslim)) / 100;
    hctx.koz_last = kOZret * CHANGEKO;
    return hctx.koz_last;
}

/// swehel.c kR()
fn kR(AltS: f64, HeightEye: f64) f64 {
    var val = -AltS - 12;
    if (val < 0) val = 0;
    if (val > 6) val = 6;
    const CHANGEK = (1 - 0.166667 * val);
    const LAMBDA = 0.55 + (CHANGEK - 1) * 0.04;
    // From Schaefer, Archaeoastronomy, XV, 2000, page 128
    return 0.1066 * swe_shim_exp(-1 * HeightEye / scaleHrayleigh) * swe_shim_pow(LAMBDA / 0.55, -4);
}

/// swehel.c Sgn()
fn Sgn(x: f64) i32 {
    if (x < 0)
        return -1;
    return 1;
}

/// swehel.c ka() — memoized in ctx
fn ka(AltS: f64, sunra: f64, Lat: f64, HeightEye: f64, TempS: f64, RH: f64, VR: f64, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const SL: f64 = @floatFromInt(Sgn(Lat));
    // depending on day/night vision, lambda eye sensibility changes
    if (AltS == hctx.ka_alts_last and sunra == hctx.ka_sunra_last)
        return hctx.ka_last;
    hctx.ka_alts_last = AltS;
    hctx.ka_sunra_last = sunra;
    const CHANGEKA = (1 - 0.166667 * mymin(6, mymax(-AltS - 12, 0)));
    const LAMBDA = 0.55 + (CHANGEKA - 1) * 0.04;
    var kaact: f64 = undefined;
    if (VR != 0) {
        if (VR >= 1) {
            // Visibility range from Narasimhan CVPR03 / ICAO AMOSSG;
            // factor 1.3 is the Koshmeider relation
            const BetaVr = 3.912 / VR;
            const Betaa = BetaVr - (kW(HeightEye, TempS, RH) / scaleHwater + kR(AltS, HeightEye) / scaleHrayleigh) * 1000 * astr2tau;
            kaact = Betaa * scaleHaerosol / 1000 * 1 / astr2tau;
            if (kaact < 0) {
                if (serr != null) {
                    const msg = "The provided Meteorological range is too long, when taking into acount other atmospheric parameters";
                    const n = @min(msg.len, serr.?.len);
                    @memcpy(serr.?[0..n], msg[0..n]);
                }
                // is a warning
            }
        } else {
            kaact = VR - kW(HeightEye, TempS, RH) - kR(AltS, HeightEye) - kOZ(AltS, sunra, Lat, hctx);
            if (kaact < 0) {
                if (serr != null) {
                    const msg = "The provided atmosphic coeefficent (ktot) is too low, when taking into acount other atmospheric parameters";
                    const n = @min(msg.len, serr.?.len);
                    @memcpy(serr.?[0..n], msg[0..n]);
                }
                // is a warning
            }
        }
    } else {
        // From Schaefer, Archaeoastronomy, XV, 2000, page 128
        var RH2 = RH;
        if (RH2 <= 0.00000001) RH2 = 0.00000001;
        if (RH2 >= 99.99999999) RH2 = 99.99999999;
        kaact = 0.1 * swe_shim_exp(-1 * HeightEye / scaleHaerosol) * swe_shim_pow(1 - 0.32 / swe_shim_log(RH2 / 100.0), 1.33) * (1 + 0.33 * SL * swe_shim_sin(sunra * DEGTORAD));
        kaact = kaact * swe_shim_pow(LAMBDA / 0.55, -1.3);
    }
    hctx.ka_last = kaact;
    return kaact;
}

/// swehel.c kt() — extinction coefficient sum
fn kt(AltS: f64, sunra: f64, Lat: f64, HeightEye: f64, TempS: f64, RH: f64, VR: f64, ExtType: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    var kRact: f64 = 0;
    var kWact: f64 = 0;
    var kOZact: f64 = 0;
    var kaact: f64 = 0;
    if (ExtType == 2 or ExtType == 4)
        kRact = kR(AltS, HeightEye);
    if (ExtType == 1 or ExtType == 4)
        kWact = kW(HeightEye, TempS, RH);
    if (ExtType == 3 or ExtType == 4)
        kOZact = kOZ(AltS, sunra, Lat, hctx);
    if (ExtType == 0 or ExtType == 4)
        kaact = ka(AltS, sunra, Lat, HeightEye, TempS, RH, VR, serr, hctx);
    if (kaact < 0)
        kaact = 0;
    return kWact + kRact + kOZact + kaact;
}

/// swehel.c Airmass()
fn Airmass(AppAltO: f64, Press: f64) f64 {
    var zend = (90 - AppAltO) * DEGTORAD;
    if (zend > PI / 2)
        zend = PI / 2;
    const airm = 1 / (swe_shim_cos(zend) + 0.025 * swe_shim_exp(-11 * swe_shim_cos(zend)));
    return Press / 1013 * airm;
}

/// swehel.c Xext()
fn Xext(scaleH: f64, zend: f64, Press: f64) f64 {
    return Press / 1013.0 / (swe_shim_cos(zend) + 0.01 * @sqrt(scaleH / 1000.0) * swe_shim_exp(-30.0 / @sqrt(scaleH / 1000.0) * swe_shim_cos(zend)));
}

/// swehel.c Xlay()
fn Xlay(scaleH: f64, zend: f64, Press: f64) f64 {
    const a = swe_shim_sin(zend) / (1.0 + (scaleH / Ra));
    return Press / 1013.0 / @sqrt(1.0 - a * a);
}

/// swehel.c TempEfromTempS()
fn TempEfromTempS(TempS: f64, HeightEye: f64, Lapse: f64) f64 {
    return TempS - Lapse * HeightEye;
}

/// swehel.c PresEfromPresS()
fn PresEfromPresS(TempS: f64, Press: f64, HeightEye: f64) f64 {
    return Press * swe_shim_exp(-9.80665 * 0.0289644 / (Kelvin(TempS) + 3.25 * HeightEye / 1000) / 8.31441 * HeightEye);
}

/// swehel.c Deltam() — memoized in ctx
fn Deltam(AltO: f64, AltS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const PresE = PresEfromPresS(datm[1], datm[0], HeightEye);
    const TempE = TempEfromTempS(datm[1], HeightEye, LapseSA);
    const AppAltO = AppAltfromTopoAlt(AltO, TempE, PresE, helflag);
    var deltam: f64 = undefined;
    if (AltS == hctx.dm_alts_last and AltO == hctx.dm_alto_last and sunra == hctx.dm_sunra_last)
        return hctx.dm_deltam_last;
    hctx.dm_alts_last = AltS;
    hctx.dm_alto_last = AltO;
    hctx.dm_sunra_last = sunra;
    if (staticAirmass == 0) {
        var zend = (90 - AppAltO) * DEGTORAD;
        if (zend > PI / 2)
            zend = PI / 2;
        // From Schaefer, Archaeoastronomy, XV, 2000, page 128
        const xR = Xext(scaleHrayleigh, zend, datm[0]);
        const XW = Xext(scaleHwater, zend, datm[0]);
        const Xa = Xext(scaleHaerosol, zend, datm[0]);
        const XOZ = Xlay(scaleHozone, zend, datm[0]);
        deltam = kR(AltS, HeightEye) * xR + kt(AltS, sunra, Lat, HeightEye, datm[1], datm[2], datm[3], 0, serr, hctx) * Xa + kOZ(AltS, sunra, Lat, hctx) * XOZ + kW(HeightEye, datm[1], datm[2]) * XW;
    } else {
        deltam = kt(AltS, sunra, Lat, HeightEye, datm[1], datm[2], datm[3], 4, serr, hctx) * Airmass(AppAltO, datm[0]);
    }
    hctx.dm_deltam_last = deltam;
    return deltam;
}

/// swehel.c Bn() — Schaefer 2000 p.128/129, adjusted for sunspot period
fn Bn(AltO: f64, JDNDayUT: f64, AltS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const PresE = PresEfromPresS(datm[1], datm[0], HeightEye);
    const TempE = TempEfromTempS(datm[1], HeightEye, LapseSA);
    var AppAltO = AppAltfromTopoAlt(AltO, TempE, PresE, helflag);
    const B0: f64 = 0.0000000000001;
    // Below altitude of 10 degrees, the Bn stays the same (page 343)
    if (AppAltO < 10)
        AppAltO = 10;
    const zend = (90 - AppAltO) * DEGTORAD;
    const rv = swedate_mod.swe_revjul(JDNDayUT, SE_GREG_CAL);
    const YearB: f64 = @floatFromInt(rv.year);
    const MonthB: f64 = @floatFromInt(rv.mon);
    const DayB: f64 = @floatFromInt(rv.day);
    const Bna = B0 * (1 + 0.3 * swe_shim_cos(6.283 * (YearB + ((DayB - 1) / 30.4 + MonthB - 1) / 12 - 1990.33) / 11.1));
    const kX = Deltam(AltO, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    // From Schaefer, Archaeoastronomy, XV, 2000, page 129
    const Bnb = Bna * (0.4 + 0.6 / @sqrt(1 - 0.96 * swe_shim_pow(swe_shim_sin(zend), 2))) * swe_shim_pow(10, -0.4 * kX);
    return mymax(Bnb, 0) * erg2nL;
}

/// swehel.c Magnitude()
fn Magnitude(JDNDaysUT: f64, dgeo: *const [3]f64, ObjectName: []const u8, helflag: i32, dmag: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, hctx: *SwehelCtx) i32 {
    var x: [20]f64 = undefined;
    const epheflag = ephemFlag(helflag);
    dmag.* = -99.0;
    const Planet = DeterObject(ObjectName);
    var iflag: i32 = SEFLG_TOPOCTR | SEFLG_EQUATORIAL | epheflag;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    if (Planet != -1) {
        sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
        if (swecl.swe_pheno_ut(JDNDaysUT, Planet, iflag, &x, serr, swed, models, dctx) == ERR)
            return ERR;
        dmag.* = x[4];
    } else {
        if (call_swe_fixstar_mag(ObjectName, dmag, serr, swed, hctx) == ERR)
            return ERR;
    }
    return OK;
}

/// swehel.c MoonsBrightness()
fn MoonsBrightness(dist: f64, phasemoon: f64) f64 {
    const log10c = 2.302585092994;
    // Moon's brightness changes with distance
    return -21.62 + 5 * swe_shim_log(dist / (Ra / 1000)) / log10c + 0.026 * @abs(phasemoon) + 0.000000004 * swe_shim_pow(phasemoon, 4);
}

/// swehel.c MoonPhase()
fn MoonPhase(AltM: f64, AziM: f64, AltS: f64, AziS: f64) f64 {
    const AltMi = AltM * DEGTORAD;
    const AltSi = AltS * DEGTORAD;
    const AziMi = AziM * DEGTORAD;
    const AziSi = AziS * DEGTORAD;
    const MoonAvgPar: f64 = 0.95;
    return 180 - swe_shim_acos(swe_shim_cos(AziSi - AziMi - MoonAvgPar * DEGTORAD) * swe_shim_cos(AltMi + MoonAvgPar * DEGTORAD) * swe_shim_cos(AltSi) + swe_shim_sin(AltSi) * swe_shim_sin(AltMi + MoonAvgPar * DEGTORAD)) / DEGTORAD;
}

/// swehel.c Bm() — moon brightness contribution
fn Bm(AltO: f64, AziO: f64, AltM: f64, AziM: f64, AltS: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const M0: f64 = -11.05;
    var Bm_v: f64 = 0;
    const lunar_radius: f64 = 0.25 * DEGTORAD;
    var object_is_moon = false;
    if (AltO == AltM and AziO == AziM)
        object_is_moon = true;
    if (AltM > -0.26 and !object_is_moon) { // second condition added by Dieter, SE2.06
        // moon only adds light when (partly) above horizon
        // From Schaefer, Archaeoastronomy, XV, 2000, page 129
        var RM = DistanceAngle(AltO * DEGTORAD, AziO * DEGTORAD, AltM * DEGTORAD, AziM * DEGTORAD) / DEGTORAD;
        if (RM <= lunar_radius) // addition by Dieter for objects behind the Moon, SE2.06
            RM = lunar_radius;
        const kXM = Deltam(AltM, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
        const kX = Deltam(AltO, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
        const C3 = swe_shim_pow(10, -0.4 * kXM);
        const FM = (62000000.0) / RM / RM + swe_shim_pow(10, 6.15 - RM / 40) + swe_shim_pow(10, 5.36) * (1.06 + swe_shim_pow(swe_shim_cos(RM * DEGTORAD), 2));
        Bm_v = FM * C3 + 440000 * (1 - C3);
        const phasemoon = MoonPhase(AltM, AziM, AltS, AziS);
        const MM = MoonsBrightness(MoonDistance, phasemoon);
        Bm_v = Bm_v * swe_shim_pow(10, -0.4 * (MM - M0 + 43.27));
        Bm_v = Bm_v * (1 - swe_shim_pow(10, -0.4 * kX));
    }
    Bm_v = mymax(Bm_v, 0) * erg2nL;
    return Bm_v;
}

/// swehel.c Btwi() — twilight brightness
fn Btwi(AltO: f64, AziO: f64, AltS: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const M0: f64 = -11.05;
    const MS: f64 = -26.74;
    const PresE = PresEfromPresS(datm[1], datm[0], HeightEye);
    const TempE = TempEfromTempS(datm[1], HeightEye, LapseSA);
    const AppAltO = AppAltfromTopoAlt(AltO, TempE, PresE, helflag);
    const ZendO = 90 - AppAltO;
    const RS = DistanceAngle(AltO * DEGTORAD, AziO * DEGTORAD, AltS * DEGTORAD, AziS * DEGTORAD) / DEGTORAD;
    const kX = Deltam(AltO, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    const k = kt(AltS, sunra, Lat, HeightEye, datm[1], datm[2], datm[3], 4, serr, hctx);
    // From Schaefer, Archaeoastronomy, XV, 2000, page 129
    var Btwi_v = swe_shim_pow(10, -0.4 * (MS - M0 + 32.5 - AltS - (ZendO / (360 * k))));
    Btwi_v = Btwi_v * (100 / RS) * (1 - swe_shim_pow(10, -0.4 * kX));
    Btwi_v = mymax(Btwi_v, 0) * erg2nL;
    return Btwi_v;
}

/// swehel.c Bday() — daylight brightness
fn Bday(AltO: f64, AziO: f64, AltS: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const M0: f64 = -11.05;
    const MS: f64 = -26.74;
    const RS = DistanceAngle(AltO * DEGTORAD, AziO * DEGTORAD, AltS * DEGTORAD, AziS * DEGTORAD) / DEGTORAD;
    const kXS = Deltam(AltS, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    const kX = Deltam(AltO, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    // From Schaefer, Archaeoastronomy, XV, 2000, page 129
    const C4 = swe_shim_pow(10, -0.4 * kXS);
    const FS = (62000000.0) / RS / RS + swe_shim_pow(10, (6.15 - RS / 40)) + swe_shim_pow(10, 5.36) * (1.06 + swe_shim_pow(swe_shim_cos(RS * DEGTORAD), 2));
    var Bday_v = FS * C4 + 440000.0 * (1 - C4);
    Bday_v = Bday_v * swe_shim_pow(10, (-0.4 * (MS - M0 + 43.27)));
    Bday_v = Bday_v * (1 - swe_shim_pow(10, -0.4 * kX));
    Bday_v = mymax(Bday_v, 0) * erg2nL;
    return Bday_v;
}

/// swehel.c Bcity()
fn Bcity(Value: f64, Press: f64) f64 {
    _ = Press; // unused in C too (Press += 0.0)
    const Bcity_v = mymax(Value, 0);
    return Bcity_v;
}

/// swehel.c Bsky() — total sky brightness
fn Bsky(AltO: f64, AziO: f64, AltM: f64, AziM: f64, JDNDaysUT: f64, AltS: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    var Bsky_v: f64 = 0;
    if (AltS < -3) {
        Bsky_v += Btwi(AltO, AziO, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    } else {
        if (AltS > 4) {
            Bsky_v += Bday(AltO, AziO, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
        } else {
            Bsky_v += mymin(Bday(AltO, AziO, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx), Btwi(AltO, AziO, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx));
        }
    }
    // if max. Bm [1E7] <5% of Bsky don't add Bm
    if (Bsky_v < 200000000.0)
        Bsky_v += Bm(AltO, AziO, AltM, AziM, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    if (AltS <= 0)
        Bsky_v += Bcity(0, datm[0]);
    // if max. Bn [250] <5% of Bsky don't add Bn
    if (Bsky_v < 5000)
        Bsky_v = Bsky_v + Bn(AltO, JDNDaysUT, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    // if max. Bm [1E7] <5% of Bsky don't add Bm
    return Bsky_v;
}

/// swehel.c default_heliacal_parameters()
fn default_heliacal_parameters(datm: *[4]f64, dgeo: *const [3]f64, dobs: *[6]f64, helflag: i32) void {
    if (datm[0] <= 0) {
        // estimate atmospheric pressure, according to the
        // International Standard Atmosphere (ISA)
        datm[0] = 1013.25 * swe_shim_pow(1 - 0.0065 * dgeo[2] / 288, 5.255);
        // temperature
        if (datm[1] == 0)
            datm[1] = 15 - 0.0065 * dgeo[2];
        // relative humidity, independent of atmospheric pressure and altitude
        if (datm[2] == 0)
            datm[2] = 40;
        // note: datm[3] / VR defaults outside this function
    }
    // age of observer
    if (dobs[0] == 0)
        dobs[0] = 36;
    // SN Snellen factor of the visual acuity of the observer
    if (dobs[1] == 0)
        dobs[1] = 1;
    if ((helflag & SE_HELFLAG_OPTICAL_PARAMS) == 0) {
        var i: usize = 2;
        while (i <= 5) : (i += 1)
            dobs[i] = 0;
    }
    // OpticMagn undefined -> use eye
    if (dobs[3] == 0) {
        dobs[2] = 1; // Binocular = 1
        dobs[3] = 1; // OpticMagn = 1: use eye
        // dobs[4] and dobs[5] (OpticDia and OpticTrans) will be defaulted in
        // OpticFactor()
    }
}

/// swehel.c VisLimMagn() — Schaefer limiting magnitude
fn VisLimMagn(dobs: *const [6]f64, AltO: f64, AziO: f64, AltM: f64, AziM: f64, JDNDaysUT: f64, AltS: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, scotopic_flag: ?*i32, serr: ?[]u8, hctx: *SwehelCtx) f64 {
    const log10c = 2.302585092994;
    var is_scotopic = false;
    var Bsk = Bsky(AltO, AziO, AltM, AziM, JDNDaysUT, AltS, AziS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    // Schaefer, Astronomy and the limits of vision, Archaeoastronomy, 1993
    const kX = Deltam(AltO, AltS, sunra, Lat, HeightEye, datm, helflag, serr, hctx);
    // influence of age
    const CorrFactor1 = OpticFactor(Bsk, kX, dobs, JDNDaysUT, "", 1, helflag);
    const CorrFactor2 = OpticFactor(Bsk, kX, dobs, JDNDaysUT, "", 0, helflag);
    // if (Bsk < BNIGHT)
    if (Bsk < 1645) // use this function for BNIGHT to make the function continuous
        is_scotopic = true;
    if ((helflag & SE_HELFLAG_VISLIM_PHOTOPIC) != 0)
        is_scotopic = false;
    if ((helflag & SE_HELFLAG_VISLIM_SCOTOPIC) != 0)
        is_scotopic = true;
    // From Schaefer, Archaeoastronomy, XV, 2000, page 129
    var C1: f64 = undefined;
    var C2: f64 = undefined;
    if (is_scotopic) {
        C1 = 1.5848931924611e-10; // C1 = 10 ^ (-9.8)
        C2 = 0.012589254117942; // C2 = 10 ^ (-1.9)
        if (scotopic_flag != null)
            scotopic_flag.?.* = 1;
    } else {
        C1 = 4.4668359215096e-9; // C1 = 10 ^ (-8.35)
        C2 = 1.2589254117942e-6; // C2 = 10 ^ (-5.9)
        if (scotopic_flag != null)
            scotopic_flag.?.* = 0;
    }
    if (scotopic_flag != null) {
        if (BNIGHT * BNIGHT_FACTOR > Bsk and BNIGHT / BNIGHT_FACTOR < Bsk)
            scotopic_flag.?.* |= 2;
    }
    Bsk = Bsk * CorrFactor1;
    const Th = C1 * swe_shim_pow(1 + @sqrt(C2 * Bsk), 2) * CorrFactor2;
    // Visual limiting magnitude of point source
    return -16.57 - 2.5 * (swe_shim_log(Th) / log10c);
}

/// tolower star name, but not Bayer designation
fn tolower_string_star(str: []u8) void {
    for (str) |*c| {
        if (c.* == 0 or c.* == ',') break;
        c.* = std.ascii.toLower(c.*);
    }
}

/// swehel.c TopoArcVisionis() — bisection for the arcus visionis
fn TopoArcVisionis(Magn: f64, dobs: *const [6]f64, AltO: f64, AziO: f64, AltM: f64, AziM: f64, JDNDaysUT: f64, AziS: f64, sunra: f64, Lat: f64, HeightEye: f64, datm: *const [4]f64, helflag: i32, dret: *f64, serr: ?[]u8, hctx: *SwehelCtx) i32 {
    var Xm: f64 = undefined;
    var AltSi: f64 = undefined;
    var AziSi: f64 = undefined;
    var xR: f64 = 0;
    var Xl: f64 = 45;
    var Yl: f64 = undefined;
    var Yr: f64 = undefined;
    Yl = Magn - VisLimMagn(dobs, AltO, AziO, AltM, AziM, JDNDaysUT, AltO - Xl, AziS, sunra, Lat, HeightEye, datm, helflag, null, serr, hctx);
    // serr is only a warning
    Yr = Magn - VisLimMagn(dobs, AltO, AziO, AltM, AziM, JDNDaysUT, AltO - xR, AziS, sunra, Lat, HeightEye, datm, helflag, null, serr, hctx);
    // http://en.wikipedia.org/wiki/Bisection_method
    if ((Yl * Yr) <= 0) {
        while (@abs(xR - Xl) > epsilon) {
            // Calculate midpoint of domain
            Xm = (xR + Xl) / 2.0;
            AltSi = AltO - Xm;
            AziSi = AziS;
            const Ym = Magn - VisLimMagn(dobs, AltO, AziO, AltM, AziM, JDNDaysUT, AltSi, AziSi, sunra, Lat, HeightEye, datm, helflag, null, serr, hctx);
            if ((Yl * Ym) > 0) {
                // Throw away left half
                Xl = Xm;
                Yl = Ym;
            } else {
                // Throw away right half
                xR = Xm;
                Yr = Ym;
            }
        }
        Xm = (xR + Xl) / 2.0;
    } else {
        Xm = 99;
    }
    if (Xm < AltO)
        Xm = AltO;
    dret.* = Xm;
    return OK;
}

/// swehel.c swe_topo_arcus_visionis()
pub fn swe_topo_arcus_visionis(tjdut: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, helflag: i32, mag: f64, azi_obj: f64, alt_obj: f64, azi_sun: f64, azi_moon: f64, alt_moon: f64, dret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    _ = cctx;
    _ = swi_set_tid_acc_pub(tjdut, helflag, 0, serr, swed, dctx);
    const sunra = SunRA(tjdut, helflag, serr, swed, models, dctx, hctx);
    if (serr != null and serr.?[0] != 0)
        return ERR;
    default_heliacal_parameters(datm, dgeo, dobs, helflag);
    return TopoArcVisionis(mag, dobs, alt_obj, azi_obj, alt_moon, azi_moon, tjdut, azi_sun, sunra, dgeo[1], dgeo[2], datm, helflag, dret, serr, hctx);
}

/// swehel.c swe_heliacal_angle()
pub fn swe_heliacal_angle(tjdut: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, helflag: i32, mag: f64, azi_obj: f64, azi_sun: f64, azi_moon: f64, alt_moon: f64, dret: *[3]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    _ = cctx;
    if (dgeo[2] < SEI_ECL_GEOALT_MIN or dgeo[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for heliacal events must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return ERR;
    }
    _ = swi_set_tid_acc_pub(tjdut, helflag, 0, serr, swed, dctx);
    default_heliacal_parameters(datm, dgeo, dobs, helflag);
    return HeliacalAngle(mag, dobs, azi_obj, alt_moon, azi_moon, tjdut, azi_sun, dgeo, datm, helflag, dret, serr, swed, models, dctx, hctx);
}

fn HeliacalAngle(Magn: f64, dobs: *const [6]f64, AziO: f64, AltM: f64, AziM: f64, JDNDaysUT: f64, AziS: f64, dgeo: *const [3]f64, datm: *const [4]f64, helflag: i32, dangret: *[3]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, hctx: *SwehelCtx) i32 {
    const sunra = SunRA(JDNDaysUT, helflag, serr, swed, models, dctx, hctx);
    const Lat = dgeo[1];
    const HeightEye = dgeo[2];
    if (PLSV == 1) {
        dangret[0] = criticalangle;
        dangret[1] = criticalangle + Magn * 2.492 + 13.447;
        dangret[2] = -(Magn * 2.492 + 13.447);
        return OK;
    }
    const minx: f64 = 2;
    const maxx: f64 = 20;
    var xmin: f64 = 0;
    var ymin: f64 = 10000;
    var x: f64 = minx;
    while (x <= maxx) : (x += 1) {
        var Arc: f64 = undefined;
        if (TopoArcVisionis(Magn, dobs, x, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, Lat, HeightEye, datm, helflag, &Arc, serr, hctx) == ERR)
            return ERR;
        if (Arc < ymin) {
            ymin = Arc;
            xmin = x;
        }
    }
    var Xl = xmin - 1;
    var xR = xmin + 1;
    var Yr: f64 = undefined;
    var Yl: f64 = undefined;
    if (TopoArcVisionis(Magn, dobs, xR, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, Lat, HeightEye, datm, helflag, &Yr, serr, hctx) == ERR)
        return ERR;
    if (TopoArcVisionis(Magn, dobs, Xl, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, Lat, HeightEye, datm, helflag, &Yl, serr, hctx) == ERR)
        return ERR;
    while (@abs(xR - Xl) > 0.1) {
        const Xm = (xR + Xl) / 2.0;
        const DELTAx: f64 = 0.025;
        const xmd = Xm + DELTAx;
        var Ym: f64 = undefined;
        var ymd: f64 = undefined;
        if (TopoArcVisionis(Magn, dobs, Xm, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, Lat, HeightEye, datm, helflag, &Ym, serr, hctx) == ERR)
            return ERR;
        if (TopoArcVisionis(Magn, dobs, xmd, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, Lat, HeightEye, datm, helflag, &ymd, serr, hctx) == ERR)
            return ERR;
        if (Ym >= ymd) {
            Xl = Xm;
            Yl = Ym;
        } else {
            xR = Xm;
            Yr = Ym;
        }
    }
    const Xm = (xR + Xl) / 2.0;
    const Ym = (Yr + Yl) / 2.0;
    dangret[1] = Ym;
    dangret[2] = Xm - Ym;
    dangret[0] = Xm;
    return OK;
}

/// sweph.c swi_set_tid_acc re-export (C's swi_set_tid_acc is callable from
/// swehel.c as an extern)
fn swi_set_tid_acc_pub(tjd_ut: f64, iflag: i32, denum: i32, serr: ?[]u8, swed: *Swed, dctx: *DeltatCtx) i32 {
    return sweph.swiSetTidAcc(tjd_ut, iflag, denum, serr, swed, dctx);
}

/// swehel.c WidthMoon() — Yallop 1998 p.3
fn WidthMoon(AltO: f64, AziO: f64, AltS: f64, AziS: f64, parallax: f64) f64 {
    const GeoAltO = AltO + parallax;
    return 0.27245 * parallax * (1 + swe_shim_sin(GeoAltO * DEGTORAD) * swe_shim_sin(parallax * DEGTORAD)) * (1 - swe_shim_cos((AltS - GeoAltO) * DEGTORAD) * swe_shim_cos((AziS - AziO) * DEGTORAD));
}

/// swehel.c LengthMoon() — Sultan 2005 crescent length
fn LengthMoon(W: f64, Diamoon_in: f64) f64 {
    var Diamoon = Diamoon_in;
    if (Diamoon == 0) Diamoon = AvgRadiusMoon * 2;
    const Wi = W * 60;
    const D = Diamoon * 60;
    return (D - 0.3 * (D + Wi) / 2.0 / Wi) / 60.0;
}

/// swehel.c qYallop()
fn qYallop(W: f64, GeoARCVact: f64) f64 {
    const Wi = W * 60;
    return (GeoARCVact - (11.8371 - 6.3226 * Wi + 0.7319 * Wi * Wi - 0.1018 * Wi * Wi * Wi)) / 10;
}

/// swehel.c crossing()
fn crossing(A: f64, B: f64, C: f64, D: f64) f64 {
    return (C - A) / ((B - A) - (D - C));
}

/// swehel.c DeterTAV()
fn DeterTAV(dobs: *const [6]f64, JDNDaysUT: f64, dgeo: *const [3]f64, datm: *const [4]f64, ObjectName: []const u8, helflag: i32, dret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var Magn: f64 = undefined;
    var AltO: f64 = undefined;
    var AziS: f64 = undefined;
    var AziO: f64 = undefined;
    var AziM: f64 = undefined;
    var AltM: f64 = undefined;
    const sunra = SunRA(JDNDaysUT, helflag, serr, swed, models, dctx, hctx);
    if (Magnitude(JDNDaysUT, dgeo, ObjectName, helflag, &Magn, serr, swed, models, dctx, hctx) == ERR)
        return ERR;
    if (ObjectLoc(JDNDaysUT, dgeo, datm, ObjectName, 0, helflag, &AltO, serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    if (ObjectLoc(JDNDaysUT, dgeo, datm, ObjectName, 1, helflag, &AziO, serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    if (std.mem.startsWith(u8, ObjectName, "moon")) {
        AltM = -90;
        AziM = 0;
    } else {
        if (ObjectLoc(JDNDaysUT, dgeo, datm, "moon", 0, helflag, &AltM, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
        if (ObjectLoc(JDNDaysUT, dgeo, datm, "moon", 1, helflag, &AziM, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
    }
    if (ObjectLoc(JDNDaysUT, dgeo, datm, "sun", 1, helflag, &AziS, serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    if (TopoArcVisionis(Magn, dobs, AltO, AziO, AltM, AziM, JDNDaysUT, AziS, sunra, dgeo[1], dgeo[2], datm, helflag, dret, serr, hctx) == ERR)
        return ERR;
    return OK;
}

/// swehel.c x2min()
fn x2min(A: f64, B: f64, C: f64) f64 {
    const term = A + C - 2 * B;
    if (term == 0)
        return 0;
    return -(A - C) / 2.0 / term;
}

/// swehel.c funct2()
fn funct2(A: f64, B: f64, C: f64, x: f64) f64 {
    return (A + C - 2 * B) / 2.0 * x * x + (A - C) / 2.0 * x + B;
}

/// swehel.c strcpy_VBsafe() — truncate to alnum/space/dash/comma chars
fn strcpy_VBsafe(sout: *[AS_MAXCH]u8, sin: []const u8) void {
    var iw: usize = 0;
    var i: usize = 0;
    // note, star name may begin with comma, such as ",zePsc"
    while (i < sin.len and iw < 30) : (i += 1) {
        const c = sin[i];
        if (c == 0) break;
        const isalnum = std.ascii.isAlphanumeric(c);
        if (!(isalnum or c == ' ' or c == '-' or c == ',')) break;
        sout[iw] = c;
        iw += 1;
    }
    sout[iw] = 0;
}

/// swehel.c swe_heliacal_pheno_ut() — 28 output values (see C comment block)
pub fn swe_heliacal_pheno_ut(JDNDaysUT: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectNameIn: []const u8, TypeEvent: i32, helflag: i32, darr: *[40]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var AziS: f64 = undefined;
    var AltS: f64 = undefined;
    var AltS2: f64 = undefined;
    var AziO: f64 = undefined;
    var AltO: f64 = undefined;
    var AltO2: f64 = undefined;
    var GeoAltO: f64 = undefined;
    var AppAltO: f64 = undefined;
    var DAZact: f64 = undefined;
    var TAVact: f64 = undefined;
    var ParO: f64 = undefined;
    var MagnO: f64 = undefined;
    var ARCVact: f64 = undefined;
    var ARCLact: f64 = undefined;
    var kact: f64 = undefined;
    var WMoon: f64 = undefined;
    var LMoon: f64 = 0;
    var qYal: f64 = undefined;
    var qCrit: f64 = undefined;
    var RiseSetO: f64 = undefined;
    var RiseSetS: f64 = undefined;
    var Lag: f64 = undefined;
    var TbYallop: f64 = undefined;
    var TfirstVR: f64 = undefined;
    var TlastVR: f64 = undefined;
    var TbVR: f64 = undefined;
    var MinTAV: f64 = 0;
    var MinTAVact: f64 = undefined;
    var Ta: f64 = undefined;
    var Tc: f64 = undefined;
    var TimeStep: f64 = undefined;
    var TimePointer: f64 = undefined;
    var MinTAVoud: f64 = 0;
    var DeltaAltoud: f64 = 0;
    var DeltaAlt: f64 = undefined;
    var TvisVR: f64 = undefined;
    var crosspoint: f64 = undefined;
    var OldestMinTAV: f64 = undefined;
    var extrax: f64 = undefined;
    var illum: f64 = undefined;
    var elong: f64 = undefined;
    var TimeCheck: f64 = undefined;
    var LocalminCheck: f64 = undefined;
    var retval: i32 = OK;
    var RS: i32 = undefined;
    var Planet: i32 = undefined;
    var noriseO = false;
    var ObjectName: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const iflag = ephemFlag(helflag);
    if (dgeo[2] < SEI_ECL_GEOALT_MIN or dgeo[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for heliacal events must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return ERR;
    }
    _ = swi_set_tid_acc_pub(JDNDaysUT, helflag, 0, serr, swed, dctx);
    const sunra = SunRA(JDNDaysUT, helflag, serr, swed, models, dctx, hctx);
    // note, the fixed stars functions rewrite the star name. The input string
    // may be too short, so we have to make sure we have enough space
    strcpy_VBsafe(&ObjectName, ObjectNameIn);
    {
        const len = std.mem.indexOfScalar(u8, &ObjectName, 0) orelse AS_MAXCH;
        tolower_string_star(ObjectName[0..len]);
    }
    default_heliacal_parameters(datm, dgeo, dobs, helflag);
    sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
    retval = ObjectLoc(JDNDaysUT, dgeo, datm, "sun", 1, helflag, &AziS, serr, swed, models, dctx, cctx);
    if (retval == OK)
        retval = ObjectLoc(JDNDaysUT, dgeo, datm, "sun", 0, helflag, &AltS, serr, swed, models, dctx, cctx);
    if (retval == OK)
        retval = ObjectLoc(JDNDaysUT, dgeo, datm, &ObjectName, 1, helflag, &AziO, serr, swed, models, dctx, cctx);
    if (retval == OK)
        retval = ObjectLoc(JDNDaysUT, dgeo, datm, &ObjectName, 0, helflag, &AltO, serr, swed, models, dctx, cctx);
    if (retval == OK)
        retval = ObjectLoc(JDNDaysUT, dgeo, datm, &ObjectName, 7, helflag, &GeoAltO, serr, swed, models, dctx, cctx);
    if (retval == ERR)
        return ERR;
    const namelen = std.mem.indexOfScalar(u8, &ObjectName, 0) orelse AS_MAXCH;
    const oname = ObjectName[0..namelen];
    AppAltO = AppAltfromTopoAlt(AltO, datm[1], datm[0], helflag);
    DAZact = AziS - AziO;
    TAVact = AltO - AltS;
    // this parallax seems to be somewhat smaller then in Yallop and SkyMap!
    ParO = GeoAltO - AltO;
    if (Magnitude(JDNDaysUT, dgeo, oname, helflag, &MagnO, serr, swed, models, dctx, hctx) == ERR)
        return ERR;
    ARCVact = TAVact + ParO;
    ARCLact = swe_shim_acos(swe_shim_cos(ARCVact * DEGTORAD) * swe_shim_cos(DAZact * DEGTORAD)) / DEGTORAD;
    Planet = DeterObject(oname);
    var attr: [20]f64 = undefined;
    if (Planet == -1) {
        elong = ARCLact;
        illum = 100;
    } else {
        retval = swecl.swe_pheno_ut(JDNDaysUT, Planet, iflag | (SEFLG_TOPOCTR | SEFLG_EQUATORIAL), &attr, serr, swed, models, dctx);
        if (retval == ERR) return ERR;
        elong = attr[2];
        illum = attr[1] * 100;
    }
    kact = kt(AltS, sunra, dgeo[1], dgeo[2], datm[1], datm[2], datm[3], 4, serr, hctx);
    WMoon = 0;
    qYal = 0;
    qCrit = 0;
    LMoon = 0;
    if (Planet == SE_MOON) {
        WMoon = WidthMoon(AltO, AziO, AltS, AziS, ParO);
        LMoon = LengthMoon(WMoon, 0);
        qYal = qYallop(WMoon, ARCVact);
        if (qYal > 0.216) qCrit = 1; // A
        if (qYal < 0.216 and qYal > -0.014) qCrit = 2; // B
        if (qYal < -0.014 and qYal > -0.16) qCrit = 3; // C
        if (qYal < -0.16 and qYal > -0.232) qCrit = 4; // D
        if (qYal < -0.232 and qYal > -0.293) qCrit = 5; // E
        if (qYal < -0.293) qCrit = 6; // F
    }
    // determine if rise or set event
    RS = 2;
    if (TypeEvent == 1 or TypeEvent == 4) RS = 1;
    retval = RiseSetPub(JDNDaysUT - 4.0 / 24.0, dgeo, datm, "sun", RS, helflag, 0, &RiseSetS, serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR)
        return ERR;
    retval = RiseSetPub(JDNDaysUT - 4.0 / 24.0, dgeo, datm, oname, RS, helflag, 0, &RiseSetO, serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR)
        return ERR;
    TbYallop = TJD_INVALID;
    if (retval == -2) { // object does not rise or set
        Lag = 0;
        noriseO = true;
    } else {
        Lag = RiseSetO - RiseSetS;
        if (Planet == SE_MOON)
            TbYallop = (RiseSetO * 4 + RiseSetS * 5) / 9.0;
    }
    var skip_walkthrough = false;
    if ((TypeEvent == 3 or TypeEvent == 4) and (Planet == -1 or Planet >= SE_MARS)) {
        TfirstVR = TJD_INVALID;
        TbVR = TJD_INVALID;
        TlastVR = TJD_INVALID;
        TvisVR = 0;
        MinTAV = 0;
        skip_walkthrough = true;
    }
    if (!skip_walkthrough) {
        // te bepalen m.b.v. walkthrough
        MinTAVact = 199;
        DeltaAlt = 0;
        OldestMinTAV = 0;
        Ta = 0;
        Tc = 0;
        TbVR = 0;
        TimeStep = -TimeStepDefault / 24.0 / 60.0;
        if (RS == 2) TimeStep = -TimeStep;
        TimePointer = RiseSetS - TimeStep;
        while (true) {
            TimePointer = TimePointer + TimeStep;
            OldestMinTAV = MinTAVoud;
            MinTAVoud = MinTAVact;
            DeltaAltoud = DeltaAlt;
            retval = ObjectLoc(TimePointer, dgeo, datm, "sun", 0, helflag, &AltS2, serr, swed, models, dctx, cctx);
            if (retval == OK)
                retval = ObjectLoc(TimePointer, dgeo, datm, oname, 0, helflag, &AltO2, serr, swed, models, dctx, cctx);
            if (retval != OK)
                return ERR;
            DeltaAlt = AltO2 - AltS2;
            if (DeterTAV(dobs, TimePointer, dgeo, datm, oname, helflag, &MinTAVact, serr, swed, models, dctx, cctx, hctx) == ERR)
                return ERR;
            if (MinTAVoud < MinTAVact and TbVR == 0) {
                // determine if this is a local minimum with object still above horizon
                TimeCheck = TimePointer + @as(f64, @floatFromInt(Sgn(TimeStep))) * LocalMinStep / 24.0 / 60.0;
                if (RiseSetO != 0) {
                    if (TimeStep > 0)
                        TimeCheck = mymin(TimeCheck, RiseSetO)
                    else
                        TimeCheck = mymax(TimeCheck, RiseSetO);
                }
                if (DeterTAV(dobs, TimeCheck, dgeo, datm, oname, helflag, &LocalminCheck, serr, swed, models, dctx, cctx, hctx) == ERR)
                    return ERR;
                if (LocalminCheck > MinTAVact) {
                    extrax = x2min(MinTAVact, MinTAVoud, OldestMinTAV);
                    TbVR = TimePointer - (1 - extrax) * TimeStep;
                    MinTAV = funct2(MinTAVact, MinTAVoud, OldestMinTAV, extrax);
                }
            }
            if (DeltaAlt > MinTAVact and Tc == 0 and TbVR == 0) {
                crosspoint = crossing(DeltaAltoud, DeltaAlt, MinTAVoud, MinTAVact);
                Tc = TimePointer - TimeStep * (1 - crosspoint);
            }
            if (DeltaAlt < MinTAVact and Ta == 0 and Tc != 0) {
                crosspoint = crossing(DeltaAltoud, DeltaAlt, MinTAVoud, MinTAVact);
                Ta = TimePointer - TimeStep * (1 - crosspoint);
            }
            if (!(@abs(TimePointer - RiseSetS) <= MaxTryHours / 24.0 and Ta == 0 and !((TbVR != 0 and (TypeEvent == 3 or TypeEvent == 4) and (!std.mem.startsWith(u8, oname, "moon") and !std.mem.startsWith(u8, oname, "venus") and !std.mem.startsWith(u8, oname, "mercury")))))) break;
        }
        if (RS == 2) {
            TfirstVR = Tc;
            TlastVR = Ta;
        } else {
            TfirstVR = Ta;
            TlastVR = Tc;
        }
        if (TfirstVR == 0 and TlastVR == 0) {
            if (RS == 1)
                TfirstVR = TbVR - 0.000001
            else
                TlastVR = TbVR + 0.000001;
        }
        if (!noriseO) {
            if (RS == 1)
                TfirstVR = mymax(TfirstVR, RiseSetO)
            else
                TlastVR = mymin(TlastVR, RiseSetO);
        }
        TvisVR = TJD_INVALID; // "#NA!"
        if (TlastVR != 0 and TfirstVR != 0)
            TvisVR = TlastVR - TfirstVR;
        if (TlastVR == 0) TlastVR = TJD_INVALID; // "#NA!"
        if (TbVR == 0) TbVR = TJD_INVALID; // "#NA!"
        if (TfirstVR == 0) TfirstVR = TJD_INVALID; // "#NA!"
    }
    // output_heliacal_pheno:
    darr[0] = AltO;
    darr[1] = AppAltO;
    darr[2] = GeoAltO;
    darr[3] = AziO;
    darr[4] = AltS;
    darr[5] = AziS;
    darr[6] = TAVact;
    darr[7] = ARCVact;
    darr[8] = DAZact;
    darr[9] = ARCLact;
    darr[10] = kact;
    darr[11] = MinTAV;
    darr[12] = TfirstVR;
    darr[13] = TbVR;
    darr[14] = TlastVR;
    darr[15] = TbYallop;
    darr[16] = WMoon;
    darr[17] = qYal;
    darr[18] = qCrit;
    darr[19] = ParO;
    darr[20] = MagnO;
    darr[21] = RiseSetO;
    darr[22] = RiseSetS;
    darr[23] = Lag;
    darr[24] = TvisVR;
    darr[25] = LMoon;
    darr[26] = elong;
    darr[27] = illum;
    return OK;
}

/// swehel.c RiseSet() helper
fn RiseSetPub(JDNDaysUT: f64, dgeo: *const [3]f64, datm: *const [4]f64, ObjectName: []const u8, RSEvent: i32, helflag: i32, Rim: i32, tret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var eventtype = RSEvent;
    if (Rim == 0)
        eventtype |= swecl.SE_BIT_DISC_CENTER;
    const Planet = DeterObject(ObjectName);
    if (Planet != -1)
        return my_rise_trans(JDNDaysUT, Planet, "", eventtype, helflag, dgeo, datm, tret, serr, swed, models, dctx, cctx, hctx)
    else
        return my_rise_trans(JDNDaysUT, -1, ObjectName, eventtype, helflag, dgeo, datm, tret, serr, swed, models, dctx, cctx, hctx);
}

/// swehel.c calc_rise_and_set() — fast rising/setting approximation
fn calc_rise_and_set(tjd_start: f64, ipl: i32, dgeo: *const [3]f64, datm: *const [4]f64, eventflag: i32, helflag: i32, trise: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    _ = hctx;
    const retc: i32 = OK;
    var xs: [6]f64 = undefined;
    var xx: [6]f64 = undefined;
    var xaz: [6]f64 = undefined;
    var xaz2: [6]f64 = undefined;
    const dfac: f64 = 1.0 / 365.25;
    var rdi: f64 = undefined;
    var rh: f64 = undefined;
    const tjd0 = tjd_start;
    var tjdrise: f64 = undefined;
    var tjdnoon = @trunc(tjd0) - dgeo[0] / 15.0 / 24.0;
    var iflag = ephemFlag(helflag);
    const epheflag = iflag;
    iflag |= SEFLG_EQUATORIAL;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    if (sweph.swe_calc_ut(tjd0, SE_SUN, iflag, &xs, swed, models, dctx, serr) == 0) {
        if (serr != null) {
            const msg = "error in calc_rise_and_set(): calc(sun) failed ";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    if (sweph.swe_calc_ut(tjd0, ipl, iflag, &xx, swed, models, dctx, serr) == 0) {
        if (serr != null) {
            const msg = "error in calc_rise_and_set(): calc(sun) failed ";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    tjdnoon -= lib.swe_degnorm(xs[0] - xx[0]) / 360.0 + 0;
    // is planet above horizon or below?
    swecl.swe_azalt(tjd0, swecl.SE_EQU2HOR, dgeo, datm[0], datm[1], xx[0..3], xaz[0..3], swed, models, dctx, cctx);
    if ((eventflag & swecl.SE_CALC_RISE) != 0) {
        if (xaz[2] > 0) {
            while (tjdnoon - tjd0 < 0.5) tjdnoon += 1;
            while (tjdnoon - tjd0 > 1.5) tjdnoon -= 1;
        } else {
            while (tjdnoon - tjd0 < 0.0) tjdnoon += 1;
            while (tjdnoon - tjd0 > 1.0) tjdnoon -= 1;
        }
    } else {
        if (xaz[2] > 0) {
            while (tjd0 - tjdnoon > 0.5) tjdnoon += 1;
            while (tjd0 - tjdnoon < -0.5) tjdnoon -= 1;
        } else {
            while (tjd0 - tjdnoon > 0.0) tjdnoon += 1;
            while (tjd0 - tjdnoon < -1.0) tjdnoon -= 1;
        }
    }
    // position of planet
    if (sweph.swe_calc_ut(tjdnoon, ipl, iflag, &xx, swed, models, dctx, serr) == ERR) {
        if (serr != null) {
            const msg = "error in calc_rise_and_set(): calc(sun) failed ";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    // apparent radius of solar disk (ignoring refraction)
    rdi = 0;
    if (ipl == SE_SUN)
        rdi = swe_shim_asin(696000000.0 / 1.49597870691e+11 / xx[2]) / DEGTORAD
    else if (ipl == SE_MOON)
        rdi = swe_shim_asin(1737000.0 / 1.49597870691e+11 / xx[2]) / DEGTORAD;
    if ((eventflag & swecl.SE_BIT_DISC_CENTER) != 0)
        rdi = 0;
    // true altitude of sun, when it appears at the horizon;
    // refraction for a body visible at the horizon at 0m above sea,
    // atmospheric temperature 10 deg C, atmospheric pressure 1013.25 is 34.5 arcmin
    rh = -(34.5 / 60.0 + rdi);
    // semidiurnal arc of sun
    const sda = swe_shim_acos(-swe_shim_tan(dgeo[1] * DEGTORAD) * swe_shim_tan(xx[1] * DEGTORAD)) * RADTODEG;
    // rough rising and setting times
    if ((eventflag & swecl.SE_CALC_RISE) != 0)
        tjdrise = tjdnoon - sda / 360.0
    else
        tjdrise = tjdnoon + sda / 360.0;
    // now calculate more accurate rising and setting times.
    iflag = epheflag | SEFLG_SPEED | SEFLG_EQUATORIAL;
    if (ipl == SE_MOON)
        iflag |= SEFLG_TOPOCTR;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    var i: i32 = 0;
    while (i < 2) : (i += 1) {
        if (sweph.swe_calc_ut(tjdrise, ipl, iflag, &xx, swed, models, dctx, serr) == ERR) {
            return ERR;
        }
        swecl.swe_azalt(tjdrise, swecl.SE_EQU2HOR, dgeo, datm[0], datm[1], xx[0..3], xaz[0..3], swed, models, dctx, cctx);
        xx[0] -= xx[3] * dfac;
        xx[1] -= xx[4] * dfac;
        swecl.swe_azalt(tjdrise - dfac, swecl.SE_EQU2HOR, dgeo, datm[0], datm[1], xx[0..3], xaz2[0..3], swed, models, dctx, cctx);
        tjdrise -= (xaz[1] - rh) / (xaz[1] - xaz2[1]) * dfac;
    }
    trise.* = tjdrise;
    return retc;
}

/// swehel.c my_rise_trans()
fn my_rise_trans(tjd: f64, ipl_in: i32, starname: []const u8, eventtype: i32, helflag: i32, dgeo: *const [3]f64, datm: *const [4]f64, tret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var ipl = ipl_in;
    if (starname.len > 0 and starname[0] != 0)
        ipl = DeterObject(starname);
    // for non-circumpolar planets we can use a faster algorithm
    if (ipl != -1 and @abs(dgeo[1]) < 63) {
        return calc_rise_and_set(tjd, ipl, dgeo, datm, eventtype, helflag, tret, serr, swed, models, dctx, cctx, hctx);
        // for stars and circumpolar planets we use a rigorous algorithm
    } else {
        return call_swe_rise_trans(tjd, ipl, starname, helflag, eventtype, dgeo, datm[0], datm[1], tret, serr, swed, models, dctx, cctx);
    }
}

/// swehel.c swe_vis_limit_mag() — public API
pub fn swe_vis_limit_mag(tjdut: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectNameIn: []u8, helflag: i32, dret: *[8]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var scotopic_flag: i32 = 0;
    var d0: f64 = undefined;
    var AltO: f64 = undefined;
    var AziO: f64 = undefined;
    var AltM: f64 = undefined;
    var AziM: f64 = undefined;
    var AltS: f64 = undefined;
    var AziS: f64 = undefined;
    for (0..7) |i|
        dret[i] = 0;
    tolower_string_star(ObjectNameIn);
    if (DeterObject(ObjectNameIn) == SE_SUN) {
        if (serr != null) {
            const msg = "it makes no sense to call swe_vis_limit_mag() for the Sun";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    _ = swi_set_tid_acc_pub(tjdut, helflag, 0, serr, swed, dctx);
    const sunra = SunRA(tjdut, helflag, serr, swed, models, dctx, hctx);
    default_heliacal_parameters(datm, dgeo, dobs, helflag);
    sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
    if (ObjectLoc(tjdut, dgeo, datm, ObjectNameIn, 0, helflag, &AltO, serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    if (AltO < 0) {
        if (serr != null) {
            const msg = "object is below local horizon";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        dret[0] = -100;
        return -2;
    }
    if (ObjectLoc(tjdut, dgeo, datm, ObjectNameIn, 1, helflag, &AziO, serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    if ((helflag & SE_HELFLAG_VISLIM_DARK) != 0) {
        AltS = -90;
        AziS = 0;
    } else {
        if (ObjectLoc(tjdut, dgeo, datm, "sun", 0, helflag, &AltS, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
        if (ObjectLoc(tjdut, dgeo, datm, "sun", 1, helflag, &AziS, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
    }
    if (std.mem.startsWith(u8, ObjectNameIn, "moon") or
        (helflag & SE_HELFLAG_VISLIM_DARK) != 0 or
        (helflag & SE_HELFLAG_VISLIM_NOMOON) != 0)
    {
        AltM = -90;
        AziM = 0;
    } else {
        if (ObjectLoc(tjdut, dgeo, datm, "moon", 0, helflag, &AltM, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
        if (ObjectLoc(tjdut, dgeo, datm, "moon", 1, helflag, &AziM, serr, swed, models, dctx, cctx) == ERR)
            return ERR;
    }
    d0 = VisLimMagn(dobs, AltO, AziO, AltM, AziM, tjdut, AltS, AziS, sunra, dgeo[1], dgeo[2], datm, helflag, &scotopic_flag, serr, hctx);
    dret[0] = d0;
    dret[1] = AltO;
    dret[2] = AziO;
    dret[3] = AltS;
    dret[4] = AziS;
    dret[5] = AltM;
    dret[6] = AziM;
    if (Magnitude(tjdut, dgeo, ObjectNameIn, helflag, &(dret[7]), serr, swed, models, dctx, hctx) == ERR)
        return ERR;
    return scotopic_flag;
}

/// swehel.c get_synodic_period() — Kelley/Milone/Aveni p.43
fn get_synodic_period(Planet: i32) f64 {
    switch (Planet) {
        SE_MOON => return 29.530588853,
        SE_MERCURY => return 115.8775,
        SE_VENUS => return 583.9214,
        SE_MARS => return 779.9361,
        SE_JUPITER => return 398.8840,
        SE_SATURN => return 378.0919,
        SE_URANUS => return 369.6560,
        SE_NEPTUNE => return 367.4867,
        SE_PLUTO => return 366.7207,
        else => {},
    }
    return 366; // for stars and default for far away planets
}

/// swehel.c moon_event_arc_vis() — lunar events via arcus visionis
fn moon_event_arc_vis(JDNDaysUTStart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, TypeEvent_in: i32, helflag: i32, dret: *[10]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var x: [20]f64 = undefined;
    const TypeEvent = TypeEvent_in;
    var TypeEventMut = TypeEvent_in;
    var goingup: i32 = 0;
    var DeltaAlt: f64 = 90;
    var tjd_moonevent: f64 = undefined;
    var tjd_moonevent_start: f64 = undefined;
    var MinTAV: f64 = undefined;
    var MinTAVoud: f64 = undefined;
    var OldestMinTAV: f64 = undefined;
    var DeltaAltoud: f64 = undefined;
    var TimeCheck: f64 = undefined;
    var LocalminCheck: f64 = undefined;
    var AltS: f64 = undefined;
    var AltO: f64 = undefined;
    var JDNDaysUT: f64 = undefined;
    var retval: i32 = undefined;
    var avkind = helflag & SE_HELFLAG_AVKIND;
    const epheflag = ephemFlag(helflag);
    dret[0] = JDNDaysUTStart; // will be returned in error case
    if (avkind == 0)
        avkind = SE_HELFLAG_AVKIND_VR;
    if (avkind != SE_HELFLAG_AVKIND_VR) {
        if (serr != null) {
            const msg = "error: in valid AV kind for the moon";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    if (TypeEvent == 1 or TypeEvent == 2) {
        if (serr != null) {
            const msg = "error: the moon has no morning first or evening last";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    const ObjectName = "moon";
    const Planet = SE_MOON;
    var iflag = SEFLG_TOPOCTR | SEFLG_EQUATORIAL | epheflag;
    if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
        iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
    var Daystep: i32 = 1;
    if (TypeEvent == 3) {
        // morning last
        TypeEventMut = 2;
    } else {
        // evening first
        TypeEventMut = 1;
        Daystep = -Daystep;
    }
    // check Synodic/phase Period
    JDNDaysUT = JDNDaysUTStart;
    // start 30 days later if TypeEvent=4 (1)
    if (TypeEventMut == 1) JDNDaysUT = JDNDaysUT + 30;
    // determination of new moon date
    _ = swecl.swe_pheno_ut(JDNDaysUT, Planet, iflag, &x, serr, swed, models, dctx);
    var phase2 = x[0];
    while (true) {
        JDNDaysUT = JDNDaysUT + @as(f64, @floatFromInt(Daystep));
        const phase1 = phase2;
        _ = swecl.swe_pheno_ut(JDNDaysUT, Planet, iflag, &x, serr, swed, models, dctx);
        phase2 = x[0];
        if (phase2 > phase1)
            goingup = 1;
        if (!(goingup == 0 or (goingup == 1 and (phase2 > phase1)))) break;
    }
    // fix the date to get the day with the smallest phase (nwest moon)
    JDNDaysUT = JDNDaysUT - @as(f64, @floatFromInt(Daystep));
    // initialize the date to look for set
    const JDNDaysUTi = JDNDaysUT;
    JDNDaysUT = JDNDaysUT - @as(f64, @floatFromInt(Daystep));
    MinTAVoud = 199;
    while (true) {
        JDNDaysUT = JDNDaysUT + @as(f64, @floatFromInt(Daystep));
        retval = RiseSetPub(JDNDaysUT, dgeo, datm, ObjectName, TypeEventMut, helflag, 0, &tjd_moonevent, serr, swed, models, dctx, cctx, hctx);
        if (retval != OK)
            return retval;
        tjd_moonevent_start = tjd_moonevent;
        MinTAV = 199;
        OldestMinTAV = MinTAV;
        while (true) {
            OldestMinTAV = MinTAVoud;
            MinTAVoud = MinTAV;
            DeltaAltoud = DeltaAlt;
            tjd_moonevent = tjd_moonevent - 1.0 / 60.0 / 24.0 * @as(f64, @floatFromInt(Sgn(@floatFromInt(Daystep))));
            if (ObjectLoc(tjd_moonevent, dgeo, datm, "sun", 0, helflag, &AltS, serr, swed, models, dctx, cctx) == ERR)
                return ERR;
            if (ObjectLoc(tjd_moonevent, dgeo, datm, ObjectName, 0, helflag, &AltO, serr, swed, models, dctx, cctx) == ERR)
                return ERR;
            DeltaAlt = AltO - AltS;
            if (DeterTAV(dobs, tjd_moonevent, dgeo, datm, ObjectName, helflag, &MinTAV, serr, swed, models, dctx, cctx, hctx) == ERR)
                return ERR;
            TimeCheck = tjd_moonevent - LocalMinStep / 60.0 / 24.0 * @as(f64, @floatFromInt(Sgn(@floatFromInt(Daystep))));
            if (DeterTAV(dobs, TimeCheck, dgeo, datm, ObjectName, helflag, &LocalminCheck, serr, swed, models, dctx, cctx, hctx) == ERR)
                return ERR;
            if (!((MinTAV <= MinTAVoud or LocalminCheck < MinTAV) and @abs(tjd_moonevent - tjd_moonevent_start) < 120.0 / 60.0 / 24.0)) break;
        }
        if (!(DeltaAltoud < MinTAVoud and @abs(JDNDaysUT - JDNDaysUTi) < 15)) break;
    }
    if (@abs(JDNDaysUT - JDNDaysUTi) < 15) {
        tjd_moonevent += (1 - x2min(MinTAV, MinTAVoud, OldestMinTAV)) * @as(f64, @floatFromInt(Sgn(@floatFromInt(Daystep)))) / 60.0 / 24.0;
    } else {
        if (serr != null) {
            const msg = "no date found for lunar event";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    dret[0] = tjd_moonevent;
    return OK;
}

/// swehel.c heliacal_ut_arc_vis() — binary day-step search by arcus visionis.
/// C's `goto swe_heliacal_err` becomes a labeled block: every error path
/// breaks out; the label code (copy serr, return) runs afterwards.
fn heliacal_ut_arc_vis(JDNDaysUTStart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, TypeEventIn: i32, helflag: i32, dret: *[10]f64, serr_ret: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var x: [6]f64 = undefined;
    var xin: [3]f64 = undefined;
    var xaz: [3]f64 = undefined;
    var dang: [3]f64 = undefined;
    var objectmagn: f64 = 0;
    var DayStep: f64 = undefined;
    var JDNDaysUT: f64 = undefined;
    var JDNDaysUTfinal: f64 = undefined;
    var JDNDaysUTstep: f64 = undefined;
    var JDNDaysUTstepoud: f64 = undefined;
    var JDNarcvisUT: f64 = undefined;
    var tjd_tt: f64 = undefined;
    var tret: f64 = undefined;
    var OudeDatum: f64 = undefined;
    const JDNDaysUTinp = JDNDaysUTStart;
    var JDNDaysUTtijd: f64 = undefined;
    var ArcusVis: f64 = undefined;
    var ArcusVisDelta: f64 = undefined;
    var ArcusVisPto: f64 = undefined;
    var ArcusVisDeltaoud: f64 = undefined;
    var Trise: f64 = undefined;
    var sunsangle: f64 = undefined;
    var Theliacal: f64 = undefined;
    var Tdelta: f64 = undefined;
    var Angle: f64 = undefined;
    var TimeStep: f64 = undefined;
    var TimePointer: f64 = undefined;
    var OldestMinTAV: f64 = undefined;
    var MinTAVoud: f64 = undefined;
    var MinTAVact: f64 = undefined;
    var extrax: f64 = undefined;
    var TbVR: f64 = 0;
    var AziS: f64 = undefined;
    var AltS: f64 = undefined;
    var AziO: f64 = undefined;
    var AltO: f64 = undefined;
    var DeltaAlt: f64 = undefined;
    var Pressure: f64 = undefined;
    var Temperature: f64 = undefined;
    var d: f64 = undefined;
    var retval: i32 = OK;
    var iflag: i32 = undefined;
    var eventtype: i32 = undefined;
    const TypeEvent = TypeEventIn;
    var doneoneday: i32 = undefined;
    var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    dret[0] = JDNDaysUTStart;
    serr[0] = 0;
    const Planet = DeterObject(ObjectName);
    Pressure = datm[0];
    Temperature = datm[1];
    blk: {
        // determine Magnitude of star
        retval = Magnitude(JDNDaysUTStart, dgeo, ObjectName, helflag, &objectmagn, &serr, swed, models, dctx, hctx);
        if (retval == ERR)
            break :blk; // goto swe_heliacal_err
        const epheflag = ephemFlag(helflag);
        iflag = SEFLG_TOPOCTR | SEFLG_EQUATORIAL | epheflag;
        if ((helflag & SE_HELFLAG_HIGH_PRECISION) == 0)
            iflag |= SEFLG_NONUT | SEFLG_TRUEPOS;
        // start values for search of heliacal rise
        // maxlength = phase period in days, smaller than minimal synodic period
        // days per step (for heliacal rise) in power of two
        var maxlength: f64 = undefined;
        switch (Planet) {
            SE_MERCURY => {
                DayStep = 1;
                maxlength = 100;
            },
            SE_VENUS => {
                DayStep = 64;
                maxlength = 384;
            },
            SE_MARS => {
                DayStep = 128;
                maxlength = 640;
            },
            SE_JUPITER => {
                DayStep = 64;
                maxlength = 384;
            },
            SE_SATURN => {
                DayStep = 64;
                maxlength = 256;
            },
            else => {
                DayStep = 64;
                maxlength = 256;
            },
        }
        // heliacal setting
        eventtype = TypeEvent;
        if (eventtype == 2) DayStep = -DayStep;
        // acronychal setting
        if (eventtype == 4) {
            eventtype = 1;
            DayStep = -DayStep;
        }
        // acronychal rising
        if (eventtype == 3) eventtype = 2;
        eventtype |= swecl.SE_BIT_DISC_CENTER;
        // normalize the maxlength to the step size
        {
            // check each Synodic/phase Period
            JDNDaysUT = JDNDaysUTStart;
            // make sure one can find an event on the just after the JDNDaysUTStart
            JDNDaysUTfinal = JDNDaysUT + maxlength;
            JDNDaysUT = JDNDaysUT - 1;
            if (DayStep < 0) {
                JDNDaysUTtijd = JDNDaysUT;
                JDNDaysUT = JDNDaysUTfinal;
                JDNDaysUTfinal = JDNDaysUTtijd;
            }
            // prepair the search
            JDNDaysUTstep = JDNDaysUT - DayStep;
            doneoneday = 0;
            ArcusVisDelta = 199;
            ArcusVisPto = -5.55;
            outer: while (true) {
                if (@abs(DayStep) == 1) doneoneday = 1;
                while (true) {
                    // init search for heliacal rise
                    JDNDaysUTstepoud = JDNDaysUTstep;
                    ArcusVisDeltaoud = ArcusVisDelta;
                    JDNDaysUTstep = JDNDaysUTstep + DayStep;
                    // determine rise/set time
                    retval = my_rise_trans(JDNDaysUTstep, SE_SUN, "", eventtype, helflag, dgeo, datm, &tret, &serr, swed, models, dctx, cctx, hctx);
                    if (retval == ERR)
                        break :blk; // goto swe_heliacal_err
                    // determine time compensation to get Sun's altitude at heliacal rise
                    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                    dctx.jpldenum = swed.jpldenum;
                    tjd_tt = tret + deltat.swe_deltat_ex(dctx, tret, epheflag);
                    retval = sweph.swe_calc(tjd_tt, SE_SUN, iflag, &x, swed, models, dctx, &serr);
                    if (retval == ERR)
                        break :blk;
                    xin[0] = x[0];
                    xin[1] = x[1];
                    swecl.swe_azalt(tret, swecl.SE_EQU2HOR, dgeo, Pressure, Temperature, xin[0..3], xaz[0..3], swed, models, dctx, cctx);
                    Trise = HourAngle(xaz[1], x[1], dgeo[1]);
                    sunsangle = ArcusVisPto;
                    if ((helflag & SE_HELFLAG_AVKIND_MIN7) != 0) sunsangle = -7;
                    if ((helflag & SE_HELFLAG_AVKIND_MIN9) != 0) sunsangle = -9;
                    Theliacal = HourAngle(sunsangle, x[1], dgeo[1]);
                    Tdelta = Theliacal - Trise;
                    if (TypeEvent == 2 or TypeEvent == 3) Tdelta = -Tdelta;
                    // determine appr.time when sun is at the wanted Sun's altitude
                    JDNarcvisUT = tret - Tdelta / 24;
                    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                    dctx.jpldenum = swed.jpldenum;
                    tjd_tt = JDNarcvisUT + deltat.swe_deltat_ex(dctx, JDNarcvisUT, epheflag);
                    // determine Sun's position
                    retval = sweph.swe_calc(tjd_tt, SE_SUN, iflag, &x, swed, models, dctx, &serr);
                    if (retval == ERR)
                        break :blk;
                    xin[0] = x[0];
                    xin[1] = x[1];
                    swecl.swe_azalt(JDNarcvisUT, swecl.SE_EQU2HOR, dgeo, Pressure, Temperature, xin[0..3], xaz[0..3], swed, models, dctx, cctx);
                    AziS = xaz[0] + 180;
                    if (AziS >= 360) AziS = AziS - 360;
                    AltS = xaz[1];
                    // determine object's position
                    if (Planet != -1) {
                        retval = sweph.swe_calc(tjd_tt, Planet, iflag, &x, swed, models, dctx, &serr);
                        if (retval == ERR)
                            break :blk;
                        // determine magnitude of Planet
                        retval = Magnitude(JDNarcvisUT, dgeo, ObjectName, helflag, &objectmagn, &serr, swed, models, dctx, hctx);
                        if (retval == ERR)
                            break :blk;
                    } else {
                        retval = call_swe_fixstar(ObjectName, tjd_tt, iflag, &x, &serr, swed, models, dctx);
                        if (retval == ERR)
                            break :blk;
                    }
                    xin[0] = x[0];
                    xin[1] = x[1];
                    swecl.swe_azalt(JDNarcvisUT, swecl.SE_EQU2HOR, dgeo, Pressure, Temperature, xin[0..3], xaz[0..3], swed, models, dctx, cctx);
                    AziO = xaz[0] + 180;
                    if (AziO >= 360) AziO = AziO - 360;
                    AltO = xaz[1];
                    // determine arcusvisionis
                    DeltaAlt = AltO - AltS;
                    retval = HeliacalAngle(objectmagn, dobs, AziO, -1, 0, JDNarcvisUT, AziS, dgeo, datm, helflag, &dang, &serr, swed, models, dctx, hctx);
                    if (retval == ERR)
                        break :blk;
                    ArcusVis = dang[1];
                    ArcusVisPto = dang[2];
                    ArcusVisDelta = DeltaAlt - ArcusVis;
                    if (!((ArcusVisDeltaoud > 0 or ArcusVisDelta < 0) and (JDNDaysUTfinal - JDNDaysUTstep) * @as(f64, @floatFromInt(Sgn(DayStep))) > 0)) break;
                }
                if (doneoneday == 0 and (JDNDaysUTfinal - JDNDaysUTstep) * @as(f64, @floatFromInt(Sgn(DayStep))) > 0) {
                    // go back to date before heliacal altitude
                    ArcusVisDelta = ArcusVisDeltaoud;
                    DayStep = @as(f64, @floatFromInt(@as(i32, @intFromFloat(@abs(DayStep) / 2.0)))) * @as(f64, @floatFromInt(Sgn(DayStep)));
                    JDNDaysUTstep = JDNDaysUTstepoud;
                }
                if (!(doneoneday == 0 and (JDNDaysUTfinal - JDNDaysUTstep) * @as(f64, @floatFromInt(Sgn(DayStep))) > 0)) break :outer;
            }
        }
        d = (JDNDaysUTfinal - JDNDaysUTstep) * @as(f64, @floatFromInt(Sgn(DayStep)));
        if (d <= 0 or d >= maxlength) {
            dret[0] = JDNDaysUTinp; // no date found, just return input
            retval = -2; // marks "not found" within synodic period
            const r = std.fmt.bufPrint(&serr, "heliacal event not found within maxlength {d:.6}\n", .{maxlength}) catch "";
            serr[r.len] = 0;
            break :blk; // goto swe_heliacal_err
        }
        var direct = TimeStepDefault / 24.0 / 60.0;
        if (DayStep < 0) direct = -direct;
        if ((helflag & SE_HELFLAG_AVKIND_VR) != 0) {
            // te bepalen m.b.v. walkthrough
            TimeStep = direct;
            TbVR = 0;
            TimePointer = JDNarcvisUT;
            if (DeterTAV(dobs, TimePointer, dgeo, datm, ObjectName, helflag, &OldestMinTAV, &serr, swed, models, dctx, cctx, hctx) == ERR)
                return ERR;
            TimePointer = TimePointer + TimeStep;
            if (DeterTAV(dobs, TimePointer, dgeo, datm, ObjectName, helflag, &MinTAVoud, &serr, swed, models, dctx, cctx, hctx) == ERR)
                return ERR;
            if (MinTAVoud > OldestMinTAV) {
                TimePointer = JDNarcvisUT;
                TimeStep = -TimeStep;
                MinTAVact = OldestMinTAV;
            } else {
                MinTAVact = MinTAVoud;
                MinTAVoud = OldestMinTAV;
            }
            while (true) {
                TimePointer = TimePointer + TimeStep;
                OldestMinTAV = MinTAVoud;
                MinTAVoud = MinTAVact;
                if (DeterTAV(dobs, TimePointer, dgeo, datm, ObjectName, helflag, &MinTAVact, &serr, swed, models, dctx, cctx, hctx) == ERR)
                    return ERR;
                if (MinTAVoud < MinTAVact) {
                    extrax = x2min(MinTAVact, MinTAVoud, OldestMinTAV);
                    TbVR = TimePointer - (1 - extrax) * TimeStep;
                }
                if (!(TbVR == 0)) break;
            }
            JDNarcvisUT = TbVR;
        }
        if ((helflag & SE_HELFLAG_AVKIND_PTO) != 0) {
            while (true) {
                OudeDatum = JDNarcvisUT;
                JDNarcvisUT = JDNarcvisUT - direct;
                dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                dctx.jpldenum = swed.jpldenum;
                tjd_tt = JDNarcvisUT + deltat.swe_deltat_ex(dctx, JDNarcvisUT, epheflag);
                if (Planet != -1) {
                    retval = sweph.swe_calc(tjd_tt, Planet, iflag, &x, swed, models, dctx, &serr);
                    if (retval == ERR)
                        break :blk;
                } else {
                    retval = call_swe_fixstar(ObjectName, tjd_tt, iflag, &x, &serr, swed, models, dctx);
                    if (retval == ERR)
                        break :blk;
                }
                xin[0] = x[0];
                xin[1] = x[1];
                swecl.swe_azalt(JDNarcvisUT, swecl.SE_EQU2HOR, dgeo, Pressure, Temperature, xin[0..3], xaz[0..3], swed, models, dctx, cctx);
                Angle = xaz[1];
                if (!(Angle > 0)) break;
            }
            JDNarcvisUT = (JDNarcvisUT + OudeDatum) / 2.0;
        }
        if (JDNarcvisUT < -9999999 or JDNarcvisUT > 9999999) {
            dret[0] = JDNDaysUT; // no date found, just return input
            const msg = "no heliacal date found";
            @memcpy(serr[0..msg.len], msg);
            serr[msg.len] = 0;
            retval = ERR;
            break :blk; // goto swe_heliacal_err
        }
        dret[0] = JDNarcvisUT;
    } // blk: end — swe_heliacal_err:
    if (serr_ret != null and serr[0] != 0) {
        const n = @min(std.mem.sliceTo(&serr, 0).len, serr_ret.?.len);
        @memcpy(serr_ret.?[0..n], serr[0..n]);
    }
    return retval;
}

/// swehel.c tcon[] — reference conjunction times
const tcon = [_]f64{
    0, 0,
    2451550, 2451550, // Moon
    2451604, 2451670, // Mercury
    2451980, 2452280, // Venus
    2451727, 2452074, // Mars
    2451673, 2451877, // Jupiter
    2451675, 2451868, // Saturn
    2451581, 2451768, // Uranus
    2451568, 2451753, // Neptune
};

/// swehel.c find_conjunct_sun() — superior/inferior conjunction, opposition
fn find_conjunct_sun(tjd_start: f64, ipl: i32, helflag: i32, TypeEvent: i32, tjd: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    const epheflag = ephemFlag(helflag);
    var daspect: f64 = 0;
    if (ipl >= SE_MARS and TypeEvent >= 3)
        daspect = 180;
    const i: usize = @intCast(@divTrunc(TypeEvent - 1, 2) + ipl * 2);
    const tjd0 = tcon[i];
    const dsynperiod = get_synodic_period(ipl);
    var tjdcon = tjd0 + (@floor((tjd_start - tjd0) / dsynperiod) + 1) * dsynperiod;
    var ds: f64 = 100;
    while (ds > 0.5) {
        var x: [6]f64 = undefined;
        var xs: [6]f64 = undefined;
        if (sweph.swe_calc(tjdcon, ipl, epheflag | SEFLG_SPEED, &x, swed, models, dctx, serr) == ERR)
            return ERR;
        if (sweph.swe_calc(tjdcon, SE_SUN, epheflag | SEFLG_SPEED, &xs, swed, models, dctx, serr) == ERR)
            return ERR;
        ds = lib.swe_degnorm(x[0] - xs[0] - daspect);
        if (ds > 180) ds -= 360;
        tjdcon -= ds / (x[3] - xs[3]);
    }
    tjd.* = tjdcon;
    return OK;
}

/// swehel.c get_asc_obl()
fn get_asc_obl(tjd: f64, ipl: i32, star: []const u8, iflag: i32, dgeo: *const [3]f64, desc_obl: bool, daop: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    const epheflag = ephemFlag(iflag);
    var x: [6]f64 = undefined;
    var s: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var star2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const n = @min(star.len, AS_MAXCH - 1);
    @memcpy(star2[0..n], star[0..n]);
    if (ipl == -1) {
        if (sweph.swe_fixstar(star2[0..n], tjd, epheflag | SEFLG_EQUATORIAL, &x, swed, models, dctx, serr) == ERR)
            return ERR;
    } else {
        if (sweph.swe_calc(tjd, ipl, epheflag | SEFLG_EQUATORIAL, &x, swed, models, dctx, serr) == ERR)
            return ERR;
    }
    var adp = swe_shim_tan(dgeo[1] * DEGTORAD) * swe_shim_tan(x[1] * DEGTORAD);
    if (@abs(adp) > 1) {
        if (star.len > 0 and star[0] != 0) {
            const m = @min(star.len, AS_MAXCH - 1);
            @memcpy(s[0..m], star[0..m]);
        } else {
            _ = sweph.swe_get_planet_name(ipl, &s, swed, models, dctx, null);
        }
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "{s} is circumpolar, cannot calculate heliacal event", .{std.mem.sliceTo(&s, 0)}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return -2;
    }
    adp = swe_shim_asin(adp) / DEGTORAD;
    if (desc_obl)
        daop.* = x[0] + adp
    else
        daop.* = x[0] - adp;
    daop.* = lib.swe_degnorm(daop.*);
    return OK;
}

/// swehel.c get_asc_obl_diff()
fn get_asc_obl_diff(tjd: f64, ipl: i32, star: []const u8, iflag: i32, dgeo: *const [3]f64, desc_obl_in: bool, is_acronychal: bool, dsunpl: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var desc_obl = desc_obl_in;
    var aosun: f64 = undefined;
    var aopl: f64 = undefined;
    // ascensio obliqua of sun
    var retval = get_asc_obl(tjd, SE_SUN, "", iflag, dgeo, desc_obl, &aosun, serr, swed, models, dctx);
    if (retval != OK)
        return retval;
    if (is_acronychal) {
        if (desc_obl == true)
            desc_obl = false
        else
            desc_obl = true;
    }
    // ascensio obliqua of body
    retval = get_asc_obl(tjd, ipl, star, iflag, dgeo, desc_obl, &aopl, serr, swed, models, dctx);
    if (retval != OK)
        return retval;
    dsunpl.* = lib.swe_degnorm(aosun - aopl);
    if (is_acronychal)
        dsunpl.* = lib.swe_degnorm(dsunpl.* - 180);
    if (dsunpl.* > 180) dsunpl.* -= 360;
    return OK;
}

/// swehel.c get_asc_obl_with_sun() — bisection for equal ascensio obliqua
fn get_asc_obl_with_sun(tjd_start_in: f64, ipl: i32, star: []const u8, helflag: i32, evtyp: i32, dperiod: f64, dgeo: *const [3]f64, tjdret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var tjd_start = tjd_start_in;
    var is_acronychal = false;
    const epheflag = ephemFlag(helflag);
    var dsunpl: f64 = 1;
    var dsunpl_save: f64 = undefined;
    var dsunpl_test: f64 = undefined;
    var tjd: f64 = undefined;
    var daystep: f64 = undefined;
    var desc_obl = false;
    var retro = false;
    if (evtyp == SE_EVENING_LAST or evtyp == SE_EVENING_FIRST)
        desc_obl = true;
    if (evtyp == SE_MORNING_FIRST or evtyp == SE_EVENING_LAST)
        retro = true;
    if (evtyp == SE_ACRONYCHAL_RISING)
        desc_obl = true;
    if (evtyp == SE_ACRONYCHAL_RISING or evtyp == SE_ACRONYCHAL_SETTING) {
        is_acronychal = true;
        if (ipl != SE_MOON)
            retro = true;
    }
    // find date when sun and object have the same ascensio obliqua
    tjd = tjd_start;
    dsunpl_save = -999999999;
    var retval = get_asc_obl_diff(tjd, ipl, star, epheflag, dgeo, desc_obl, is_acronychal, &dsunpl, serr, swed, models, dctx);
    if (retval != OK) // retval may be ERR or -2
        return retval;
    daystep = 20;
    var i: i32 = 0;
    while (dsunpl_save == -999999999 or
        @abs(dsunpl) + @abs(dsunpl_save) > 180 or
        (retro and !(dsunpl_save < 0 and dsunpl >= 0)) or
        (!retro and !(dsunpl_save >= 0 and dsunpl < 0)))
    {
        i += 1;
        if (i > 5000) {
            if (serr != null) {
                const msg = "loop in get_asc_obl_with_sun() (1)";
                const n = @min(msg.len, serr.?.len);
                @memcpy(serr.?[0..n], msg[0..n]);
            }
            return ERR;
        }
        dsunpl_save = dsunpl;
        tjd += 10.0;
        if (dperiod > 0 and tjd - tjd_start > dperiod)
            return -2;
        retval = get_asc_obl_diff(tjd, ipl, star, epheflag, dgeo, desc_obl, is_acronychal, &dsunpl, serr, swed, models, dctx);
        if (retval != OK) // retval may be ERR or -2
            return retval;
    }
    tjd_start = tjd - daystep;
    daystep /= 2.0;
    tjd = tjd_start + daystep;
    retval = get_asc_obl_diff(tjd, ipl, star, epheflag, dgeo, desc_obl, is_acronychal, &dsunpl_test, serr, swed, models, dctx);
    if (retval != OK) // retval may be ERR or -2
        return retval;
    i = 0;
    while (@abs(dsunpl) > 0.00001) {
        i += 1;
        if (i > 5000) {
            if (serr != null) {
                const msg = "loop in get_asc_obl_with_sun() (2)";
                const n = @min(msg.len, serr.?.len);
                @memcpy(serr.?[0..n], msg[0..n]);
            }
            return ERR;
        }
        if (dsunpl_save * dsunpl_test >= 0) {
            dsunpl_save = dsunpl_test;
            tjd_start = tjd;
        } else {
            dsunpl = dsunpl_test;
        }
        daystep /= 2.0;
        tjd = tjd_start + daystep;
        retval = get_asc_obl_diff(tjd, ipl, star, epheflag, dgeo, desc_obl, is_acronychal, &dsunpl_test, serr, swed, models, dctx);
        if (retval != OK) // retval may be ERR or -2
            return retval;
    }
    tjdret.* = tjd;
    return OK;
}

/// swehel.c get_heliacal_day() — day/minute search for visibility
fn get_heliacal_day(tjd_in: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, helflag: i32, TypeEvent: i32, thel: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var visible_at_sunsetrise: i32 = undefined;
    var is_rise_or_set: i32 = 0;
    var ndays: i32 = undefined;
    var retval: i32 = undefined;
    var retval_old: i32 = -2;
    var direct_day: f64 = 0;
    var direct_time: f64 = 0;
    var tfac: f64 = undefined;
    var tend: f64 = undefined;
    var daystep: f64 = undefined;
    var tday: f64 = undefined;
    var vdelta: f64 = undefined;
    var tret: f64 = undefined;
    var darr: [30]f64 = undefined;
    var vd: f64 = undefined;
    var dmag: f64 = undefined;
    var div: f64 = undefined;
    const ipl = DeterObject(ObjectName);
    // find the day and minute on which the object becomes visible
    switch (TypeEvent) {
        // morning first
        1 => {
            is_rise_or_set = swecl.SE_CALC_RISE;
            direct_day = 1;
            direct_time = -1;
        },
        // evening last
        2 => {
            is_rise_or_set = swecl.SE_CALC_SET;
            direct_day = -1;
            direct_time = 1;
        },
        // evening first
        3 => {
            is_rise_or_set = swecl.SE_CALC_SET;
            direct_day = 1;
            direct_time = 1;
        },
        // morning last
        4 => {
            is_rise_or_set = swecl.SE_CALC_RISE;
            direct_day = -1;
            direct_time = -1;
        },
        else => {},
    }
    tfac = 1;
    var tjd = tjd_in;
    switch (ipl) {
        SE_MOON => {
            ndays = 16;
            daystep = 1;
        },
        SE_MERCURY => {
            ndays = 60;
            tjd -= 0 * direct_day;
            daystep = 5;
            tfac = 5;
        },
        SE_VENUS => {
            ndays = 300;
            tjd -= 30 * direct_day;
            daystep = 5;
            if (TypeEvent >= 3) {
                daystep = 15;
                tfac = 3;
            }
        },
        SE_MARS => {
            ndays = 400;
            daystep = 15;
            tfac = 5;
        },
        SE_SATURN => {
            ndays = 300;
            daystep = 20;
            tfac = 5;
        },
        -1 => {
            ndays = 300;
            if (call_swe_fixstar_mag(ObjectName, &dmag, serr, swed, hctx) == ERR) {
                return ERR;
            }
            daystep = 15;
            tfac = 10;
            if (dmag > 2) {
                daystep = 15;
            }
            if (dmag < 0) {
                tfac = 3;
            }
        },
        else => {
            ndays = 300;
            daystep = 15;
            tfac = 3;
        },
    }
    tend = tjd + @as(f64, @floatFromInt(ndays)) * direct_day;
    retval_old = -2;
    tday = tjd;
    var i: i32 = 0;
    while ((direct_day > 0 and tday < tend) or (direct_day < 0 and tday > tend)) : ({
        tday += daystep * direct_day;
        i += 1;
    }) {
        vdelta = -100;
        if (i > 0)
            tday -= 0.3 * direct_day;
        retval = my_rise_trans(tday, SE_SUN, "", is_rise_or_set, helflag, dgeo, datm, &tret, serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) {
            return ERR;
        }
        // sun does not rise: try next day
        if (retval == -2) {
            retval_old = retval;
            continue;
        }
        var oname_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        const on = @min(ObjectName.len, AS_MAXCH - 1);
        @memcpy(oname_buf[0..on], ObjectName[0..on]);
        retval = swe_vis_limit_mag(tret, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR)
            return ERR;
        //  object has appeared above horizon: reduce daystep
        if (retval_old == -2 and retval >= 0 and daystep > 1) {
            retval_old = retval;
            tday -= daystep * direct_day;
            daystep = 1;
            // Note: beyond latitude 55N (?), Mars can have a morning last.
            // If the period of visibility is less than 5 days, we may miss
            // the event.
            if (ipl >= SE_MARS or ipl == -1)
                daystep = 5;
            continue;
        }
        retval_old = retval;
        //  object below horizon: try next day
        if (retval == -2)
            continue;
        vdelta = darr[0] - darr[7];
        // find minute of object's becoming visible
        div = 1440.0;
        vd = -1;
        visible_at_sunsetrise = 1;
        while (retval != -2) {
            vd = darr[0] - darr[7];
            if (vd >= 0) break;
            visible_at_sunsetrise = 0;
            if (vd < -1.0)
                tret += 5.0 / div * direct_time * tfac
            else if (vd < -0.5)
                tret += 2.0 / div * direct_time * tfac
            else if (vd < -0.1)
                tret += 1.0 / div * direct_time * tfac
            else
                tret += 1.0 / div * direct_time;
            retval = swe_vis_limit_mag(tret, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
            if (retval == ERR)
                return ERR;
        }
        // if possible move a bit away from sunset, where vis_limit_mag()
        // has strange behaviour
        if (visible_at_sunsetrise != 0) {
            var irep: i32 = 0;
            while (irep < 10) : (irep += 1) {
                retval = swe_vis_limit_mag(tret + 1.0 / div * direct_time, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
                if (retval >= 0 and darr[0] - darr[7] > vd) {
                    vd = darr[0] - darr[7];
                    tret += 1.0 / div * direct_time;
                }
            }
        }
        vdelta = darr[0] - darr[7];
        // object is visible, save time of appearance
        if (vdelta > 0) {
            if ((ipl >= SE_MARS or ipl == -1) and daystep > 1) {
                tday -= daystep * direct_day;
                daystep = 1;
            } else {
                thel.* = tret;
                return OK;
            }
        }
    }
    if (serr != null) {
        const msg = "heliacal event does not happen";
        const n = @min(msg.len, serr.?.len);
        @memcpy(serr.?[0..n], msg[0..n]);
    }
    return -2;
}

/// swehel.c time_optimum_visibility()
fn time_optimum_visibility(tjd_in: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, helflag: i32, tret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var retval: i32 = undefined;
    var retval_sv: i32 = undefined;
    var darr: [10]f64 = undefined;
    var phot_scot_opic: i32 = undefined;
    var phot_scot_opic_sv: i32 = undefined;
    var tjd = tjd_in;
    var oname_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const on = @min(ObjectName.len, AS_MAXCH - 1);
    @memcpy(oname_buf[0..on], ObjectName[0..on]);
    tret.* = tjd;
    retval = swe_vis_limit_mag(tjd, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR) return ERR;
    retval_sv = retval;
    var t1 = tjd;
    var t2 = tjd;
    var vl1: f64 = -1;
    var vl2: f64 = -1;
    phot_scot_opic_sv = retval & SE_SCOTOPIC_FLAG;
    var d: f64 = 100.0 / 86400.0;
    var i: i32 = 0;
    while (i < 3) : ({
        i += 1;
        d /= 10.0;
    }) {
        t1 += d;
        var t_has_changed: i32 = 0;
        while (true) {
            retval = swe_vis_limit_mag(t1 - d, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
            if (!(retval >= 0 and darr[0] > darr[7] and darr[0] - darr[7] > vl1)) break;
            t1 -= d;
            vl1 = darr[0] - darr[7];
            t_has_changed = 1;
            retval_sv = retval;
            phot_scot_opic_sv = retval & SE_SCOTOPIC_FLAG;
        }
        if (t_has_changed == 0)
            t1 -= d; // revert initial addition (C: comment says subtract)
        if (retval == ERR) return ERR;
    }
    d = 100.0 / 86400.0;
    i = 0;
    while (i < 3) : ({
        i += 1;
        d /= 10.0;
    }) {
        t2 -= d;
        var t_has_changed: i32 = 0;
        while (true) {
            retval = swe_vis_limit_mag(t2 + d, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
            if (!(retval >= 0 and darr[0] > darr[7] and darr[0] - darr[7] > vl2)) break;
            t2 += d;
            vl2 = darr[0] - darr[7];
            t_has_changed = 1;
            retval_sv = retval;
            phot_scot_opic_sv = retval & SE_SCOTOPIC_FLAG;
        }
        if (t_has_changed == 0)
            t2 += d; // revert initial subtraction
        if (retval == ERR) return ERR;
    }
    if (vl2 > vl1)
        tjd = t2
    else
        tjd = t1;
    tret.* = tjd;
    if (retval >= 0) {
        // search for optimum came to an end because change scotopic/photopic:
        phot_scot_opic = (retval & SE_SCOTOPIC_FLAG);
        if (phot_scot_opic_sv != phot_scot_opic) {
            // calling function writes warning into serr
            return -2;
        }
        // valid result found but it is close to the scotopic/photopic limit
        if ((retval_sv & SE_MIXEDOPIC_FLAG) != 0) {
            return -2;
        }
    }
    return OK;
}

/// swehel.c time_limit_invisible()
fn time_limit_invisible(tjd_in: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, helflag: i32, direct: i32, tret: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var retval: i32 = undefined;
    var retval_sv: i32 = undefined;
    var ncnt: i32 = 3;
    var d: f64 = 0;
    var darr: [10]f64 = undefined;
    var phot_scot_opic: i32 = undefined;
    var phot_scot_opic_sv: i32 = undefined;
    var d0: f64 = 100.0 / 86400.0;
    var tjd = tjd_in;
    var oname_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const on = @min(ObjectName.len, AS_MAXCH - 1);
    @memcpy(oname_buf[0..on], ObjectName[0..on]);
    tret.* = tjd;
    if (std.mem.eql(u8, ObjectName, "moon")) {
        d0 *= 10;
        ncnt = 4;
    }
    retval = swe_vis_limit_mag(tjd + d * @as(f64, @floatFromInt(direct)), dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR) return ERR;
    retval_sv = retval;
    phot_scot_opic_sv = retval & SE_SCOTOPIC_FLAG;
    d = d0;
    var i: i32 = 0;
    while (i < ncnt) : ({
        i += 1;
        d /= 10.0;
    }) {
        while (true) {
            retval = swe_vis_limit_mag(tjd + d * @as(f64, @floatFromInt(direct)), dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
            if (!(retval >= 0 and darr[0] > darr[7])) break;
            tjd += d * @as(f64, @floatFromInt(direct));
            retval_sv = retval;
            phot_scot_opic_sv = retval & SE_SCOTOPIC_FLAG;
        }
    }
    tret.* = tjd;
    // if object disappears at setting, retval is -2, but we want it OK, and
    // also suppress the warning "object is below local horizon"
    if (serr) |sr| sr[0] = 0;
    if (retval >= 0) {
        // search for limit came to an end because change scotopic/photopic:
        phot_scot_opic = (retval & SE_SCOTOPIC_FLAG);
        if (phot_scot_opic_sv != phot_scot_opic) {
            // calling function writes warning into serr
            return -2;
        }
        // valid result found but it is close to the scotopic/photopic limit
        if ((retval_sv & SE_MIXEDOPIC_FLAG) != 0) {
            return -2;
        }
    }
    return OK;
}

/// swehel.c get_acronychal_day()
fn get_acronychal_day(tjd_in: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, helflag_in: i32, TypeEvent: i32, thel: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var tjd = tjd_in;
    var helflag = helflag_in;
    var tret: f64 = undefined;
    var tret_dark: f64 = undefined;
    var darr: [30]f64 = undefined;
    var dtret: f64 = undefined;
    var is_rise_or_set: i32 = undefined;
    var direct: i32 = undefined;
    const ipl = DeterObject(ObjectName);
    helflag |= SE_HELFLAG_VISLIM_PHOTOPIC;
    if (TypeEvent == 3 or TypeEvent == 5) {
        is_rise_or_set = swecl.SE_CALC_RISE;
        direct = -1;
    } else {
        is_rise_or_set = swecl.SE_CALC_SET;
        direct = 1;
    }
    dtret = 999;
    _ = &dtret;
    while (@abs(dtret) > 0.5 / 1440.0) {
        var oname_buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        const on = @min(ObjectName.len, AS_MAXCH - 1);
        @memcpy(oname_buf[0..on], ObjectName[0..on]);
        const retval0 = my_rise_trans(tjd, ipl, ObjectName, is_rise_or_set, helflag, dgeo, datm, &tjd, serr, swed, models, dctx, cctx, hctx);
        if (retval0 == ERR) return ERR;
        var retval = swe_vis_limit_mag(tjd, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) return ERR;
        while (darr[0] < darr[7]) {
            tjd += 10.0 / 1440.0 * @as(f64, @floatFromInt(-direct));
            retval = swe_vis_limit_mag(tjd, dgeo, datm, dobs, oname_buf[0..on], helflag, darr[0..8], serr, swed, models, dctx, cctx, hctx);
            if (retval == ERR) return ERR;
        }
        retval = time_limit_invisible(tjd, dgeo, datm, dobs, ObjectName, helflag | SE_HELFLAG_VISLIM_DARK, direct, &tret_dark, serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) return ERR;
        retval = time_limit_invisible(tjd, dgeo, datm, dobs, ObjectName, helflag | SE_HELFLAG_VISLIM_NOMOON, direct, &tret, serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) return ERR;
        dtret = @abs(tret - tret_dark);
    }
    if (azalt_cart(tret, dgeo, datm, "sun", helflag, darr[0..6], serr, swed, models, dctx, cctx) == ERR)
        return ERR;
    thel.* = tret;
    if (darr[1] < -12) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "acronychal rising/setting not available, {d:.6}", .{darr[1]}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return OK;
    } else {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "solar altitude, {d:.6}", .{darr[1]}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
    }
    return OK;
}

/// swehel.c get_heliacal_details()
fn get_heliacal_details(tday: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, TypeEvent: i32, helflag: i32, dret: *[10]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var direct: i32 = undefined;
    // find next optimum visibility
    var optimum_undefined = false;
    var retval = time_optimum_visibility(tday, dgeo, datm, dobs, ObjectName, helflag, &(dret[1]), serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR) return ERR;
    if (retval == -2) {
        retval = OK;
        optimum_undefined = true; // change photopic <-> scotopic vision
    }
    // find moment of becoming visible
    direct = 1;
    if (TypeEvent == 1 or TypeEvent == 4)
        direct = -1;
    var limit_1_undefined = false;
    retval = time_limit_invisible(tday, dgeo, datm, dobs, ObjectName, helflag, direct, &(dret[0]), serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR) return ERR;
    if (retval == -2) {
        retval = OK;
        limit_1_undefined = true; // change photopic <-> scotopic vision
    }
    // find moment of end of visibility
    direct *= -1;
    var limit_2_undefined = false;
    retval = time_limit_invisible(dret[1], dgeo, datm, dobs, ObjectName, helflag, direct, &(dret[2]), serr, swed, models, dctx, cctx, hctx);
    if (retval == ERR) return ERR;
    if (retval == -2) {
        retval = OK;
        limit_2_undefined = true; // change photopic <-> scotopic vision
    }
    // correct sequence of times:
    // with event types 2 and 3 swap dret[0] and dret[2]
    if (TypeEvent == 2 or TypeEvent == 3) {
        const tday2 = dret[2];
        dret[2] = dret[0];
        dret[0] = tday2;
        const i: bool = limit_1_undefined;
        limit_1_undefined = limit_2_undefined;
        limit_2_undefined = i;
    }
    if (optimum_undefined or limit_1_undefined or limit_2_undefined) {
        if (serr != null) {
            var buf: [AS_MAXCH]u8 = undefined;
            var msg: []const u8 = "";
            if (limit_1_undefined and optimum_undefined and limit_2_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [0,1,2,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else if (limit_1_undefined and optimum_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [0,1,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else if (limit_1_undefined and limit_2_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [0,2,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else if (optimum_undefined and limit_2_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [1,2,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else if (limit_1_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [0,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else if (optimum_undefined) {
                msg = std.fmt.bufPrint(&buf, "return values [1,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            } else {
                msg = std.fmt.bufPrint(&buf, "return values [2,] are uncertain due to change between photopic and scotopic vision", .{}) catch "";
            }
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
    }
    return OK;
}

/// swehel.c heliacal_ut_vis_lim() — visibility-limit method driver
fn heliacal_ut_vis_lim(tjd_start: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, TypeEventIn: i32, helflag: i32, dret: *[10]f64, serr_ret: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var tday: f64 = undefined;
    var retval: i32 = OK;
    const helflag2 = helflag;
    const TypeEvent = TypeEventIn;
    var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    for (0..10) |i|
        dret[i] = 0;
    dret[0] = tjd_start;
    serr[0] = 0;
    const ipl = DeterObject(ObjectName);
    var tjd: f64 = undefined;
    if (ipl == SE_MERCURY)
        tjd = tjd_start - 30
    else
        tjd = tjd_start - 50; // -50 makes sure, that no event is missed,
    // but may return an event before start date
    blk: {
        // heliacal event
        if (ipl == SE_MERCURY or ipl == SE_VENUS or TypeEvent <= 2) {
            if (ipl == -1) {
                // find date when star rises with sun (cosmic rising)
                retval = get_asc_obl_with_sun(tjd, ipl, ObjectName, helflag, TypeEvent, 0, dgeo, &tjd, &serr, swed, models, dctx);
                if (retval != OK)
                    break :blk; // goto swe_heliacal_err
            } else {
                // find date of conjunction of object with sun
                retval = find_conjunct_sun(tjd, ipl, helflag, TypeEvent, &tjd, &serr, swed, models, dctx);
                if (retval == ERR) {
                    break :blk;
                }
            }
            // find the day and minute on which the object becomes visible
            retval = get_heliacal_day(tjd, dgeo, datm, dobs, ObjectName, helflag2, TypeEvent, &tday, &serr, swed, models, dctx, cctx, hctx);
            if (retval != OK)
                break :blk;
            // acronychal event
        } else {
            if (true or ipl == -1) {
                retval = get_asc_obl_with_sun(tjd, ipl, ObjectName, helflag, TypeEvent, 0, dgeo, &tjd, &serr, swed, models, dctx);
                if (retval != OK)
                    break :blk;
            } else {
                // find date of conjunction of object with sun
                retval = find_conjunct_sun(tjd, ipl, helflag, TypeEvent, &tjd, &serr, swed, models, dctx);
                if (retval == ERR)
                    break :blk;
            }
            tday = tjd;
            retval = get_acronychal_day(tjd, dgeo, datm, dobs, ObjectName, helflag2, TypeEvent, &tday, &serr, swed, models, dctx, cctx, hctx);
            if (retval != OK)
                break :blk;
        }
        dret[0] = tday;
        if ((helflag & SE_HELFLAG_NO_DETAILS) == 0) {
            // more precise event times for
            // - morning first, evening last
            // - venus and mercury's evening first and morning last
            if (ipl == SE_MERCURY or ipl == SE_VENUS or TypeEvent <= 2) {
                retval = get_heliacal_details(dret[0], dgeo, datm, dobs, ObjectName, TypeEvent, helflag2, dret, &serr, swed, models, dctx, cctx, hctx);
                if (retval == ERR) break :blk;
            }
        }
    }
    // swe_heliacal_err:
    if (serr_ret != null and serr[0] != 0) {
        const n = @min(std.mem.sliceTo(&serr, 0).len, serr_ret.?.len);
        @memcpy(serr_ret.?[0..n], serr[0..n]);
    }
    return retval;
}

/// swehel.c moon_event_vis_lim() — visibility-limit lunar events
fn moon_event_vis_lim(tjdstart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, TypeEvent: i32, helflag: i32, dret: *[10]f64, serr_ret: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var tjd: f64 = undefined;
    var trise: f64 = undefined;
    var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const ObjectName = "moon";
    var retval: i32 = undefined;
    dret[0] = tjdstart; // will be returned in error case
    if (TypeEvent == 1 or TypeEvent == 2) {
        if (serr_ret != null) {
            const msg = "error: the moon has no morning first or evening last";
            const n = @min(msg.len, serr_ret.?.len);
            @memcpy(serr_ret.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    const ipl = SE_MOON;
    var helflag2 = helflag;
    helflag2 &= ~SE_HELFLAG_HIGH_PRECISION;
    // check Synodic/phase Period
    tjd = tjdstart - 30; // -50 makes sure, that no event is missed,
    // but may return an event before start date
    blk: {
        retval = find_conjunct_sun(tjd, ipl, helflag, TypeEvent, &tjd, &serr, swed, models, dctx);
        if (retval == ERR)
            break :blk;
        // find the day and minute on which the object becomes visible
        retval = get_heliacal_day(tjd, dgeo, datm, dobs, ObjectName, helflag2, TypeEvent, &tjd, &serr, swed, models, dctx, cctx, hctx);
        if (retval != OK)
            break :blk;
        dret[0] = tjd;
        // find next optimum visibility
        retval = time_optimum_visibility(tjd, dgeo, datm, dobs, ObjectName, helflag, &tjd, &serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) break :blk;
        dret[1] = tjd;
        // find moment of becoming visible
        // Note: On the day of first light the moon may become visible
        // already during day. It also may appear during day, disappear again
        // and then reappear after sunset
        var direct: i32 = 1;
        if (TypeEvent == 4)
            direct = -1;
        retval = time_limit_invisible(tjd, dgeo, datm, dobs, ObjectName, helflag, direct, &tjd, &serr, swed, models, dctx, cctx, hctx);
        if (retval == ERR) break :blk;
        dret[2] = tjd;
        // find moment of end of visibility
        direct *= -1;
        retval = time_limit_invisible(dret[1], dgeo, datm, dobs, ObjectName, helflag, direct, &tjd, &serr, swed, models, dctx, cctx, hctx);
        dret[0] = tjd;
        if (retval == ERR) break :blk;
        // if the moon is visible before sunset, we return sunset as start time
        if (TypeEvent == 3) {
            retval = my_rise_trans(tjd, SE_SUN, "", swecl.SE_CALC_SET, helflag, dgeo, datm, &trise, &serr, swed, models, dctx, cctx, hctx);
            if (retval == ERR)
                return ERR;
            if (trise < dret[1]) {
                dret[0] = trise;
                // do not warn, it happens too often
            }
            // if the moon is visible after sunrise, we return sunrise as end time
        } else {
            retval = my_rise_trans(dret[1], SE_SUN, "", swecl.SE_CALC_RISE, helflag, dgeo, datm, &trise, &serr, swed, models, dctx, cctx, hctx);
            if (retval == ERR)
                return ERR;
            if (dret[0] > trise) {
                dret[0] = trise;
                // do not warn, it happens too often
            }
        }
        // correct order of the three times:
        if (TypeEvent == 4) {
            tjd = dret[0];
            dret[0] = dret[2];
            dret[2] = tjd;
        }
    }
    // moon_event_err:
    if (serr_ret != null and serr[0] != 0) {
        const n = @min(std.mem.sliceTo(&serr, 0).len, serr_ret.?.len);
        @memcpy(serr_ret.?[0..n], serr[0..n]);
    }
    return retval;
}

/// swehel.c MoonEventJDut()
fn MoonEventJDut(JDNDaysUTStart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, TypeEvent: i32, helflag: i32, dret: *[10]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    const avkind = helflag & SE_HELFLAG_AVKIND;
    if (avkind != 0)
        return moon_event_arc_vis(JDNDaysUTStart, dgeo, datm, dobs, TypeEvent, helflag, dret, serr, swed, models, dctx, cctx, hctx)
    else
        return moon_event_vis_lim(JDNDaysUTStart, dgeo, datm, dobs, TypeEvent, helflag, dret, serr, swed, models, dctx, cctx, hctx);
}

/// swehel.c heliacal_ut() dispatch
fn heliacal_ut(JDNDaysUTStart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectName: []const u8, TypeEventIn: i32, helflag: i32, dret: *[10]f64, serr_ret: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    const avkind = helflag & SE_HELFLAG_AVKIND;
    if (avkind != 0)
        return heliacal_ut_arc_vis(JDNDaysUTStart, dgeo, datm, dobs, ObjectName, TypeEventIn, helflag, dret, serr_ret, swed, models, dctx, cctx, hctx)
    else
        return heliacal_ut_vis_lim(JDNDaysUTStart, dgeo, datm, dobs, ObjectName, TypeEventIn, helflag, dret, serr_ret, swed, models, dctx, cctx, hctx);
}

/// swehel.c swe_heliacal_ut() — public API, outer loop over synodic periods
pub fn swe_heliacal_ut(JDNDaysUTStart: f64, dgeo: *[3]f64, datm: *[4]f64, dobs: *[6]f64, ObjectNameIn: []const u8, TypeEvent: i32, helflag: i32, dret: *[10]f64, serr_ret: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, cctx: *SweclCtx, hctx: *SwehelCtx) i32 {
    var retval: i32 = undefined;
    var ObjectName: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var serr: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    var s: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    const tjd0 = JDNDaysUTStart;
    var tjd: f64 = undefined;
    var dsynperiod: f64 = undefined;
    var tjdmax: f64 = undefined;
    var tadd: f64 = undefined;
    var MaxCountSynodicPeriod: i32 = MAX_COUNT_SYNPER;
    const sevent = [_][]const u8{ "", "morning first", "evening last", "evening first", "morning last", "acronychal rising", "acronychal setting" };
    if (dgeo[2] < SEI_ECL_GEOALT_MIN or dgeo[2] > SEI_ECL_GEOALT_MAX) {
        if (serr_ret != null) {
            const r = std.fmt.bufPrint(serr_ret.?[0 .. serr_ret.?.len - 1], "location for heliacal events must be between {d:.0} and {d:.0} m above sea\n", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr_ret.?.len) serr_ret.?[r.len] = 0;
        }
        return ERR;
    }
    _ = swi_set_tid_acc_pub(JDNDaysUTStart, helflag, 0, serr_ret, swed, dctx);
    if ((helflag & SE_HELFLAG_LONG_SEARCH) != 0)
        MaxCountSynodicPeriod = MAX_COUNT_SYNPER_MAX;
    // note, the fixed stars functions rewrite the star name. The input
    // string may be too short, so we have to make sure we have enough space
    strcpy_VBsafe(&ObjectName, ObjectNameIn);
    {
        const len = std.mem.indexOfScalar(u8, &ObjectName, 0) orelse AS_MAXCH;
        tolower_string_star(ObjectName[0..len]);
    }
    default_heliacal_parameters(datm, dgeo, dobs, helflag);
    sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
    const namelen = std.mem.indexOfScalar(u8, &ObjectName, 0) orelse AS_MAXCH;
    const oname = ObjectName[0..namelen];
    const Planet = DeterObject(oname);
    if (Planet == SE_SUN) {
        if (serr_ret != null) {
            const msg = "the sun has no heliacal rising or setting\n";
            const n = @min(msg.len, serr_ret.?.len);
            @memcpy(serr_ret.?[0..n], msg[0..n]);
        }
        return ERR;
    }
    // Moon events
    if (Planet == SE_MOON) {
        if (TypeEvent == 1 or TypeEvent == 2) {
            if (serr_ret != null) {
                const r = std.fmt.bufPrint(serr_ret.?[0 .. serr_ret.?.len - 1], "{s} (event type {d}) does not exist for the moon\n", .{ sevent[@intCast(TypeEvent)], TypeEvent }) catch "";
                if (r.len < serr_ret.?.len) serr_ret.?[r.len] = 0;
            }
            return ERR;
        }
        tjd = tjd0;
        retval = MoonEventJDut(tjd, dgeo, datm, dobs, TypeEvent, helflag, dret, &serr, swed, models, dctx, cctx, hctx);
        while (retval != -2 and dret[0] < tjd0) {
            tjd += 15;
            serr[0] = 0;
            retval = MoonEventJDut(tjd, dgeo, datm, dobs, TypeEvent, helflag, dret, &serr, swed, models, dctx, cctx, hctx);
        }
        if (serr_ret != null and serr[0] != 0) {
            const n = @min(std.mem.sliceTo(&serr, 0).len, serr_ret.?.len);
            @memcpy(serr_ret.?[0..n], serr[0..n]);
        }
        return retval;
    }
    // planets and fixed stars
    if ((helflag & SE_HELFLAG_AVKIND) == 0) {
        if (Planet == -1 or Planet >= SE_MARS) {
            if (TypeEvent == 3 or TypeEvent == 4) {
                if (serr_ret != null) {
                    if (Planet == -1) {
                        const n = @min(oname.len, s.len);
                        @memcpy(s[0..n], oname[0..n]);
                    } else {
                        _ = sweph.swe_get_planet_name(Planet, &s, swed, models, dctx, null);
                    }
                    const r = std.fmt.bufPrint(serr_ret.?[0 .. serr_ret.?.len - 1], "{s} (event type {d}) does not exist for {s}\n", .{ sevent[@intCast(TypeEvent)], TypeEvent, std.mem.sliceTo(&s, 0) }) catch "";
                    if (r.len < serr_ret.?.len) serr_ret.?[r.len] = 0;
                }
                return ERR;
            }
        }
    }
    // arcus visionis method: set the TypeEvent for acronychal events
    var TypeEventMut = TypeEvent;
    if ((helflag & SE_HELFLAG_AVKIND) != 0) {
        if (Planet == -1 or Planet >= SE_MARS) {
            if (TypeEventMut == SE_ACRONYCHAL_RISING)
                TypeEventMut = 3;
            if (TypeEventMut == SE_ACRONYCHAL_SETTING)
                TypeEventMut = 4;
        }
        // acronychal rising and setting (cosmic setting) are ill-defined.
        // We do not calculate them with the "visibility limit method"
    } else {
        if (TypeEventMut == SE_ACRONYCHAL_RISING or TypeEventMut == SE_ACRONYCHAL_SETTING) {
            if (serr_ret != null) {
                if (Planet == -1) {
                    const n = @min(oname.len, s.len);
                    @memcpy(s[0..n], oname[0..n]);
                } else {
                    _ = sweph.swe_get_planet_name(Planet, &s, swed, models, dctx, null);
                }
                const r = std.fmt.bufPrint(serr_ret.?[0 .. serr_ret.?.len - 1], "{s} (event type {d}) is not provided for {s}\n", .{ sevent[@intCast(TypeEventMut)], TypeEventMut, std.mem.sliceTo(&s, 0) }) catch "";
                if (r.len < serr_ret.?.len) serr_ret.?[r.len] = 0;
            }
            return ERR;
        }
    }
    dsynperiod = get_synodic_period(Planet);
    tjdmax = tjd0 + dsynperiod * @as(f64, @floatFromInt(MaxCountSynodicPeriod));
    tadd = dsynperiod * 0.6;
    if (Planet == SE_MERCURY)
        tadd = 30;
    // this is the outer loop over n synodic periods
    retval = -2; // indicates that another synodic period has to be done
    tjd = tjd0;
    while (tjd < tjdmax and retval == -2) : (tjd += tadd) {
        serr[0] = 0;
        retval = heliacal_ut(tjd, dgeo, datm, dobs, oname, TypeEventMut, helflag, dret, &serr, swed, models, dctx, cctx, hctx);
        // if resulting event date < start date for search (tjd0): retry
        // starting from half a period later. The event must be found now,
        // unless there is none, as is often the case with Mercury
        while (retval != -2 and dret[0] < tjd0) {
            tjd += tadd;
            serr[0] = 0;
            retval = heliacal_ut(tjd, dgeo, datm, dobs, oname, TypeEventMut, helflag, dret, &serr, swed, models, dctx, cctx, hctx);
        }
    }
    // no event was found within MaxCountSynodicPeriod, return error
    if ((helflag & SE_HELFLAG_SEARCH_1_PERIOD) != 0 and (retval == -2 or dret[0] > tjd0 + dsynperiod * 1.5)) {
        const msg = "no heliacal date found within this synodic period";
        const n = @min(msg.len, serr.len);
        @memcpy(serr[0..n], msg[0..n]);
        retval = -2;
    } else if (retval == -2) {
        const r = std.fmt.bufPrint(&serr, "no heliacal date found within {d} synodic periods", .{MaxCountSynodicPeriod}) catch "";
        serr[r.len] = 0;
        retval = ERR;
    }
    if (serr_ret != null and serr[0] != 0) {
        const n = @min(std.mem.sliceTo(&serr, 0).len, serr_ret.?.len);
        @memcpy(serr_ret.?[0..n], serr[0..n]);
    }
    return retval;
}
