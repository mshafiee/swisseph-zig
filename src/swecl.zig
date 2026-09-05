// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port — swecl module (eclipse/phenomena machinery).
// Port of swecl.c; see docs/parity.md for the bit-parity contract.
// C file-static state lives in SweclCtx.
const std = @import("std");
const lib = @import("swephlib");
const deltat_mod = @import("deltat");
const sweph = @import("sweph");
const houses = @import("swehouse");

const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;
const swe_shim_tan = lib.swe_shim_tan;
const swe_shim_asin = lib.swe_shim_asin;
const swe_shim_acos = lib.swe_shim_acos;
const swe_shim_atan2 = lib.swe_shim_atan2;
const swe_shim_pow = lib.swe_shim_pow;
const swe_shim_atan = lib.swe_shim_atan;
const swemmoon_mod = @import("swemmoon");
const swe_shim_log10 = lib.swe_shim_log10;

const AstroModels = lib.AstroModels;
const DeltatCtx = deltat_mod.DeltatCtx;
const Swed = sweph.Swed;

const DEGTORAD = lib.DEGTORAD;
const RADTODEG = lib.RADTODEG;
const PI = lib.PI;
const AUNIT = lib.AUNIT;
const CLIGHT = lib.CLIGHT;
const EARTH_RADIUS: f64 = 6378136.6; // AA 2006 K6 (sweph.h)
const SE_LAPSE_RATE: f64 = 0.0065; // deg K / m (sweph.h)

// swecl.c file-static TLS global; the port models it as an explicit
// context field threaded through the swecl API.
pub const SweclCtx = struct {
    const_lapse_rate: f64 = SE_LAPSE_RATE,
};

pub const SE_ECL2HOR: i32 = 0;
pub const SE_EQU2HOR: i32 = 1;
pub const SE_HOR2ECL: i32 = 0;
pub const SE_HOR2EQU: i32 = 1;
pub const SE_TRUE_TO_APP: i32 = 0;
pub const SE_APP_TO_TRUE: i32 = 1;

/// swecl.c swe_set_lapse_rate()
pub fn swe_set_lapse_rate(lapse_rate: f64, ctx: *SweclCtx) void {
    ctx.const_lapse_rate = lapse_rate;
}

/// swecl.c calc_astronomical_refr() — Sinclair formula.
fn calc_astronomical_refr(inalt: f64, atpress: f64, attemp: f64) f64 {
    var r: f64 = undefined;
    if (inalt > 17.904104638432) { // for continuous function, instead of '>15'
        r = 0.97 / swe_shim_tan(inalt * DEGTORAD);
    } else {
        r = (34.46 + 4.23 * inalt + 0.004 * inalt * inalt) /
            (1 + 0.505 * inalt + 0.0845 * inalt * inalt);
    }
    r = ((atpress - 80) / 930 / (1 + 0.00008 * (r + 39) * (attemp - 10)) * r) / 60.0;
    return r;
}

/// swecl.c calc_dip() — Thom/Reijs dip of the horizon.
fn calc_dip(geoalt: f64, atpress: f64, attemp: f64, lapse_rate: f64) f64 {
    const krefr = (0.0342 + lapse_rate) / (@as(f64, 0.154) * @as(f64, 0.0238));
    const d = 1 - 1.8480 * krefr * atpress / (273.15 + attemp) / (273.15 + attemp);
    return -180.0 / PI * swe_shim_acos(1 / (1 + geoalt / EARTH_RADIUS)) * @sqrt(d);
}

/// swecl.c swe_refrac() — Meeus algorithm.
pub fn swe_refrac(inalt: f64, atpress: f64, attemp: f64, calc_flag: i32) f64 {
    var a: f64 = undefined;
    var refr: f64 = undefined;
    const pt_factor = atpress / 1010.0 * 283.0 / (273.0 + attemp);
    var trualt: f64 = undefined;
    var appalt: f64 = undefined;
    // another algorithm, from Meeus, German, p. 114ff.
    if (calc_flag == SE_TRUE_TO_APP) {
        trualt = inalt;
        if (trualt > 15) {
            a = swe_shim_tan((90 - trualt) * DEGTORAD);
            refr = (58.276 * a - 0.0824 * a * a * a);
            refr *= pt_factor / 3600.0;
        } else if (trualt > -5) {
            // the following tan is not defined for a value
            // of trualt near -5.00158 and 89.89158
            a = trualt + 10.3 / (trualt + 5.11);
            if (a + 1e-10 >= 90)
                refr = 0
            else
                refr = 1.02 / swe_shim_tan(a * DEGTORAD);
            refr *= pt_factor / 60.0;
        } else refr = 0;
        appalt = trualt;
        if (appalt + refr > 0)
            appalt += refr;
        return appalt;
    } else {
        // apparent to true
        appalt = inalt;
        // the following tan is not defined for a value
        // of inalt near -4.3285 and 89.9225
        a = appalt + 7.31 / (appalt + 4.4);
        if (a + 1e-10 >= 90)
            refr = 0
        else {
            refr = 1.00 / swe_shim_tan(a * DEGTORAD);
            refr -= 0.06 * swe_shim_sin(14.7 * refr + 13);
        }
        refr *= pt_factor / 60.0;
        trualt = appalt;
        if (appalt - refr > 0)
            trualt = appalt - refr;
        return trualt;
    }
}

/// swecl.c swe_refrac_extended() — Reijs refraction with dip of horizon.
/// dret: optional array of 4 doubles (true alt, apparent alt, refraction, dip).
pub fn swe_refrac_extended(
    inalt_in: f64,
    geoalt: f64,
    atpress: f64,
    attemp: f64,
    lapse_rate: f64,
    calc_flag: i32,
    dret: ?*[4]f64,
) f64 {
    var inalt = inalt_in;
    var refr: f64 = undefined;
    var trualt: f64 = undefined;
    const dip = calc_dip(geoalt, atpress, attemp, lapse_rate);
    var D: f64 = undefined;
    var D0: f64 = undefined;
    var N: f64 = undefined;
    var y: f64 = undefined;
    var yy0: f64 = undefined;
    // make sure that inalt <=90
    if ((inalt > 90))
        inalt = 180 - inalt;
    if (calc_flag == SE_TRUE_TO_APP) {
        if (inalt < -10) {
            if (dret != null) {
                dret.?[0] = inalt;
                dret.?[1] = inalt;
                dret.?[2] = 0;
                dret.?[3] = dip;
            }
            return inalt;
        }
        // by iteration
        y = inalt;
        D = 0.0;
        yy0 = 0;
        D0 = D;
        var i: usize = 0;
        while (i < 5) : (i += 1) {
            D = calc_astronomical_refr(y, atpress, attemp);
            N = y - yy0;
            yy0 = D - D0 - N; // denominator of derivative
            if (N != 0.0 and yy0 != 0.0) // sic !!! code by Moshier
                N = y - N * (inalt + D - y) / yy0 // Newton iteration with numerically estimated derivative
            else // Can't do it on first pass
                N = inalt + D;
            yy0 = y;
            D0 = D;
            y = N;
        }
        refr = D;
        if (inalt + refr < dip) {
            if (dret != null) {
                dret.?[0] = inalt;
                dret.?[1] = inalt;
                dret.?[2] = 0;
                dret.?[3] = dip;
            }
            return inalt;
        }
        if (dret != null) {
            dret.?[0] = inalt;
            dret.?[1] = inalt + refr;
            dret.?[2] = refr;
            dret.?[3] = dip;
        }
        return inalt + refr;
    } else {
        refr = calc_astronomical_refr(inalt, atpress, attemp);
        trualt = inalt - refr;
        if (dret != null) {
            if (inalt > dip) {
                dret.?[0] = trualt;
                dret.?[1] = inalt;
                dret.?[2] = refr;
                dret.?[3] = dip;
            } else {
                dret.?[0] = inalt;
                dret.?[1] = inalt;
                dret.?[2] = 0;
                dret.?[3] = dip;
            }
        }
        // Apparent altitude cannot be below dip.
        // True altitude is only returned if apparent altitude is higher than dip.
        // Otherwise the apparent altitude is returned.
        if (inalt >= dip) // bug fix dieter, 4 feb 20
            return trualt
        else
            return inalt;
    }
}

/// swecl.c swe_azalt() — equatorial or ecliptic input -> azimuth/altitude.
/// Reads xin[0..1] (RA/decl or lon/lat in degrees); xaz gets azimuth,
/// true height, apparent height.
pub fn swe_azalt(
    tjd_ut: f64,
    calc_flag: i32,
    geopos: *const [3]f64,
    atpress_in: f64,
    attemp: f64,
    xin: *const [3]f64,
    xaz: *[3]f64,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    ctx: *SweclCtx,
) void {
    var atpress = atpress_in;
    var x: [6]f64 = undefined;
    var xra: [3]f64 = undefined;
    const armc = lib.swe_degnorm(lib.swe_sidtime(tjd_ut, models, dctx, nutInterp(swed)) * 15 + geopos[0]);
    var mdd: f64 = undefined;
    var eps_true: f64 = undefined;
    var i: usize = 0;
    while (i < 2) : (i += 1)
        xra[i] = xin[i];
    xra[2] = 1;
    if (calc_flag == SE_ECL2HOR) {
        // C's swe_deltat_ex reads the moon-file denum live; refresh first
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        _ = sweph.swe_calc(tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, -1), sweph.SE_ECL_NUT, 0, &x, swed, models, dctx, null);
        eps_true = x[0];
        houses.swe_cotrans(xra[0..], xra[0..], -eps_true);
    }
    mdd = lib.swe_degnorm(xra[0] - armc);
    x[0] = lib.swe_degnorm(mdd - 90);
    x[1] = xra[1];
    x[2] = 1;
    // azimuth from east, counterclock
    houses.swe_cotrans(x[0..], x[0..], 90 - geopos[1]);
    // azimuth from south to west
    x[0] = lib.swe_degnorm(x[0] + 90);
    xaz[0] = 360 - x[0];
    xaz[1] = x[1]; // true height
    if (atpress == 0) {
        // estimate atmospheric pressure
        atpress = 1013.25 * swe_shim_pow(1 - 0.0065 * geopos[2] / 288, 5.255);
    }
    xaz[2] = swe_refrac_extended(x[1], geopos[2], atpress, attemp, ctx.const_lapse_rate, SE_TRUE_TO_APP, null);
}

/// swecl.c swe_azalt_rev() — azimuth + true altitude -> equatorial or
/// ecliptic coordinates. Reads xin[0..1] (azimuth, true altitude).
pub fn swe_azalt_rev(
    tjd_ut: f64,
    calc_flag: i32,
    geopos: *const [3]f64,
    xin: *const [3]f64,
    xout: *[2]f64,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) void {
    var x: [6]f64 = undefined;
    var xaz: [3]f64 = undefined;
    const geolon = geopos[0];
    const geolat = geopos[1];
    const armc = lib.swe_degnorm(lib.swe_sidtime(tjd_ut, models, dctx, nutInterp(swed)) * 15 + geolon);
    var eps_true: f64 = undefined;
    var dang: f64 = undefined;
    var i: usize = 0;
    while (i < 2) : (i += 1)
        xaz[i] = xin[i];
    xaz[2] = 1;
    // azimuth is from south, clockwise.
    // we need it from east, counterclock
    xaz[0] = 360 - xaz[0];
    xaz[0] = lib.swe_degnorm(xaz[0] - 90);
    // equatorial positions
    dang = geolat - 90;
    houses.swe_cotrans(xaz[0..], xaz[0..], dang);
    xaz[0] = lib.swe_degnorm(xaz[0] + armc + 90);
    xout[0] = xaz[0];
    xout[1] = xaz[1];
    // ecliptic positions
    if (calc_flag == SE_HOR2ECL) {
        // C's swe_deltat_ex reads the moon-file denum live; refresh first
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        _ = sweph.swe_calc(tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, -1), sweph.SE_ECL_NUT, 0, &x, swed, models, dctx, null);
        eps_true = x[0];
        houses.swe_cotrans(xaz[0..], x[0..], eps_true);
        xout[0] = x[0];
        xout[1] = x[1];
    }
}

/// sweph.c nutInterp equivalent (nutation interpolation state)
fn nutInterp(swed: *Swed) ?*lib.Interp {
    return if (swed.do_interpolate_nut) &swed.interp else null;
}

// swe_pheno / swe_pheno_ut  (swecl.c)

pub const SE_SUN: i32 = 0;
pub const SE_MOON: i32 = 1;
pub const SE_MERCURY: i32 = 2;
pub const SE_VENUS: i32 = 3;
pub const SE_MARS: i32 = 4;
pub const SE_JUPITER: i32 = 5;
pub const SE_SATURN: i32 = 6;
pub const SE_URANUS: i32 = 7;
pub const SE_NEPTUNE: i32 = 8;
pub const SE_PLUTO: i32 = 9;
pub const SE_MEAN_NODE: i32 = 10;
pub const SE_TRUE_NODE: i32 = 11;
pub const SE_MEAN_APOG: i32 = 12;
pub const SE_OSCU_APOG: i32 = 13;
pub const SE_EARTH: i32 = 14;
pub const SE_CHIRON: i32 = 15;
pub const SE_PHOLUS: i32 = 16;
pub const SE_CERES: i32 = 17;
pub const SE_PALLAS: i32 = 18;
pub const SE_JUNO: i32 = 19;
pub const SE_VESTA: i32 = 20;
pub const SE_AST_OFFSET: i32 = 10000;

pub const SEFLG_JPLEPH: i32 = 1;
pub const SEFLG_SWIEPH: i32 = 2;
pub const SEFLG_MOSEPH: i32 = 4;
pub const SEFLG_HELCTR: i32 = 8;
pub const SEFLG_TRUEPOS: i32 = 16;
pub const SEFLG_J2000: i32 = 32;
pub const SEFLG_NONUT: i32 = 64;
pub const SEFLG_SPEED: i32 = 256;
pub const SEFLG_NOGDEFL: i32 = 512;
pub const SEFLG_NOABERR: i32 = 1024;
pub const SEFLG_EQUATORIAL: i32 = 2 * 1024;
pub const SEFLG_XYZ: i32 = 4 * 1024;
pub const SEFLG_RADIANS: i32 = 8 * 1024;
pub const SEFLG_TOPOCTR: i32 = 32 * 1024;
pub const SEFLG_SIDEREAL: i32 = 64 * 1024;
pub const SEFLG_JPLHOR: i32 = 256 * 1024;
pub const SEFLG_JPLHOR_APPROX: i32 = 512 * 1024;
pub const SEFLG_BARYCTR: i32 = 16 * 1024;
pub const SEFLG_EPHMASK: i32 = 1 | 2 | 4;

const NDIAM: usize = @intCast(SE_VESTA + 1);
const NMAG_ELEM: usize = @intCast(SE_VESTA + 1);
const EULER: f64 = 2.718281828459;

// swecl.c mag_elem[NMAG_ELEM][4] — values transcribed 1:1; entries that C
// writes as plain decimals are exact.
const mag_elem = [NMAG_ELEM][4]f64{
    .{ -26.86, 0, 0, 0 }, // Sun
    .{ -12.55, 0, 0, 0 }, // Moon
    .{ -0.42, 3.80, -2.73, 2.00 }, // Mercury (obsolete, but don't delete this line!)
    .{ -4.40, 0.09, 2.39, -0.65 }, // Venus (obsolete, but don't delete this line!)
    .{ -1.52, 1.60, 0, 0 }, // Mars
    .{ -9.40, 0.5, 0, 0 }, // Jupiter
    .{ -8.88, -2.60, 1.25, 0.044 }, // Saturn
    .{ -7.19, 0.0, 0, 0 }, // Uranus
    .{ -6.87, 0.0, 0, 0 }, // Neptune
    .{ -1.00, 0.0, 0, 0 }, // Pluto
    .{ 99, 0, 0, 0 }, // nodes and apogees
    .{ 99, 0, 0, 0 },
    .{ 99, 0, 0, 0 },
    .{ 99, 0, 0, 0 },
    .{ 99, 0, 0, 0 }, // Earth
    .{ 6.5, 0.15, 0, 0 }, // Chiron
    .{ 7.0, 0.15, 0, 0 }, // Pholus
    .{ 3.34, 0.12, 0, 0 }, // Ceres
    .{ 4.13, 0.11, 0, 0 }, // Pallas
    .{ 5.33, 0.32, 0, 0 }, // Juno
    .{ 3.20, 0.32, 0, 0 }, // Vesta
};

// sweph.h pla_diam[NDIAM] — the C entries written as `x * 2` fold
// multiplication-by-2, which is exact in binary floating point, so the
// products are written out (same value, one literal).
const pla_diam = [NDIAM]f64{
    1392000000.0, // Sun
    3475000.0, // Moon
    2439400.0 * 2, // Mercury
    6051800.0 * 2, // Venus
    3389500.0 * 2, // Mars
    69911000.0 * 2, // Jupiter
    58232000.0 * 2, // Saturn
    25362000.0 * 2, // Uranus
    24622000.0 * 2, // Neptune
    1188300.0 * 2, // Pluto
    0, 0, 0, 0, // nodes and apogees
    6371008.4 * 2, // Earth
    271370.0, // Chiron
    290000.0, // Pholus
    939400.0, // Ceres
    545000.0, // Pallas
    246596.0, // Juno
    525400.0, // Vesta
};

/// swecl.c swe_pheno() — phase, angle, elongation, diameter, magnitude,
/// parallax. attr must have room for 20 doubles.
pub fn swe_pheno(
    tjd: f64,
    ipl_in: i32,
    iflag_in: i32,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var ipl = ipl_in;
    var iflag = iflag_in;
    var xx: [6]f64 = undefined;
    var xx2: [6]f64 = undefined;
    var xxs: [6]f64 = undefined;
    var lbr: [6]f64 = undefined;
    var lbr2: [6]f64 = undefined;
    var dt: f64 = 0;
    var dd: f64 = undefined;
    var serr2: [256]u8 = [_]u8{0} ** 256; // AS_MAXCH
    var i: usize = 0;
    iflag &= ~(SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX);
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    for (attr) |*a| {
        a.* = 0;
    }
    // Ceres - Vesta must be SE_CERES etc., not 10001 etc.
    if (ipl > SE_AST_OFFSET and ipl <= SE_AST_OFFSET + 4)
        ipl = ipl - SE_AST_OFFSET - 1 + SE_CERES;
    iflag = iflag & (SEFLG_EPHMASK |
        SEFLG_TRUEPOS |
        SEFLG_J2000 |
        SEFLG_NONUT |
        SEFLG_NOGDEFL |
        SEFLG_NOABERR |
        SEFLG_TOPOCTR);
    var iflagp = iflag & (SEFLG_EPHMASK |
        SEFLG_TRUEPOS |
        SEFLG_J2000 |
        SEFLG_NONUT |
        SEFLG_NOABERR);
    iflagp |= SEFLG_HELCTR;
    var epheflag = iflag & SEFLG_EPHMASK;
    // geocentric planet
    const retflag = sweph.swe_calc(tjd, ipl, iflag | SEFLG_XYZ, &xx, swed, models, dctx, serr);
    if (retflag == lib.ERR)
        return lib.ERR;
    // check epheflag and adjust iflag
    const epheflag2 = retflag & SEFLG_EPHMASK;
    if (epheflag != epheflag2) {
        iflag &= ~epheflag;
        iflagp &= ~epheflag;
        iflag |= epheflag2;
        iflagp |= epheflag2;
        epheflag = epheflag2;
    }
    if (sweph.swe_calc(tjd, ipl, iflag, &lbr, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    // if moon, we need sun as well, for magnitude
    if (ipl == SE_MOON) {
        if (sweph.swe_calc(tjd, SE_SUN, iflag | SEFLG_XYZ, &xxs, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    }
    if (ipl != SE_SUN and ipl != SE_EARTH and
        ipl != SE_MEAN_NODE and ipl != SE_TRUE_NODE and
        ipl != SE_MEAN_APOG and ipl != SE_OSCU_APOG)
    {
        // light time planet - earth
        dt = lbr[2] * AUNIT / CLIGHT / 86400.0;
        if ((iflag & SEFLG_TRUEPOS) != 0)
            dt = 0;
        // heliocentric planet at tjd - dt
        if (sweph.swe_calc(tjd - dt, ipl, iflagp | SEFLG_XYZ, &xx2, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd - dt, ipl, iflagp, &lbr2, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        // phase angle
        attr[0] = swe_shim_acos(lib.swi_dot_prod_unit(xx[0..3], xx2[0..3])) * RADTODEG;
        // phase
        attr[1] = (1 + swe_shim_cos(attr[0] * DEGTORAD)) / 2;
    }
    // apparent diameter of disk
    if (ipl >= 0 and @as(usize, @intCast(ipl)) < NDIAM) {
        dd = pla_diam[@intCast(ipl)];
    } else if (ipl > SE_AST_OFFSET) {
        dd = swed.ast_diam * 1000; // km -> m
    } else {
        dd = 0;
    }
    if (lbr[2] < dd / 2 / AUNIT)
        attr[3] = 180 // assume position on surface of earth
    else
        attr[3] = swe_shim_asin(dd / 2 / AUNIT / lbr[2]) * 2 * RADTODEG;
    // apparent magnitude
    if (ipl > SE_AST_OFFSET or (ipl >= 0 and @as(usize, @intCast(ipl)) < NMAG_ELEM and mag_elem[@intCast(ipl)][0] < 99)) {
        if (ipl == SE_SUN) {
            // ratio apparent diameter : average diameter
            const fac0 = attr[3] / (swe_shim_asin(pla_diam[@intCast(SE_SUN)] / 2.0 / AUNIT) * 2 * RADTODEG);
            const fac = fac0 * fac0;
            attr[4] = mag_elem[@intCast(ipl)][0] - 2.5 * swe_shim_log10(fac);
        } else if (ipl == SE_MOON) {
            // formula according to Allen, C.W., 1976, Astrophysical Quantities
            // (MAG_MOON_VREIJS = 1: the stitched Allen/Samaha formula)
            const a = attr[0];
            if (a <= 147.1385465) {
                attr[4] = -21.62 + 0.026 * @abs(a) + 0.000000004 * swe_shim_pow(a, 4);
                attr[4] += 5 * swe_shim_log10(lbr[2] * lbr2[2] * AUNIT / EARTH_RADIUS);
            } else {
                // using the cube phase angle proposed by Samaha (Samaha, A.E.; Asaad,
                // A. S. and Mikhail, J. S. (1969). Visibility of the New Moon,
                // Bulletin of Observatory Helwan, 84), and VR adjusted the stitch
                // phase (align Allen's and Samaha's magnitude) of 147.14degrees.
                attr[4] = -4.5444 - (2.5 * swe_shim_log10(swe_shim_pow(180 - a, 3)));
                attr[4] += 5 * swe_shim_log10(lbr[2] * lbr2[2] * AUNIT / EARTH_RADIUS);
            }
            // see: A. Mallama, J.Hilton,
            // "ComputingApparentPlanetaryMagnitudesForTheAstronomicalAlmanac" (2018)
            // https://arxiv.org/ftp/arxiv/papers/1808/1808.01973.pdf
        } else if (ipl == SE_MERCURY) {
            const a = attr[0];
            const a2 = a * a;
            const a3 = a2 * a;
            const a4 = a3 * a;
            const a5 = a4 * a;
            const a6 = a5 * a;
            attr[4] = -0.613 + a * 6.3280E-02 - a2 * 1.6336E-03 + a3 * 3.3644E-05 - a4 * 3.4265E-07 + a5 * 1.6893E-09 - a6 * 3.0334E-12;
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
        } else if (ipl == SE_VENUS) {
            const a = attr[0];
            const a2 = a * a;
            const a3 = a2 * a;
            const a4 = a3 * a;
            if (a <= 163.7)
                attr[4] = -4.384 - a * 1.044E-03 + a2 * 3.687E-04 - a3 * 2.814E-06 + a4 * 8.938E-09
            else
                attr[4] = 236.05828 - a * 2.81914E+00 + a2 * 8.39034E-03;
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
            if (attr[0] > 179.0) {
                const r = std.fmt.bufPrint(&serr2, "magnitude value for Venus at phase angle i={d:.1} is bad; formula is valid only for i < 179.0", .{attr[0]}) catch "";
                serr2[r.len] = 0;
            }
        } else if (ipl == SE_MARS) {
            const a = attr[0];
            const a2 = a * a;
            // With the following formulae, the terms +L(λe)+L(LS) have been omitted.
            // The apparent magnitude of Mars changes considerably within hours;
            // the deviation of this simplified solution from Horizons is < 0.1m.
            if (a <= 50.0)
                attr[4] = -1.601 + a * 0.02267 - a2 * 0.0001302
            else // irrelevant to earth-centered observation
                attr[4] = -0.367 - a * 0.02573 + a2 * 0.0003445;
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
        } else if (ipl == SE_JUPITER) {
            // the phase angle of Jupiter never exceeds 12°.
            const a = attr[0];
            const a2 = a * a;
            attr[4] = -9.395 - a * 3.7E-04 + a2 * 6.16E-04;
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
        } else if (ipl == SE_SATURN) {
            const a = attr[0];
            // Mallama does not provide B; derived from Meeus p. 301ff.
            // (German version 329ff.) There are small differences from
            // Horizons < 0.02m.
            var sinB: f64 = undefined;
            const T = (tjd - dt - lib.J2000) / 36525.0;
            const in = (28.075216 - 0.012998 * T + 0.000004 * T * T) * DEGTORAD;
            const om = (169.508470 + 1.394681 * T + 0.000412 * T * T) * DEGTORAD;
            var sinB2: f64 = undefined;
            sinB = (swe_shim_sin(in) * swe_shim_cos(lbr[1] * DEGTORAD) *
                swe_shim_sin(lbr[0] * DEGTORAD - om) -
                swe_shim_cos(in) * swe_shim_sin(lbr[1] * DEGTORAD));
            sinB2 = (swe_shim_sin(in) * swe_shim_cos(lbr2[1] * DEGTORAD) *
                swe_shim_sin(lbr2[0] * DEGTORAD - om) -
                swe_shim_cos(in) * swe_shim_sin(lbr2[1] * DEGTORAD));
            sinB = @abs(swe_shim_sin((swe_shim_asin(sinB) + swe_shim_asin(sinB2)) / 2.0));
            attr[4] = -8.914 - 1.825 * sinB + 0.026 * a - 0.378 * sinB * swe_shim_pow(2.7182818, -2.25 * a);
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
        } else if (ipl == SE_URANUS) {
            // simplified solution ignoring the sub-Earth latitude term
            const a = attr[0];
            const a2 = a * a;
            const fi_: f64 = 0; // sub-Earth latitude in deg; ignored here
            attr[4] = -7.110 - 8.4E-04 * fi_ + a * 6.587E-3 + a2 * 1.045E-4;
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
            // instead of the term with fi_, we do subtract the 0.05m.
            attr[4] -= 0.05;
        } else if (ipl == SE_NEPTUNE) {
            if (tjd < 2444239.5) {
                attr[4] = -6.89;
            } else if (tjd <= 2451544.5) {
                attr[4] = -6.89 - 0.0055 * (tjd - 2444239.5) / 365.25;
                // Mallama has 0.0054, but that would make the curve discontinuous
            } else {
                attr[4] = -7.00;
            }
            attr[4] += 5 * swe_shim_log10(lbr2[2] * lbr[2]);
        } else if (ipl < SE_CHIRON) {
            attr[4] = 5 * swe_shim_log10(lbr2[2] * lbr[2]) +
                mag_elem[@intCast(ipl)][1] * attr[0] / 100.0 +
                mag_elem[@intCast(ipl)][2] * attr[0] * attr[0] / 10000.0 +
                mag_elem[@intCast(ipl)][3] * attr[0] * attr[0] * attr[0] / 1000000.0 +
                mag_elem[@intCast(ipl)][0];
        } else if (@as(usize, @intCast(ipl)) < NMAG_ELEM or ipl > SE_AST_OFFSET) { // other planets, asteroids
            const ph1 = swe_shim_pow(EULER, -3.33 * swe_shim_pow(swe_shim_tan(attr[0] * DEGTORAD / 2), 0.63));
            const ph2 = swe_shim_pow(EULER, -1.87 * swe_shim_pow(swe_shim_tan(attr[0] * DEGTORAD / 2), 1.22));
            var me: [2]f64 = undefined;
            if (@as(usize, @intCast(ipl)) < NMAG_ELEM) { // other planets, main asteroids
                me[0] = mag_elem[@intCast(ipl)][0];
                me[1] = mag_elem[@intCast(ipl)][1];
            } else if (ipl == SE_AST_OFFSET + 1566) {
                // Icarus has elements from JPL database
                me[0] = 16.9;
                me[1] = 0.15;
            } else { // other asteroids
                me[0] = swed.ast_H;
                me[1] = swed.ast_G;
            }
            attr[4] = 5 * swe_shim_log10(lbr2[2] * lbr[2]) +
                me[0] -
                2.5 * swe_shim_log10((1 - me[1]) * ph1 + me[1] * ph2);
        } else { // fictitious bodies
            attr[4] = 0;
        }
    }
    if (ipl != SE_SUN and ipl != SE_EARTH) {
        // elongation of planet
        if (sweph.swe_calc(tjd, SE_SUN, iflag | SEFLG_XYZ, &xx2, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_SUN, iflag, &lbr2, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        attr[2] = swe_shim_acos(lib.swi_dot_prod_unit(xx[0..3], xx2[0..3])) * RADTODEG;
    }
    // horizontal parallax
    if (ipl == SE_MOON) {
        var xm: [6]f64 = undefined;
        // geocentric horizontal parallax
        // Expl.Suppl. to the AA 1984, p.400
        if (sweph.swe_calc(tjd, ipl, epheflag | SEFLG_TRUEPOS | SEFLG_EQUATORIAL | SEFLG_RADIANS, &xm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        const sinhp = EARTH_RADIUS / xm[2] / AUNIT;
        attr[5] = swe_shim_asin(sinhp) / DEGTORAD;
        // topocentric horizontal parallax
        if ((iflag & SEFLG_TOPOCTR) != 0) {
            if (sweph.swe_calc(tjd, ipl, epheflag | SEFLG_XYZ | SEFLG_TOPOCTR, &xm, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            if (sweph.swe_calc(tjd, ipl, epheflag | SEFLG_XYZ, &xx, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            attr[5] = swe_shim_acos(lib.swi_dot_prod_unit(xm[0..3], xx[0..3])) / DEGTORAD;
        }
    }
    if (serr2[0] != 0 and serr != null) {
        const src = std.mem.sliceTo(&serr2, 0);
        const n = @min(src.len, serr.?.len);
        @memcpy(serr.?[0..n], src[0..n]);
    }
    _ = &i;
    return iflag;
}

/// swecl.c swe_pheno_ut()
pub fn swe_pheno_ut(
    tjd_ut: f64,
    ipl: i32,
    iflag_in: i32,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var iflag = iflag_in;
    var epheflag = iflag & SEFLG_EPHMASK;
    if (epheflag == 0) {
        epheflag = SEFLG_SWIEPH;
        iflag |= SEFLG_SWIEPH;
    }
    // C's calc_deltat reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    const deltat_v = deltat_mod.swe_deltat_ex(dctx, tjd_ut, iflag);
    var retflag = swe_pheno(tjd_ut + deltat_v, ipl, iflag, attr, serr, swed, models, dctx);
    // if ephe required is not ephe returned, adjust delta t:
    if ((retflag & SEFLG_EPHMASK) != epheflag) {
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        const deltat2 = deltat_mod.swe_deltat_ex(dctx, tjd_ut, retflag);
        retflag = swe_pheno(tjd_ut + deltat2, ipl, iflag, attr, serr, swed, models, dctx);
    }
    return retflag;
}

// rise, set, and meridian transits  (swecl.c)

pub const SE_CALC_RISE: i32 = 1;
pub const SE_CALC_SET: i32 = 2;
pub const SE_CALC_MTRANSIT: i32 = 4;
pub const SE_CALC_ITRANSIT: i32 = 8;
pub const SE_BIT_GEOCTR_NO_ECL_LAT: i32 = 128;
pub const SE_BIT_DISC_CENTER: i32 = 256;
pub const SE_BIT_NO_REFRACTION: i32 = 512;
pub const SE_BIT_CIVIL_TWILIGHT: i32 = 1024;
pub const SE_BIT_NAUTIC_TWILIGHT: i32 = 2048;
pub const SE_BIT_ASTRO_TWILIGHT: i32 = 4096;
pub const SE_BIT_DISC_BOTTOM: i32 = 8192;
pub const SE_BIT_FIXED_DISC_SIZE: i32 = 16384;
pub const SE_BIT_FORCE_SLOW_METHOD: i32 = 32768;
pub const SE_BIT_HINDU_RISING: i32 = SE_BIT_DISC_CENTER | SE_BIT_NO_REFRACTION | SE_BIT_GEOCTR_NO_ECL_LAT;

const SEI_ECL_GEOALT_MIN: f64 = -500.0;
const SEI_ECL_GEOALT_MAX: f64 = 25000.0;

/// swecl.c find_maximum()
fn find_maximum(y00: f64, y11: f64, y2: f64, dx: f64, dxret: *f64, yret: ?*f64) i32 {
    const c = y11;
    const b = (y2 - y00) / 2.0;
    const a = (y2 + y00) / 2.0 - c;
    const x = -b / 2 / a;
    const y = (4 * a * c - b * b) / 4 / a;
    dxret.* = (x - 1) * dx;
    if (yret != null)
        yret.?.* = y;
    return lib.OK;
}

/// swecl.c find_zero()
fn find_zero(y00: f64, y11: f64, y2: f64, dx: f64, dxret: *f64, dxret2: *f64) i32 {
    const c = y11;
    const b = (y2 - y00) / 2.0;
    const a = (y2 + y00) / 2.0 - c;
    if (b * b - 4 * a * c < 0)
        return lib.ERR;
    const x1 = (-b + @sqrt(b * b - 4 * a * c)) / 2 / a;
    const x2 = (-b - @sqrt(b * b - 4 * a * c)) / 2 / a;
    dxret.* = (x1 - 1) * dx;
    dxret2.* = (x2 - 1) * dx;
    return lib.OK;
}

/// swecl.c rdi_twilight() — non-static in C.
pub fn rdi_twilight(rsmi: i32) f64 {
    var rdi: f64 = 0;
    if ((rsmi & SE_BIT_CIVIL_TWILIGHT) != 0)
        rdi = 6;
    if ((rsmi & SE_BIT_NAUTIC_TWILIGHT) != 0)
        rdi = 12;
    if ((rsmi & SE_BIT_ASTRO_TWILIGHT) != 0)
        rdi = 18;
    return rdi;
}

/// swecl.c get_sun_rad_plus_refr()
fn get_sun_rad_plus_refr(ipl: i32, dd_in: f64, rsmi: i32, refr: f64) f64 {
    var rdi: f64 = 0;
    var dd = dd_in;
    if ((rsmi & SE_BIT_FIXED_DISC_SIZE) != 0) {
        if (ipl == SE_SUN)
            dd = 1.0
        else if (ipl == SE_MOON)
            dd = 0.00257;
    }
    // apparent radius of disc
    if ((rsmi & SE_BIT_DISC_CENTER) == 0)
        rdi = swe_shim_asin(pla_diam[@intCast(ipl)] / 2.0 / AUNIT / dd) * RADTODEG;
    if ((rsmi & SE_BIT_DISC_BOTTOM) != 0)
        rdi = -rdi;
    if ((rsmi & SE_BIT_NO_REFRACTION) == 0) {
        rdi += refr; // (34.5 / 60.0);
    }
    return rdi;
}

/// swecl.c rise_set_fast() — simple fast algorithm for risings and settings;
/// C's `goto run_rise_again` retry becomes a while loop with the same
/// state mutations in the same order.
fn rise_set_fast(
    tjd_ut_in: f64,
    ipl: i32,
    epheflag: i32,
    rsmi: i32,
    dgeo: *const [3]f64,
    atpress_in: f64,
    attemp: f64,
    tret: *f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    ctx: *SweclCtx,
) i32 {
    var tjd_ut = tjd_ut_in;
    var xx: [6]f64 = undefined;
    var xaz: [6]f64 = undefined;
    var xaz2: [6]f64 = undefined;
    var dd: f64 = undefined;
    var dt: f64 = undefined;
    var refr: f64 = undefined;
    const iflag = epheflag & (SEFLG_JPLEPH | SEFLG_SWIEPH | SEFLG_MOSEPH);
    var iflagtopo = iflag | SEFLG_EQUATORIAL;
    var sda: f64 = undefined;
    var armc: f64 = undefined;
    var md: f64 = undefined;
    var dmd: f64 = undefined;
    var mdrise: f64 = undefined;
    var rdi: f64 = undefined;
    var tr: f64 = undefined;
    var dalt: f64 = undefined;
    var decl: f64 = undefined;
    const tjd_ut0 = tjd_ut;
    var facrise: i32 = 1;
    var tohor_flag: i32 = SE_EQU2HOR;
    var is_second_run = false;
    var nloop: i32 = 2;
    var atpress = atpress_in;
    tret.* = 0;
    if (ipl == SE_MOON)
        nloop = 4;
    if ((rsmi & SE_CALC_SET) != 0)
        facrise = -1;
    if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) == 0) {
        iflagtopo |= SEFLG_TOPOCTR;
        sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
    }
    while (true) { // run_rise_again:
        if (sweph.swe_calc_ut(tjd_ut, ipl, iflagtopo, &xx, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        // the diurnal arc is a bit fuzzy, ...
        decl = xx[1];
        // semi-diurnal arcs
        sda = -swe_shim_tan(dgeo[1] * DEGTORAD) * swe_shim_tan(decl * DEGTORAD);
        if (sda >= 1) {
            sda = 10; // actually sda = 0°, but we give it a value of 10°
        } else if (sda <= -1) {
            sda = 180;
        } else {
            sda = swe_shim_acos(sda) * RADTODEG;
        }
        // sidereal time at tjd_start
        armc = lib.swe_degnorm(lib.swe_sidtime(tjd_ut, models, dctx, nutInterp(swed)) * 15 + dgeo[0]);
        // meridian distance of object
        md = lib.swe_degnorm(xx[0] - armc);
        mdrise = lib.swe_degnorm(sda * @as(f64, @floatFromInt(facrise)));
        dmd = lib.swe_degnorm(md - mdrise);
        // Avoid the risk of getting the event of next day:
        if (dmd > 358) {
            dmd -= 360;
        }
        // rough subsequent rising/setting time
        tr = tjd_ut + dmd / 360;
        rdi = 0;
        // true altitude of sun, when it appears at the horizon;
        if (atpress == 0) {
            // estimate atmospheric pressure
            atpress = 1013.25 * swe_shim_pow(1 - 0.0065 * dgeo[2] / 288, 5.255);
        }
        _ = swe_refrac_extended(0.000001, 0, atpress, attemp, ctx.const_lapse_rate, SE_APP_TO_TRUE, xx[0..4]);
        refr = xx[1] - xx[0];
        if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0) {
            tohor_flag = SE_ECL2HOR;
            iflagtopo = iflag;
        } else {
            tohor_flag = SE_EQU2HOR; // this is more efficient
            iflagtopo = iflag | SEFLG_EQUATORIAL;
            iflagtopo |= SEFLG_TOPOCTR;
            sweph.swe_set_topo(dgeo[0], dgeo[1], dgeo[2], swed);
        }
        var iloop: i32 = 0;
        while (iloop < nloop) : (iloop += 1) {
            if (sweph.swe_calc_ut(tr, ipl, iflagtopo, &xx, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0)
                xx[1] = 0;
            rdi = get_sun_rad_plus_refr(ipl, xx[2], rsmi, refr);
            swe_azalt(tr, tohor_flag, dgeo, atpress, attemp, xx[0..3], xaz[0..3], swed, models, dctx, ctx);
            swe_azalt(tr + 0.001, tohor_flag, dgeo, atpress, attemp, xx[0..3], xaz2[0..3], swed, models, dctx, ctx);
            dd = (xaz2[1] - xaz[1]);
            dalt = xaz[1] + rdi;
            dt = dalt / dd / 1000.0;
            if (dt > 0.1) {
                dt = 0.1;
            } else if (dt < -0.1) {
                dt = -0.1;
            }
            tr -= dt;
        }
        // if the event found is before input time, we search next event.
        if (tr < tjd_ut0 and !is_second_run) {
            tjd_ut += 0.5;
            is_second_run = true;
            continue; // goto run_rise_again
        }
        break;
    }
    tret.* = tr;
    return lib.OK;
}

/// swecl.c swe_rise_trans()
pub fn swe_rise_trans(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[]u8,
    epheflag: i32,
    rsmi: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    tret: *f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    ctx: *SweclCtx,
) i32 {
    // Simple fast algorithm for risings and settings of
    // - planets Sun, Moon, Mercury - Pluto + Lunar Nodes
    const do_fixstar = starname != null and starname.?.len > 0 and starname.?[0] != 0;
    if (!do_fixstar and
        (rsmi & (SE_CALC_RISE | SE_CALC_SET)) != 0 and
        (rsmi & SE_BIT_FORCE_SLOW_METHOD) == 0 and
        (rsmi & (SE_BIT_CIVIL_TWILIGHT | SE_BIT_NAUTIC_TWILIGHT | SE_BIT_ASTRO_TWILIGHT)) == 0 and
        (ipl >= SE_SUN and ipl <= SE_TRUE_NODE) and
        (@abs(geopos[1]) <= 60 or (ipl == SE_SUN and @abs(geopos[1]) <= 65)))
    {
        return rise_set_fast(tjd_ut, ipl, epheflag, rsmi, geopos, atpress, attemp, tret, serr, swed, models, dctx, ctx);
    }
    return swe_rise_trans_true_hor(tjd_ut, ipl, starname, epheflag, rsmi, geopos, atpress, attemp, 0, tret, serr, swed, models, dctx, ctx);
}

/// swecl.c swe_rise_trans_true_hor() — same as swe_rise_trans() but with an
/// explicit horizon height (horhgt; -100 = dip of horizon).
pub fn swe_rise_trans_true_hor(
    tjd_ut: f64,
    ipl_in: i32,
    starname: ?[]u8,
    epheflag: i32,
    rsmi_in: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    horhgt_in: f64,
    tret: *f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    ctx: *SweclCtx,
) i32 {
    var ipl = ipl_in;
    var rsmi = rsmi_in;
    var horhgt = horhgt_in;
    var nculm: i32 = -1;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    const tjd_et = tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, epheflag);
    var xc: [6]f64 = undefined;
    var xh: [20][6]f64 = undefined;
    var ah: [6]f64 = undefined;
    var aha: f64 = undefined;
    var tculm: [4]f64 = undefined;
    var tcu: f64 = undefined;
    var tc: [20]f64 = undefined;
    var h: [20]f64 = undefined;
    var t2: [6]f64 = undefined;
    var dc: [6]f64 = undefined;
    var dtint: f64 = undefined;
    var dx: f64 = undefined;
    var rdi: f64 = undefined;
    var dd: f64 = 0;
    var iflag = epheflag;
    var jmax: i32 = 14;
    var t: f64 = undefined;
    var te: f64 = undefined;
    var tt: f64 = undefined;
    var dt: f64 = undefined;
    const twohrs: f64 = 1.0 / 12.0;
    var curdist: f64 = undefined;
    var tohor_flag: i32 = SE_EQU2HOR;
    const do_fixstar = starname != null and starname.?.len > 0 and starname.?[0] != 0;
    if (geopos[2] < SEI_ECL_GEOALT_MIN or geopos[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for swe_rise_trans() must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    // if horhgt == -100, set horhgt = dip of horizon, i.e. refracted height
    // of ocean if visible at horizon.
    if (horhgt == -100) {
        horhgt = 0.0001 + calc_dip(geopos[2], atpress, attemp, ctx.const_lapse_rate);
    }
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    xh[0][0] = 0; // to shut up mint
    // allowing SEFLG_NONUT and SEFLG_TRUEPOS speeds it up
    iflag &= (SEFLG_EPHMASK | SEFLG_NONUT | SEFLG_TRUEPOS);
    tret.* = 0;
    if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0) {
        tohor_flag = SE_ECL2HOR;
    } else {
        tohor_flag = SE_EQU2HOR;
        iflag |= SEFLG_EQUATORIAL;
        iflag |= SEFLG_TOPOCTR;
        sweph.swe_set_topo(geopos[0], geopos[1], geopos[2], swed);
    }
    if ((rsmi & (SE_CALC_MTRANSIT | SE_CALC_ITRANSIT)) != 0)
        return calc_mer_trans(tjd_ut, ipl, epheflag, rsmi, geopos, starname, tret, serr, swed, models, dctx);
    if ((rsmi & (SE_CALC_RISE | SE_CALC_SET)) == 0)
        rsmi |= SE_CALC_RISE;
    // twilight calculation
    if (ipl == SE_SUN and (rsmi & (SE_BIT_CIVIL_TWILIGHT | SE_BIT_NAUTIC_TWILIGHT | SE_BIT_ASTRO_TWILIGHT)) != 0) {
        rsmi |= (SE_BIT_NO_REFRACTION | SE_BIT_DISC_CENTER);
        horhgt = -rdi_twilight(rsmi);
        // note: twilight is not dependent on height of horizon, so we can
        // use this parameter and define a fictitious height of horizon
    }
    // find culmination points within 28 hours from t0 - twohrs.
    if (do_fixstar) {
        if (sweph.swe_fixstar(starname.?, tjd_et, iflag, &xc, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    }
    var ii: i32 = 0;
    t = tjd_ut - twohrs;
    while (ii <= jmax) : ({
        ii += 1;
        t += twohrs;
    }) {
        const iu: usize = @intCast(ii);
        tc[iu] = t;
        if (!do_fixstar) {
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            te = t + deltat_mod.swe_deltat_ex(dctx, t, epheflag);
            if (sweph.swe_calc(te, ipl, iflag, &xc, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
        }
        if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0)
            xc[1] = 0;
        // diameter of object in km
        if (ii == 0) {
            if (do_fixstar)
                dd = 0
            else if ((rsmi & SE_BIT_DISC_CENTER) != 0)
                dd = 0
            else if (ipl < @as(i32, @intCast(NDIAM)))
                dd = pla_diam[@intCast(ipl)]
            else if (ipl > SE_AST_OFFSET)
                dd = swed.ast_diam * 1000 // km -> m
            else
                dd = 0;
        }
        curdist = xc[2];
        if ((rsmi & SE_BIT_FIXED_DISC_SIZE) != 0) {
            if (ipl == SE_SUN) {
                curdist = 1.0;
            } else if (ipl == SE_MOON) {
                curdist = 0.00257;
            }
        }
        // apparent radius of disc
        rdi = swe_shim_asin(dd / 2 / AUNIT / curdist) * RADTODEG;
        // true height of center of body
        swe_azalt(t, tohor_flag, geopos, atpress, attemp, xc[0..3], xh[iu][0..3], swed, models, dctx, ctx);
        if ((rsmi & SE_BIT_DISC_BOTTOM) != 0) {
            // true height of bottom point of body
            xh[iu][1] -= rdi;
        } else {
            // true height of uppermost point of body
            xh[iu][1] += rdi;
        }
        // apparent height of uppermost point of body
        if ((rsmi & SE_BIT_NO_REFRACTION) != 0) {
            xh[iu][1] -= horhgt;
            h[iu] = xh[iu][1];
        } else {
            swe_azalt_rev(t, SE_HOR2EQU, geopos, xh[iu][0..3], xc[0..2], swed, models, dctx);
            swe_azalt(t, SE_EQU2HOR, geopos, atpress, attemp, xc[0..3], xh[iu][0..3], swed, models, dctx, ctx);
            xh[iu][1] -= horhgt;
            xh[iu][2] -= horhgt;
            h[iu] = xh[iu][2];
        }
        var calc_culm: i32 = 0;
        if (ii > 1) {
            dc[0] = xh[iu - 2][1];
            dc[1] = xh[iu - 1][1];
            dc[2] = xh[iu][1];
            if (dc[1] > dc[0] and dc[1] > dc[2])
                calc_culm = 1;
            if (dc[1] < dc[0] and dc[1] < dc[2])
                calc_culm = 2;
        }
        if (calc_culm != 0) {
            dt = twohrs;
            tcu = t - dt;
            const rfm = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dx);
            _ = rfm;
            tcu += dtint + dt;
            dt /= 3;
            while (dt > 0.0001) : (dt /= 3) {
                var iculm: usize = 0;
                tt = tcu - dt;
                while (iculm < 3) : ({
                    tt += dt;
                    iculm += 1;
                }) {
                    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                    dctx.jpldenum = swed.jpldenum;
                    te = tt + deltat_mod.swe_deltat_ex(dctx, tt, epheflag);
                    if (!do_fixstar) {
                        if (sweph.swe_calc(te, ipl, iflag, &xc, swed, models, dctx, serr) == lib.ERR)
                            return lib.ERR;
                    }
                    if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0)
                        xc[1] = 0;
                    swe_azalt(tt, tohor_flag, geopos, atpress, attemp, xc[0..3], ah[0..3], swed, models, dctx, ctx);
                    ah[1] -= horhgt;
                    dc[iculm] = ah[1];
                }
                const rfm2 = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dx);
                _ = rfm2;
                tcu += dtint + dt;
            }
            nculm += 1;
            tculm[@intCast(nculm)] = tcu;
        }
    }
    // note: there can be a rise or set on the poles, even if
    // there is no culmination. So, we must not leave here
    // in any case.
    // insert culminations into array of heights
    {
        var i: i32 = 0;
        while (i <= nculm) : (i += 1) {
            var j: i32 = 1;
            while (j <= jmax) : (j += 1) {
                if (tculm[@intCast(i)] < tc[@intCast(j)]) {
                    var k: i32 = jmax;
                    while (k >= j) : (k -= 1) {
                        tc[@intCast(k + 1)] = tc[@intCast(k)];
                        h[@intCast(k + 1)] = h[@intCast(k)];
                    }
                    tc[@intCast(j)] = tculm[@intCast(i)];
                    if (!do_fixstar) {
                        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                        dctx.jpldenum = swed.jpldenum;
                        te = tc[@intCast(j)] + deltat_mod.swe_deltat_ex(dctx, tc[@intCast(j)], epheflag);
                        if (sweph.swe_calc(te, ipl, iflag, &xc, swed, models, dctx, serr) == lib.ERR)
                            return lib.ERR;
                        if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0)
                            xc[1] = 0;
                    }
                    curdist = xc[2];
                    if ((rsmi & SE_BIT_FIXED_DISC_SIZE) != 0) {
                        if (ipl == SE_SUN) {
                            curdist = 1.0;
                        } else if (ipl == SE_MOON) {
                            curdist = 0.00257;
                        }
                    }
                    // apparent radius of disc
                    rdi = swe_shim_asin(dd / 2 / AUNIT / curdist) * RADTODEG;
                    // true height of center of body
                    swe_azalt(tc[@intCast(j)], tohor_flag, geopos, atpress, attemp, xc[0..3], ah[0..3], swed, models, dctx, ctx);
                    if ((rsmi & SE_BIT_DISC_BOTTOM) != 0) {
                        // true height of bottom point of body
                        ah[1] -= rdi;
                    } else {
                        // true height of uppermost point of body
                        ah[1] += rdi;
                    }
                    // apparent height of uppermost point of body
                    if ((rsmi & SE_BIT_NO_REFRACTION) != 0) {
                        ah[1] -= horhgt;
                        h[@intCast(j)] = ah[1];
                    } else {
                        swe_azalt_rev(tc[@intCast(j)], SE_HOR2EQU, geopos, ah[0..3], xc[0..2], swed, models, dctx);
                        swe_azalt(tc[@intCast(j)], SE_EQU2HOR, geopos, atpress, attemp, xc[0..3], ah[0..3], swed, models, dctx, ctx);
                        ah[1] -= horhgt;
                        ah[2] -= horhgt;
                        h[@intCast(j)] = ah[2];
                    }
                    jmax += 1;
                    break;
                }
            }
        }
    }
    tret.* = 0;
    // find points with zero height.
    // binary search
    ii = 1;
    while (ii <= jmax) : (ii += 1) {
        const iu: usize = @intCast(ii);
        if (h[iu - 1] * h[iu] >= 0)
            continue;
        if (h[iu - 1] < h[iu] and (rsmi & SE_CALC_RISE) == 0)
            continue;
        if (h[iu - 1] > h[iu] and (rsmi & SE_CALC_SET) == 0)
            continue;
        dc[0] = h[iu - 1];
        dc[1] = h[iu];
        t2[0] = tc[iu - 1];
        t2[1] = tc[iu];
        var ibin: usize = 0;
        while (ibin < 20) : (ibin += 1) {
            t = (t2[0] + t2[1]) / 2;
            if (!do_fixstar) {
                dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                dctx.jpldenum = swed.jpldenum;
                te = t + deltat_mod.swe_deltat_ex(dctx, t, epheflag);
                if (sweph.swe_calc(te, ipl, iflag, &xc, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if ((rsmi & SE_BIT_GEOCTR_NO_ECL_LAT) != 0)
                    xc[1] = 0;
            }
            curdist = xc[2];
            if ((rsmi & SE_BIT_FIXED_DISC_SIZE) != 0) {
                if (ipl == SE_SUN) {
                    curdist = 1.0;
                } else if (ipl == SE_MOON) {
                    curdist = 0.00257;
                }
            }
            // apparent radius of disc
            rdi = swe_shim_asin(dd / 2 / AUNIT / curdist) * RADTODEG;
            // true height of center of body
            swe_azalt(t, tohor_flag, geopos, atpress, attemp, xc[0..3], ah[0..3], swed, models, dctx, ctx);
            if ((rsmi & SE_BIT_DISC_BOTTOM) != 0) {
                // true height of bottom point of body
                ah[1] -= rdi;
            } else {
                // true height of uppermost point of body
                ah[1] += rdi;
            }
            // apparent height of uppermost point of body
            if ((rsmi & SE_BIT_NO_REFRACTION) != 0) {
                ah[1] -= horhgt;
                aha = ah[1];
            } else {
                swe_azalt_rev(t, SE_HOR2EQU, geopos, ah[0..3], xc[0..2], swed, models, dctx);
                swe_azalt(t, SE_EQU2HOR, geopos, atpress, attemp, xc[0..3], ah[0..3], swed, models, dctx, ctx);
                ah[1] -= horhgt;
                ah[2] -= horhgt;
                aha = ah[2];
            }
            if (aha * dc[0] <= 0) {
                dc[1] = aha;
                t2[1] = t;
            } else {
                dc[0] = aha;
                t2[0] = t;
            }
        }
        if (t > tjd_ut) {
            tret.* = t;
            return lib.OK;
        }
    }
    if (serr != null) {
        const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "rise or set not found for planet {d}", .{ipl}) catch "";
        if (r.len < serr.?.len) serr.?[r.len] = 0;
    }
    return -2; // no t of rise or set found
}

/// swecl.c calc_mer_trans() — meridian transits
fn calc_mer_trans(
    tjd_ut: f64,
    ipl: i32,
    epheflag: i32,
    rsmi: i32,
    geopos: *const [3]f64,
    starname: ?[]u8,
    tret: *f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var x0: [6]f64 = undefined;
    var x: [6]f64 = undefined;
    var armc: f64 = undefined;
    var arxc: f64 = undefined;
    const do_fixstar = starname != null and starname.?.len > 0 and starname.?[0] != 0;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    const tjd_et = tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, epheflag);
    var iflag = epheflag;
    tret.* = 0;
    iflag &= SEFLG_EPHMASK;
    iflag |= (SEFLG_EQUATORIAL | SEFLG_TOPOCTR);
    var armc0 = lib.swe_sidtime(tjd_ut, models, dctx, nutInterp(swed)) + geopos[0] / 15;
    if (armc0 >= 24)
        armc0 -= 24;
    if (armc0 < 0)
        armc0 += 24;
    armc0 *= 15;
    if (do_fixstar) {
        if (sweph.swe_fixstar(starname.?, tjd_et, iflag, &x0, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    } else {
        if (sweph.swe_calc(tjd_et, ipl, iflag, &x0, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    }
    // meridian transits
    x[0] = x0[0];
    x[1] = x0[1];
    var t = tjd_ut;
    arxc = armc0;
    if ((rsmi & SE_CALC_ITRANSIT) != 0)
        arxc = lib.swe_degnorm(arxc + 180);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        var mdd = lib.swe_degnorm(x[0] - arxc);
        if (i > 0 and mdd > 180)
            mdd -= 360;
        t += mdd / 361;
        armc = lib.swe_sidtime(t, models, dctx, nutInterp(swed)) + geopos[0] / 15;
        if (armc >= 24)
            armc -= 24;
        if (armc < 0)
            armc += 24;
        armc *= 15;
        arxc = armc;
        if ((rsmi & SE_CALC_ITRANSIT) != 0)
            arxc = lib.swe_degnorm(arxc + 180);
        if (!do_fixstar) {
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            const te = t + deltat_mod.swe_deltat_ex(dctx, t, epheflag);
            if (sweph.swe_calc(te, ipl, iflag, &x, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
        }
    }
    tret.* = t;
    return lib.OK;
}

// nodes, apsides, orbital elements, gauquelin sector  (swecl.c)

pub const SE_NODBIT_MEAN: i32 = 1;
pub const SE_NODBIT_OSCU: i32 = 2;
pub const SE_NODBIT_OSCU_BAR: i32 = 4;
pub const SE_NODBIT_FOPOINT: i32 = 256;
pub const SEFLG_ORBEL_AA: i32 = SEFLG_TOPOCTR; // used for AA mode in orb. elements

const MOON_MEAN_DIST: f64 = 384400000.0; // in m, AA 1996, F2
const MOON_MEAN_INCL: f64 = 5.1453964; // AA 1996, D2
const MOON_MEAN_ECC: f64 = 0.054900489; // AA 1996, F2
const EARTH_MOON_MRAT: f64 = @as(f64, 1.0) / @as(f64, 0.0123000383); // AA 2006, K7
const HELGRAVCONST: f64 = 1.32712440017987e+20; // G*M(sun), m^3/sec^2, AA 2006 K6
const GEOGCONST: f64 = 3.98600448e+14; // G*M(earth), m^3/sec^2, AA 1996 K6
const NODE_CALC_INTV: f64 = 0.0001;
const NODE_CALC_INTV_MOSH: f64 = 0.1; // (sweph.h)

// swecl.c el_node/el_peri/el_incl/el_ecce/el_sema tables (transcribed 1:1)
const el_node = [8][4]f64{
    .{ 48.330893, 1.1861890, 0.00017587, 0.000000211 }, // Mercury
    .{ 76.679920, 0.9011190, 0.00040665, -0.000000080 }, // Venus
    .{ 0, 0, 0, 0 }, // Earth
    .{ 49.558093, 0.7720923, 0.00001605, 0.000002325 }, // Mars
    .{ 100.464441, 1.0209550, 0.00040117, 0.000000569 }, // Jupiter
    .{ 113.665524, 0.8770970, -0.00012067, -0.000002380 }, // Saturn
    .{ 74.005947, 0.5211258, 0.00133982, 0.000018516 }, // Uranus
    .{ 131.784057, 1.1022057, 0.00026006, -0.000000636 }, // Neptune
};
const el_peri = [8][4]f64{
    .{ 77.456119, 1.5564775, 0.00029589, 0.000000056 }, // Mercury
    .{ 131.563707, 1.4022188, -0.00107337, -0.000005315 }, // Venus
    .{ 102.937348, 1.7195269, 0.00045962, 0.000000499 }, // Earth
    .{ 336.060234, 1.8410331, 0.00013515, 0.000000318 }, // Mars
    .{ 14.331309, 1.6126668, 0.00103127, -0.000004569 }, // Jupiter
    .{ 93.056787, 1.9637694, 0.00083757, 0.000004899 }, // Saturn
    .{ 173.005159, 1.4863784, 0.00021450, 0.000000433 }, // Uranus
    .{ 48.123691, 1.4262677, 0.00037918, -0.000000003 }, // Neptune
};
const el_incl = [8][4]f64{
    .{ 7.004986, 0.0018215, -0.00001809, 0.000000053 }, // Mercury
    .{ 3.394662, 0.0010037, -0.00000088, -0.000000007 }, // Venus
    .{ 0, 0, 0, 0 }, // Earth
    .{ 1.849726, -0.0006010, 0.00001276, -0.000000006 }, // Mars
    .{ 1.303270, -0.0054966, 0.00000465, -0.000000004 }, // Jupiter
    .{ 2.488878, -0.0037363, -0.00001516, 0.000000089 }, // Saturn
    .{ 0.773196, 0.0007744, 0.00003749, -0.000000092 }, // Uranus
    .{ 1.769952, -0.0093082, -0.00000708, 0.000000028 }, // Neptune
};
const el_ecce = [8][4]f64{
    .{ 0.20563175, 0.000020406, -0.0000000284, -0.00000000017 }, // Mercury
    .{ 0.00677188, -0.000047766, 0.0000000975, 0.00000000044 }, // Venus
    .{ 0.01670862, -0.000042037, -0.0000001236, 0.00000000004 }, // Earth
    .{ 0.09340062, 0.000090483, -0.0000000806, -0.00000000035 }, // Mars
    .{ 0.04849485, 0.000163244, -0.0000004719, -0.00000000197 }, // Jupiter
    .{ 0.05550862, -0.000346818, -0.0000006456, 0.00000000338 }, // Saturn
    .{ 0.04629590, -0.000027337, 0.0000000790, 0.00000000025 }, // Uranus
    .{ 0.00898809, 0.000006408, -0.0000000008, -0.00000000005 }, // Neptune
};
const el_sema = [8][4]f64{
    .{ 0.387098310, 0.0, 0.0, 0.0 }, // Mercury
    .{ 0.723329820, 0.0, 0.0, 0.0 }, // Venus
    .{ 1.000001018, 0.0, 0.0, 0.0 }, // Earth
    .{ 1.523679342, 0.0, 0.0, 0.0 }, // Mars
    .{ 5.202603191, 0.0000001913, 0.0, 0.0 }, // Jupiter
    .{ 9.554909596, 0.0000021389, 0.0, 0.0 }, // Saturn
    .{ 19.218446062, -0.0000000372, 0.00000000098, 0.0 }, // Uranus
    .{ 30.110386869, -0.0000001663, 0.00000000069, 0.0 }, // Neptune
};
// Ratios of mass of Sun to masses of the planets
const plmass = [9]f64{
    6023600, // Mercury
    408523.719, // Venus
    328900.5, // Earth and Moon
    3098703.59, // Mars
    1047.348644, // Jupiter
    3497.9018, // Saturn
    22902.98, // Uranus
    19412.26, // Neptune
    136566000, // Pluto
};
const ipl_to_elem = [15]i32{ 2, 0, 0, 1, 3, 4, 5, 6, 7, 0, 0, 0, 0, 0, 2 };

// planet numbers used here (duplicated from swecl.zig's SE_* block)
const SE_INTP_APOG: i32 = 21;
const SE_INTP_PERG: i32 = 22;
const SE_NPLANETS_EXP: i32 = 23; // swephexp.h SE_NPLANETS

/// swecl.c swe_nod_aps() — mean and true nodes/apsides.
/// xnasc/xndsc/xperi/xaphe: optional arrays of 6 doubles each.
pub fn swe_nod_aps(
    tjd_et: f64,
    ipl_in: i32,
    iflag_in: i32,
    method_in: i32,
    xnasc: ?*[6]f64,
    xndsc: ?*[6]f64,
    xperi: ?*[6]f64,
    xaphe: ?*[6]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var ipl = ipl_in;
    var iflag = iflag_in;
    var method = method_in;
    var i: usize = undefined;
    var ij: usize = undefined;
    var iplx: usize = undefined;
    var ipli: usize = undefined;
    var istart: i32 = undefined;
    var iend: i32 = undefined;
    var iflJ2000: i32 = undefined;
    var daya: f64 = undefined;
    var plm: f64 = undefined;
    var t: f64 = (tjd_et - lib.J2000) / 36525;
    var dt: f64 = undefined;
    var x: [6]f64 = undefined;
    var xx: [24]f64 = undefined;
    var xobs: [6]f64 = undefined;
    var x2000: [6]f64 = undefined;
    var xpos: [3][6]f64 = undefined;
    var xnorm: [6]f64 = undefined;
    var xposm: [6]f64 = undefined;
    var xn: [3][6]f64 = undefined;
    var xs: [3][6]f64 = undefined;
    var xq: [3][6]f64 = undefined;
    var xa: [3][6]f64 = undefined;
    var xobs2: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var xp: []f64 = undefined;
    var incl: f64 = undefined;
    var sema: f64 = undefined;
    var ecce: f64 = undefined;
    var parg: f64 = undefined;
    var ea: f64 = undefined;
    var vincl: f64 = undefined;
    var vsema: f64 = undefined;
    var vecce: f64 = undefined;
    var pargx: f64 = undefined;
    var eax: f64 = undefined;
    var Gmsm: f64 = undefined;
    var dzmin: f64 = undefined;
    var rxy: f64 = undefined;
    var rxyz: f64 = undefined;
    var fac: f64 = undefined;
    var sgn: f64 = undefined;
    var sinnode: f64 = undefined;
    var cosnode: f64 = undefined;
    var sinincl: f64 = undefined;
    var cosincl: f64 = undefined;
    var sinu: f64 = undefined;
    var cosu: f64 = undefined;
    var sinE: f64 = undefined;
    var cosE: f64 = undefined;
    var cosE2: f64 = undefined;
    var uu: f64 = undefined;
    var ny: f64 = undefined;
    var ny2: f64 = undefined;
    var c2: f64 = undefined;
    var v2: f64 = undefined;
    var pp: f64 = undefined;
    var ro: f64 = undefined;
    var ro2: f64 = undefined;
    var rn: f64 = undefined;
    var rn2: f64 = undefined;
    var oe: *const lib.Eps = undefined;
    var is_true_nodaps = false;
    var do_aberr = (iflag & (sweph.SEFLG_TRUEPOS | sweph.SEFLG_NOABERR)) == 0;
    var do_defl = (iflag & sweph.SEFLG_TRUEPOS) == 0 and (iflag & sweph.SEFLG_NOGDEFL) == 0;
    const do_focal_point = (method & SE_NODBIT_FOPOINT) != 0;
    var ellipse_is_bary = false;
    var iflg0: i32 = undefined;
    iflag &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    // xna = xx; xnd = xx+6; xpe = xx+12; xap = xx+18 (slices below)
    xpos[0][0] = 0; // to shut up mint
    // to get control over the save area:
    sweph.forceAppPos(swed);
    method = @rem(method, SE_NODBIT_FOPOINT);
    // (C computes ipli = ipl here — int32, negative allowed; the
    // not-implemented guard below uses ipl, and ipli is only dereferenced
    // after the guard passed, so the port assigns ipli after the guard.)
    if (ipl == SE_MOON) {
        do_defl = false;
        if ((iflag & sweph.SEFLG_HELCTR) == 0)
            do_aberr = false;
    }
    iflg0 = (iflag & (SEFLG_EPHMASK | sweph.SEFLG_NONUT)) | sweph.SEFLG_SPEED | sweph.SEFLG_TRUEPOS;
    // C: if (ipli != SE_MOON) — ipli == ipl here (remap below can't make
    // it SE_MOON), and ipl is signed where ipli (usize) is not yet set.
    if (ipl != SE_MOON) {
        iflg0 |= sweph.SEFLG_HELCTR;
    }
    if (ipl == SE_MEAN_NODE or ipl == SE_TRUE_NODE or
        ipl == SE_MEAN_APOG or ipl == SE_OSCU_APOG or
        ipl < 0 or
        (ipl >= SE_NPLANETS_EXP and ipl <= SE_AST_OFFSET))
    {
        // C: ipl >= SE_NPLANETS (swephexp.h: 23) && ipl <= SE_AST_OFFSET
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "nodes/apsides for planet {d:5.0} are not implemented", .{@as(f64, @floatFromInt(ipl))}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        if (xnasc != null) {
            for (0..6) |k| xnasc.?[k] = 0;
        }
        if (xndsc != null) {
            for (0..6) |k| xndsc.?[k] = 0;
        }
        if (xaphe != null) {
            for (0..6) |k| xaphe.?[k] = 0;
        }
        if (xperi != null) {
            for (0..6) |k| xperi.?[k] = 0;
        }
        return lib.ERR;
    }
    ipli = @intCast(ipl);
    if (ipl == SE_SUN)
        ipli = @intCast(SE_EARTH);
    for (0..24) |k| xx[k] = 0;
    const xna = xx[0..6];
    const xnd = xx[6..12];
    const xpe = xx[12..18];
    const xap = xx[18..24];
    // mean nodes and apsides
    // mean points only for Sun - Neptune
    if ((method == 0 or (method & SE_NODBIT_MEAN) != 0) and
        ((ipl >= SE_SUN and ipl <= SE_NEPTUNE) or ipl == SE_EARTH))
    {
        if (ipl == SE_MOON) {
            var mnode: f64 = undefined;
            var mdnode: f64 = undefined;
            var mperi: f64 = undefined;
            var mdperi: f64 = undefined;
            swemmoon_mod.swi_mean_lunar_elements(tjd_et, &mnode, &mdnode, &mperi, &mdperi, &swed.moon_ws);
            xna[0] = mnode;
            xna[3] = mdnode;
            xpe[0] = mperi;
            xpe[3] = mdperi;
            incl = MOON_MEAN_INCL;
            vincl = 0;
            ecce = MOON_MEAN_ECC;
            vecce = 0;
            sema = MOON_MEAN_DIST / AUNIT;
            vsema = 0;
        } else {
            iplx = @intCast(ipl_to_elem[@intCast(ipl)]);
            var ep: *const [4]f64 = &el_incl[iplx];
            incl = ep[0] + ep[1] * t + ep[2] * t * t + ep[3] * t * t * t;
            vincl = ep[1] / 36525;
            ep = &el_sema[iplx];
            sema = ep[0] + ep[1] * t + ep[2] * t * t + ep[3] * t * t * t;
            vsema = ep[1] / 36525;
            ep = &el_ecce[iplx];
            ecce = ep[0] + ep[1] * t + ep[2] * t * t + ep[3] * t * t * t;
            vecce = ep[1] / 36525;
            ep = &el_node[iplx];
            // ascending node
            xna[0] = ep[0] + ep[1] * t + ep[2] * t * t + ep[3] * t * t * t;
            xna[3] = ep[1] / 36525;
            // perihelion
            ep = &el_peri[iplx];
            xpe[0] = ep[0] + ep[1] * t + ep[2] * t * t + ep[3] * t * t * t;
            xpe[3] = ep[1] / 36525;
        }
        // descending node
        xnd[0] = lib.swe_degnorm(xna[0] + 180);
        xnd[3] = xna[3];
        // angular distance of perihelion from node
        // C: parg = xpe[0] = swe_degnorm(xpe[0] - xna[0]);
        xpe[0] = lib.swe_degnorm(xpe[0] - xna[0]);
        parg = xpe[0];
        // C: pargx = xpe[3] = swe_degnorm(xpe[0] + xpe[3] - xna[3]); (new xpe[0])
        xpe[3] = lib.swe_degnorm(xpe[0] + xpe[3] - xna[3]);
        pargx = xpe[3];
        // transform from orbital plane to mean ecliptic of date
        houses.swe_cotrans(xpe[0..3], xpe[0..3], -incl);
        // xpe+3 is aux. position, not speed!!!
        houses.swe_cotrans(xpe[3..6], xpe[3..6], -incl - vincl);
        // add node again
        xpe[0] = lib.swe_degnorm(xpe[0] + xna[0]);
        // xpe+3 is aux. position, not speed!!!
        xpe[3] = lib.swe_degnorm(xpe[3] + xna[0] + xna[3]);
        // speed
        xpe[3] = lib.swe_degnorm(xpe[3] - xpe[0]);
        // heliocentric distance of perihelion and aphelion
        xpe[2] = sema * (1 - ecce);
        xpe[5] = (sema + vsema) * (1 - ecce - vecce) - xpe[2];
        // aphelion
        xap[0] = lib.swe_degnorm(xpe[0] + 180);
        xap[1] = -xpe[1];
        xap[3] = xpe[3];
        xap[4] = -xpe[4];
        if (do_focal_point) {
            xap[2] = sema * ecce * 2;
            xap[5] = (sema + vsema) * (ecce + vecce) * 2 - xap[2];
        } else {
            xap[2] = sema * (1 + ecce);
            xap[5] = (sema + vsema) * (1 + ecce + vecce) - xap[2];
        }
        // heliocentric distance of nodes
        ea = swe_shim_atan(swe_shim_tan(-parg * DEGTORAD / 2) * @sqrt((1 - ecce) / (1 + ecce))) * 2;
        eax = swe_shim_atan(swe_shim_tan(-pargx * DEGTORAD / 2) * @sqrt((1 - ecce - vecce) / (1 + ecce + vecce))) * 2;
        xna[2] = sema * (swe_shim_cos(ea) - ecce) / swe_shim_cos(parg * DEGTORAD);
        xna[5] = (sema + vsema) * (swe_shim_cos(eax) - ecce - vecce) / swe_shim_cos(pargx * DEGTORAD);
        xna[5] -= xna[2];
        ea = swe_shim_atan(swe_shim_tan((180 - parg) * DEGTORAD / 2) * @sqrt((1 - ecce) / (1 + ecce))) * 2;
        eax = swe_shim_atan(swe_shim_tan((180 - pargx) * DEGTORAD / 2) * @sqrt((1 - ecce - vecce) / (1 + ecce + vecce))) * 2;
        xnd[2] = sema * (swe_shim_cos(ea) - ecce) / swe_shim_cos((180 - parg) * DEGTORAD);
        xnd[5] = (sema + vsema) * (swe_shim_cos(eax) - ecce - vecce) / swe_shim_cos((180 - pargx) * DEGTORAD);
        xnd[5] -= xnd[2];
        // no light-time correction because speed is extremely small
        i = 0;
        xp = xx[0..];
        while (i < 4) : ({
            i += 1;
            xp = xp[6..];
        }) {
            // to cartesian coordinates
            xp[0] *= DEGTORAD;
            xp[1] *= DEGTORAD;
            xp[3] *= DEGTORAD;
            xp[4] *= DEGTORAD;
            lib.swi_polcart_sp(xp[0..6], xp[0..6]);
        }
        // "true" or osculating nodes and apsides
    } else {
        // first, we need a heliocentric distance of the planet
        if (sweph.swe_calc(tjd_et, @intCast(ipli), iflg0, &x, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        iflJ2000 = (iflag & SEFLG_EPHMASK) | sweph.SEFLG_J2000 | sweph.SEFLG_EQUATORIAL | sweph.SEFLG_XYZ | sweph.SEFLG_TRUEPOS | sweph.SEFLG_NONUT | sweph.SEFLG_SPEED;
        ellipse_is_bary = false;
        if (ipli != @as(usize, @intCast(SE_MOON))) {
            if ((method & SE_NODBIT_OSCU_BAR) != 0 and x[2] > 6) {
                iflJ2000 |= sweph.SEFLG_BARYCTR; // only planets beyond Jupiter
                ellipse_is_bary = true;
            } else {
                iflJ2000 |= sweph.SEFLG_HELCTR;
            }
        }
        // we need three positions and three speeds
        // for three nodes/apsides. from the three node positions,
        // the speed of the node will be computed.
        if (ipli == @as(usize, @intCast(SE_MOON))) {
            dt = NODE_CALC_INTV;
            dzmin = 1e-15;
            Gmsm = GEOGCONST * (1 + 1 / EARTH_MOON_MRAT) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
        } else {
            if ((ipli >= @as(usize, @intCast(SE_MERCURY)) and ipli <= @as(usize, @intCast(SE_PLUTO))) or ipli == @as(usize, @intCast(SE_EARTH)))
                plm = 1 / plmass[@intCast(ipl_to_elem[ipli])]
            else
                plm = 0;
            dt = NODE_CALC_INTV * 10 * x[2];
            dzmin = 1e-15 * dt / NODE_CALC_INTV;
            Gmsm = HELGRAVCONST * (1 + plm) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
        }
        if ((iflag & sweph.SEFLG_SPEED) != 0) {
            istart = 0;
            iend = 2;
        } else {
            istart = 0;
            iend = 0;
            dt = 0;
        }
        i = @intCast(istart);
        t = tjd_et - dt;
        while (i <= @as(usize, @intCast(iend))) : ({
            i += 1;
            t += dt;
        }) {
            if (istart == iend)
                t = tjd_et;
            if (sweph.swe_calc(t, @intCast(ipli), iflJ2000, &xpos[i], swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            // the EMB is used instead of the earth
            if (ipli == @as(usize, @intCast(SE_EARTH))) {
                if (sweph.swe_calc(t, SE_MOON, iflJ2000 & ~(sweph.SEFLG_BARYCTR | sweph.SEFLG_HELCTR), &xposm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                for (0..6) |k|
                    xpos[i][k] += xposm[k] / (EARTH_MOON_MRAT + 1.0);
            }
            sweph.swi_plan_for_osc_elem(iflg0, t, &xpos[i], swed, models);
        }
        i = @intCast(istart);
        while (i <= @as(usize, @intCast(iend))) : (i += 1) {
            if (@abs(xpos[i][5]) < dzmin)
                xpos[i][5] = dzmin;
            fac = xpos[i][2] / xpos[i][5];
            sgn = xpos[i][5] / @abs(xpos[i][5]);
            for (0..3) |k| {
                xn[i][k] = (xpos[i][k] - fac * xpos[i][k + 3]) * sgn;
                xs[i][k] = -xn[i][k];
            }
        }
        i = @intCast(istart);
        while (i <= @as(usize, @intCast(iend))) : (i += 1) {
            // node
            rxy = @sqrt(xn[i][0] * xn[i][0] + xn[i][1] * xn[i][1]);
            cosnode = xn[i][0] / rxy;
            sinnode = xn[i][1] / rxy;
            // inclination
            lib.swi_cross_prod_slice(xpos[i][0..3], xpos[i][3..6], xnorm[0..3]);
            rxy = xnorm[0] * xnorm[0] + xnorm[1] * xnorm[1];
            c2 = (rxy + xnorm[2] * xnorm[2]);
            rxyz = @sqrt(c2);
            rxy = @sqrt(rxy);
            sinincl = rxy / rxyz;
            cosincl = @sqrt(1 - sinincl * sinincl);
            if (xnorm[2] < 0) cosincl = -cosincl; // retrograde asteroid
            // argument of latitude
            cosu = xpos[i][0] * cosnode + xpos[i][1] * sinnode;
            sinu = xpos[i][2] / sinincl;
            uu = swe_shim_atan2(sinu, cosu);
            // semi-axis
            rxyz = @sqrt(sweph.square_sum(&xpos[i]));
            v2 = sweph.square_sum(xpos[i][3..6]);
            sema = 1 / (2 / rxyz - v2 / Gmsm);
            // eccentricity
            pp = c2 / Gmsm;
            ecce = @sqrt(1 - pp / sema);
            // eccentric anomaly
            cosE = 1 / ecce * (1 - rxyz / sema);
            sinE = 1 / ecce / @sqrt(sema * Gmsm) * sweph.dot_prod(xpos[i][0..3], xpos[i][3..6]);
            // true anomaly
            ny = 2 * swe_shim_atan(@sqrt((1 + ecce) / (1 - ecce)) * sinE / (1 + cosE));
            // distance of perihelion from ascending node
            xq[i][0] = lib.swi_mod2PI(uu - ny);
            xq[i][1] = 0; // latitude
            xq[i][2] = sema * (1 - ecce); // distance of perihelion
            // transformation to ecliptic coordinates
            lib.swi_polcart(xq[i][0..3], xq[i][0..3]);
            lib.swi_coortrf2(xq[i][0..3], xq[i][0..3], -sinincl, cosincl);
            lib.swi_cartpol(xq[i][0..3], xq[i][0..3]);
            // adding node, we get perihelion in ecl. coord.
            xq[i][0] += swe_shim_atan2(sinnode, cosnode);
            xa[i][0] = lib.swi_mod2PI(xq[i][0] + PI);
            xa[i][1] = -xq[i][1];
            if (do_focal_point) {
                xa[i][2] = sema * ecce * 2; // distance of aphelion
            } else {
                xa[i][2] = sema * (1 + ecce); // distance of aphelion
            }
            lib.swi_polcart(xq[i][0..3], xq[i][0..3]);
            lib.swi_polcart(xa[i][0..3], xa[i][0..3]);
            // new distance of node from orbital ellipse:
            // true anomaly of node:
            ny = lib.swi_mod2PI(ny - uu);
            ny2 = lib.swi_mod2PI(ny + PI);
            // eccentric anomaly
            cosE = swe_shim_cos(2 * swe_shim_atan(swe_shim_tan(ny / 2) / @sqrt((1 + ecce) / (1 - ecce))));
            cosE2 = swe_shim_cos(2 * swe_shim_atan(swe_shim_tan(ny2 / 2) / @sqrt((1 + ecce) / (1 - ecce))));
            // new distance
            rn = sema * (1 - ecce * cosE);
            rn2 = sema * (1 - ecce * cosE2);
            // old node distance
            ro = @sqrt(sweph.square_sum(&xn[i]));
            ro2 = @sqrt(sweph.square_sum(&xs[i]));
            // correct length of position vector
            for (0..3) |k| {
                xn[i][k] *= rn / ro;
                xs[i][k] *= rn2 / ro2;
            }
        }
        for (0..3) |k| {
            if ((iflag & sweph.SEFLG_SPEED) != 0) {
                xpe[k] = xq[1][k];
                xpe[k + 3] = (xq[2][k] - xq[0][k]) / dt / 2;
                xap[k] = xa[1][k];
                xap[k + 3] = (xa[2][k] - xa[0][k]) / dt / 2;
                xna[k] = xn[1][k];
                xna[k + 3] = (xn[2][k] - xn[0][k]) / dt / 2;
                xnd[k] = xs[1][k];
                xnd[k + 3] = (xs[2][k] - xs[0][k]) / dt / 2;
            } else {
                xpe[k] = xq[0][k];
                xpe[k + 3] = 0;
                xap[k] = xa[0][k];
                xap[k + 3] = 0;
                xna[k] = xn[0][k];
                xna[k + 3] = 0;
                xnd[k] = xs[0][k];
                xnd[k + 3] = 0;
            }
        }
        is_true_nodaps = true;
    }
    // to set the variables required in the save area,
    // i.e. ecliptic, nutation, barycentric sun, earth
    // we compute the planet
    if (ipli == @as(usize, @intCast(SE_MOON)) and (iflag & (sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR)) != 0) {
        sweph.forceAppPos(swed);
        if (sweph.swe_calc(tjd_et, SE_SUN, iflg0, &x, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    } else {
        if (sweph.swe_calc(tjd_et, @intCast(ipli), iflg0 | (iflag & sweph.SEFLG_TOPOCTR), &x, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
    }
    // position of observer
    if ((iflag & sweph.SEFLG_TOPOCTR) != 0) {
        // geocentric position of observer
        if (sweph.swi_get_observer(tjd_et, iflag, false, &xobs, swed, models, dctx, serr) != lib.OK)
            return lib.ERR;
    } else {
        for (0..6) |k|
            xobs[k] = 0;
    }
    // C: pointers into the save area — the aberration block's
    // swe_calc(tjd_et - dt) call UPDATES them, and xobs2 reads the
    // t-dt earth through the same pointer afterwards.
    const xsun = &swed.pldat[sweph.SEI_SUNBARY].x;
    const xear = &swed.pldat[sweph.SEI_EARTH].x;
    if ((iflag & (sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR)) != 0) {
        if ((iflag & sweph.SEFLG_HELCTR) != 0 and (iflag & SEFLG_MOSEPH) == 0) {
            for (0..6) |k|
                xobs[k] = xsun[k];
        }
    } else if (ipl == SE_SUN and (iflag & SEFLG_MOSEPH) == 0) {
        for (0..6) |k|
            xobs[k] = xsun[k];
    } else {
        // barycentric position of observer
        for (0..6) |k|
            xobs[k] += xear[k];
    }
    // ecliptic obliquity
    if ((iflag & sweph.SEFLG_J2000) != 0)
        oe = &swed.oec2000
    else
        oe = &swed.oec;
    // conversions shared by mean and osculating points
    ij = 0;
    xp = xx[0..];
    while (ij < 4) : ({
        ij += 1;
        xp = xp[6..];
    }) {
        // no nodes for earth
        if (ipli == @as(usize, @intCast(SE_EARTH)) and ij <= 1) {
            for (0..6) |k|
                xp[k] = 0;
            continue;
        }
        // to equator
        if (is_true_nodaps and (iflag & sweph.SEFLG_NONUT) == 0) {
            lib.swi_coortrf2(xp[0..3], xp[0..3], -swed.nut.snut, swed.nut.cnut);
            if ((iflag & sweph.SEFLG_SPEED) != 0)
                lib.swi_coortrf2(xp[3..6], xp[3..6], -swed.nut.snut, swed.nut.cnut);
        }
        lib.swi_coortrf2(xp[0..3], xp[0..3], -oe.seps, oe.ceps);
        lib.swi_coortrf2(xp[3..6], xp[3..6], -oe.seps, oe.ceps);
        if (is_true_nodaps) {
            // to mean ecliptic of date
            if ((iflag & sweph.SEFLG_NONUT) == 0)
                sweph.swi_nutate(xp[0..6], iflag, true, swed);
        }
        // to J2000
        _ = lib.swi_precess(xp[0..3], tjd_et, iflag, lib.J_TO_J2000, models);
        if ((iflag & sweph.SEFLG_SPEED) != 0)
            sweph.swi_precess_speed(xp[0..6], tjd_et, iflag, lib.J_TO_J2000, swed, models);
        // to barycenter
        if (ipli == @as(usize, @intCast(SE_MOON))) {
            for (0..6) |k|
                xp[k] += xear[k];
        } else {
            if ((iflag & SEFLG_MOSEPH) == 0 and !ellipse_is_bary) {
                for (0..6) |k|
                    xp[k] += xsun[k];
            }
        }
        // to correct center
        for (0..6) |k|
            xp[k] -= xobs[k];
        // geocentric perigee/apogee of sun
        if (ipl == SE_SUN and (iflag & (sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR)) == 0) {
            for (0..6) |k|
                xp[k] = -xp[k];
        }
        // light deflection
        dt = @sqrt(sweph.square_sum(xp[0..6])) * AUNIT / CLIGHT / 86400.0;
        if (do_defl)
            sweph.swi_deflect_light(xp[0..6], dt, iflag, swed);
        // aberration
        if (do_aberr) {
            sweph.swi_aberr_light(xp[0..6], &xobs, iflag);
            // Apparent speed is also influenced by the difference of speed
            // of the earth between t and t-dt.
            if ((iflag & sweph.SEFLG_SPEED) != 0) {
                // get barycentric sun and earth for t-dt into save area
                if (sweph.swe_calc(tjd_et - dt, @intCast(ipli), iflg0 | (iflag & sweph.SEFLG_TOPOCTR), &x2, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if ((iflag & sweph.SEFLG_TOPOCTR) != 0) {
                    // geocentric position of observer
                    for (0..6) |k|
                        xobs2[k] = swed.topd.xobs[k];
                } else {
                    for (0..6) |k|
                        xobs2[k] = 0;
                }
                if ((iflag & (sweph.SEFLG_HELCTR | sweph.SEFLG_BARYCTR)) != 0) {
                    if ((iflag & sweph.SEFLG_HELCTR) != 0 and (iflag & SEFLG_MOSEPH) == 0) {
                        for (0..6) |k|
                            xobs2[k] = xsun[k];
                    }
                } else if (ipl == SE_SUN and (iflag & SEFLG_MOSEPH) == 0) {
                    for (0..6) |k|
                        xobs2[k] = xsun[k];
                } else {
                    // barycentric position of observer
                    for (0..6) |k|
                        xobs2[k] += xear[k];
                }
                for (3..6) |k|
                    xp[k] += xobs[k] - xobs2[k];
                // The above call of swe_calc() has destroyed the parts of
                // the save area (i.e. bary sun, earth nutation matrix!).
                // to restore it:
                if (sweph.swe_calc(tjd_et, SE_SUN, iflg0 | (iflag & sweph.SEFLG_TOPOCTR), &x2, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
            }
        }
        // precession
        // save J2000 coordinates; required for sidereal positions
        for (0..6) |k|
            x2000[k] = xp[k];
        if ((iflag & sweph.SEFLG_J2000) == 0) {
            _ = lib.swi_precess(xp[0..3], tjd_et, iflag, lib.J2000_TO_J, models);
            if ((iflag & sweph.SEFLG_SPEED) != 0)
                sweph.swi_precess_speed(xp[0..6], tjd_et, iflag, lib.J2000_TO_J, swed, models);
        }
        // nutation
        if ((iflag & sweph.SEFLG_NONUT) == 0)
            sweph.swi_nutate(xp[0..6], iflag, false, swed);
        // now we have equatorial cartesian coordinates; keep them
        // (local pldat.xreturn array, as in C)
        var xreturn: [24]f64 = undefined;
        for (0..6) |k|
            xreturn[18 + k] = xp[k];
        // transformation to ecliptic.
        // with sidereal calc. this will be overwritten afterwards.
        lib.swi_coortrf2(xp[0..3], xp[0..3], oe.seps, oe.ceps);
        if ((iflag & sweph.SEFLG_SPEED) != 0)
            lib.swi_coortrf2(xp[3..6], xp[3..6], oe.seps, oe.ceps);
        if ((iflag & sweph.SEFLG_NONUT) == 0) {
            lib.swi_coortrf2(xp[0..3], xp[0..3], swed.nut.snut, swed.nut.cnut);
            if ((iflag & sweph.SEFLG_SPEED) != 0)
                lib.swi_coortrf2(xp[3..6], xp[3..6], swed.nut.snut, swed.nut.cnut);
        }
        // now we have ecliptic cartesian coordinates
        for (0..6) |k|
            xreturn[6 + k] = xp[k];
        // sidereal positions
        if ((iflag & sweph.SEFLG_SIDEREAL) != 0) {
            // project onto ecliptic t0
            if ((swed.sidd.sid_mode & sweph.SE_SIDBIT_ECL_T0) != 0) {
                if (sweph.swi_trop_ra2sid_lon(&x2000, xreturn[6..12], xreturn[18..24], iflag, swed, models, dctx) != lib.OK)
                    return lib.ERR;
                // project onto solar system equator
            } else if ((swed.sidd.sid_mode & sweph.SE_SIDBIT_SSY_PLANE) != 0) {
                if (sweph.swi_trop_ra2sid_lon_sosy(&x2000, xreturn[6..12], iflag, swed, models, dctx) != lib.OK)
                    return lib.ERR;
            } else {
                // traditional algorithm
                lib.swi_cartpol_sp(xreturn[6..12], xreturn[0..6]);
                if (sweph.swe_get_ayanamsa_ex(tjd_et, iflag, &daya, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                xreturn[0] -= daya * DEGTORAD;
                lib.swi_polcart_sp(xreturn[0..6], xreturn[6..12]);
            }
        }
        if ((iflag & sweph.SEFLG_XYZ) != 0 and (iflag & sweph.SEFLG_EQUATORIAL) != 0) {
            for (0..6) |k|
                xp[k] = xreturn[18 + k];
            continue;
        }
        if ((iflag & sweph.SEFLG_XYZ) != 0) {
            for (0..6) |k|
                xp[k] = xreturn[6 + k];
            continue;
        }
        // transformation to polar coordinates
        lib.swi_cartpol_sp(xreturn[18..24], xreturn[12..18]);
        lib.swi_cartpol_sp(xreturn[6..12], xreturn[0..6]);
        // radians to degrees
        if ((iflag & sweph.SEFLG_RADIANS) == 0) {
            for (0..2) |k| {
                xreturn[k] *= RADTODEG; // ecliptic
                xreturn[k + 3] *= RADTODEG;
                xreturn[k + 12] *= RADTODEG; // equator
                xreturn[k + 15] *= RADTODEG;
            }
        }
        if ((iflag & sweph.SEFLG_EQUATORIAL) != 0) {
            for (0..6) |k|
                xp[k] = xreturn[12 + k];
            continue;
        } else {
            for (0..6) |k|
                xp[k] = xreturn[k];
            continue;
        }
    }
    for (0..6) |k| {
        if (k > 2 and (iflag & sweph.SEFLG_SPEED) == 0) {
            xna[k] = 0;
            xnd[k] = 0;
            xpe[k] = 0;
            xap[k] = 0;
        }
        if (xnasc != null)
            xnasc.?[k] = xna[k];
        if (xndsc != null)
            xndsc.?[k] = xnd[k];
        if (xperi != null)
            xperi.?[k] = xpe[k];
        if (xaphe != null)
            xaphe.?[k] = xap[k];
    }
    return lib.OK;
}

/// swecl.c swe_nod_aps_ut()
pub fn swe_nod_aps_ut(
    tjd_ut: f64,
    ipl: i32,
    iflag: i32,
    method: i32,
    xnasc: ?*[6]f64,
    xndsc: ?*[6]f64,
    xperi: ?*[6]f64,
    xaphe: ?*[6]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    return swe_nod_aps(tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, iflag), ipl, iflag, method, xnasc, xndsc, xperi, xaphe, serr, swed, models, dctx);
}

/// swecl.c get_gmsm() — GM of the central body (sun+inner planets)
fn get_gmsm(tjd_et: f64, ipl: i32, iflag: i32, r: f64, gmsm: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var Gmsm: f64 = 0;
    var plm: f64 = 0;
    var x: [6]f64 = undefined;
    var iflJ2000p = (iflag & (SEFLG_EPHMASK | SEFLG_HELCTR | SEFLG_BARYCTR)) | sweph.SEFLG_J2000 | sweph.SEFLG_TRUEPOS | sweph.SEFLG_NONUT;
    if ((iflJ2000p & (SEFLG_HELCTR | SEFLG_BARYCTR)) == 0) {
        iflJ2000p |= SEFLG_HELCTR;
    }
    if (ipl == SE_MOON) {
        Gmsm = GEOGCONST * (1 + 1 / EARTH_MOON_MRAT) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
    } else {
        if ((ipl >= SE_MERCURY and ipl <= SE_PLUTO) or ipl == SE_EARTH) {
            plm = 0;
            // to reproduce AA orbital elements, sum up masses of all planets
            // that are inside the orbit to be computed
            if ((iflag & SEFLG_ORBEL_AA) != 0) {
                if (ipl == SE_EARTH) {
                    plm = 1.0 / plmass[@intCast(ipl_to_elem[@intCast(ipl)])];
                    plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(SE_VENUS)])];
                    plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(SE_MERCURY)])];
                } else {
                    var j: i32 = ipl;
                    while (j >= SE_MERCURY) : (j -= 1) {
                        plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(j)])];
                    }
                    if (ipl >= SE_MARS)
                        plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(SE_EARTH)])];
                }
                // ... treat it as a pure two-body problem
            } else {
                plm = 1.0 / plmass[@intCast(ipl_to_elem[@intCast(ipl)])];
            }
            Gmsm = HELGRAVCONST * (1 + plm) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
            // asteroid or fictitious object
        } else {
            plm = 0;
            if ((iflag & SEFLG_ORBEL_AA) != 0) {
                var j: i32 = SE_MERCURY;
                while (j <= SE_PLUTO) : (j += 1) {
                    if (sweph.swe_calc(tjd_et, j, iflJ2000p, &x, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    if (r > x[2])
                        plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(j)])];
                }
                if (sweph.swe_calc(tjd_et, SE_EARTH, iflJ2000p, &x, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (r > x[2])
                    plm += 1.0 / plmass[@intCast(ipl_to_elem[@intCast(SE_EARTH)])];
            }
            Gmsm = HELGRAVCONST * (1 + plm) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
        }
    }
    gmsm.* = Gmsm;
    return lib.OK;
}

/// swecl.c swe_get_orbital_elements() — osculating Kepler elements; dret[50]
pub fn swe_get_orbital_elements(
    tjd_et: f64,
    ipl: i32,
    iflag: i32,
    dret: *[50]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var x: [6]f64 = undefined;
    var xpos: [6]f64 = undefined;
    var xposm: [6]f64 = undefined;
    var xn: [6]f64 = undefined;
    var xs: [6]f64 = undefined;
    var xnorm: [6]f64 = undefined;
    var xq: [6]f64 = undefined;
    var xa: [6]f64 = undefined;
    var iflJ2000 = (iflag & SEFLG_EPHMASK) | sweph.SEFLG_J2000 | sweph.SEFLG_XYZ | sweph.SEFLG_TRUEPOS | sweph.SEFLG_NONUT | sweph.SEFLG_SPEED;
    const iflJ2000p = (iflag & SEFLG_EPHMASK) | sweph.SEFLG_J2000 | sweph.SEFLG_TRUEPOS | sweph.SEFLG_NONUT | sweph.SEFLG_SPEED;
    var Gmsm: f64 = undefined;
    var fac: f64 = undefined;
    var sgn: f64 = undefined;
    var rxy: f64 = undefined;
    var rxyz: f64 = undefined;
    var c2: f64 = undefined;
    var cosnode: f64 = undefined;
    var sinnode: f64 = undefined;
    var incl: f64 = undefined;
    var node: f64 = undefined;
    var parg: f64 = undefined;
    var peri: f64 = undefined;
    var mlon: f64 = undefined;
    var csid: f64 = undefined;
    var ctro: f64 = undefined;
    var csyn: f64 = undefined;
    var dmot: f64 = undefined;
    var pa: f64 = undefined;
    var ytrop: f64 = undefined;
    var ysid: f64 = undefined;
    var T: f64 = undefined;
    var T2: f64 = undefined;
    var T3: f64 = undefined;
    var T4: f64 = undefined;
    var T5: f64 = undefined;
    var sinincl: f64 = undefined;
    var cosincl: f64 = undefined;
    var cosu: f64 = undefined;
    var sinu: f64 = undefined;
    var uu: f64 = undefined;
    var eanom: f64 = undefined;
    var tanom: f64 = undefined;
    var manom: f64 = undefined;
    var v2: f64 = undefined;
    var sema: f64 = undefined;
    var pp: f64 = undefined;
    var ecce: f64 = undefined;
    var cosE: f64 = undefined;
    var sinE: f64 = undefined;
    var ny: f64 = undefined;
    var ny2: f64 = undefined;
    var rn: f64 = undefined;
    var rn2: f64 = undefined;
    var ro: f64 = undefined;
    var ro2: f64 = undefined;
    var cosE2: f64 = undefined;
    var r: f64 = undefined;
    var ecce2: f64 = undefined;
    if (ipl <= 0 or ipl == SE_MEAN_NODE or ipl == SE_TRUE_NODE or ipl == SE_MEAN_APOG or ipl == SE_OSCU_APOG or ipl == SE_INTP_APOG or ipl == SE_INTP_PERG) {
        if (serr != null) {
            const r2 = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "error in swe_get_orbital_elements(): object {d} not valid\n", .{ipl}) catch "";
            if (r2.len < serr.?.len) serr.?[r2.len] = 0;
        }
        return lib.ERR;
    }
    // if (ipl != SE_MOON) iflg0 |= SEFLG_HELCTR;
    // first, we need a heliocentric distance of the planet
    if (sweph.swe_calc(tjd_et, ipl, iflJ2000p, &x, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    r = x[2];
    if (ipl != SE_MOON) {
        if ((iflag & SEFLG_BARYCTR) != 0 and r > 6) {
            iflJ2000 |= SEFLG_BARYCTR; // only planets beyond Jupiter
        } else {
            iflJ2000 |= SEFLG_HELCTR;
        }
    }
    if (get_gmsm(tjd_et, ipl, iflag, r, &Gmsm, serr, swed, models, dctx) != lib.OK)
        return lib.ERR;
    if (sweph.swe_calc(tjd_et, ipl, iflJ2000, &xpos, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    // the EMB is used instead of the earth
    if (ipl == SE_EARTH) {
        if (sweph.swe_calc(tjd_et, SE_MOON, iflJ2000 & ~(SEFLG_BARYCTR | SEFLG_HELCTR), &xposm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        for (0..6) |j|
            xpos[j] += xposm[j] / (EARTH_MOON_MRAT + 1.0);
    }
    fac = xpos[2] / xpos[5];
    sgn = xpos[5] / @abs(xpos[5]);
    for (0..3) |j| {
        xn[j] = (xpos[j] - fac * xpos[j + 3]) * sgn;
        xs[j] = -xn[j];
    }
    // node
    rxy = @sqrt(xn[0] * xn[0] + xn[1] * xn[1]);
    cosnode = xn[0] / rxy;
    sinnode = xn[1] / rxy;
    // inclination
    lib.swi_cross_prod_slice(xpos[0..3], xpos[3..6], xnorm[0..3]);
    rxy = xnorm[0] * xnorm[0] + xnorm[1] * xnorm[1];
    c2 = (rxy + xnorm[2] * xnorm[2]);
    rxyz = @sqrt(c2);
    rxy = @sqrt(rxy);
    sinincl = rxy / rxyz;
    cosincl = @sqrt(1 - sinincl * sinincl);
    if (xnorm[2] < 0) cosincl = -cosincl; // retrograde asteroid, e.g. 20461 Dioretsa
    incl = swe_shim_acos(cosincl) * RADTODEG; // inclination
    // argument of latitude
    cosu = xpos[0] * cosnode + xpos[1] * sinnode;
    sinu = xpos[2] / sinincl;
    uu = swe_shim_atan2(sinu, cosu);
    // semi-axis
    rxyz = @sqrt(sweph.square_sum(&xpos));
    v2 = sweph.square_sum(xpos[3..6]);
    sema = 1.0 / (2.0 / rxyz - v2 / Gmsm);
    // eccentricity
    pp = c2 / Gmsm;
    ecce = pp / sema;
    if (ecce > 1)
        ecce = 1;
    ecce = @sqrt(1 - ecce);
    // eccentric anomaly
    ecce2 = ecce;
    if (ecce2 == 0)
        ecce2 = 0.0000000001;
    cosE = 1 / ecce2 * (1 - rxyz / sema);
    sinE = 1 / ecce2 / @sqrt(sema * Gmsm) * sweph.dot_prod(xpos[0..3], xpos[3..6]);
    eanom = lib.swe_degnorm(swe_shim_atan2(sinE, cosE) * RADTODEG);
    // true anomaly
    ny = 2 * swe_shim_atan(@sqrt((1 + ecce) / (1 - ecce)) * sinE / (1 + cosE));
    tanom = lib.swe_degnorm(ny * RADTODEG);
    if (eanom > 180 and tanom < 180)
        tanom += 180;
    if (eanom < 180 and tanom > 180)
        tanom -= 180;
    // mean anomaly
    manom = lib.swe_degnorm(eanom - ecce * RADTODEG * swe_shim_sin(eanom * DEGTORAD)); // mean anomaly
    // distance of perihelion from ascending node
    xq[0] = lib.swi_mod2PI(uu - ny);
    parg = xq[0] * RADTODEG;
    xq[1] = 0; // latitude
    xq[2] = sema * (1 - ecce); // distance of perihelion
    // transformation to ecliptic coordinates
    lib.swi_polcart(xq[0..3], xq[0..3]);
    lib.swi_coortrf2(xq[0..3], xq[0..3], -sinincl, cosincl);
    lib.swi_cartpol(xq[0..3], xq[0..3]);
    // adding node, we get perihelion in ecl. coord.
    xq[0] += swe_shim_atan2(sinnode, cosnode);
    xa[0] = lib.swi_mod2PI(xq[0] + PI);
    xa[1] = -xq[1];
    xa[2] = sema * (1 + ecce); // distance of aphelion
    lib.swi_polcart(xq[0..3], xq[0..3]);
    lib.swi_polcart(xa[0..3], xa[0..3]);
    // new distance of node from orbital ellipse:
    // true anomaly of node:
    ny = lib.swi_mod2PI(ny - uu);
    ny2 = lib.swi_mod2PI(ny + PI);
    // eccentric anomaly
    cosE = swe_shim_cos(2 * swe_shim_atan(swe_shim_tan(ny / 2) / @sqrt((1 + ecce) / (1 - ecce))));
    cosE2 = swe_shim_cos(2 * swe_shim_atan(swe_shim_tan(ny2 / 2) / @sqrt((1 + ecce) / (1 - ecce))));
    // new distance
    rn = sema * (1 - ecce * cosE);
    rn2 = sema * (1 - ecce * cosE2);
    // old node distance
    ro = @sqrt(sweph.square_sum(&xn));
    ro2 = @sqrt(sweph.square_sum(&xs));
    // correct length of position vector
    for (0..3) |j| {
        xn[j] *= rn / ro;
        xs[j] *= rn2 / ro2;
    }
    lib.swi_cartpol(xn[0..3], xn[0..3]);
    lib.swi_cartpol(xq[0..3], xq[0..3]);
    node = xn[0] * RADTODEG;
    peri = lib.swe_degnorm(node + parg);
    mlon = lib.swe_degnorm(manom + peri);
    csid = sema * @sqrt(sema); // sidereal period in sidereal years
    if (ipl == SE_MOON) {
        const semam = sema * AUNIT / 383397772.5;
        csid = semam * @sqrt(semam); // sidereal period in sidereal months
        csid *= 27.32166 / 365.25636300;
    }
    dmot = 0.9856076686 / csid; // daily motion
    csid *= 365.25636 / 365.242189; // sidereal period in tropical years J2000
    // daily motion due to precession (Simon et alii 1994)
    T = (tjd_et - lib.J2000) / 365250.0;
    T2 = T * T;
    T3 = T2 * T;
    T4 = T3 * T;
    T5 = T4 * T;
    pa = (50288.200 + 222.4045 * T + 0.2095 * T2 - 0.9408 * T3 - 0.0090 * T4 + 0.0010 * T5) / 3600.0 / 365250.0;
    // sidereal and tropical year length (Simon et alii 1994)
    ysid = (1295977422.83429 - 2 * 2.0441 * T - 3 * 0.00523 * T * T) / 3600.0 / 365250.0;
    ysid = 360.0 / ysid;
    ytrop = (1296027711.03429 + 2 * 109.15809 * T + 3 * 0.07207 * T2 - 4 * 0.23530 * T3 - 5 * 0.00180 * T4 + 6 * 0.00020 * T5) / 3600.0 / 365250.0;
    ytrop = 360.0 / ytrop;
    ctro = 360.0 / (dmot + pa) / 365.242189; // tropical period in years
    ctro *= ysid / ytrop; // tropical period in tropical years J2000
    if (ipl == SE_EARTH)
        csyn = 0
    else
        csyn = 360.0 / (0.9856076686 - dmot); // synodic period in days
    dret[0] = sema; // semimajor axis
    dret[1] = ecce; // eccentricity
    dret[2] = incl; // inclination
    dret[3] = node; // node
    dret[4] = parg; // argument of perihelion
    dret[5] = peri; // longitude of perihelion
    dret[6] = manom; // mean anomaly
    dret[7] = tanom; // true anomaly
    dret[8] = eanom; // eccentric anomaly
    dret[9] = mlon; // mean longitude
    dret[10] = csid; // sidereal orbital period in sidereal years
    dret[11] = dmot; // daily motion
    dret[12] = ctro; // tropical period in years
    dret[13] = csyn; // synodic period in days
    dret[14] = tjd_et - dret[6] / dmot; // tjd_et of perihelion passage
    dret[15] = sema * (1 - ecce); // perihelion distance
    dret[16] = sema * (1 + ecce); // aphelion distance
    return lib.OK;
}

/// swecl.c osc_get_orbit_constants()
fn osc_get_orbit_constants(dp: *const [50]f64, pqr: *[20]f64) void {
    const sema = dp[0];
    const ecce = dp[1];
    const incl = dp[2];
    const node = dp[3];
    const parg = dp[4];
    const cosnode = swe_shim_cos(node * DEGTORAD);
    const sinnode = swe_shim_sin(node * DEGTORAD);
    const cosincl = swe_shim_cos(incl * DEGTORAD);
    const sinincl = swe_shim_sin(incl * DEGTORAD);
    const cosparg = swe_shim_cos(parg * DEGTORAD);
    const sinparg = swe_shim_sin(parg * DEGTORAD);
    const fac = @sqrt((1 - ecce) * (1 + ecce));
    pqr[0] = cosparg * cosnode - sinparg * cosincl * sinnode;
    pqr[1] = -sinparg * cosnode - cosparg * cosincl * sinnode;
    pqr[2] = sinincl * sinnode;
    pqr[3] = cosparg * sinnode + sinparg * cosincl * cosnode;
    pqr[4] = -sinparg * sinnode + cosparg * cosincl * cosnode;
    pqr[5] = -sinincl * cosnode;
    pqr[6] = sinparg * sinincl;
    pqr[7] = cosparg * sinincl;
    pqr[8] = cosincl;
    pqr[9] = sema;
    pqr[10] = ecce;
    pqr[11] = fac;
}

/// swecl.c osc_get_ecl_pos()
fn osc_get_ecl_pos(ean: f64, pqr: *const [20]f64, xp: *[3]f64) void {
    var x: [2]f64 = undefined;
    const cose = swe_shim_cos(ean * DEGTORAD);
    const sine = swe_shim_sin(ean * DEGTORAD);
    const sema = pqr[9];
    const ecce = pqr[10];
    const fac = pqr[11];
    x[0] = sema * (cose - ecce);
    x[1] = sema * fac * sine;
    // transformation to ecliptic
    xp[0] = pqr[0] * x[0] + pqr[1] * x[1];
    xp[1] = pqr[3] * x[0] + pqr[4] * x[1];
    xp[2] = pqr[6] * x[0] + pqr[7] * x[1];
}

/// swecl.c get_dist_from_2_vectors()
fn get_dist_from_2_vectors(x1: *const [3]f64, x2: *const [3]f64) f64 {
    const r0 = x1[0] - x2[0];
    const r1 = x1[1] - x2[1];
    const r2 = x1[2] - x2[2];
    return @sqrt(r0 * r0 + r1 * r1 + r2 * r2);
}

/// swecl.c osc_iterate_max_dist()
fn osc_iterate_max_dist(ean_in: f64, pqr: *const [20]f64, xa: *[3]f64, xb: *const [3]f64, deanopt: *f64, drmax: *f64, high_prec: bool) void {
    var r: f64 = undefined;
    var rmax: f64 = undefined;
    var eansv: f64 = 0;
    var dstep: f64 = undefined;
    var dstep_min: f64 = 1;
    if (high_prec)
        dstep_min = 0.000001;
    var ean = ean_in;
    _ = &ean;
    ean = 0;
    osc_get_ecl_pos(ean, pqr, xa);
    r = get_dist_from_2_vectors(xb, xa);
    rmax = r;
    dstep = 1;
    while (dstep >= dstep_min) {
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            while (r >= rmax) {
                eansv = ean;
                if (i == 0)
                    ean += dstep
                else
                    ean -= dstep;
                osc_get_ecl_pos(ean, pqr, xa);
                r = get_dist_from_2_vectors(xb, xa);
                if (r > rmax)
                    rmax = r;
            }
            ean = eansv;
            r = rmax;
        }
        ean = eansv;
        r = rmax;
        dstep /= 10;
    }
    drmax.* = rmax;
    deanopt.* = eansv;
}

/// swecl.c osc_iterate_min_dist()
fn osc_iterate_min_dist(ean_in: f64, pqr: *const [20]f64, xa: *[3]f64, xb: *const [3]f64, deanopt: *f64, drmin: *f64, high_prec: bool) void {
    var r: f64 = undefined;
    var rmin: f64 = undefined;
    var eansv: f64 = 0;
    var dstep: f64 = undefined;
    var dstep_min: f64 = 1;
    if (high_prec)
        dstep_min = 0.000001;
    var ean = ean_in;
    _ = &ean;
    ean = 0;
    osc_get_ecl_pos(ean, pqr, xa);
    r = get_dist_from_2_vectors(xb, xa);
    rmin = r;
    dstep = 1;
    while (dstep >= dstep_min) {
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            while (r <= rmin) {
                eansv = ean;
                if (i == 0)
                    ean += dstep
                else
                    ean -= dstep;
                osc_get_ecl_pos(ean, pqr, xa);
                r = get_dist_from_2_vectors(xb, xa);
                if (r < rmin)
                    rmin = r;
            }
            ean = eansv;
            r = rmin;
        }
        ean = eansv;
        r = rmin;
        dstep /= 10;
    }
    drmin.* = rmin;
    deanopt.* = eansv;
}

/// swecl.c orbit_max_min_true_distance_helio()
fn orbit_max_min_true_distance_helio(tjd_et: f64, ipl: i32, iflag: i32, dmax: *f64, dmin: *f64, dtrue: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var xinner: [3]f64 = undefined;
    var pqri: [20]f64 = undefined;
    var eani: f64 = undefined;
    var de: [50]f64 = undefined;
    var ipli = ipl;
    const iflagi = (iflag & (SEFLG_EPHMASK | SEFLG_HELCTR | SEFLG_BARYCTR));
    if (ipl == SE_SUN) {
        ipli = SE_EARTH;
    }
    // Kepler elements
    const retval = swe_get_orbital_elements(tjd_et, ipli, iflagi, &de, serr, swed, models, dctx);
    if (retval == lib.ERR)
        return lib.ERR;
    dmax.* = de[16];
    dmin.* = de[15];
    osc_get_orbit_constants(&de, &pqri);
    // true distance
    eani = de[8];
    // heliocentric ecliptic position of EMB, cartesian coordinates J2000
    osc_get_ecl_pos(eani, &pqri, &xinner);
    // its distance
    dtrue.* = @sqrt(xinner[0] * xinner[0] + xinner[1] * xinner[1] + xinner[2] * xinner[2]);
    return retval;
}

/// swecl.c swe_orbit_max_min_true_distance()
pub fn swe_orbit_max_min_true_distance(tjd_et: f64, ipl: i32, iflag: i32, dmax: *f64, dmin: *f64, dtrue: *f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    const iflagi = (iflag & (SEFLG_EPHMASK | SEFLG_HELCTR | SEFLG_BARYCTR));
    var dp: [50]f64 = undefined;
    var de: [50]f64 = undefined;
    var xouter: [3]f64 = undefined;
    var xinner: [3]f64 = undefined;
    var max_xouter: [3]f64 = undefined;
    var max_xinner: [3]f64 = undefined;
    var min_xouter: [3]f64 = undefined;
    var min_xinner: [3]f64 = undefined;
    var pqro: [20]f64 = undefined;
    var pqri: [20]f64 = undefined;
    var eano: f64 = undefined;
    var eani: f64 = undefined;
    var r: f64 = undefined;
    var rtrue: f64 = undefined;
    var rmax: f64 = 0;
    var rmin: f64 = 100000000;
    var rminsv: f64 = 0;
    var rmaxsv: f64 = 0;
    var min_eanisv: f64 = 0;
    var min_eanosv: f64 = 0;
    var max_eanisv: f64 = 0;
    var max_eanosv: f64 = 0;
    const nitermax: f64 = 300;
    var ncnt: i32 = undefined;
    var dstep: f64 = undefined;
    // separate handling for the Sun, Moon and heliocentric calculation
    if (ipl == SE_SUN or ipl == SE_MOON or (iflagi & (SEFLG_HELCTR | SEFLG_BARYCTR)) != 0) {
        return orbit_max_min_true_distance_helio(tjd_et, ipl, iflagi, dmax, dmin, dtrue, serr, swed, models, dctx);
    }
    if (swe_get_orbital_elements(tjd_et, ipl, iflagi, &dp, serr, swed, models, dctx) == lib.ERR)
        return lib.ERR;
    if (swe_get_orbital_elements(tjd_et, SE_EARTH, iflagi, &de, serr, swed, models, dctx) == lib.ERR)
        return lib.ERR;
    var douter: *const [50]f64 = undefined;
    var dinner: *const [50]f64 = undefined;
    if (de[0] > dp[0]) {
        douter = &de;
        dinner = &dp;
    } else {
        douter = &dp;
        dinner = &de;
    }
    osc_get_orbit_constants(douter, &pqro);
    osc_get_orbit_constants(dinner, &pqri);
    eano = douter[8]; // ecc. anomaly outer planet
    eani = dinner[8]; // ecc. anomaly inner planet
    osc_get_ecl_pos(eano, &pqro, &xouter); // coordinates outer planet J2000
    osc_get_ecl_pos(eani, &pqri, &xinner); // coordinates inner planet J2000
    rtrue = get_dist_from_2_vectors(&xouter, &xinner); // true distance between them
    // search rough maximum and minimum distance for objects on the two
    // ellipses (see C comment for the algorithm's caveats)
    ncnt = 182;
    dstep = 2;
    for (0..3) |k| { // initialisation
        max_xouter[k] = 0;
        max_xinner[k] = 0;
        min_xouter[k] = 0;
        min_xinner[k] = 0;
    }
    var j: i32 = 0;
    while (j < ncnt) : (j += 1) {
        eano = @as(f64, @floatFromInt(j)) * dstep;
        osc_get_ecl_pos(eano, &pqro, &xouter);
        var i: i32 = 0;
        while (i < ncnt) : (i += 1) {
            eani = @floatFromInt(i);
            osc_get_ecl_pos(eani, &pqri, &xinner);
            r = get_dist_from_2_vectors(&xouter, &xinner);
            // maximum/minimum found; save positions and ecc. anomalies
            if (r > rmax) {
                rmax = r;
                max_eanisv = eani;
                max_eanosv = eano;
                for (0..3) |k| {
                    max_xouter[k] = xouter[k];
                    max_xinner[k] = xinner[k];
                }
            }
            if (r < rmin) {
                rmin = r;
                min_eanisv = eani;
                min_eanosv = eano;
                for (0..3) |k| {
                    min_xouter[k] = xouter[k];
                    min_xinner[k] = xinner[k];
                }
            }
        }
    }
    // find accurate values, starting iterations from above-calculated rough
    // values; maximum distance:
    eani = max_eanisv;
    eano = max_eanosv;
    for (0..3) |k| {
        xouter[k] = max_xouter[k];
        xinner[k] = max_xinner[k];
    }
    var k2: i32 = 0;
    while (k2 <= @as(i32, @intFromFloat(nitermax))) : (k2 += 1) {
        osc_iterate_max_dist(eani, &pqri, &xinner, &xouter, &eani, &rmax, true);
        osc_iterate_max_dist(eano, &pqro, &xouter, &xinner, &eano, &rmax, true);
        if (k2 > 0 and @abs(rmax - rmaxsv) < 0.00000001)
            break;
        rmaxsv = rmax;
    }
    // minimum distance:
    eani = min_eanisv;
    eano = min_eanosv;
    for (0..3) |k| {
        xouter[k] = min_xouter[k];
        xinner[k] = min_xinner[k];
    }
    k2 = 0;
    while (k2 <= @as(i32, @intFromFloat(nitermax))) : (k2 += 1) {
        osc_iterate_min_dist(eani, &pqri, &xinner, &xouter, &eani, &rmin, true);
        osc_iterate_min_dist(eano, &pqro, &xouter, &xinner, &eano, &rmin, true);
        if (k2 > 0 and @abs(rmin - rminsv) < 0.00000001)
            break;
        rminsv = rmin;
    }
    dmax.* = rmax;
    dmin.* = rmin;
    dtrue.* = rtrue;
    return lib.OK;
}

/// swecl.c swe_gauquelin_sector()
pub fn swe_gauquelin_sector(
    t_ut: f64,
    ipl_in: i32,
    starname: ?[]u8,
    iflag: i32,
    imeth: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    dgsect: *f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var ipl = ipl_in;
    var rise_found = true;
    var set_found = true;
    var retval: i32 = undefined;
    var tret: [3]f64 = undefined;
    var t_et: f64 = undefined;
    var t: f64 = undefined;
    var x0: [6]f64 = undefined;
    var eps: f64 = undefined;
    var nutlo: [2]f64 = undefined;
    var armc: f64 = undefined;
    const epheflag = iflag & SEFLG_EPHMASK;
    const do_fixstar = starname != null and starname.?.len > 0 and starname.?[0] != 0;
    var risemeth: i32 = 0;
    var above_horizon = false;
    if (imeth < 0 or imeth > 5) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "invalid method: {d}", .{imeth}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    // geometrically from ecl. longitude and latitude
    if (imeth == 0 or imeth == 1) {
        // C's swe_deltat_ex reads the moon-file denum live; refresh first
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        t_et = t_ut + deltat_mod.swe_deltat_ex(dctx, t_ut, iflag);
        eps = lib.swi_epsiln(t_et, iflag, models) * RADTODEG;
        _ = lib.swi_nutation(t_et, iflag, &nutlo, models, nutInterp(swed));
        nutlo[0] *= RADTODEG;
        nutlo[1] *= RADTODEG;
        armc = lib.swe_degnorm(lib.swe_sidtime0(t_ut, eps + nutlo[1], nutlo[0], models, dctx, nutInterp(swed)) * 15 + geopos[0]);
        if (do_fixstar) {
            if (sweph.swe_fixstar(starname.?, t_et, iflag, &x0, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
        } else {
            if (sweph.swe_calc(t_et, ipl, iflag, &x0, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
        }
        if (imeth == 1)
            x0[1] = 0;
        // 'G' never reaches the Sunshine memo in swe_house_pos, so a local
        // HouseCtx is behaviorally identical to C's shared static here.
        var gsect_hctx = houses.HouseCtx{};
        dgsect.* = houses.swe_house_pos(armc, geopos[1], eps + nutlo[1], 'G', &x0, null, &gsect_hctx);
        return lib.OK;
    }
    // from rise and set times
    if (imeth == 2 or imeth == 4)
        risemeth |= SE_BIT_NO_REFRACTION;
    if (imeth == 2 or imeth == 3)
        risemeth |= SE_BIT_DISC_CENTER;
    // find the next rising time of the planet or star
    var star2: [256]u8 = [_]u8{0} ** 256;
    var stararg: ?[]u8 = null;
    if (do_fixstar) {
        const n = @min(starname.?.len, 255);
        @memcpy(star2[0..n], starname.?[0..n]);
        stararg = star2[0..n];
    }
    retval = swe_rise_trans(t_ut, ipl, stararg, epheflag, SE_CALC_RISE | risemeth, geopos, atpress, attemp, &(tret[0]), serr, swed, models, dctx, cctx);
    if (retval == lib.ERR) {
        return lib.ERR;
    } else if (retval == -2) {
        // (see C comment: keep the variable for possible circumpolar support)
        rise_found = false;
    }
    // find the next setting time of the planet or star
    retval = swe_rise_trans(t_ut, ipl, stararg, epheflag, SE_CALC_SET | risemeth, geopos, atpress, attemp, &(tret[1]), serr, swed, models, dctx, cctx);
    if (retval == lib.ERR) {
        return lib.ERR;
    } else if (retval == -2) {
        set_found = false;
    }
    if (tret[0] < tret[1] and rise_found == true) {
        above_horizon = false;
        // find last set
        t = t_ut - 1.2;
        if (set_found) t = tret[1] - 1.2;
        set_found = true;
        retval = swe_rise_trans(t, ipl, stararg, epheflag, SE_CALC_SET | risemeth, geopos, atpress, attemp, &(tret[1]), serr, swed, models, dctx, cctx);
        if (retval == lib.ERR) {
            return lib.ERR;
        } else if (retval == -2) {
            set_found = false;
        }
    } else if (tret[0] >= tret[1] and set_found == true) {
        above_horizon = true;
        // find last rise
        t = t_ut - 1.2;
        if (rise_found) t = tret[0] - 1.2;
        rise_found = true;
        retval = swe_rise_trans(t, ipl, stararg, epheflag, SE_CALC_RISE | risemeth, geopos, atpress, attemp, &(tret[0]), serr, swed, models, dctx, cctx);
        if (retval == lib.ERR) {
            return lib.ERR;
        } else if (retval == -2) {
            rise_found = false;
        }
    }
    if (rise_found and set_found) {
        if (above_horizon) {
            dgsect.* = (t_ut - tret[0]) / (tret[1] - tret[0]) * 18 + 1;
        } else {
            dgsect.* = (t_ut - tret[1]) / (tret[0] - tret[1]) * 18 + 19;
        }
        return lib.OK;
    } else {
        dgsect.* = 0;
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "rise or set not found for planet {d}", .{ipl}) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
}

// eclipses & occultations  (swecl.c)

pub const SE_ECL_CENTRAL: i32 = 1;
pub const SE_ECL_NONCENTRAL: i32 = 2;
pub const SE_ECL_TOTAL: i32 = 4;
pub const SE_ECL_ANNULAR: i32 = 8;
pub const SE_ECL_PARTIAL: i32 = 16;
pub const SE_ECL_ANNULAR_TOTAL: i32 = 32;
pub const SE_ECL_VISIBLE: i32 = 128;
pub const SE_ECL_MAX_VISIBLE: i32 = 256;
pub const SE_ECL_1ST_VISIBLE: i32 = 512;
pub const SE_ECL_2ND_VISIBLE: i32 = 1024;
pub const SE_ECL_3RD_VISIBLE: i32 = 2048;
pub const SE_ECL_4TH_VISIBLE: i32 = 4096;

pub const SE_ECL_ONE_CELL: i32 = 8 * 1024 * 1024;

// swecl.c defines
const DSUN: f64 = 1392000000.0 / AUNIT; // (the #else value)
const DMOON: f64 = 3476300.0 / AUNIT;
const RSUN: f64 = DSUN / 2;
const RMOON: f64 = DMOON / 2;
const DEARTH: f64 = 6378140.0 * 2 / AUNIT;
const REARTH: f64 = DEARTH / 2;
const EARTH_OBLATENESS_ECL: f64 = 1.0 / @as(f64, 298.25642); // AA 2006 K6
const NDIAM_ECL: usize = @intCast(SE_VESTA + 1);

/// swecl.c calc_planet_star()
fn calc_planet_star(tjd_et: f64, ipl: i32, starname: ?[]u8, iflag: i32, x: *[6]f64, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    if (starname == null or starname.?.len == 0 or starname.?[0] == 0) {
        return sweph.swe_calc(tjd_et, ipl, iflag, x, swed, models, dctx, serr);
    }
    return sweph.swe_fixstar(starname.?, tjd_et, iflag, x, swed, models, dctx, serr);
}

/// swecl.c saros table (solar): series numbers + start dates, transcribed 1:1
const NSAROS_SOLAR: usize = 181;
const SAROS_CYCLE: f64 = 6585.3213;
const saros_data_solar = [NSAROS_SOLAR]struct { series_no: i32, tstart: f64 }{
    .{ .series_no = 0, .tstart = 641886.5 },    .{ .series_no = 1, .tstart = 672214.5 },    .{ .series_no = 2, .tstart = 676200.5 },
    .{ .series_no = 3, .tstart = 693357.5 },    .{ .series_no = 4, .tstart = 723685.5 },    .{ .series_no = 5, .tstart = 727671.5 },
    .{ .series_no = 6, .tstart = 744829.5 },    .{ .series_no = 7, .tstart = 775157.5 },    .{ .series_no = 8, .tstart = 779143.5 },
    .{ .series_no = 9, .tstart = 783131.5 },    .{ .series_no = 10, .tstart = 820044.5 },   .{ .series_no = 11, .tstart = 810859.5 },
    .{ .series_no = 12, .tstart = 748993.5 },   .{ .series_no = 13, .tstart = 792492.5 },   .{ .series_no = 14, .tstart = 789892.5 },
    .{ .series_no = 15, .tstart = 787294.5 },   .{ .series_no = 16, .tstart = 824207.5 },   .{ .series_no = 17, .tstart = 834779.5 },
    .{ .series_no = 18, .tstart = 838766.5 },   .{ .series_no = 19, .tstart = 869094.5 },   .{ .series_no = 20, .tstart = 886251.5 },
    .{ .series_no = 21, .tstart = 890238.5 },   .{ .series_no = 22, .tstart = 927151.5 },   .{ .series_no = 23, .tstart = 937722.5 },
    .{ .series_no = 24, .tstart = 941709.5 },   .{ .series_no = 25, .tstart = 978623.5 },   .{ .series_no = 26, .tstart = 989194.5 },
    .{ .series_no = 27, .tstart = 993181.5 },   .{ .series_no = 28, .tstart = 1023510.5 },  .{ .series_no = 29, .tstart = 1034081.5 },
    .{ .series_no = 30, .tstart = 972214.5 },   .{ .series_no = 31, .tstart = 1061811.5 },  .{ .series_no = 32, .tstart = 1006529.5 },
    .{ .series_no = 33, .tstart = 997345.5 },   .{ .series_no = 34, .tstart = 1021088.5 },  .{ .series_no = 35, .tstart = 1038245.5 },
    .{ .series_no = 36, .tstart = 1042231.5 },  .{ .series_no = 37, .tstart = 1065974.5 },  .{ .series_no = 38, .tstart = 1089716.5 },
    .{ .series_no = 39, .tstart = 1093703.5 },  .{ .series_no = 40, .tstart = 1117446.5 },  .{ .series_no = 41, .tstart = 1141188.5 },
    .{ .series_no = 42, .tstart = 1145175.5 },  .{ .series_no = 43, .tstart = 1168918.5 },  .{ .series_no = 44, .tstart = 1192660.5 },
    .{ .series_no = 45, .tstart = 1196647.5 },  .{ .series_no = 46, .tstart = 1220390.5 },  .{ .series_no = 47, .tstart = 1244132.5 },
    .{ .series_no = 48, .tstart = 1234948.5 },  .{ .series_no = 49, .tstart = 1265277.5 },  .{ .series_no = 50, .tstart = 1282433.5 },
    .{ .series_no = 51, .tstart = 1207395.5 },  .{ .series_no = 52, .tstart = 1217968.5 },  .{ .series_no = 53, .tstart = 1254881.5 },
    .{ .series_no = 54, .tstart = 1252282.5 },  .{ .series_no = 55, .tstart = 1262855.5 },  .{ .series_no = 56, .tstart = 1293182.5 },
    .{ .series_no = 57, .tstart = 1297169.5 },  .{ .series_no = 58, .tstart = 1314326.5 },  .{ .series_no = 59, .tstart = 1344654.5 },
    .{ .series_no = 60, .tstart = 1348640.5 },  .{ .series_no = 61, .tstart = 1365798.5 },  .{ .series_no = 62, .tstart = 1396126.5 },
    .{ .series_no = 63, .tstart = 1400112.5 },  .{ .series_no = 64, .tstart = 1417270.5 },  .{ .series_no = 65, .tstart = 1447598.5 },
    .{ .series_no = 66, .tstart = 1444999.5 },  .{ .series_no = 67, .tstart = 1462157.5 },  .{ .series_no = 68, .tstart = 1492485.5 },
    .{ .series_no = 69, .tstart = 1456959.5 },  .{ .series_no = 70, .tstart = 1421434.5 },  .{ .series_no = 71, .tstart = 1471518.5 },
    .{ .series_no = 72, .tstart = 1455748.5 },  .{ .series_no = 73, .tstart = 1466320.5 },  .{ .series_no = 74, .tstart = 1496648.5 },
    .{ .series_no = 75, .tstart = 1500634.5 },  .{ .series_no = 76, .tstart = 1511207.5 },  .{ .series_no = 77, .tstart = 1548120.5 },
    .{ .series_no = 78, .tstart = 1552106.5 },  .{ .series_no = 79, .tstart = 1562679.5 },  .{ .series_no = 80, .tstart = 1599592.5 },
    .{ .series_no = 81, .tstart = 1603578.5 },  .{ .series_no = 82, .tstart = 1614150.5 },  .{ .series_no = 83, .tstart = 1644479.5 },
    .{ .series_no = 84, .tstart = 1655050.5 },  .{ .series_no = 85, .tstart = 1659037.5 },  .{ .series_no = 86, .tstart = 1695950.5 },
    .{ .series_no = 87, .tstart = 1693351.5 },  .{ .series_no = 88, .tstart = 1631484.5 },  .{ .series_no = 89, .tstart = 1727666.5 },
    .{ .series_no = 90, .tstart = 1672384.5 },  .{ .series_no = 91, .tstart = 1663200.5 },  .{ .series_no = 92, .tstart = 1693529.5 },
    .{ .series_no = 93, .tstart = 1710685.5 },  .{ .series_no = 94, .tstart = 1714672.5 },  .{ .series_no = 95, .tstart = 1738415.5 },
    .{ .series_no = 96, .tstart = 1755572.5 },  .{ .series_no = 97, .tstart = 1766144.5 },  .{ .series_no = 98, .tstart = 1789887.5 },
    .{ .series_no = 99, .tstart = 1807044.5 },  .{ .series_no = 100, .tstart = 1817616.5 }, .{ .series_no = 101, .tstart = 1841359.5 },
    .{ .series_no = 102, .tstart = 1858516.5 }, .{ .series_no = 103, .tstart = 1862502.5 }, .{ .series_no = 104, .tstart = 1892831.5 },
    .{ .series_no = 105, .tstart = 1903402.5 }, .{ .series_no = 106, .tstart = 1887633.5 }, .{ .series_no = 107, .tstart = 1924547.5 },
    .{ .series_no = 108, .tstart = 1921948.5 }, .{ .series_no = 109, .tstart = 1873251.5 }, .{ .series_no = 110, .tstart = 1890409.5 },
    .{ .series_no = 111, .tstart = 1914151.5 }, .{ .series_no = 112, .tstart = 1918138.5 }, .{ .series_no = 113, .tstart = 1935296.5 },
    .{ .series_no = 114, .tstart = 1959038.5 }, .{ .series_no = 115, .tstart = 1963024.5 }, .{ .series_no = 116, .tstart = 1986767.5 },
    .{ .series_no = 117, .tstart = 2010510.5 }, .{ .series_no = 118, .tstart = 2014496.5 }, .{ .series_no = 119, .tstart = 2031654.5 },
    .{ .series_no = 120, .tstart = 2061982.5 }, .{ .series_no = 121, .tstart = 2065968.5 }, .{ .series_no = 122, .tstart = 2083126.5 },
    .{ .series_no = 123, .tstart = 2113454.5 }, .{ .series_no = 124, .tstart = 2104269.5 }, .{ .series_no = 125, .tstart = 2108256.5 },
    .{ .series_no = 126, .tstart = 2151755.5 }, .{ .series_no = 127, .tstart = 2083302.5 }, .{ .series_no = 128, .tstart = 2080704.5 },
    .{ .series_no = 129, .tstart = 2124203.5 }, .{ .series_no = 130, .tstart = 2121603.5 }, .{ .series_no = 131, .tstart = 2132176.5 },
    .{ .series_no = 132, .tstart = 2162504.5 }, .{ .series_no = 133, .tstart = 2166490.5 }, .{ .series_no = 134, .tstart = 2177062.5 },
    .{ .series_no = 135, .tstart = 2207390.5 }, .{ .series_no = 136, .tstart = 2217962.5 }, .{ .series_no = 137, .tstart = 2228534.5 },
    .{ .series_no = 138, .tstart = 2258862.5 }, .{ .series_no = 139, .tstart = 2269434.5 }, .{ .series_no = 140, .tstart = 2273421.5 },
    .{ .series_no = 141, .tstart = 2310334.5 }, .{ .series_no = 142, .tstart = 2314320.5 }, .{ .series_no = 143, .tstart = 2311722.5 },
    .{ .series_no = 144, .tstart = 2355221.5 }, .{ .series_no = 145, .tstart = 2319695.5 }, .{ .series_no = 146, .tstart = 2284169.5 },
    .{ .series_no = 147, .tstart = 2314498.5 }, .{ .series_no = 148, .tstart = 2325069.5 }, .{ .series_no = 149, .tstart = 2329056.5 },
    .{ .series_no = 150, .tstart = 2352799.5 }, .{ .series_no = 151, .tstart = 2369956.5 }, .{ .series_no = 152, .tstart = 2380528.5 },
    .{ .series_no = 153, .tstart = 2404271.5 }, .{ .series_no = 154, .tstart = 2421428.5 }, .{ .series_no = 155, .tstart = 2425414.5 },
    .{ .series_no = 156, .tstart = 2455743.5 }, .{ .series_no = 157, .tstart = 2472900.5 }, .{ .series_no = 158, .tstart = 2476886.5 },
    .{ .series_no = 159, .tstart = 2500629.5 }, .{ .series_no = 160, .tstart = 2517786.5 }, .{ .series_no = 161, .tstart = 2515187.5 },
    .{ .series_no = 162, .tstart = 2545516.5 }, .{ .series_no = 163, .tstart = 2556087.5 }, .{ .series_no = 164, .tstart = 2487635.5 },
    .{ .series_no = 165, .tstart = 2504793.5 }, .{ .series_no = 166, .tstart = 2535121.5 }, .{ .series_no = 167, .tstart = 2525936.5 },
    .{ .series_no = 168, .tstart = 2543094.5 }, .{ .series_no = 169, .tstart = 2573422.5 }, .{ .series_no = 170, .tstart = 2577408.5 },
    .{ .series_no = 171, .tstart = 2594566.5 }, .{ .series_no = 172, .tstart = 2624894.5 }, .{ .series_no = 173, .tstart = 2628880.5 },
    .{ .series_no = 174, .tstart = 2646038.5 }, .{ .series_no = 175, .tstart = 2669780.5 }, .{ .series_no = 176, .tstart = 2673766.5 },
    .{ .series_no = 177, .tstart = 2690924.5 }, .{ .series_no = 178, .tstart = 2721252.5 }, .{ .series_no = 179, .tstart = 2718653.5 },
    .{ .series_no = 180, .tstart = 2729226.5 },
};

/// swecl.c eclipse_where() — geographic position of maximum eclipse,
/// core/half-shadow diameters (see C comment for dcore layout)
fn eclipse_where(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[]u8,
    ifl: i32,
    geopos: *[2]f64,
    dcore: *[10]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    _ = cctx;
    var retc: i32 = 0;
    var niter: i32 = 0;
    var e: [6]f64 = undefined;
    var et: [6]f64 = undefined;
    var rm: [6]f64 = undefined;
    var rs: [6]f64 = undefined;
    var rmt: [6]f64 = undefined;
    var rst: [6]f64 = undefined;
    var xs: [6]f64 = undefined;
    var xst: [6]f64 = undefined;
    var x: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lx: [6]f64 = undefined;
    var dsm: f64 = undefined;
    var dsmt: f64 = undefined;
    var d0: f64 = undefined;
    var D0: f64 = undefined;
    var s0: f64 = undefined;
    var r0: f64 = undefined;
    var d: f64 = undefined;
    var s: f64 = undefined;
    var dm: f64 = undefined;
    const de: f64 = 6378140.0 / AUNIT;
    var earthobl: f64 = 1 - EARTH_OBLATENESS_ECL;
    var deltat: f64 = undefined;
    var tjd: f64 = undefined;
    var sidt: f64 = undefined;
    var drad: f64 = undefined;
    var sinf1: f64 = undefined;
    var sinf2: f64 = undefined;
    var cosf1: f64 = undefined;
    var cosf2: f64 = undefined;
    const rmoon: f64 = RMOON;
    const dmoon: f64 = 2 * rmoon;
    var iflag: i32 = undefined;
    var iflag2: i32 = undefined;
    var no_eclipse = false;
    const oe = &swed.oec;
    for (0..10) |i|
        dcore[i] = 0;
    // nutation need not be in lunar and solar positions,
    // if mean sidereal time will be used
    iflag = sweph.SEFLG_SPEED | sweph.SEFLG_EQUATORIAL | ifl;
    iflag2 = iflag | sweph.SEFLG_RADIANS;
    iflag = iflag | sweph.SEFLG_XYZ;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    deltat = deltat_mod.swe_deltat_ex(dctx, tjd_ut, ifl);
    tjd = tjd_ut + deltat;
    // moon in cartesian coordinates
    retc = sweph.swe_calc(tjd, SE_MOON, iflag, &rm, swed, models, dctx, serr);
    if (retc == lib.ERR)
        return retc;
    // moon in polar coordinates
    retc = sweph.swe_calc(tjd, SE_MOON, iflag2, &lm, swed, models, dctx, serr);
    if (retc == lib.ERR)
        return retc;
    // sun in cartesian coordinates
    retc = calc_planet_star(tjd, ipl, starname, iflag, &rs, serr, swed, models, dctx);
    if (retc == lib.ERR)
        return retc;
    // sun in polar coordinates
    retc = calc_planet_star(tjd, ipl, starname, iflag2, &ls, serr, swed, models, dctx);
    if (retc == lib.ERR)
        return retc;
    // save sun position
    for (0..3) |i|
        rst[i] = rs[i];
    // save moon position
    for (0..3) |i|
        rmt[i] = rm[i];
    if ((iflag & sweph.SEFLG_NONUT) != 0)
        sidt = lib.swe_sidtime0(tjd_ut, oe.eps * RADTODEG, 0, models, dctx, nutInterp(swed)) * 15 * DEGTORAD
    else
        sidt = lib.swe_sidtime(tjd_ut, models, dctx, nutInterp(swed)) * 15 * DEGTORAD;
    // radius of planet disk in AU
    if (starname != null and starname.?.len > 0 and starname.?[0] != 0)
        drad = 0
    else if (ipl >= 0 and @as(usize, @intCast(ipl)) < NDIAM_ECL)
        drad = pla_diam[@intCast(ipl)] / 2 / AUNIT
    else if (ipl > SE_AST_OFFSET)
        drad = swed.ast_diam / 2 * 1000 / AUNIT // km -> m -> AU
    else
        drad = 0;
    // iter_where:
    while (true) {
        for (0..3) |i| {
            rs[i] = rst[i];
            rm[i] = rmt[i];
        }
        // Account for oblateness of earth: correction to the z coordinate
        // of the moon and the sun.
        for (0..3) |i|
            lx[i] = lm[i];
        lib.swi_polcart(lx[0..3], rm[0..3]);
        rm[2] /= earthobl;
        // distance of moon from geocenter
        dm = @sqrt(sweph.square_sum(&rm));
        // Account for oblateness of earth
        for (0..3) |i|
            lx[i] = ls[i];
        lib.swi_polcart(lx[0..3], rs[0..3]);
        rs[2] /= earthobl;
        // sun - moon vector
        for (0..3) |i| {
            e[i] = (rm[i] - rs[i]);
            et[i] = (rmt[i] - rst[i]);
        }
        // distance sun - moon
        dsm = @sqrt(sweph.square_sum(&e));
        dsmt = @sqrt(sweph.square_sum(&et));
        // sun - moon unit vector
        for (0..3) |i| {
            e[i] /= dsm;
            et[i] /= dsmt;
        }
        sinf1 = ((drad - rmoon) / dsm);
        cosf1 = @sqrt(1 - sinf1 * sinf1);
        sinf2 = ((drad + rmoon) / dsm);
        cosf2 = @sqrt(1 - sinf2 * sinf2);
        // distance of moon from fundamental plane
        s0 = -sweph.dot_prod(rm[0..3], e[0..3]);
        // distance of shadow axis from geocenter
        r0 = @sqrt(dm * dm - s0 * s0);
        // diameter of core shadow on fundamental plane
        d0 = (s0 / dsm * (drad * 2 - dmoon) - dmoon) / cosf1;
        // diameter of half-shadow on fundamental plane
        D0 = (s0 / dsm * (drad * 2 + dmoon) + dmoon) / cosf2;
        dcore[2] = r0;
        dcore[3] = d0;
        dcore[4] = D0;
        dcore[5] = cosf1;
        dcore[6] = cosf2;
        for (2..5) |i|
            dcore[i] *= AUNIT / 1000.0;
        // central (total or annular) phase
        retc = 0;
        if (de * cosf1 >= r0) {
            retc |= SE_ECL_CENTRAL;
        } else if (r0 <= de * cosf1 + @abs(d0) / 2) {
            retc |= SE_ECL_NONCENTRAL;
        } else if (r0 <= de * cosf2 + D0 / 2) {
            retc |= (SE_ECL_PARTIAL | SE_ECL_NONCENTRAL);
        } else {
            if (serr != null) {
                const r2 = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "no solar eclipse at tjd = {d:.6}", .{tjd}) catch "";
                if (r2.len < serr.?.len) serr.?[r2.len] = 0;
            }
            for (0..2) |i|
                geopos[i] = 0;
            dcore[0] = 0;
            retc = 0;
            d = 0;
            no_eclipse = true;
        }
        // distance of shadow point from fundamental plane
        d = s0 * s0 + de * de - dm * dm;
        if (d > 0)
            d = @sqrt(d)
        else
            d = 0;
        // distance of moon from shadow point on earth
        s = s0 - d;
        // geographic position of eclipse center (maximum)
        for (0..3) |i|
            xs[i] = rm[i] + s * e[i];
        // we need geographic position with correct z, as well
        for (0..3) |i|
            xst[i] = xs[i];
        xst[2] *= earthobl;
        lib.swi_cartpol(xst[0..3], xst[0..3]);
        if (niter <= 0) {
            const cosfi = swe_shim_cos(xst[1]);
            const sinfi = swe_shim_sin(xst[1]);
            const eobl = EARTH_OBLATENESS_ECL;
            const cc = 1 / @sqrt(cosfi * cosfi + (1 - eobl) * (1 - eobl) * sinfi * sinfi);
            const ss = (1 - eobl) * (1 - eobl) * cc;
            earthobl = ss;
            niter += 1;
            continue; // goto iter_where
        }
        lib.swi_polcart(xst[0..3], xst[0..3]);
        // to longitude and latitude
        lib.swi_cartpol(xs[0..3], xs[0..3]);
        // measure from sidereal time at greenwich
        xs[0] -= sidt;
        xs[0] *= RADTODEG;
        xs[1] *= RADTODEG;
        xs[0] = lib.swe_degnorm(xs[0]);
        // west is negative
        if (xs[0] > 180)
            xs[0] -= 360;
        geopos[0] = xs[0];
        geopos[1] = xs[1];
        // diameter of core shadow:
        // first, distance moon - place of eclipse on earth
        for (0..3) |i|
            x[i] = rmt[i] - xst[i];
        s = @sqrt(sweph.square_sum(&x));
        // diameter of core shadow at place of maximum eclipse
        dcore[0] = (s / dsmt * (drad * 2 - dmoon) - dmoon) * cosf1;
        dcore[0] *= AUNIT / 1000.0;
        // diameter of penumbra at place of maximum eclipse
        dcore[1] = (s / dsmt * (drad * 2 + dmoon) + dmoon) * cosf2;
        dcore[1] *= AUNIT / 1000.0;
        if ((retc & SE_ECL_PARTIAL) == 0 and !no_eclipse) {
            if (dcore[0] > 0) {
                retc |= SE_ECL_ANNULAR;
            } else {
                retc |= SE_ECL_TOTAL;
            }
        }
        return retc;
    }
}

/// swecl.c eclipse_how() — attributes of an eclipse at a given location
fn eclipse_how(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[]u8,
    ifl: i32,
    geolon: f64,
    geolat: f64,
    geohgt: f64,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var retc: i32 = 0;
    var te: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var x1: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var rmoon: f64 = undefined;
    var rsun: f64 = undefined;
    var rsplusrm: f64 = undefined;
    var rsminusrm: f64 = undefined;
    var dctr: f64 = undefined;
    var drad: f64 = undefined;
    const iflag: i32 = sweph.SEFLG_EQUATORIAL | sweph.SEFLG_TOPOCTR | ifl;
    const iflagcart: i32 = iflag | sweph.SEFLG_XYZ;
    var xh: [6]f64 = undefined;
    var hmin_appr: f64 = undefined;
    var lsun: f64 = undefined;
    var lmoon: f64 = undefined;
    var lctr: f64 = undefined;
    var lsunleft: f64 = undefined;
    var a: f64 = undefined;
    var b: f64 = undefined;
    var sc1: f64 = undefined;
    var sc2: f64 = undefined;
    var geopos: [3]f64 = undefined;
    for (0..10) |i|
        attr[i] = 0;
    geopos[0] = geolon;
    geopos[1] = geolat;
    geopos[2] = geohgt;
    // C's swe_deltat_ex reads the moon-file denum live; refresh first
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    te = tjd_ut + deltat_mod.swe_deltat_ex(dctx, tjd_ut, ifl);
    sweph.swe_set_topo(geolon, geolat, geohgt, swed);
    if (calc_planet_star(te, ipl, starname, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
        return lib.ERR;
    if (sweph.swe_calc(te, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    if (calc_planet_star(te, ipl, starname, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
        return lib.ERR;
    if (sweph.swe_calc(te, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    // radius of planet disk in AU
    if (starname != null and starname.?.len > 0 and starname.?[0] != 0)
        drad = 0
    else if (ipl >= 0 and @as(usize, @intCast(ipl)) < NDIAM_ECL)
        drad = pla_diam[@intCast(ipl)] / 2 / AUNIT
    else if (ipl > SE_AST_OFFSET)
        drad = swed.ast_diam / 2 * 1000 / AUNIT // km -> m -> AU
    else
        drad = 0;
    // azimuth and altitude of sun or planet
    // (USE_AZ_NAV = 0: the swe_azalt variant is active)
    swe_azalt(tjd_ut, SE_EQU2HOR, &geopos, 0, 10, ls[0..3], xh[0..3], swed, models, dctx, cctx); // azimuth from south, clockwise, via west
    // eclipse description
    rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
    rsun = swe_shim_asin(drad / ls[2]) * RADTODEG;
    rsplusrm = rsun + rmoon;
    rsminusrm = rsun - rmoon;
    for (0..3) |i| {
        x1[i] = xs[i] / ls[2];
        x2[i] = xm[i] / lm[2];
    }
    dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
    // phase
    if (dctr < rsminusrm)
        retc = SE_ECL_ANNULAR
    else if (dctr < @abs(rsminusrm))
        retc = SE_ECL_TOTAL
    else if (dctr < rsplusrm)
        retc = SE_ECL_PARTIAL
    else {
        retc = 0;
        if (serr != null) {
            const r2 = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "no solar eclipse at tjd = {d:.6}", .{tjd_ut}) catch "";
            if (r2.len < serr.?.len) serr.?[r2.len] = 0;
        }
    }
    // ratio of diameter of moon to that of sun
    if (rsun > 0)
        attr[1] = rmoon / rsun
    else
        attr[1] = 0;
    // eclipse magnitude:
    // fraction of solar diameter covered by moon
    lsun = swe_shim_asin(rsun / 2 * DEGTORAD) * 2;
    lsunleft = (-dctr + rsun + rmoon);
    if (lsun > 0) {
        attr[0] = lsunleft / rsun / 2;
    } else {
        attr[0] = 1;
    }
    // obscuration:
    // fraction of solar disc obscured by moon
    lsun = rsun;
    lmoon = rmoon;
    lctr = dctr;
    if (retc == 0 or lsun == 0) {
        attr[2] = 1;
    } else if (retc == SE_ECL_TOTAL or retc == SE_ECL_ANNULAR) {
        attr[2] = lmoon * lmoon / lsun / lsun;
    } else {
        a = 2 * lctr * lmoon;
        b = 2 * lctr * lsun;
        if (a < 1e-9) {
            attr[2] = lmoon * lmoon / lsun / lsun;
        } else {
            a = (lctr * lctr + lmoon * lmoon - lsun * lsun) / a;
            if (a > 1) a = 1;
            if (a < -1) a = -1;
            b = (lctr * lctr + lsun * lsun - lmoon * lmoon) / b;
            if (b > 1) b = 1;
            if (b < -1) b = -1;
            a = swe_shim_acos(a);
            b = swe_shim_acos(b);
            sc1 = a * lmoon * lmoon / 2;
            sc2 = b * lsun * lsun / 2;
            sc1 -= (swe_shim_cos(a) * swe_shim_sin(a)) * lmoon * lmoon / 2;
            sc2 -= (swe_shim_cos(b) * swe_shim_sin(b)) * lsun * lsun / 2;
            attr[2] = (sc1 + sc2) * 2 / PI / lsun / lsun;
        }
    }
    attr[7] = dctr;
    // approximate minimum height for visibility, considering
    // refraction and dip
    hmin_appr = -(34.4556 + (1.75 + 0.37) * @sqrt(geohgt)) / 60;
    if (xh[1] + rsun + @abs(hmin_appr) >= 0 and retc != 0)
        retc |= SE_ECL_VISIBLE; // eclipse visible
    // (USE_AZ_NAV = 0)
    attr[4] = xh[0]; // azimuth, from south, clockwise, via west
    attr[5] = xh[1]; // height
    attr[6] = xh[2]; // height
    if (ipl == SE_SUN and (starname == null or starname.?.len == 0 or starname.?[0] == 0)) {
        // magnitude of solar eclipse according to NASA
        attr[8] = attr[0]; // fraction of diameter occulted
        if ((retc & (SE_ECL_TOTAL | SE_ECL_ANNULAR)) != 0)
            attr[8] = attr[1]; // ratio between diameters of sun and moon
        // saros series and member
        var i: usize = 0;
        var j: i32 = undefined;
        var d: f64 = undefined;
        while (i < NSAROS_SOLAR) : (i += 1) {
            d = (tjd_ut - saros_data_solar[i].tstart) / SAROS_CYCLE;
            if (d < 0 and d * SAROS_CYCLE > -2) d = 0.0000001;
            if (d < 0) continue;
            j = @intFromFloat(d);
            if ((d - @as(f64, @floatFromInt(j))) * SAROS_CYCLE < 2) {
                attr[9] = @floatFromInt(saros_data_solar[i].series_no);
                attr[10] = @floatFromInt(j + 1);
                break;
            }
            const k = j + 1;
            if ((@as(f64, @floatFromInt(k)) - d) * SAROS_CYCLE < 2) {
                attr[9] = @floatFromInt(saros_data_solar[i].series_no);
                attr[10] = @floatFromInt(k + 1);
                break;
            }
        }
        if (i == NSAROS_SOLAR) {
            attr[9] = -99999999;
            attr[10] = -99999999;
        }
    }
    return retc;
}

/// swecl.c swe_sol_eclipse_where()
pub fn swe_sol_eclipse_where(
    tjd_ut: f64,
    ifl_in: i32,
    geopos: *[2]f64,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var dcore: [10]f64 = undefined;
    var ifl = ifl_in;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_ut, ifl, 0, serr, swed, dctx);
    const retflag = eclipse_where(tjd_ut, SE_SUN, null, ifl, geopos, &dcore, serr, swed, models, dctx, cctx);
    if (retflag < 0)
        return retflag;
    var attr10: [20]f64 = [_]f64{0} ** 20;
    const retflag2 = eclipse_how(tjd_ut, SE_SUN, null, ifl, geopos[0], geopos[1], 0, &attr10, serr, swed, models, dctx, cctx);
    if (retflag2 == lib.ERR)
        return retflag2;
    for (0..11) |i|
        attr[i] = attr10[i];
    attr[3] = dcore[0];
    return retflag;
}

/// swecl.c swe_lun_occult_where()
pub fn swe_lun_occult_where(
    tjd_ut: f64,
    ipl_in: i32,
    starname: ?[]u8,
    ifl_in: i32,
    geopos: *[2]f64,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var dcore: [10]f64 = undefined;
    var ipl = ipl_in;
    var ifl = ifl_in;
    if (ipl < 0) ipl = 0;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_ut, ifl, 0, serr, swed, dctx);
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    const retflag = eclipse_where(tjd_ut, ipl, starname, ifl, geopos, &dcore, serr, swed, models, dctx, cctx);
    if (retflag < 0)
        return retflag;
    var attr10: [20]f64 = [_]f64{0} ** 20;
    const retflag2 = eclipse_how(tjd_ut, ipl, starname, ifl, geopos[0], geopos[1], 0, &attr10, serr, swed, models, dctx, cctx);
    if (retflag2 == lib.ERR)
        return retflag2;
    for (0..11) |i|
        attr[i] = attr10[i];
    attr[3] = dcore[0];
    return retflag;
}

/// swecl.c swe_sol_eclipse_how()
pub fn swe_sol_eclipse_how(
    tjd_ut: f64,
    ifl_in: i32,
    geopos: *const [3]f64,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var dcore: [10]f64 = undefined;
    var ls: [6]f64 = undefined;
    var xaz: [6]f64 = undefined;
    var ifl = ifl_in;
    for (0..11) |i|
        attr[i] = 0;
    if (geopos[2] < SEI_ECL_GEOALT_MIN or geopos[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for eclipses must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_ut, ifl, 0, serr, swed, dctx);
    var attr10: [20]f64 = undefined;
    var retflag = eclipse_how(tjd_ut, SE_SUN, null, ifl, geopos[0], geopos[1], geopos[2], &attr10, serr, swed, models, dctx, cctx);
    if (retflag == lib.ERR)
        return lib.ERR;
    for (0..11) |i|
        attr[i] = attr10[i];
    var geopos2_2: [2]f64 = undefined;
    const retflag2 = eclipse_where(tjd_ut, SE_SUN, null, ifl, &geopos2_2, &dcore, serr, swed, models, dctx, cctx);
    if (retflag2 == lib.ERR)
        return retflag2;
    if (retflag != 0)
        retflag |= (retflag2 & (SE_ECL_CENTRAL | SE_ECL_NONCENTRAL));
    attr[3] = dcore[0];
    sweph.swe_set_topo(geopos[0], geopos[1], geopos[2], swed);
    if (sweph.swe_calc_ut(tjd_ut, SE_SUN, ifl | sweph.SEFLG_TOPOCTR | sweph.SEFLG_EQUATORIAL, &ls, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    swe_azalt(tjd_ut, SE_EQU2HOR, geopos, 0, 10, ls[0..3], xaz[0..3], swed, models, dctx, cctx);
    attr[4] = xaz[0];
    attr[5] = xaz[1];
    attr[6] = xaz[2];
    if (xaz[2] <= 0)
        retflag = 0;
    if (retflag == 0) {
        for (0..4) |i|
            attr[i] = 0;
        for (8..11) |i|
            attr[i] = 0;
    }
    return retflag;
}

pub const SE_ECL_ONE_TRY: i32 = 32 * 1024;

/// swecl.c swe_sol_eclipse_when_glob()
pub fn swe_sol_eclipse_when_glob(
    tjd_start: f64,
    ifl_in: i32,
    ifltype_in: i32,
    tret: *[10]f64,
    backward: bool,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var idx1: usize = 0;
    var idx2: usize = 0;
    var retflag: i32 = 0;
    var retflag2: i32 = 0;
    const de: f64 = 6378.140;
    var a: f64 = undefined;
    var t: f64 = undefined;
    var tt: f64 = undefined;
    var tjd: f64 = undefined;
    var tjds: f64 = undefined;
    var dt: f64 = undefined;
    var dtint: f64 = undefined;
    var dta: f64 = undefined;
    var dtb: f64 = undefined;
    var T: f64 = undefined;
    var T2: f64 = undefined;
    var T3: f64 = undefined;
    var T4: f64 = undefined;
    var K: f64 = undefined;
    var M: f64 = undefined;
    var Mm: f64 = undefined;
    var E: f64 = undefined;
    var Ff: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var rmoon: f64 = undefined;
    var rsun: f64 = undefined;
    var dcore: [10]f64 = undefined;
    var dc: [3]f64 = undefined;
    var dctr: f64 = undefined;
    const twohr: f64 = 2.0 / 24.0;
    const tenmin: f64 = 10.0 / 24.0 / 60.0;
    var dt1: f64 = 0;
    var dt2: f64 = 0;
    var geopos: [20]f64 = undefined;
    var attr: [20]f64 = undefined;
    var dtstart: f64 = undefined;
    var dtdiv: f64 = undefined;
    var xa: [6]f64 = undefined;
    var xb: [6]f64 = undefined;
    var direction: i32 = 1;
    var dont_times = false;
    var iflag: i32 = undefined;
    var iflagcart: i32 = undefined;
    var ifl = ifl_in;
    var ifltype = ifltype_in;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_start, ifl, 0, serr, swed, dctx);
    iflag = sweph.SEFLG_EQUATORIAL | ifl;
    iflagcart = iflag | sweph.SEFLG_XYZ;
    if (ifltype == (SE_ECL_PARTIAL | SE_ECL_CENTRAL)) {
        if (serr != null) {
            const msg = "central partial eclipses do not exist";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return lib.ERR;
    }
    if (ifltype == (SE_ECL_ANNULAR_TOTAL | SE_ECL_NONCENTRAL)) {
        if (serr != null) {
            const msg = "non-central hybrid (annular-total) eclipses do not exist";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return lib.ERR;
    }
    if (ifltype == 0)
        ifltype = SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_PARTIAL |
            SE_ECL_ANNULAR_TOTAL | SE_ECL_NONCENTRAL | SE_ECL_CENTRAL;
    if (ifltype == SE_ECL_TOTAL or ifltype == SE_ECL_ANNULAR or ifltype == SE_ECL_ANNULAR_TOTAL)
        ifltype |= (SE_ECL_NONCENTRAL | SE_ECL_CENTRAL);
    if (ifltype == SE_ECL_PARTIAL)
        ifltype |= SE_ECL_NONCENTRAL;
    if (backward)
        direction = -1;
    K = @trunc((tjd_start - lib.J2000) / 365.2425 * 12.3685);
    K -= @floatFromInt(direction);
    // next_try:
    while (true) {
        retflag = 0;
        dont_times = false;
        for (0..10) |i|
            tret[i] = 0;
        T = K / 1236.85;
        T2 = T * T;
        T3 = T2 * T;
        T4 = T3 * T;
        Ff = lib.swe_degnorm(160.7108 + 390.67050274 * K - 0.0016341 * T2 - 0.00000227 * T3 + 0.000000011 * T4);
        if (Ff > 180)
            Ff -= 180;
        if (Ff > 21 and Ff < 159) { // no eclipse possible
            K += @floatFromInt(direction);
            continue;
        }
        // approximate time of geocentric maximum eclipse
        // formula from Meeus, German, p. 381
        tjd = 2451550.09765 + 29.530588853 * K + 0.0001337 * T2 - 0.000000150 * T3 + 0.00000000073 * T4;
        M = lib.swe_degnorm(2.5534 + 29.10535669 * K - 0.0000218 * T2 - 0.00000011 * T3);
        Mm = lib.swe_degnorm(201.5643 + 385.81693528 * K + 0.1017438 * T2 + 0.00001239 * T3 + 0.000000058 * T4);
        E = 1 - 0.002516 * T - 0.0000074 * T2;
        M *= DEGTORAD;
        Mm *= DEGTORAD;
        tjd = tjd - 0.4075 * swe_shim_sin(Mm) + 0.1721 * E * swe_shim_sin(M);
        // time of maximum eclipse (if eclipse) =
        // minimum geocentric angle between sun and moon edges.
        dtstart = 1;
        if (tjd < 2000000 or tjd > 2500000)
            dtstart = 5;
        dtdiv = 4;
        dt = dtstart;
        while (dt > 0.0001) : (dt /= dtdiv) {
            var i: usize = 0;
            t = tjd - dt;
            while (i <= 2) : ({
                i += 1;
                t += dt;
            }) {
                if (sweph.swe_calc(t, SE_SUN, iflag, &ls, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                for (0..3) |m| {
                    xa[m] = xs[m] / ls[2];
                    xb[m] = xm[m] / lm[2];
                }
                dc[i] = swe_shim_acos(lib.swi_dot_prod_unit(xa[0..3], xb[0..3])) * RADTODEG;
                rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
                rsun = swe_shim_asin(RSUN / ls[2]) * RADTODEG;
                dc[i] -= (rmoon + rsun);
            }
            _ = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dctr);
            tjd += dtint + dt;
        }
        // C's swe_deltat_ex reads the moon-file denum live; refresh first
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tjds = tjd - deltat_mod.swe_deltat_ex(dctx, tjd, ifl);
        tjds = tjd - deltat_mod.swe_deltat_ex(dctx, tjds, ifl);
        tjds = tjd - deltat_mod.swe_deltat_ex(dctx, tjds, ifl);
        tjd = tjds;
        retflag = eclipse_where(tjd, SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR)
            return retflag;
        retflag2 = retflag;
        // in extreme cases _where() returns no eclipse, where there is
        // actually a very small one, therefore call _how() with the
        // coordinates returned by _where():
        retflag2 = eclipse_how(tjd, SE_SUN, null, ifl, geopos[0], geopos[1], 0, &attr, serr, swed, models, dctx, cctx);
        if (retflag2 == lib.ERR)
            return retflag2;
        if (retflag2 == 0) {
            K += @floatFromInt(direction);
            continue; // goto next_try
        }
        tret[0] = tjd;
        if ((backward and tret[0] >= tjd_start - 0.0001) or
            (!backward and tret[0] <= tjd_start + 0.0001))
        {
            K += @floatFromInt(direction);
            continue; // goto next_try
        }
        // eclipse type, SE_ECL_TOTAL, _ANNULAR, etc.
        // SE_ECL_ANNULAR_TOTAL will be discovered later
        retflag = eclipse_where(tjd, SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR)
            return retflag;
        if (retflag == 0) { // can happen with extremely small percentage
            retflag = SE_ECL_PARTIAL | SE_ECL_NONCENTRAL;
            tret[4] = tjd;
            tret[5] = tjd; // fix this ????
            dont_times = true;
        }
        // check whether or not eclipse type found is wanted
        // non central eclipse is wanted:
        if ((ifltype & SE_ECL_NONCENTRAL) == 0 and (retflag & SE_ECL_NONCENTRAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // central eclipse is wanted:
        if ((ifltype & SE_ECL_CENTRAL) == 0 and (retflag & SE_ECL_CENTRAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // non annular eclipse is wanted:
        if ((ifltype & SE_ECL_ANNULAR) == 0 and (retflag & SE_ECL_ANNULAR) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // non partial eclipse is wanted:
        if ((ifltype & SE_ECL_PARTIAL) == 0 and (retflag & SE_ECL_PARTIAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // annular-total eclipse will be discovered later
        if ((ifltype & (SE_ECL_TOTAL | SE_ECL_ANNULAR_TOTAL)) == 0 and (retflag & SE_ECL_TOTAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        if (dont_times)
            return retflag; // goto end_search_global
        // n = 0: times of eclipse begin and end
        // n = 1: times of totality begin and end
        // n = 2: times of center line begin and end
        var o: i32 = undefined;
        if ((retflag & SE_ECL_PARTIAL) != 0)
            o = 0
        else if ((retflag & SE_ECL_NONCENTRAL) != 0)
            o = 1
        else
            o = 2;
        dta = twohr;
        dtb = tenmin / 3.0;
        var n: i32 = 0;
        while (n <= o) : (n += 1) {
            if (n == 0) {
                idx1 = 2;
                idx2 = 3;
            } else if (n == 1) {
                if ((retflag & SE_ECL_PARTIAL) != 0)
                    continue;
                idx1 = 4;
                idx2 = 5;
            } else if (n == 2) {
                if ((retflag & SE_ECL_NONCENTRAL) != 0)
                    continue;
                idx1 = 6;
                idx2 = 7;
            }
            var i: usize = 0;
            t = tjd - dta;
            while (i <= 2) : ({
                i += 1;
                t += dta;
            }) {
                retflag2 = eclipse_where(t, SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
                if (retflag2 == lib.ERR)
                    return retflag2;
                if (n == 0)
                    dc[i] = dcore[4] / 2 + de / dcore[5] - dcore[2]
                else if (n == 1)
                    dc[i] = @abs(dcore[3]) / 2 + de / dcore[6] - dcore[2]
                else if (n == 2)
                    dc[i] = de / dcore[6] - dcore[2];
            }
            _ = find_zero(dc[0], dc[1], dc[2], dta, &dt1, &dt2);
            tret[idx1] = tjd + dt1 + dta;
            tret[idx2] = tjd + dt2 + dta;
            var m: i32 = 0;
            dt = dtb;
            while (m < 3) : ({
                m += 1;
                dt /= 3;
            }) {
                var j: usize = idx1;
                while (j <= idx2) : (j += (idx2 - idx1)) {
                    i = 0;
                    t = tret[j] - dt;
                    while (i < 2) : ({
                        i += 1;
                        t += dt;
                    }) {
                        retflag2 = eclipse_where(t, SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
                        if (retflag2 == lib.ERR)
                            return retflag2;
                        if (n == 0)
                            dc[i] = dcore[4] / 2 + de / dcore[5] - dcore[2]
                        else if (n == 1)
                            dc[i] = @abs(dcore[3]) / 2 + de / dcore[6] - dcore[2]
                        else if (n == 2)
                            dc[i] = de / dcore[6] - dcore[2];
                    }
                    dt1 = dc[1] / ((dc[1] - dc[0]) / dt);
                    tret[j] -= dt1;
                    if (idx1 == idx2) break;
                }
            }
        }
        // annular-total eclipses
        if ((retflag & SE_ECL_TOTAL) != 0) {
            retflag2 = eclipse_where(tret[0], SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[0] = dcore[0];
            retflag2 = eclipse_where(tret[4], SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[1] = dcore[0];
            retflag2 = eclipse_where(tret[5], SE_SUN, null, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[2] = dcore[0];
            // the maximum is always total, and there is either one or
            // two times before and after, when the core shadow becomes
            // zero and totality changes into annularity or vice versa.
            if (dc[0] * dc[1] < 0 or dc[0] * dc[2] < 0) {
                retflag |= SE_ECL_ANNULAR_TOTAL;
                retflag &= ~SE_ECL_TOTAL;
            }
        }
        // if eclipse is given but not wanted:
        if ((ifltype & SE_ECL_TOTAL) == 0 and (retflag & SE_ECL_TOTAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // if annular_total eclipse is given but not wanted:
        if ((ifltype & SE_ECL_ANNULAR_TOTAL) == 0 and (retflag & SE_ECL_ANNULAR_TOTAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // time of maximum eclipse at local apparent noon
        // first, find out, if there is a solar transit
        // between begin and end of eclipse
        const k: usize = 2;
        {
            var i: usize = 0;
            while (i < 2) : (i += 1) {
                const j = i + k;
                dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                dctx.jpldenum = swed.jpldenum;
                tt = tret[j] + deltat_mod.swe_deltat_ex(dctx, tret[j], ifl);
                if (sweph.swe_calc(tt, SE_SUN, iflag, &ls, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(tt, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dc[i] = lib.swe_degnorm(ls[0] - lm[0]);
                if (dc[i] > 180)
                    dc[i] -= 360;
            }
        }
        if (dc[0] * dc[1] >= 0) { // no transit
            tret[1] = 0;
        } else {
            tjd = tjds;
            dt = 0.1;
            dt1 = (tret[3] - tret[2]) / 2.0;
            if (dt1 < dt)
                dt = dt1 / 2.0;
            var j: i32 = 0;
            while (dt > 0.01) : ({
                j += 1;
                dt /= 3;
            }) {
                var i: usize = 0;
                t = tjd;
                while (i <= 1) : ({
                    i += 1;
                    t -= dt;
                }) {
                    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                    dctx.jpldenum = swed.jpldenum;
                    tt = t + deltat_mod.swe_deltat_ex(dctx, t, ifl);
                    if (sweph.swe_calc(tt, SE_SUN, iflag, &ls, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(tt, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    dc[i] = lib.swe_degnorm(ls[0] - lm[0]);
                    if (dc[i] > 180)
                        dc[i] -= 360;
                    if (dc[i] > 180)
                        dc[i] -= 360;
                }
                a = (dc[1] - dc[0]) / dt;
                if (a < 1e-10)
                    break;
                dt1 = dc[0] / a;
                tjd += dt1;
            }
            tret[1] = tjd;
        }
        return retflag; // end_search_global
    }
}

/// swecl.c swe_sol_eclipse_when_loc()
pub fn swe_sol_eclipse_when_loc(
    tjd_start: f64,
    ifl_in: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: bool,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var ifl = ifl_in;
    if (geopos[2] < SEI_ECL_GEOALT_MIN or geopos[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for eclipses must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_start, ifl, 0, serr, swed, dctx);
    var retflag = eclipse_when_loc(tjd_start, ifl, geopos, tret, attr, backward, serr, swed, models, dctx, cctx);
    if (retflag <= 0)
        return retflag;
    // diameter of core shadow
    var geopos2: [2]f64 = undefined;
    var dcore: [10]f64 = undefined;
    const retflag2 = eclipse_where(tret[0], SE_SUN, null, ifl, &geopos2, &dcore, serr, swed, models, dctx, cctx);
    if (retflag2 == lib.ERR)
        return retflag2;
    retflag |= (retflag2 & SE_ECL_NONCENTRAL);
    attr[3] = dcore[0];
    return retflag;
}

/// swecl.c eclipse_when_loc() — next solar eclipse at a given position.
/// C's goto next_try becomes a while loop with the same K mutations.
fn eclipse_when_loc(
    tjd_start: f64,
    ifl: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: bool,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var retflag: i32 = 0;
    var retc: i32 = undefined;
    var t: f64 = undefined;
    var tjd: f64 = undefined;
    var dt: f64 = undefined;
    var dtint: f64 = undefined;
    var K: f64 = undefined;
    var T: f64 = undefined;
    var T2: f64 = undefined;
    var T3: f64 = undefined;
    var T4: f64 = undefined;
    var F: f64 = undefined;
    var M: f64 = undefined;
    var Mm: f64 = undefined;
    var tjdr: f64 = undefined;
    var tjds: f64 = undefined;
    var E: f64 = undefined;
    var Ff: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var x1: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var dm: f64 = undefined;
    var ds: f64 = undefined;
    var rmoon: f64 = undefined;
    var rsun: f64 = undefined;
    var rsplusrm: f64 = undefined;
    var rsminusrm: f64 = undefined;
    var dc: [3]f64 = undefined;
    var dctr: f64 = undefined;
    var dctrmin: f64 = undefined;
    const twomin: f64 = 2.0 / 24.0 / 60.0;
    const tensec: f64 = 10.0 / 24.0 / 60.0 / 60.0;
    const twohr: f64 = 2.0 / 24.0;
    const tenmin: f64 = 10.0 / 24.0 / 60.0;
    var dt1: f64 = 0;
    var dt2: f64 = 0;
    var dtdiv: f64 = undefined;
    var dtstart: f64 = undefined;
    const iflag: i32 = sweph.SEFLG_EQUATORIAL | sweph.SEFLG_TOPOCTR | ifl;
    const iflagcart: i32 = iflag | sweph.SEFLG_XYZ;
    sweph.swe_set_topo(geopos[0], geopos[1], geopos[2], swed);
    K = @trunc((tjd_start - lib.J2000) / 365.2425 * 12.3685);
    if (backward)
        K += 1
    else
        K -= 1;
    // next_try:
    while (true) {
        T = K / 1236.85;
        T2 = T * T;
        T3 = T2 * T;
        T4 = T3 * T;
        Ff = lib.swe_degnorm(160.7108 + 390.67050274 * K - 0.0016341 * T2 - 0.00000227 * T3 + 0.000000011 * T4);
        F = Ff;
        if (Ff > 180)
            Ff -= 180;
        if (Ff > 21 and Ff < 159) { // no eclipse possible
            if (backward)
                K -= 1
            else
                K += 1;
            continue;
        }
        // approximate time of geocentric maximum eclipse.
        // formula from Meeus, German, p. 381
        tjd = 2451550.09765 + 29.530588853 * K + 0.0001337 * T2 - 0.000000150 * T3 + 0.00000000073 * T4;
        M = lib.swe_degnorm(2.5534 + 29.10535669 * K - 0.0000218 * T2 - 0.00000011 * T3);
        Mm = lib.swe_degnorm(201.5643 + 385.81693528 * K + 0.1017438 * T2 + 0.00001239 * T3 + 0.000000058 * T4);
        E = 1 - 0.002516 * T - 0.0000074 * T2;
        M *= DEGTORAD;
        Mm *= DEGTORAD;
        F *= DEGTORAD;
        tjd = tjd - 0.4075 * swe_shim_sin(Mm) + 0.1721 * E * swe_shim_sin(M);
        sweph.swe_set_topo(geopos[0], geopos[1], geopos[2], swed);
        dtdiv = 2;
        dtstart = 0.5;
        if (tjd < 1900000 or tjd > 2500000) // because above formula is not good (delta t?)
            dtstart = 2;
        dt = dtstart;
        while (dt > 0.00001) : (dt /= dtdiv) {
            if (dt < 0.1)
                dtdiv = 3;
            var i: usize = 0;
            t = tjd - dt;
            while (i <= 2) : ({
                i += 1;
                t += dt;
            }) {
                // this takes some time, but is necessary to avoid
                // missing an eclipse
                if (sweph.swe_calc(t, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_SUN, iflag, &ls, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dm = @sqrt(sweph.square_sum(&xm));
                ds = @sqrt(sweph.square_sum(&xs));
                for (0..3) |k| {
                    x1[k] = xs[k] / ds;
                    x2[k] = xm[k] / dm;
                }
                dc[i] = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
            }
            _ = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dctr);
            tjd += dtint + dt;
        }
        if (sweph.swe_calc(tjd, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_SUN, iflag, &ls, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        dctr = swe_shim_acos(lib.swi_dot_prod_unit(xs[0..3], xm[0..3])) * RADTODEG;
        rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
        rsun = swe_shim_asin(RSUN / ls[2]) * RADTODEG;
        rsplusrm = rsun + rmoon;
        rsminusrm = rsun - rmoon;
        if (dctr > rsplusrm) {
            if (backward)
                K -= 1
            else
                K += 1;
            continue;
        }
        // C's swe_deltat_ex reads the moon-file denum live; refresh first
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tret[0] = tjd - deltat_mod.swe_deltat_ex(dctx, tjd, ifl);
        tret[0] = tjd - deltat_mod.swe_deltat_ex(dctx, tret[0], ifl); // iteration!
        if ((backward and tret[0] >= tjd_start - 0.0001) or
            (!backward and tret[0] <= tjd_start + 0.0001))
        {
            if (backward)
                K -= 1
            else
                K += 1;
            continue;
        }
        if (dctr < rsminusrm)
            retflag = SE_ECL_ANNULAR
        else if (dctr < @abs(rsminusrm))
            retflag = SE_ECL_TOTAL
        else if (dctr <= rsplusrm)
            retflag = SE_ECL_PARTIAL;
        dctrmin = dctr;
        // contacts 2 and 3
        if (dctr > @abs(rsminusrm)) { // partial, no 2nd and 3rd contact
            tret[2] = 0;
            tret[3] = 0;
        } else {
            dc[1] = @abs(rsminusrm) - dctrmin;
            {
                var i: usize = 0;
                t = tjd - twomin;
                while (i <= 2) : ({
                    i += 2;
                    t = tjd + twomin;
                }) {
                    if (sweph.swe_calc(t, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    dm = @sqrt(sweph.square_sum(&xm));
                    ds = @sqrt(sweph.square_sum(&xs));
                    rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                    rmoon *= 0.99916; // better accuracy for 2nd/3rd contacts
                    rsun = swe_shim_asin(RSUN / ds) * RADTODEG;
                    rsminusrm = rsun - rmoon;
                    for (0..3) |k| {
                        x1[k] = xs[k] / ds;
                        x2[k] = xm[k] / dm;
                    }
                    dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                    dc[i] = @abs(rsminusrm) - dctr;
                }
            }
            _ = find_zero(dc[0], dc[1], dc[2], twomin, &dt1, &dt2);
            tret[2] = tjd + dt1 + twomin;
            tret[3] = tjd + dt2 + twomin;
            var m: i32 = 0;
            dt = tensec;
            while (m < 2) : ({
                m += 1;
                dt /= 10;
            }) {
                var j: usize = 2;
                while (j <= 3) : (j += 1) {
                    if (sweph.swe_calc(tret[j], SE_SUN, iflagcart | sweph.SEFLG_SPEED, &xs, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(tret[j], SE_MOON, iflagcart | sweph.SEFLG_SPEED, &xm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    var i: usize = 0;
                    while (i < 2) : (i += 1) {
                        if (i == 1) {
                            for (0..3) |k| {
                                xs[k] -= xs[k + 3] * dt;
                                xm[k] -= xm[k + 3] * dt;
                            }
                        }
                        dm = @sqrt(sweph.square_sum(&xm));
                        ds = @sqrt(sweph.square_sum(&xs));
                        rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                        rmoon *= 0.99916; // better accuracy for 2nd/3rd contacts
                        rsun = swe_shim_asin(RSUN / ds) * RADTODEG;
                        rsminusrm = rsun - rmoon;
                        for (0..3) |k| {
                            x1[k] = xs[k] / ds;
                            x2[k] = xm[k] / dm;
                        }
                        dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                        dc[i] = @abs(rsminusrm) - dctr;
                    }
                    dt1 = -dc[0] / ((dc[0] - dc[1]) / dt);
                    tret[j] += dt1;
                }
            }
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[2] -= deltat_mod.swe_deltat_ex(dctx, tret[2], ifl);
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[3] -= deltat_mod.swe_deltat_ex(dctx, tret[3], ifl);
        }
        // contacts 1 and 4
        dc[1] = rsplusrm - dctrmin;
        {
            var i: usize = 0;
            t = tjd - twohr;
            while (i <= 2) : ({
                i += 2;
                t = tjd + twohr;
            }) {
                if (sweph.swe_calc(t, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dm = @sqrt(sweph.square_sum(&xm));
                ds = @sqrt(sweph.square_sum(&xs));
                rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                rsun = swe_shim_asin(RSUN / ds) * RADTODEG;
                rsplusrm = rsun + rmoon;
                for (0..3) |k| {
                    x1[k] = xs[k] / ds;
                    x2[k] = xm[k] / dm;
                }
                dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                dc[i] = rsplusrm - dctr;
            }
        }
        _ = find_zero(dc[0], dc[1], dc[2], twohr, &dt1, &dt2);
        tret[1] = tjd + dt1 + twohr;
        tret[4] = tjd + dt2 + twohr;
        var m2: i32 = 0;
        dt = tenmin;
        while (m2 < 3) : ({
            m2 += 1;
            dt /= 10;
        }) {
            var j: usize = 1;
            while (j <= 4) : (j += 3) {
                if (sweph.swe_calc(tret[j], SE_SUN, iflagcart | sweph.SEFLG_SPEED, &xs, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(tret[j], SE_MOON, iflagcart | sweph.SEFLG_SPEED, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                var i: usize = 0;
                while (i < 2) : (i += 1) {
                    if (i == 1) {
                        for (0..3) |k| {
                            xs[k] -= xs[k + 3] * dt;
                            xm[k] -= xm[k + 3] * dt;
                        }
                    }
                    dm = @sqrt(sweph.square_sum(&xm));
                    ds = @sqrt(sweph.square_sum(&xs));
                    rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                    rsun = swe_shim_asin(RSUN / ds) * RADTODEG;
                    rsplusrm = rsun + rmoon;
                    for (0..3) |k| {
                        x1[k] = xs[k] / ds;
                        x2[k] = xm[k] / dm;
                    }
                    dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                    dc[i] = @abs(rsplusrm) - dctr;
                }
                dt1 = -dc[0] / ((dc[0] - dc[1]) / dt);
                tret[j] += dt1;
            }
        }
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tret[1] -= deltat_mod.swe_deltat_ex(dctx, tret[1], ifl);
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tret[4] -= deltat_mod.swe_deltat_ex(dctx, tret[4], ifl);
        // visibility of eclipse phases
        {
            var i: i32 = 4;
            while (i >= 0) : (i -= 1) { // attr for i = 0 must be kept !!!
                const iu: usize = @intCast(i);
                if (tret[iu] == 0)
                    continue;
                if (eclipse_how(tret[iu], SE_SUN, null, ifl, geopos[0], geopos[1], geopos[2], attr, serr, swed, models, dctx, cctx) == lib.ERR)
                    return lib.ERR;
                // (could be wrong for 1st/4th contact)
                if (attr[6] > 0) { // sun above horizon, using app. alt.
                    retflag |= SE_ECL_VISIBLE;
                    switch (i) {
                        0 => retflag |= SE_ECL_MAX_VISIBLE,
                        1 => retflag |= SE_ECL_1ST_VISIBLE,
                        2 => retflag |= SE_ECL_2ND_VISIBLE,
                        3 => retflag |= SE_ECL_3RD_VISIBLE,
                        4 => retflag |= SE_ECL_4TH_VISIBLE,
                        else => {},
                    }
                }
            }
        }
        // (C's #if 1 block: active)
        if ((retflag & SE_ECL_VISIBLE) == 0) {
            if (backward)
                K -= 1
            else
                K += 1;
            continue;
        }
        retc = swe_rise_trans(tret[1] - 0.001, SE_SUN, null, iflag, SE_CALC_RISE | SE_BIT_DISC_BOTTOM, geopos, 0, 0, &tjdr, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc == -2) // circumpolar sun
            return retflag;
        retc = swe_rise_trans(tret[1] - 0.001, SE_SUN, null, iflag, SE_CALC_SET | SE_BIT_DISC_BOTTOM, geopos, 0, 0, &tjds, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc == -2) // circumpolar sun
            return retflag;
        if (tjds < tret[1] or (tjds > tjdr and tjdr > tret[4])) {
            if (backward)
                K -= 1
            else
                K += 1;
            continue;
        }
        if (tjdr > tret[1] and tjdr < tret[4]) {
            tret[5] = tjdr;
            if ((retflag & SE_ECL_MAX_VISIBLE) == 0) {
                tret[0] = tjdr;
                retc = eclipse_how(tret[5], SE_SUN, null, ifl, geopos[0], geopos[1], geopos[2], attr, serr, swed, models, dctx, cctx);
                if (retc == lib.ERR)
                    return lib.ERR;
                retflag &= ~(SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_PARTIAL);
                retflag |= (retc & (SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_PARTIAL));
            }
        }
        if (tjds > tret[1] and tjds < tret[4]) {
            tret[6] = tjds;
            if ((retflag & SE_ECL_MAX_VISIBLE) == 0) {
                tret[0] = tjds;
                retc = eclipse_how(tret[6], SE_SUN, null, ifl, geopos[0], geopos[1], geopos[2], attr, serr, swed, models, dctx, cctx);
                if (retc == lib.ERR)
                    return lib.ERR;
                retflag &= ~(SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_PARTIAL);
                retflag |= (retc & (SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_PARTIAL));
            }
        }
        return retflag;
    }
}

/// swecl.c swe_lun_occult_when_glob() — next occultation anywhere on earth.
/// C's goto next_try becomes a while loop with the same t/tjd mutations.
pub fn swe_lun_occult_when_glob(
    tjd_start: f64,
    ipl_in: i32,
    starname: ?[]u8,
    ifl_in: i32,
    ifltype_in: i32,
    tret: *[10]f64,
    backward_in: i32,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var idx1: usize = undefined;
    var idx2: usize = undefined;
    var retflag: i32 = 0;
    var retflag2: i32 = 0;
    const de: f64 = 6378.140;
    var a: f64 = undefined;
    var t: f64 = undefined;
    var tt: f64 = undefined;
    var tjd: f64 = 0;
    var tjds: f64 = undefined;
    var dt: f64 = undefined;
    var dtint: f64 = undefined;
    var dta: f64 = undefined;
    var dtb: f64 = undefined;
    var drad: f64 = undefined;
    var dl: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var rmoon: f64 = undefined;
    var rsun: f64 = undefined;
    var dcore: [10]f64 = undefined;
    var dc: [20]f64 = undefined;
    var dctr: f64 = undefined;
    const twohr: f64 = 2.0 / 24.0;
    const tenmin: f64 = 10.0 / 24.0 / 60.0;
    var dt1: f64 = 0;
    var dt2: f64 = 0;
    const dadd2: f64 = 1;
    var geopos: [20]f64 = undefined;
    var dtstart: f64 = undefined;
    var dtdiv: f64 = undefined;
    var direction: i32 = 1;
    var ifltype2: i32 = undefined;
    var iflag: i32 = undefined;
    var iflagcart: i32 = undefined;
    var dont_times = false;
    var ipl = ipl_in;
    var ifl = ifl_in;
    var ifltype = ifltype_in;
    var backward = backward_in;
    const one_try = backward & SE_ECL_ONE_TRY;
    if (ipl < 0) ipl = 0;
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_start, ifl, 0, serr, swed, dctx);
    iflag = sweph.SEFLG_EQUATORIAL | ifl;
    iflagcart = iflag | sweph.SEFLG_XYZ;
    backward &= 1;
    // initializations
    if (ifltype == (SE_ECL_PARTIAL | SE_ECL_CENTRAL)) {
        if (serr != null) {
            const msg = "central partial eclipses do not exist";
            const n = @min(msg.len, serr.?.len);
            @memcpy(serr.?[0..n], msg[0..n]);
        }
        return lib.ERR;
    }
    if (ipl != SE_SUN) {
        ifltype2 = (ifltype & ~(SE_ECL_NONCENTRAL | SE_ECL_CENTRAL));
        if (ifltype2 == SE_ECL_ANNULAR or ifltype == SE_ECL_ANNULAR_TOTAL) {
            if (serr != null) {
                const sn: ?[]const u8 = starname;
                const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "annular occulation do not exist for object {d} {s}\n", .{ ipl, sn orelse "" }) catch "";
                if (r.len < serr.?.len) serr.?[r.len] = 0;
            }
            return lib.ERR;
        }
    }
    if (ipl != SE_SUN and (ifltype & (SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL)) != 0)
        ifltype &= ~(SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL);
    if (ifltype == 0) {
        ifltype = SE_ECL_TOTAL | SE_ECL_PARTIAL | SE_ECL_NONCENTRAL | SE_ECL_CENTRAL;
        if (ipl == SE_SUN)
            ifltype |= (SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL);
    }
    if ((ifltype & (SE_ECL_TOTAL | SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL)) != 0)
        ifltype |= (SE_ECL_NONCENTRAL | SE_ECL_CENTRAL);
    if ((ifltype & SE_ECL_PARTIAL) != 0)
        ifltype |= SE_ECL_NONCENTRAL;
    retflag = 0;
    for (0..10) |i|
        tret[i] = 0;
    if (backward != 0)
        direction = -1;
    t = tjd_start;
    tjd = t;
    var star2: [256]u8 = [_]u8{0} ** 256;
    var stararg: ?[]u8 = null;
    if (starname != null and starname.?.len > 0) {
        @memcpy(star2[0..starname.?.len], starname.?[0..starname.?.len]);
        // C's starname is an AS_MAXCH buffer mutated in place by swe_fixstar
        stararg = star2[0..255];
    }
    // next_try:
    while (true) {
        if (calc_planet_star(t, ipl, stararg, ifl, &ls, serr, swed, models, dctx) == lib.ERR)
            return lib.ERR;
        // fixed stars with an ecliptic latitude > 7 or < -7 cannot have
        // an occultation.
        if (@abs(ls[1]) > 7 and stararg != null and stararg.?.len > 0 and stararg.?[0] != 0) {
            if (serr != null) {
                const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "occultation never occurs: star {s} has ecl. lat. {d:.1}", .{ std.mem.sliceTo(stararg.?, 0), ls[1] }) catch "";
                if (r.len < serr.?.len) serr.?[r.len] = 0;
            }
            return lib.ERR;
        }
        if (sweph.swe_calc(t, SE_MOON, ifl, &lm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        dl = lib.swe_degnorm(ls[0] - lm[0]);
        if (direction < 0)
            dl -= 360;
        // get rough conjunction in ecliptic longitude
        while (@abs(dl) > 0.1) {
            t += dl / 13;
            if (calc_planet_star(t, ipl, stararg, ifl, &ls, serr, swed, models, dctx) == lib.ERR)
                return lib.ERR;
            if (sweph.swe_calc(t, SE_MOON, ifl, &lm, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            dl = lib.swe_degnorm(ls[0] - lm[0]);
            if (dl > 180) dl -= 360;
        }
        tjd = t;
        // difference in latitude too big for an occultation
        drad = @abs(ls[1] - lm[1]);
        if (drad > 2) {
            if (one_try != 0) {
                tret[0] = t + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
                return 0;
            }
            t += @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue; // goto next_try
        }
        // radius of planet disk in AU
        if (stararg != null and stararg.?.len > 0 and stararg.?[0] != 0)
            drad = 0
        else if (ipl >= 0 and @as(usize, @intCast(ipl)) < NDIAM_ECL)
            drad = pla_diam[@intCast(ipl)] / 2 / AUNIT
        else if (ipl > SE_AST_OFFSET)
            drad = swed.ast_diam / 2 * 1000 / AUNIT // km -> m -> AU
        else
            drad = 0;
        // time of maximum eclipse (if eclipse) =
        // minimum geocentric angle between moon and body edges.
        dtstart = dadd2; // originally 1
        dtdiv = 3;
        dt = dtstart;
        while (dt > 0.0001) : (dt /= dtdiv) {
            var i: usize = 0;
            t = tjd - dt;
            while (i <= 2) : ({
                i += 1;
                t += dt;
            }) {
                if (calc_planet_star(t, ipl, stararg, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (calc_planet_star(t, ipl, stararg, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dc[i] = swe_shim_acos(lib.swi_dot_prod_unit(xs[0..3], xm[0..3])) * RADTODEG;
                rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
                rsun = swe_shim_asin(drad / ls[2]) * RADTODEG;
                dc[i] -= (rmoon + rsun);
            }
            _ = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dctr);
            tjd += dtint + dt;
        }
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tjd -= deltat_mod.swe_deltat_ex(dctx, tjd, ifl);
        tjds = tjd;
        retflag = eclipse_where(tjd, ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR)
            return retflag;
        retflag2 = retflag;
        // (C's eclipse_how call is commented out)
        if (retflag2 == 0) {
            // only one try!
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue; // goto next_try
        }
        tret[0] = tjd;
        // should not happen anymore Version 2.01
        if ((backward != 0 and tret[0] >= tjd_start - 0.0001) or
            (backward == 0 and tret[0] <= tjd_start + 0.0001))
        {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue;
        }
        // eclipse type, SE_ECL_TOTAL, _ANNULAR, etc.
        retflag = eclipse_where(tjd, ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR)
            return retflag;
        if (retflag == 0) { // can happen with extremely small percentage
            retflag = SE_ECL_PARTIAL | SE_ECL_NONCENTRAL;
            tret[4] = tjd;
            tret[5] = tjd; // fix this ????
            dont_times = true;
        }
        // check whether or not eclipse type found is wanted
        if ((ifltype & SE_ECL_NONCENTRAL) == 0 and (retflag & SE_ECL_NONCENTRAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        if ((ifltype & SE_ECL_CENTRAL) == 0 and (retflag & SE_ECL_CENTRAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        if ((ifltype & SE_ECL_ANNULAR) == 0 and (retflag & SE_ECL_ANNULAR) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        if ((ifltype & SE_ECL_PARTIAL) == 0 and (retflag & SE_ECL_PARTIAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        if ((ifltype & (SE_ECL_TOTAL | SE_ECL_ANNULAR_TOTAL)) == 0 and (retflag & SE_ECL_TOTAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        if (dont_times)
            return retflag; // goto end_search_global
        // n = 0: times of eclipse begin and end
        // n = 1: times of totality begin and end
        // n = 2: times of center line begin and end
        var o: i32 = undefined;
        if ((retflag & SE_ECL_PARTIAL) != 0)
            o = 0
        else if ((retflag & SE_ECL_NONCENTRAL) != 0)
            o = 1
        else
            o = 2;
        dta = twohr;
        dtb = tenmin;
        var n: i32 = 0;
        while (n <= o) : (n += 1) {
            if (n == 0) {
                idx1 = 2;
                idx2 = 3;
            } else if (n == 1) {
                if ((retflag & SE_ECL_PARTIAL) != 0)
                    continue;
                idx1 = 4;
                idx2 = 5;
            } else if (n == 2) {
                if ((retflag & SE_ECL_NONCENTRAL) != 0)
                    continue;
                idx1 = 6;
                idx2 = 7;
            }
            var i: usize = 0;
            t = tjd - dta;
            while (i <= 2) : ({
                i += 1;
                t += dta;
            }) {
                retflag2 = eclipse_where(t, ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
                if (retflag2 == lib.ERR)
                    return retflag2;
                if (n == 0)
                    dc[i] = dcore[4] / 2 + de / dcore[5] - dcore[2]
                else if (n == 1)
                    dc[i] = @abs(dcore[3]) / 2 + de / dcore[6] - dcore[2]
                else if (n == 2)
                    dc[i] = de / dcore[6] - dcore[2];
            }
            _ = find_zero(dc[0], dc[1], dc[2], dta, &dt1, &dt2);
            tret[idx1] = tjd + dt1 + dta;
            tret[idx2] = tjd + dt2 + dta;
            var m: i32 = 0;
            dt = dtb;
            while (m < 3) : ({
                m += 1;
                dt /= 3;
            }) {
                var j: usize = idx1;
                while (j <= idx2) : (j += (idx2 - idx1)) {
                    i = 0;
                    t = tret[j] - dt;
                    while (i < 2) : ({
                        i += 1;
                        t += dt;
                    }) {
                        retflag2 = eclipse_where(t, ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
                        if (retflag2 == lib.ERR)
                            return retflag2;
                        if (n == 0)
                            dc[i] = dcore[4] / 2 + de / dcore[5] - dcore[2]
                        else if (n == 1)
                            dc[i] = @abs(dcore[3]) / 2 + de / dcore[6] - dcore[2]
                        else if (n == 2)
                            dc[i] = de / dcore[6] - dcore[2];
                    }
                    dt1 = dc[1] / ((dc[1] - dc[0]) / dt);
                    tret[j] -= dt1;
                    if (idx1 == idx2) break;
                }
            }
        }
        // annular-total eclipses
        if ((retflag & SE_ECL_TOTAL) != 0) {
            retflag2 = eclipse_where(tret[0], ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[0] = dcore[0];
            retflag2 = eclipse_where(tret[4], ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[1] = dcore[0];
            retflag2 = eclipse_where(tret[5], ipl, stararg, ifl, geopos[0..2], &dcore, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return retflag2;
            dc[2] = dcore[0];
            // the maximum is always total, and there is either one or
            // two times before and after, when the core shadow becomes
            // zero and totality changes into annularity or vice versa.
            if (dc[0] * dc[1] < 0 or dc[0] * dc[2] < 0) {
                retflag |= SE_ECL_ANNULAR_TOTAL;
                retflag &= ~SE_ECL_TOTAL;
            }
        }
        // if eclipse is given but not wanted:
        if ((ifltype & SE_ECL_TOTAL) == 0 and (retflag & SE_ECL_TOTAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        // if annular_total eclipse is given but not wanted:
        if ((ifltype & SE_ECL_ANNULAR_TOTAL) == 0 and (retflag & SE_ECL_ANNULAR_TOTAL) != 0) {
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            if (one_try != 0) {
                tret[0] = tjd;
                return 0;
            }
            tjd = t;
            continue;
        }
        // time of maximum eclipse at local apparent noon
        // first, find out, if there is a solar transit
        // between begin and end of eclipse
        const k: usize = 2;
        {
            var i: usize = 0;
            while (i < 2) : (i += 1) {
                const j = i + k;
                dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                dctx.jpldenum = swed.jpldenum;
                tt = tret[j] + deltat_mod.swe_deltat_ex(dctx, tret[j], ifl);
                if (calc_planet_star(tt, ipl, stararg, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(tt, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dc[i] = lib.swe_degnorm(ls[0] - lm[0]);
                if (dc[i] > 180)
                    dc[i] -= 360;
            }
        }
        if (dc[0] * dc[1] >= 0) { // no transit
            tret[1] = 0;
        } else {
            tjd = tjds;
            dt = 0.1;
            dt1 = (tret[3] - tret[2]) / 2.0;
            if (dt1 < dt)
                dt = dt1 / 2.0;
            var j: i32 = 0;
            while (dt > 0.01) : ({
                j += 1;
                dt /= 3;
            }) {
                var i: usize = 0;
                t = tjd;
                while (i <= 1) : ({
                    i += 1;
                    t -= dt;
                }) {
                    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
                    dctx.jpldenum = swed.jpldenum;
                    tt = t + deltat_mod.swe_deltat_ex(dctx, t, ifl);
                    if (calc_planet_star(tt, ipl, stararg, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(tt, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    dc[i] = lib.swe_degnorm(ls[0] - lm[0]);
                    if (dc[i] > 180)
                        dc[i] -= 360;
                    if (dc[i] > 180)
                        dc[i] -= 360;
                }
                a = (dc[1] - dc[0]) / dt;
                if (a < 1e-10)
                    break;
                dt1 = dc[0] / a;
                tjd += dt1;
            }
            tret[1] = tjd;
        }
        return retflag; // end_search_global
    }
}

pub const SE_ECL_OCC_BEG_DAYLIGHT: i32 = 8192;
pub const SE_ECL_OCC_END_DAYLIGHT: i32 = 16384;

/// swecl.c occult_when_loc() — next occultation at a given location.
/// C's goto next_try becomes a while loop with the same t/tjd mutations.
fn occult_when_loc(
    tjd_start: f64,
    ipl_in: i32,
    starname: ?[]u8,
    ifl: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward_in: i32,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var retflag: i32 = 0;
    var retc: i32 = undefined;
    var t: f64 = undefined;
    var tjd: f64 = undefined;
    var dt: f64 = undefined;
    var dtint: f64 = undefined;
    var tjdr: f64 = undefined;
    var tjds: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var ls: [6]f64 = undefined;
    var lm: [6]f64 = undefined;
    var x1: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var dm: f64 = undefined;
    var ds: f64 = undefined;
    var rmoon: f64 = undefined;
    var rsun: f64 = undefined;
    var rsplusrm: f64 = undefined;
    var rsminusrm: f64 = undefined;
    var dc: [20]f64 = undefined;
    var dctr: f64 = undefined;
    var dctrmin: f64 = undefined;
    const twomin: f64 = 2.0 / 24.0 / 60.0;
    const tensec: f64 = 10.0 / 24.0 / 60.0 / 60.0;
    const twohr: f64 = 2.0 / 24.0;
    const tenmin: f64 = 10.0 / 24.0 / 60.0;
    var dt1: f64 = 0;
    var dt2: f64 = 0;
    var dtdiv: f64 = undefined;
    var dtstart: f64 = undefined;
    const dadd2: f64 = 1;
    var drad: f64 = undefined;
    var dl: f64 = undefined;
    const iflag: i32 = sweph.SEFLG_TOPOCTR | ifl;
    const iflaggeo: i32 = iflag & ~sweph.SEFLG_TOPOCTR;
    const iflagcart: i32 = iflag | sweph.SEFLG_XYZ;
    var direction: i32 = 1;
    const one_try = backward_in & SE_ECL_ONE_TRY;
    var stop_after_this = false;
    var backward = backward_in;
    backward &= 1;
    retflag = 0;
    sweph.swe_set_topo(geopos[0], geopos[1], geopos[2], swed);
    for (0..10) |i|
        tret[i] = 0;
    if (backward != 0)
        direction = -1;
    t = tjd_start;
    tjd = tjd_start;
    var star2: [256]u8 = [_]u8{0} ** 256;
    var stararg: ?[]u8 = null;
    if (starname != null and starname.?.len > 0) {
        @memcpy(star2[0..starname.?.len], starname.?[0..starname.?.len]);
        stararg = star2[0..255];
    }
    var ipl = ipl_in;
    if (ipl < 0) ipl = 0;
    // next_try:
    outer: while (true) {
        if (calc_planet_star(t, ipl, stararg, iflaggeo, &ls, serr, swed, models, dctx) == lib.ERR)
            return lib.ERR;
        // fixed stars with an ecliptic latitude > 7 or < -7 cannot have
        // an occultation.
        if (@abs(ls[1]) > 7 and stararg != null and stararg.?.len > 0 and stararg.?[0] != 0) {
            if (serr != null) {
                const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "occultation never occurs: star {s} has ecl. lat. {d:.1}", .{ std.mem.sliceTo(stararg.?, 0), ls[1] }) catch "";
                if (r.len < serr.?.len) serr.?[r.len] = 0;
            }
            return lib.ERR;
        }
        if (sweph.swe_calc(t, SE_MOON, iflaggeo, &lm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        dl = lib.swe_degnorm(ls[0] - lm[0]);
        if (direction < 0)
            dl -= 360;
        // get rough conjunction in ecliptic longitude
        while (@abs(dl) > 0.1) {
            t += dl / 13;
            if (calc_planet_star(t, ipl, stararg, iflaggeo, &ls, serr, swed, models, dctx) == lib.ERR)
                return lib.ERR;
            if (sweph.swe_calc(t, SE_MOON, iflaggeo, &lm, swed, models, dctx, serr) == lib.ERR)
                return lib.ERR;
            dl = lib.swe_degnorm(ls[0] - lm[0]);
            if (dl > 180) dl -= 360;
        }
        tjd = t;
        // difference in latitude too big for an occultation
        drad = @abs(ls[1] - lm[1]);
        if (drad > 2) {
            if (one_try != 0) {
                tret[0] = t + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
                return 0;
            }
            t += @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue; // goto next_try
        }
        // radius of planet disk in AU
        if (stararg != null and stararg.?.len > 0 and stararg.?[0] != 0)
            drad = 0
        else if (ipl >= 0 and @as(usize, @intCast(ipl)) < NDIAM_ECL)
            drad = pla_diam[@intCast(ipl)] / 2 / AUNIT
        else if (ipl > SE_AST_OFFSET)
            drad = swed.ast_diam / 2 * 1000 / AUNIT // km -> m -> AU
        else
            drad = 0;
        // now find out, if there is an occultation at our geogr. location
        dtdiv = 2;
        dtstart = dadd2; // formerly 0.2
        dt = dtstart;
        while (dt > 0.00001) : (dt /= dtdiv) {
            if (dt < 0.01)
                dtdiv = 2;
            var i: usize = 0;
            t = tjd - dt;
            while (i <= 2) : ({
                i += 1;
                t += dt;
            }) {
                // this takes some time, but is necessary to avoid
                // missing an eclipse
                if (calc_planet_star(t, ipl, stararg, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (calc_planet_star(t, ipl, stararg, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (dt < 0.1 and @abs(ls[1] - lm[1]) > 2) {
                    if (one_try != 0 or stop_after_this) {
                        stop_after_this = true;
                    } else {
                        t = tjd + @as(f64, @floatFromInt(direction)) * 20;
                        tjd = t;
                        continue :outer; // goto next_try
                    }
                }
                dc[i] = swe_shim_acos(lib.swi_dot_prod_unit(xs[0..3], xm[0..3])) * RADTODEG;
                rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
                rsun = swe_shim_asin(drad / ls[2]) * RADTODEG;
                dc[i] -= (rmoon + rsun);
            }
            _ = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dctr);
            tjd += dtint + dt;
        }
        if (stop_after_this) { // has one_try = TRUE
            tret[0] = tjd + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
            return 0;
        }
        if (calc_planet_star(tjd, ipl, stararg, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
            return lib.ERR;
        if (calc_planet_star(tjd, ipl, stararg, iflag, &ls, serr, swed, models, dctx) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        if (sweph.swe_calc(tjd, SE_MOON, iflag, &lm, swed, models, dctx, serr) == lib.ERR)
            return lib.ERR;
        dctr = swe_shim_acos(lib.swi_dot_prod_unit(xs[0..3], xm[0..3])) * RADTODEG;
        rmoon = swe_shim_asin(RMOON / lm[2]) * RADTODEG;
        rsun = swe_shim_asin(drad / ls[2]) * RADTODEG;
        rsplusrm = rsun + rmoon;
        rsminusrm = rsun - rmoon;
        if (dctr > rsplusrm) {
            if (one_try != 0) {
                tret[0] = tjd + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
                return 0;
            }
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue; // goto next_try
        }
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tret[0] = tjd - deltat_mod.swe_deltat_ex(dctx, tjd, ifl);
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tret[0] = tjd - deltat_mod.swe_deltat_ex(dctx, tret[0], ifl);
        if ((backward != 0 and tret[0] >= tjd_start - 0.0001) or
            (backward == 0 and tret[0] <= tjd_start + 0.0001))
        {
            if (one_try != 0) {
                tret[0] = tjd + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
                return 0;
            }
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue;
        }
        if (dctr < rsminusrm)
            retflag = SE_ECL_ANNULAR
        else if (dctr < @abs(rsminusrm))
            retflag = SE_ECL_TOTAL
        else if (dctr <= rsplusrm)
            retflag = SE_ECL_PARTIAL;
        dctrmin = dctr;
        // contacts 2 and 3
        if (dctr > @abs(rsminusrm)) { // partial, no 2nd and 3rd contact
            tret[2] = 0;
            tret[3] = 0;
        } else {
            dc[1] = @abs(rsminusrm) - dctrmin;
            {
                var i: usize = 0;
                t = tjd - twomin;
                while (i <= 2) : ({
                    i += 2;
                    t = tjd + twomin;
                }) {
                    if (calc_planet_star(t, ipl, stararg, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    dm = @sqrt(sweph.square_sum(&xm));
                    ds = @sqrt(sweph.square_sum(&xs));
                    rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                    rmoon *= 0.99916; // better accuracy for 2nd/3rd contacts
                    rsun = swe_shim_asin(drad / ds) * RADTODEG;
                    rsminusrm = rsun - rmoon;
                    for (0..3) |k| {
                        x1[k] = xs[k] / ds;
                        x2[k] = xm[k] / dm;
                    }
                    dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                    dc[i] = @abs(rsminusrm) - dctr;
                }
            }
            _ = find_zero(dc[0], dc[1], dc[2], twomin, &dt1, &dt2);
            tret[2] = tjd + dt1 + twomin;
            tret[3] = tjd + dt2 + twomin;
            var m: i32 = 0;
            dt = tensec;
            while (m < 2) : ({
                m += 1;
                dt /= 10;
            }) {
                var j: usize = 2;
                while (j <= 3) : (j += 1) {
                    if (calc_planet_star(tret[j], ipl, stararg, iflagcart | sweph.SEFLG_SPEED, &xs, serr, swed, models, dctx) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(tret[j], SE_MOON, iflagcart | sweph.SEFLG_SPEED, &xm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    var i: usize = 0;
                    while (i < 2) : (i += 1) {
                        if (i == 1) {
                            for (0..3) |k| {
                                xs[k] -= xs[k + 3] * dt;
                                xm[k] -= xm[k + 3] * dt;
                            }
                        }
                        dm = @sqrt(sweph.square_sum(&xm));
                        ds = @sqrt(sweph.square_sum(&xs));
                        rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                        rmoon *= 0.99916; // better accuracy for 2nd/3rd contacts
                        rsun = swe_shim_asin(drad / ds) * RADTODEG;
                        rsminusrm = rsun - rmoon;
                        for (0..3) |k| {
                            x1[k] = xs[k] / ds;
                            x2[k] = xm[k] / dm;
                        }
                        dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                        dc[i] = @abs(rsminusrm) - dctr;
                    }
                    dt1 = -dc[0] / ((dc[0] - dc[1]) / dt);
                    tret[j] += dt1;
                }
            }
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[2] -= deltat_mod.swe_deltat_ex(dctx, tret[2], ifl);
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[3] -= deltat_mod.swe_deltat_ex(dctx, tret[3], ifl);
        }
        // contacts 1 and 4
        dc[1] = rsplusrm - dctrmin;
        if (stararg == null or stararg.?.len == 0 or stararg.?[0] == 0) {
            var i: usize = 0;
            t = tjd - twohr;
            while (i <= 2) : ({
                i += 2;
                t = tjd + twohr;
            }) {
                if (calc_planet_star(t, ipl, stararg, iflagcart, &xs, serr, swed, models, dctx) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                dm = @sqrt(sweph.square_sum(&xm));
                ds = @sqrt(sweph.square_sum(&xs));
                rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                rsun = swe_shim_asin(drad / ds) * RADTODEG;
                rsplusrm = rsun + rmoon;
                for (0..3) |k| {
                    x1[k] = xs[k] / ds;
                    x2[k] = xm[k] / dm;
                }
                dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                dc[i] = rsplusrm - dctr;
            }
            _ = find_zero(dc[0], dc[1], dc[2], twohr, &dt1, &dt2);
            tret[1] = tjd + dt1 + twohr;
            tret[4] = tjd + dt2 + twohr;
            var m2: i32 = 0;
            dt = tenmin;
            while (m2 < 3) : ({
                m2 += 1;
                dt /= 10;
            }) {
                var j: usize = 1;
                while (j <= 4) : (j += 3) {
                    if (calc_planet_star(tret[j], ipl, stararg, iflagcart | sweph.SEFLG_SPEED, &xs, serr, swed, models, dctx) == lib.ERR)
                        return lib.ERR;
                    if (sweph.swe_calc(tret[j], SE_MOON, iflagcart | sweph.SEFLG_SPEED, &xm, swed, models, dctx, serr) == lib.ERR)
                        return lib.ERR;
                    var ic: usize = 0;
                    while (ic < 2) : (ic += 1) {
                        if (ic == 1) {
                            for (0..3) |k| {
                                xs[k] -= xs[k + 3] * dt;
                                xm[k] -= xm[k + 3] * dt;
                            }
                        }
                        dm = @sqrt(sweph.square_sum(&xm));
                        ds = @sqrt(sweph.square_sum(&xs));
                        rmoon = swe_shim_asin(RMOON / dm) * RADTODEG;
                        rsun = swe_shim_asin(drad / ds) * RADTODEG;
                        rsplusrm = rsun + rmoon;
                        for (0..3) |k| {
                            x1[k] = xs[k] / ds;
                            x2[k] = xm[k] / dm;
                        }
                        dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
                        dc[ic] = @abs(rsplusrm) - dctr;
                    }
                    dt1 = -dc[0] / ((dc[0] - dc[1]) / dt);
                    tret[j] += dt1;
                }
            }
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[1] -= deltat_mod.swe_deltat_ex(dctx, tret[1], ifl);
            dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
            dctx.jpldenum = swed.jpldenum;
            tret[4] -= deltat_mod.swe_deltat_ex(dctx, tret[4], ifl);
        } else { // fixed stars are point sources, contacts 1 and 4 = contacts 2 and 3
            tret[1] = tret[2];
            tret[4] = tret[3];
        }
        // visibility of eclipse phases
        {
            var i: i32 = 4;
            while (i >= 0) : (i -= 1) { // attr for i = 0 must be kept !!!
                const iu: usize = @intCast(i);
                if (tret[iu] == 0)
                    continue;
                if (eclipse_how(tret[iu], ipl, stararg, ifl, geopos[0], geopos[1], geopos[2], attr, serr, swed, models, dctx, cctx) == lib.ERR)
                    return lib.ERR;
                // (could be wrong for 1st/4th contact)
                if (attr[6] > 0) { // sun above horizon (using app. alt.)
                    retflag |= SE_ECL_VISIBLE;
                    switch (i) {
                        0 => retflag |= SE_ECL_MAX_VISIBLE,
                        1 => retflag |= SE_ECL_1ST_VISIBLE,
                        2 => retflag |= SE_ECL_2ND_VISIBLE,
                        3 => retflag |= SE_ECL_3RD_VISIBLE,
                        4 => retflag |= SE_ECL_4TH_VISIBLE,
                        else => {},
                    }
                }
            }
        }
        // (C's #if 1 block: active)
        if ((retflag & SE_ECL_VISIBLE) == 0) {
            if (one_try != 0) {
                tret[0] = tjd + @as(f64, @floatFromInt(direction)); // return a date suitable for next try
                return 0;
            }
            t = tjd + @as(f64, @floatFromInt(direction)) * 20;
            tjd = t;
            continue;
        }
        retc = swe_rise_trans(tret[1] - 0.1, ipl, stararg, iflag, SE_CALC_RISE | SE_BIT_DISC_BOTTOM, geopos, 0, 0, &tjdr, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc >= 0) {
            retc = swe_rise_trans(tret[1] - 0.1, ipl, stararg, iflag, SE_CALC_SET | SE_BIT_DISC_BOTTOM, geopos, 0, 0, &tjds, serr, swed, models, dctx, cctx);
            if (retc == lib.ERR)
                return lib.ERR;
        }
        if (retc >= 0) {
            if (tjdr > tret[1] and tjdr < tret[4])
                tret[5] = tjdr;
            if (tjds > tret[1] and tjds < tret[4])
                tret[6] = tjds;
        }
        // note, circumpolar sun above horizon is not tested
        retc = swe_rise_trans(tret[1], SE_SUN, null, iflag, SE_CALC_RISE, geopos, 0, 0, &tjdr, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc >= 0) {
            retc = swe_rise_trans(tret[1], SE_SUN, null, iflag, SE_CALC_SET, geopos, 0, 0, &tjds, serr, swed, models, dctx, cctx);
            if (retc == lib.ERR)
                return lib.ERR;
            if (retc >= 0) {
                if (tjds < tjdr)
                    retflag |= SE_ECL_OCC_BEG_DAYLIGHT;
            }
        }
        retc = swe_rise_trans(tret[4], SE_SUN, null, iflag, SE_CALC_RISE, geopos, 0, 0, &tjdr, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc >= 0) {
            retc = swe_rise_trans(tret[4], SE_SUN, null, iflag, SE_CALC_SET, geopos, 0, 0, &tjds, serr, swed, models, dctx, cctx);
            if (retc == lib.ERR)
                return lib.ERR;
            if (retc >= 0) {
                if (tjds < tjdr)
                    retflag |= SE_ECL_OCC_END_DAYLIGHT;
            }
        }
        return retflag;
    }
}

/// swecl.c swe_lun_occult_when_loc()
pub fn swe_lun_occult_when_loc(
    tjd_start: f64,
    ipl_in: i32,
    starname: ?[]u8,
    ifl_in: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: i32,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var ipl = ipl_in;
    var ifl = ifl_in;
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (geopos[2] < SEI_ECL_GEOALT_MIN or geopos[2] > SEI_ECL_GEOALT_MAX) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for occultations must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    if (ipl < 0) ipl = 0;
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_start, ifl, 0, serr, swed, dctx);
    var retflag = occult_when_loc(tjd_start, ipl, starname, ifl, geopos, tret, attr, backward, serr, swed, models, dctx, cctx);
    if (retflag <= 0)
        return retflag;
    // diameter of core shadow
    var geopos2: [2]f64 = undefined;
    var dcore: [10]f64 = undefined;
    const retflag2 = eclipse_where(tret[0], ipl, starname, ifl, &geopos2, &dcore, serr, swed, models, dctx, cctx);
    if (retflag2 == lib.ERR)
        return retflag2;
    retflag |= (retflag2 & SE_ECL_NONCENTRAL);
    attr[3] = dcore[0];
    return retflag;
}

pub const SE_ECL_PENUMBRAL: i32 = 64;
pub const SE_ECL_PARTBEG_VISIBLE: i32 = 512;
pub const SE_ECL_TOTBEG_VISIBLE: i32 = 1024;
pub const SE_ECL_TOTEND_VISIBLE: i32 = 2048;
pub const SE_ECL_PARTEND_VISIBLE: i32 = 4096;
pub const SE_ECL_PENUMBBEG_VISIBLE: i32 = 8192;
pub const SE_ECL_PENUMBEND_VISIBLE: i32 = 16384;
pub const SE_ECL_ALLTYPES_LUNAR: i32 = SE_ECL_TOTAL | SE_ECL_PARTIAL | SE_ECL_PENUMBRAL;

// swecl.c saros_data_lunar (transcribed verbatim from the C table)
const NSAROS_LUNAR: usize = 180;
const saros_data_lunar = [NSAROS_LUNAR]struct { series_no: i32, tstart: f64 }{
    .{ .series_no = 1, .tstart = 782437.5 },    .{ .series_no = 2, .tstart = 799593.5 },    .{ .series_no = 3, .tstart = 783824.5 },
    .{ .series_no = 4, .tstart = 754884.5 },    .{ .series_no = 5, .tstart = 824724.5 },    .{ .series_no = 6, .tstart = 762857.5 },
    .{ .series_no = 7, .tstart = 773430.5 },    .{ .series_no = 8, .tstart = 810343.5 },    .{ .series_no = 9, .tstart = 807743.5 },
    .{ .series_no = 10, .tstart = 824901.5 },   .{ .series_no = 11, .tstart = 855229.5 },   .{ .series_no = 12, .tstart = 859215.5 },
    .{ .series_no = 13, .tstart = 876373.5 },   .{ .series_no = 14, .tstart = 906701.5 },   .{ .series_no = 15, .tstart = 910687.5 },
    .{ .series_no = 16, .tstart = 927845.5 },   .{ .series_no = 17, .tstart = 958173.5 },   .{ .series_no = 18, .tstart = 962159.5 },
    .{ .series_no = 19, .tstart = 979317.5 },   .{ .series_no = 20, .tstart = 1009645.5 },  .{ .series_no = 21, .tstart = 1007046.5 },
    .{ .series_no = 22, .tstart = 1017618.5 },  .{ .series_no = 23, .tstart = 1054531.5 },  .{ .series_no = 24, .tstart = 979493.5 },
    .{ .series_no = 25, .tstart = 976895.5 },   .{ .series_no = 26, .tstart = 1020394.5 },  .{ .series_no = 27, .tstart = 1017794.5 },
    .{ .series_no = 28, .tstart = 1028367.5 },  .{ .series_no = 29, .tstart = 1058695.5 },  .{ .series_no = 30, .tstart = 1062681.5 },
    .{ .series_no = 31, .tstart = 1073253.5 },  .{ .series_no = 32, .tstart = 1110167.5 },  .{ .series_no = 33, .tstart = 1114153.5 },
    .{ .series_no = 34, .tstart = 1131311.5 },  .{ .series_no = 35, .tstart = 1161639.5 },  .{ .series_no = 36, .tstart = 1165625.5 },
    .{ .series_no = 37, .tstart = 1176197.5 },  .{ .series_no = 38, .tstart = 1213111.5 },  .{ .series_no = 39, .tstart = 1217097.5 },
    .{ .series_no = 40, .tstart = 1221084.5 },  .{ .series_no = 41, .tstart = 1257997.5 },  .{ .series_no = 42, .tstart = 1255398.5 },
    .{ .series_no = 43, .tstart = 1186946.5 },  .{ .series_no = 44, .tstart = 1283128.5 },  .{ .series_no = 45, .tstart = 1227845.5 },
    .{ .series_no = 46, .tstart = 1225247.5 },  .{ .series_no = 47, .tstart = 1255575.5 },  .{ .series_no = 48, .tstart = 1272732.5 },
    .{ .series_no = 49, .tstart = 1276719.5 },  .{ .series_no = 50, .tstart = 1307047.5 },  .{ .series_no = 51, .tstart = 1317619.5 },
    .{ .series_no = 52, .tstart = 1328191.5 },  .{ .series_no = 53, .tstart = 1358519.5 },  .{ .series_no = 54, .tstart = 1375676.5 },
    .{ .series_no = 55, .tstart = 1379663.5 },  .{ .series_no = 56, .tstart = 1409991.5 },  .{ .series_no = 57, .tstart = 1420562.5 },
    .{ .series_no = 58, .tstart = 1424549.5 },  .{ .series_no = 59, .tstart = 1461463.5 },  .{ .series_no = 60, .tstart = 1465449.5 },
    .{ .series_no = 61, .tstart = 1436509.5 },  .{ .series_no = 62, .tstart = 1493179.5 },  .{ .series_no = 63, .tstart = 1457653.5 },
    .{ .series_no = 64, .tstart = 1435298.5 },  .{ .series_no = 65, .tstart = 1452456.5 },  .{ .series_no = 66, .tstart = 1476198.5 },
    .{ .series_no = 67, .tstart = 1480184.5 },  .{ .series_no = 68, .tstart = 1503928.5 },  .{ .series_no = 69, .tstart = 1527670.5 },
    .{ .series_no = 70, .tstart = 1531656.5 },  .{ .series_no = 71, .tstart = 1548814.5 },  .{ .series_no = 72, .tstart = 1579142.5 },
    .{ .series_no = 73, .tstart = 1583128.5 },  .{ .series_no = 74, .tstart = 1600286.5 },  .{ .series_no = 75, .tstart = 1624028.5 },
    .{ .series_no = 76, .tstart = 1628015.5 },  .{ .series_no = 77, .tstart = 1651758.5 },  .{ .series_no = 78, .tstart = 1675500.5 },
    .{ .series_no = 79, .tstart = 1672901.5 },  .{ .series_no = 80, .tstart = 1683474.5 },  .{ .series_no = 81, .tstart = 1713801.5 },
    .{ .series_no = 82, .tstart = 1645349.5 },  .{ .series_no = 83, .tstart = 1649336.5 },  .{ .series_no = 84, .tstart = 1686249.5 },
    .{ .series_no = 85, .tstart = 1683650.5 },  .{ .series_no = 86, .tstart = 1694222.5 },  .{ .series_no = 87, .tstart = 1731136.5 },
    .{ .series_no = 88, .tstart = 1735122.5 },  .{ .series_no = 89, .tstart = 1745694.5 },  .{ .series_no = 90, .tstart = 1776022.5 },
    .{ .series_no = 91, .tstart = 1786594.5 },  .{ .series_no = 92, .tstart = 1797166.5 },  .{ .series_no = 93, .tstart = 1827494.5 },
    .{ .series_no = 94, .tstart = 1838066.5 },  .{ .series_no = 95, .tstart = 1848638.5 },  .{ .series_no = 96, .tstart = 1878966.5 },
    .{ .series_no = 97, .tstart = 1882952.5 },  .{ .series_no = 98, .tstart = 1880354.5 },  .{ .series_no = 99, .tstart = 1923853.5 },
    .{ .series_no = 100, .tstart = 1881741.5 }, .{ .series_no = 101, .tstart = 1852801.5 }, .{ .series_no = 102, .tstart = 1889715.5 },
    .{ .series_no = 103, .tstart = 1893701.5 }, .{ .series_no = 104, .tstart = 1897688.5 }, .{ .series_no = 105, .tstart = 1928016.5 },
    .{ .series_no = 106, .tstart = 1938588.5 }, .{ .series_no = 107, .tstart = 1942575.5 }, .{ .series_no = 108, .tstart = 1972903.5 },
    .{ .series_no = 109, .tstart = 1990059.5 }, .{ .series_no = 110, .tstart = 1994046.5 }, .{ .series_no = 111, .tstart = 2024375.5 },
    .{ .series_no = 112, .tstart = 2034946.5 }, .{ .series_no = 113, .tstart = 2045518.5 }, .{ .series_no = 114, .tstart = 2075847.5 },
    .{ .series_no = 115, .tstart = 2086418.5 }, .{ .series_no = 116, .tstart = 2083820.5 }, .{ .series_no = 117, .tstart = 2120733.5 },
    .{ .series_no = 118, .tstart = 2124719.5 }, .{ .series_no = 119, .tstart = 2062852.5 }, .{ .series_no = 120, .tstart = 2086596.5 },
    .{ .series_no = 121, .tstart = 2103752.5 }, .{ .series_no = 122, .tstart = 2094568.5 }, .{ .series_no = 123, .tstart = 2118311.5 },
    .{ .series_no = 124, .tstart = 2142054.5 }, .{ .series_no = 125, .tstart = 2146040.5 }, .{ .series_no = 126, .tstart = 2169783.5 },
    .{ .series_no = 127, .tstart = 2186940.5 }, .{ .series_no = 128, .tstart = 2197512.5 }, .{ .series_no = 129, .tstart = 2214670.5 },
    .{ .series_no = 130, .tstart = 2238412.5 }, .{ .series_no = 131, .tstart = 2242398.5 }, .{ .series_no = 132, .tstart = 2266142.5 },
    .{ .series_no = 133, .tstart = 2289884.5 }, .{ .series_no = 134, .tstart = 2287285.5 }, .{ .series_no = 135, .tstart = 2311028.5 },
    .{ .series_no = 136, .tstart = 2334770.5 }, .{ .series_no = 137, .tstart = 2292659.5 }, .{ .series_no = 138, .tstart = 2276890.5 },
    .{ .series_no = 139, .tstart = 2326974.5 }, .{ .series_no = 140, .tstart = 2304619.5 }, .{ .series_no = 141, .tstart = 2308606.5 },
    .{ .series_no = 142, .tstart = 2345520.5 }, .{ .series_no = 143, .tstart = 2349506.5 }, .{ .series_no = 144, .tstart = 2360078.5 },
    .{ .series_no = 145, .tstart = 2390406.5 }, .{ .series_no = 146, .tstart = 2394392.5 }, .{ .series_no = 147, .tstart = 2411550.5 },
    .{ .series_no = 148, .tstart = 2441878.5 }, .{ .series_no = 149, .tstart = 2445864.5 }, .{ .series_no = 150, .tstart = 2456437.5 },
    .{ .series_no = 151, .tstart = 2486765.5 }, .{ .series_no = 152, .tstart = 2490751.5 }, .{ .series_no = 153, .tstart = 2501323.5 },
    .{ .series_no = 154, .tstart = 2538236.5 }, .{ .series_no = 155, .tstart = 2529052.5 }, .{ .series_no = 156, .tstart = 2473771.5 },
    .{ .series_no = 157, .tstart = 2563367.5 }, .{ .series_no = 158, .tstart = 2508085.5 }, .{ .series_no = 159, .tstart = 2505486.5 },
    .{ .series_no = 160, .tstart = 2542400.5 }, .{ .series_no = 161, .tstart = 2546386.5 }, .{ .series_no = 162, .tstart = 2556958.5 },
    .{ .series_no = 163, .tstart = 2587287.5 }, .{ .series_no = 164, .tstart = 2597858.5 }, .{ .series_no = 165, .tstart = 2601845.5 },
    .{ .series_no = 166, .tstart = 2632173.5 }, .{ .series_no = 167, .tstart = 2649330.5 }, .{ .series_no = 168, .tstart = 2653317.5 },
    .{ .series_no = 169, .tstart = 2683645.5 }, .{ .series_no = 170, .tstart = 2694217.5 }, .{ .series_no = 171, .tstart = 2698203.5 },
    .{ .series_no = 172, .tstart = 2728532.5 }, .{ .series_no = 173, .tstart = 2739103.5 }, .{ .series_no = 174, .tstart = 2683822.5 },
    .{ .series_no = 175, .tstart = 2740492.5 }, .{ .series_no = 176, .tstart = 2724722.5 }, .{ .series_no = 177, .tstart = 2708952.5 },
    .{ .series_no = 178, .tstart = 2732695.5 }, .{ .series_no = 179, .tstart = 2749852.5 }, .{ .series_no = 180, .tstart = 2753839.5 },
};

/// swecl.c lun_eclipse_how() — lunar eclipse attributes
fn lun_eclipse_how(
    tjd_ut: f64,
    ifl: i32,
    attr: ?*[20]f64,
    dcore: *[10]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32 {
    var retc: i32 = 0;
    var e: [6]f64 = undefined;
    var rm: [6]f64 = undefined;
    var rs: [6]f64 = undefined;
    var dsm: f64 = undefined;
    var d0: f64 = undefined;
    var D0: f64 = undefined;
    var s0: f64 = undefined;
    var r0: f64 = undefined;
    var ds: f64 = undefined;
    var dm: f64 = undefined;
    var dctr: f64 = undefined;
    var x1: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var f1: f64 = undefined;
    var f2: f64 = undefined;
    var deltat: f64 = undefined;
    var tjd: f64 = undefined;
    var d: f64 = undefined;
    var cosf1: f64 = undefined;
    var cosf2: f64 = undefined;
    const rmoon: f64 = RMOON;
    const dmoon: f64 = 2 * rmoon;
    var iflag: i32 = undefined;
    for (0..10) |i|
        dcore[i] = 0;
    if (attr != null) {
        for (0..20) |i|
            attr.?[i] = 0;
    }
    // nutation need not be in lunar and solar positions,
    // if mean sidereal time will be used
    iflag = sweph.SEFLG_SPEED | sweph.SEFLG_EQUATORIAL | ifl;
    iflag = iflag | sweph.SEFLG_XYZ;
    dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    deltat = deltat_mod.swe_deltat_ex(dctx, tjd_ut, ifl);
    tjd = tjd_ut + deltat;
    // moon in cartesian coordinates
    if (sweph.swe_calc(tjd, SE_MOON, iflag, &rm, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    // distance of moon from geocenter
    dm = @sqrt(sweph.square_sum(&rm));
    // sun in cartesian coordinates
    if (sweph.swe_calc(tjd, SE_SUN, iflag, &rs, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    // distance of sun from geocenter
    ds = @sqrt(sweph.square_sum(&rs));
    for (0..3) |i| {
        x1[i] = rs[i] / ds;
        x2[i] = rm[i] / dm;
    }
    dctr = swe_shim_acos(lib.swi_dot_prod_unit(x1[0..3], x2[0..3])) * RADTODEG;
    // selenocentric sun
    for (0..3) |i|
        rs[i] -= rm[i];
    // selenocentric earth
    for (0..3) |i|
        rm[i] = -rm[i];
    // sun - earth vector
    for (0..3) |i|
        e[i] = (rm[i] - rs[i]);
    // distance sun - earth
    dsm = @sqrt(sweph.square_sum(&e));
    // sun - earth unit vector
    for (0..3) |i|
        e[i] /= dsm;
    f1 = ((RSUN - REARTH) / dsm);
    cosf1 = @sqrt(1 - f1 * f1);
    f2 = ((RSUN + REARTH) / dsm);
    cosf2 = @sqrt(1 - f2 * f2);
    // distance of earth from fundamental plane
    s0 = -sweph.dot_prod(rm[0..3], e[0..3]);
    // distance of shadow axis from selenocenter
    r0 = @sqrt(dm * dm - s0 * s0);
    // diameter of core shadow on fundamental plane
    // (one 50th is added for effect of atmosphere, AA98, L4)
    d0 = @abs(s0 / dsm * (DSUN - DEARTH) - DEARTH) * (1 + 1.0 / 50.0) / cosf1;
    // diameter of half-shadow on fundamental plane
    D0 = (s0 / dsm * (DSUN + DEARTH) + DEARTH) * (1 + 1.0 / 50.0) / cosf2;
    d0 /= cosf1;
    D0 /= cosf2;
    // for better agreement with NASA:
    d0 *= 0.99405;
    D0 *= 0.98813;
    dcore[0] = r0;
    dcore[1] = d0;
    dcore[2] = D0;
    dcore[3] = cosf1;
    dcore[4] = cosf2;
    // phase and umbral magnitude
    retc = 0;
    if (d0 / 2 >= r0 + rmoon / cosf1) {
        retc = SE_ECL_TOTAL;
        if (attr != null) attr.?[0] = (d0 / 2 - r0 + rmoon) / dmoon;
    } else if (d0 / 2 >= r0 - rmoon / cosf1) {
        retc = SE_ECL_PARTIAL;
        if (attr != null) attr.?[0] = (d0 / 2 - r0 + rmoon) / dmoon;
    } else if (D0 / 2 >= r0 - rmoon / cosf2) {
        retc = SE_ECL_PENUMBRAL;
        if (attr != null) attr.?[0] = 0;
    } else {
        if (serr != null) {
            const r2 = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "no lunar eclipse at tjd = {d:.6}", .{tjd}) catch "";
            if (r2.len < serr.?.len) serr.?[r2.len] = 0;
        }
    }
    if (attr != null) attr.?[8] = attr.?[0];
    // penumbral magnitude
    if (attr != null) {
        attr.?[1] = (D0 / 2 - r0 + rmoon) / dmoon;
        if (retc != 0)
            attr.?[7] = 180 - @abs(dctr);
        // saros series and member
        var i: usize = 0;
        var j: i32 = undefined;
        while (i < NSAROS_LUNAR) : (i += 1) {
            d = (tjd_ut - saros_data_lunar[i].tstart) / SAROS_CYCLE;
            if (d < 0 and d * SAROS_CYCLE > -2) d = 0.0000001;
            if (d < 0) continue;
            j = @intFromFloat(d);
            if ((d - @as(f64, @floatFromInt(j))) * SAROS_CYCLE < 2) {
                attr.?[9] = @floatFromInt(saros_data_lunar[i].series_no);
                attr.?[10] = @floatFromInt(j + 1);
                break;
            }
            const k = j + 1;
            if ((@as(f64, @floatFromInt(k)) - d) * SAROS_CYCLE < 2) {
                attr.?[9] = @floatFromInt(saros_data_lunar[i].series_no);
                attr.?[10] = @floatFromInt(k + 1);
                break;
            }
        }
        if (i == NSAROS_LUNAR) {
            attr.?[9] = -99999999;
            attr.?[10] = -99999999;
        }
    }
    return retc;
}

/// swecl.c swe_lun_eclipse_how()
pub fn swe_lun_eclipse_how(
    tjd_ut: f64,
    ifl_in: i32,
    geopos: ?*[3]f64,
    attr: *[20]f64,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var dcore: [10]f64 = undefined;
    var lm: [6]f64 = undefined;
    var xaz: [6]f64 = undefined;
    var ifl = ifl_in;
    // attention: geopos[] is not used so far; may be NULL
    if (geopos != null and (geopos.?[2] < SEI_ECL_GEOALT_MIN or geopos.?[2] > SEI_ECL_GEOALT_MAX)) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for eclipses must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    ifl = ifl & ~sweph.SEFLG_TOPOCTR;
    ifl &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    _ = sweph.swiSetTidAcc(tjd_ut, ifl, 0, serr, swed, dctx);
    const retc = lun_eclipse_how(tjd_ut, ifl, attr, &dcore, serr, swed, models, dctx);
    if (geopos == null) {
        return retc;
    }
    // azimuth and altitude of moon
    sweph.swe_set_topo(geopos.?[0], geopos.?[1], geopos.?[2], swed);
    if (sweph.swe_calc_ut(tjd_ut, SE_MOON, ifl | sweph.SEFLG_TOPOCTR | sweph.SEFLG_EQUATORIAL, &lm, swed, models, dctx, serr) == lib.ERR)
        return lib.ERR;
    swe_azalt(tjd_ut, SE_EQU2HOR, geopos.?, 0, 10, lm[0..3], xaz[0..3], swed, models, dctx, cctx);
    attr[4] = xaz[0];
    attr[5] = xaz[1];
    attr[6] = xaz[2];
    if (xaz[2] <= 0)
        return 0;
    return retc;
}

/// swecl.c swe_lun_eclipse_when()
pub fn swe_lun_eclipse_when(
    tjd_start: f64,
    ifl_in: i32,
    ifltype_in: i32,
    tret: *[10]f64,
    backward: i32,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var idx1: usize = 0;
    var idx2: usize = 0;
    var retflag: i32 = 0;
    var retflag2: i32 = 0;
    var t: f64 = undefined;
    var tjd: f64 = undefined;
    var tjd2: f64 = undefined;
    var dt: f64 = undefined;
    var dtint: f64 = undefined;
    var dta: f64 = undefined;
    var dtb: f64 = undefined;
    var T: f64 = undefined;
    var T2: f64 = undefined;
    var T3: f64 = undefined;
    var T4: f64 = undefined;
    var K: f64 = undefined;
    var F: f64 = undefined;
    var M: f64 = undefined;
    var Mm: f64 = undefined;
    var E: f64 = undefined;
    var Ff: f64 = undefined;
    var F1: f64 = undefined;
    var A1: f64 = undefined;
    var Om: f64 = undefined;
    var xs: [6]f64 = undefined;
    var xm: [6]f64 = undefined;
    var dm: f64 = undefined;
    var ds: f64 = undefined;
    var rsun: f64 = undefined;
    var rearth: f64 = undefined;
    var dcore: [10]f64 = undefined;
    var dc: [3]f64 = undefined;
    var dctr: f64 = undefined;
    const twohr: f64 = 2.0 / 24.0;
    const tenmin: f64 = 10.0 / 24.0 / 60.0;
    var dt1: f64 = 0;
    var dt2: f64 = 0;
    var kk: f64 = undefined;
    var attr: [20]f64 = undefined;
    var dtstart: f64 = undefined;
    var dtdiv: f64 = undefined;
    var xa: [6]f64 = undefined;
    var xb: [6]f64 = undefined;
    var direction: i32 = 1;
    var iflag: i32 = undefined;
    var iflagcart: i32 = undefined;
    var ifl = ifl_in;
    var ifltype = ifltype_in;
    ifl &= SEFLG_EPHMASK;
    _ = sweph.swiSetTidAcc(tjd_start, ifl, 0, serr, swed, dctx);
    iflag = sweph.SEFLG_EQUATORIAL | ifl;
    iflagcart = iflag | sweph.SEFLG_XYZ;
    ifltype &= ~(SE_ECL_CENTRAL | SE_ECL_NONCENTRAL);
    if ((ifltype & (SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL)) != 0) {
        ifltype &= ~(SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL);
        if (ifltype == 0) {
            if (serr != null) {
                const msg = "annular lunar eclipses don't exist";
                const n = @min(msg.len, serr.?.len);
                @memcpy(serr.?[0..n], msg[0..n]);
            }
            return lib.ERR; // avoids infinite loop
        }
    }
    if (ifltype == 0)
        ifltype = SE_ECL_TOTAL | SE_ECL_PENUMBRAL | SE_ECL_PARTIAL;
    if (backward != 0)
        direction = -1;
    K = @trunc((tjd_start - lib.J2000) / 365.2425 * 12.3685);
    K -= @floatFromInt(direction);
    // next_try:
    while (true) {
        retflag = 0;
        for (0..10) |i|
            tret[i] = 0;
        kk = K + 0.5;
        T = kk / 1236.85;
        T2 = T * T;
        T3 = T2 * T;
        T4 = T3 * T;
        Ff = lib.swe_degnorm(160.7108 + 390.67050274 * kk - 0.0016341 * T2 - 0.00000227 * T3 + 0.000000011 * T4);
        F = Ff;
        if (Ff > 180)
            Ff -= 180;
        if (Ff > 21 and Ff < 159) { // no eclipse possible
            K += @floatFromInt(direction);
            continue;
        }
        // approximate time of geocentric maximum eclipse
        // formula from Meeus, German, p. 381
        tjd = 2451550.09765 + 29.530588853 * kk + 0.0001337 * T2 - 0.000000150 * T3 + 0.00000000073 * T4;
        M = lib.swe_degnorm(2.5534 + 29.10535669 * kk - 0.0000218 * T2 - 0.00000011 * T3);
        Mm = lib.swe_degnorm(201.5643 + 385.81693528 * kk + 0.1017438 * T2 + 0.00001239 * T3 + 0.000000058 * T4);
        Om = lib.swe_degnorm(124.7746 - 1.56375580 * kk + 0.0020691 * T2 + 0.00000215 * T3);
        E = 1 - 0.002516 * T - 0.0000074 * T2;
        A1 = lib.swe_degnorm(299.77 + 0.107408 * kk - 0.009173 * T2);
        M *= DEGTORAD;
        Mm *= DEGTORAD;
        F *= DEGTORAD;
        Om *= DEGTORAD;
        F1 = F - 0.02665 * swe_shim_sin(Om) * DEGTORAD;
        A1 *= DEGTORAD;
        tjd = tjd - 0.4075 * swe_shim_sin(Mm) +
            0.1721 * E * swe_shim_sin(M) +
            0.0161 * swe_shim_sin(2 * Mm) -
            0.0097 * swe_shim_sin(2 * F1) +
            0.0073 * E * swe_shim_sin(Mm - M) -
            0.0050 * E * swe_shim_sin(Mm + M) -
            0.0023 * swe_shim_sin(Mm - 2 * F1) +
            0.0021 * E * swe_shim_sin(2 * M) +
            0.0012 * swe_shim_sin(Mm + 2 * F1) +
            0.0006 * E * swe_shim_sin(2 * Mm + M) -
            0.0004 * swe_shim_sin(3 * Mm) -
            0.0003 * E * swe_shim_sin(M + 2 * F1) +
            0.0003 * swe_shim_sin(A1) -
            0.0002 * E * swe_shim_sin(M - 2 * F1) -
            0.0002 * E * swe_shim_sin(2 * Mm - M) -
            0.0002 * swe_shim_sin(Om);
        // precise computation:
        // time of maximum eclipse (if eclipse) =
        // minimum selenocentric angle between sun and earth edges.
        dtstart = 0.1;
        if (tjd < 2100000 or tjd > 2500000) // was tjd < 2000000 until 26-aug-22
            dtstart = 5;
        dtdiv = 4;
        var j: i32 = 0;
        dt = dtstart;
        while (dt > 0.001) : ({
            j += 1;
            dt /= dtdiv;
        }) {
            var i: usize = 0;
            t = tjd - dt;
            while (i <= 2) : ({
                i += 1;
                t += dt;
            }) {
                if (sweph.swe_calc(t, SE_SUN, iflagcart, &xs, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                if (sweph.swe_calc(t, SE_MOON, iflagcart, &xm, swed, models, dctx, serr) == lib.ERR)
                    return lib.ERR;
                for (0..3) |m| {
                    xs[m] -= xm[m]; // selenocentric sun
                    xm[m] = -xm[m]; // selenocentric earth
                }
                ds = @sqrt(sweph.square_sum(&xs));
                dm = @sqrt(sweph.square_sum(&xm));
                for (0..3) |m| {
                    xa[m] = xs[m] / ds;
                    xb[m] = xm[m] / dm;
                }
                dc[i] = swe_shim_acos(lib.swi_dot_prod_unit(xa[0..3], xb[0..3])) * RADTODEG;
                rearth = swe_shim_asin(REARTH / dm) * RADTODEG;
                rsun = swe_shim_asin(RSUN / ds) * RADTODEG;
                dc[i] -= (rearth + rsun);
            }
            _ = find_maximum(dc[0], dc[1], dc[2], dt, &dtint, &dctr);
            tjd += dtint + dt;
        }
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tjd2 = tjd - deltat_mod.swe_deltat_ex(dctx, tjd, ifl);
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tjd2 = tjd - deltat_mod.swe_deltat_ex(dctx, tjd2, ifl);
        dctx.sweph_denum = swed.fidat[sweph.SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        tjd = tjd - deltat_mod.swe_deltat_ex(dctx, tjd2, ifl);
        retflag = swe_lun_eclipse_how(tjd, ifl, null, &attr, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR)
            return retflag;
        if (retflag == 0) {
            K += @floatFromInt(direction);
            continue;
        }
        tret[0] = tjd;
        if ((backward != 0 and tret[0] >= tjd_start - 0.0001) or
            (backward == 0 and tret[0] <= tjd_start + 0.0001))
        {
            K += @floatFromInt(direction);
            continue;
        }
        // check whether or not eclipse type found is wanted
        // non penumbral eclipse is wanted:
        if ((ifltype & SE_ECL_PENUMBRAL) == 0 and (retflag & SE_ECL_PENUMBRAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // non partial eclipse is wanted:
        if ((ifltype & SE_ECL_PARTIAL) == 0 and (retflag & SE_ECL_PARTIAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // annular-total eclipse will be discovered later
        if ((ifltype & SE_ECL_TOTAL) == 0 and (retflag & SE_ECL_TOTAL) != 0) {
            K += @floatFromInt(direction);
            continue;
        }
        // n = 0: times of eclipse begin and end
        // n = 1: times of totality begin and end
        // n = 2: times of center line begin and end
        var o: i32 = undefined;
        if ((retflag & SE_ECL_PENUMBRAL) != 0)
            o = 0
        else if ((retflag & SE_ECL_PARTIAL) != 0)
            o = 1
        else
            o = 2;
        dta = twohr;
        dtb = tenmin;
        var n: i32 = 0;
        while (n <= o) : (n += 1) {
            if (n == 0) {
                idx1 = 6;
                idx2 = 7;
            } else if (n == 1) {
                idx1 = 2;
                idx2 = 3;
            } else if (n == 2) {
                idx1 = 4;
                idx2 = 5;
            }
            // (C's #if 1: active branch)
            var i: usize = 0;
            t = tjd - dta;
            while (i <= 2) : ({
                i += 1;
                t += dta;
            }) {
                retflag2 = lun_eclipse_how(t, ifl, &attr, &dcore, serr, swed, models, dctx);
                if (retflag2 == lib.ERR)
                    return retflag2;
                if (n == 0)
                    dc[i] = dcore[2] / 2 + RMOON / dcore[4] - dcore[0]
                else if (n == 1)
                    dc[i] = dcore[1] / 2 + RMOON / dcore[3] - dcore[0]
                else if (n == 2)
                    dc[i] = dcore[1] / 2 - RMOON / dcore[3] - dcore[0];
            }
            _ = find_zero(dc[0], dc[1], dc[2], dta, &dt1, &dt2);
            dtb = (dt1 + dta) / 2;
            tret[idx1] = tjd + dt1 + dta;
            tret[idx2] = tjd + dt2 + dta;
            var m: i32 = 0;
            dt = dtb / 2;
            while (m < 3) : ({
                m += 1;
                dt /= 2;
            }) {
                var jj: usize = idx1;
                while (jj <= idx2) : (jj += (idx2 - idx1)) {
                    i = 0;
                    t = tret[jj] - dt;
                    while (i < 2) : ({
                        i += 1;
                        t += dt;
                    }) {
                        retflag2 = lun_eclipse_how(t, ifl, &attr, &dcore, serr, swed, models, dctx);
                        if (retflag2 == lib.ERR)
                            return retflag2;
                        if (n == 0)
                            dc[i] = dcore[2] / 2 + RMOON / dcore[4] - dcore[0]
                        else if (n == 1)
                            dc[i] = dcore[1] / 2 + RMOON / dcore[3] - dcore[0]
                        else if (n == 2)
                            dc[i] = dcore[1] / 2 - RMOON / dcore[3] - dcore[0];
                    }
                    dt1 = dc[1] / ((dc[1] - dc[0]) / dt);
                    tret[jj] -= dt1;
                    if (idx1 == idx2) break;
                }
            }
        }
        return retflag;
    }
}

/// swecl.c swe_lun_eclipse_when_loc() — C's goto next_lun_ecl as a loop
pub fn swe_lun_eclipse_when_loc(
    tjd_start_in: f64,
    ifl_in: i32,
    geopos: ?*[3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: i32,
    serr: ?[]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    cctx: *SweclCtx,
) i32 {
    var retflag2: i32 = undefined;
    var retc: i32 = undefined;
    var tjdr: f64 = undefined;
    var tjds: f64 = undefined;
    var tjd_max: f64 = 0;
    var tjd_start = tjd_start_in;
    var ifl = ifl_in;
    if (geopos != null and (geopos.?[2] < SEI_ECL_GEOALT_MIN or geopos.?[2] > SEI_ECL_GEOALT_MAX)) {
        if (serr != null) {
            const r = std.fmt.bufPrint(serr.?[0 .. serr.?.len - 1], "location for eclipses must be between {d:.0} and {d:.0} m above sea", .{ SEI_ECL_GEOALT_MIN, SEI_ECL_GEOALT_MAX }) catch "";
            if (r.len < serr.?.len) serr.?[r.len] = 0;
        }
        return lib.ERR;
    }
    ifl &= ~(sweph.SEFLG_JPLHOR | sweph.SEFLG_JPLHOR_APPROX);
    // next_lun_ecl:
    while (true) {
        const retflag = swe_lun_eclipse_when(tjd_start, ifl, 0, tret, backward, serr, swed, models, dctx, cctx);
        if (retflag == lib.ERR) {
            return lib.ERR;
        }
        // visibility of eclipse phases
        var retflag_out: i32 = 0;
        var i: i32 = 7;
        while (i >= 0) : (i -= 1) {
            if (i == 1) continue;
            const iu: usize = @intCast(i);
            if (tret[iu] == 0) continue;
            retflag2 = swe_lun_eclipse_how(tret[iu], ifl, geopos, attr, serr, swed, models, dctx, cctx);
            if (retflag2 == lib.ERR)
                return lib.ERR;
            if (attr[6] > 0) { // moon above horizon, using app. alt.
                retflag_out |= SE_ECL_VISIBLE;
                switch (i) {
                    0 => retflag_out |= SE_ECL_MAX_VISIBLE,
                    2 => retflag_out |= SE_ECL_PARTBEG_VISIBLE,
                    3 => retflag_out |= SE_ECL_PARTEND_VISIBLE,
                    4 => retflag_out |= SE_ECL_TOTBEG_VISIBLE,
                    5 => retflag_out |= SE_ECL_TOTEND_VISIBLE,
                    6 => retflag_out |= SE_ECL_PENUMBBEG_VISIBLE,
                    7 => retflag_out |= SE_ECL_PENUMBEND_VISIBLE,
                    else => {},
                }
            }
        }
        if ((retflag_out & SE_ECL_VISIBLE) == 0) {
            if (backward != 0)
                tjd_start = tret[0] - 25
            else
                tjd_start = tret[0] + 25;
            continue; // goto next_lun_ecl
        }
        // moon rise and moon set
        tjd_max = tret[0];
        retc = swe_rise_trans(tret[6] - 0.001, SE_MOON, null, ifl, SE_CALC_RISE | SE_BIT_DISC_BOTTOM, geopos.?, 0, 0, &tjdr, serr, swed, models, dctx, cctx);
        if (retc == lib.ERR)
            return lib.ERR;
        if (retc >= 0) {
            retc = swe_rise_trans(tret[6] - 0.001, SE_MOON, null, ifl, SE_CALC_SET | SE_BIT_DISC_BOTTOM, geopos.?, 0, 0, &tjds, serr, swed, models, dctx, cctx);
            if (retc == lib.ERR)
                return lib.ERR;
        }
        if (retc >= 0) {
            if (tjds < tret[6] or (tjds > tjdr and tjdr > tret[7])) {
                if (backward != 0)
                    tjd_start = tret[0] - 25
                else
                    tjd_start = tret[0] + 25;
                continue; // goto next_lun_ecl
            }
            if (tjdr > tret[6] and tjdr < tret[7]) {
                tret[6] = 0;
                var ii: usize = 2;
                while (ii <= 5) : (ii += 1) {
                    if (tjdr > tret[ii])
                        tret[ii] = 0;
                }
                tret[8] = tjdr;
                if (tjdr > tret[0]) {
                    tjd_max = tjdr;
                }
            }
            if (tjds > tret[6] and tjds < tret[7]) {
                tret[7] = 0;
                var ii: usize = 2;
                while (ii <= 5) : (ii += 1) {
                    if (tjds < tret[ii])
                        tret[ii] = 0;
                }
                tret[9] = tjds;
                if (tjds < tret[0]) {
                    tjd_max = tjds;
                }
            }
        }
        tret[0] = tjd_max;
        retflag2 = swe_lun_eclipse_how(tjd_max, ifl, geopos, attr, serr, swed, models, dctx, cctx);
        if (retflag2 == lib.ERR)
            return lib.ERR;
        if (retflag2 == 0) {
            if (backward != 0)
                tjd_start = tret[0] - 25
            else
                tjd_start = tret[0] + 25;
            continue; // goto next_lun_ecl
        }
        return retflag_out | (retflag2 & SE_ECL_ALLTYPES_LUNAR);
    }
}
