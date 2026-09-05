// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port --- swephlib module (shared helpers).
// Translated 1:1 from swephlib.c to preserve exact floating-point
// operation order, differential-tested against the C oracle.
// Scope so far: the helpers needed by swemmoon (obliquity, precession
// family, coordinate conversions) plus general angle helpers.
const std = @import("std");

// Platform libm via shim (see libmshim.c) or pure Zig std.math when -Dpure
const build_options = @import("build_options");
const cr = @import("libm/cr.zig");
const pure = build_options.pure;
pub fn swe_shim_sin(x: f64) f64 {
    if (pure) return std.math.sin(x);
    const c = struct {
        extern "c" fn swe_shim_sin(x: f64) f64;
    };
    return c.swe_shim_sin(x);
}
pub fn swe_shim_cos(x: f64) f64 {
    if (pure) return std.math.cos(x);
    const c = struct {
        extern "c" fn swe_shim_cos(x: f64) f64;
    };
    return c.swe_shim_cos(x);
}
pub fn swe_shim_tan(x: f64) f64 {
    if (pure) return std.math.tan(x);
    const c = struct {
        extern "c" fn swe_shim_tan(x: f64) f64;
    };
    return c.swe_shim_tan(x);
}
pub fn swe_shim_asin(x: f64) f64 {
    if (pure) return cr.asin(x);
    const c = struct {
        extern "c" fn swe_shim_asin(x: f64) f64;
    };
    return c.swe_shim_asin(x);
}
pub fn swe_shim_acos(x: f64) f64 {
    if (pure) return cr.acos(x);
    const c = struct {
        extern "c" fn swe_shim_acos(x: f64) f64;
    };
    return c.swe_shim_acos(x);
}
pub fn swe_shim_atan(x: f64) f64 {
    if (pure) return cr.atan(x);
    const c = struct {
        extern "c" fn swe_shim_atan(x: f64) f64;
    };
    return c.swe_shim_atan(x);
}
pub fn swe_shim_atan2(y: f64, x: f64) f64 {
    if (pure) return cr.atan2(y, x);
    const c = struct {
        extern "c" fn swe_shim_atan2(y: f64, x: f64) f64;
    };
    return c.swe_shim_atan2(y, x);
}
pub fn swe_shim_fmod(x: f64, y: f64) f64 {
    if (pure) return @rem(x, y);
    const c = struct {
        extern "c" fn swe_shim_fmod(x: f64, y: f64) f64;
    };
    return c.swe_shim_fmod(x, y);
}
pub fn swe_shim_log10(x: f64) f64 {
    if (pure) return std.math.log10(x);
    const c = struct {
        extern "c" fn swe_shim_log10(x: f64) f64;
    };
    return c.swe_shim_log10(x);
}
pub fn swe_shim_log(x: f64) f64 {
    if (pure) return std.math.log(f64, std.math.e, x); // std f128 log2 is f64 fallback; cr.log no better
    const c = struct {
        extern "c" fn swe_shim_log(x: f64) f64;
    };
    return c.swe_shim_log(x);
}
pub fn swe_shim_exp(x: f64) f64 {
    if (pure) return std.math.exp(x);
    const c = struct {
        extern "c" fn swe_shim_exp(x: f64) f64;
    };
    return c.swe_shim_exp(x);
}
pub fn swe_shim_pow(x: f64, y: f64) f64 {
    if (pure) return std.math.pow(f64, x, y); // std f128 exp2 is f64 fallback; cr.pow no better
    const c = struct {
        extern "c" fn swe_shim_pow(x: f64, y: f64) f64;
    };
    return c.swe_shim_pow(x, y);
}

pub const DEGTORAD: f64 = std.math.pi / 180.0;
pub const RADTODEG: f64 = 180.0 / std.math.pi;
pub const PI: f64 = std.math.pi;
pub const TWOPI: f64 = 2.0 * std.math.pi;
pub const J2000: f64 = 2451545.0;
pub const J1900: f64 = 2415020.0; // 1900 January 0.5
pub const J_TO_J2000: i32 = 1;
pub const J2000_TO_J: i32 = -1;
pub const B1850: f64 = 2396758.2035810;

// swephexp.h model selections
pub const SEMOD_PREC_IAU_1976: i32 = 1;
pub const SEMOD_PREC_LASKAR_1986: i32 = 2;
pub const SEMOD_PREC_WILL_EPS_LASK: i32 = 3;
pub const SEMOD_PREC_WILLIAMS_1994: i32 = 4;
pub const SEMOD_PREC_SIMON_1994: i32 = 5;
pub const SEMOD_PREC_IAU_2000: i32 = 6;
pub const SEMOD_PREC_BRETAGNON_2003: i32 = 7;
pub const SEMOD_PREC_IAU_2006: i32 = 8;
pub const SEMOD_PREC_VONDRAK_2011: i32 = 9;
pub const SEMOD_PREC_OWEN_1990: i32 = 10;
pub const SEMOD_PREC_NEWCOMB: i32 = 11;
pub const SEMOD_PREC_DEFAULT: i32 = SEMOD_PREC_VONDRAK_2011;
pub const SEMOD_PREC_DEFAULT_SHORT: i32 = SEMOD_PREC_VONDRAK_2011;
pub const SEMOD_JPLHORA_1: i32 = 1;
pub const SEMOD_JPLHORA_2: i32 = 2;
pub const SEMOD_JPLHORA_3: i32 = 3;
pub const SEMOD_JPLHORA_DEFAULT: i32 = SEMOD_JPLHORA_3;
pub const OK: i32 = 0;
pub const ERR: i32 = -1;
pub const B1950: f64 = 2433282.42345905; // 1950 January 0.923
pub const NOT_AVAILABLE: i32 = -2;
pub const BEYOND_EPH_LIMITS: i32 = -3;
pub const SEFLG_ICRS: i32 = 128 * 1024;
pub const SEFLG_JPLHOR: i32 = 256 * 1024;
pub const SEFLG_JPLHOR_APPROX: i32 = 512 * 1024;
pub const SEFLG_JPLEPH: i32 = 1;
pub const SEFLG_SWIEPH: i32 = 2;
pub const SEFLG_MOSEPH: i32 = 4;

pub const SEMOD_NUT_IAU_1980: i32 = 1;
pub const SEMOD_NUT_IAU_CORR_1987: i32 = 2;
pub const SEMOD_NUT_IAU_2000A: i32 = 3;
pub const SEMOD_NUT_IAU_2000B: i32 = 4;
pub const SEMOD_NUT_WOOLARD: i32 = 5;
pub const SEMOD_NUT_DEFAULT: i32 = SEMOD_NUT_IAU_2000B;
pub const SEMOD_BIAS_NONE: i32 = 1;
pub const SEMOD_BIAS_IAU2000: i32 = 2;
pub const SEMOD_BIAS_IAU2006: i32 = 3;
pub const SEMOD_BIAS_DEFAULT: i32 = SEMOD_BIAS_IAU2006;
pub const SEMOD_SIDT_IAU_1976: i32 = 1;
pub const SEMOD_SIDT_IAU_2006: i32 = 2;
pub const SEMOD_SIDT_IERS_CONV_2010: i32 = 3;
pub const SEMOD_SIDT_LONGTERM: i32 = 4;
pub const SEMOD_SIDT_DEFAULT: i32 = SEMOD_SIDT_LONGTERM;
pub const SEFLG_SPEED: i32 = 256;
pub const DPSI_IAU1980_TJD0: f64 = 64.284 / 1000.0; // arcsec
pub const DEPS_IAU1980_TJD0: f64 = 6.151 / 1000.0; // arcsec
pub const CLIGHT: f64 = 2.99792458e+8; // m/s
pub const AUNIT: f64 = 1.49597870700e+11; // au in meters, DE431
const O1MAS2DEG: f64 = @as(f64, 1.0) / 3600.0 / 10000000.0;
const NLS: usize = 678;
const NLS_2000B: usize = 77;
const NPL: usize = 687;
pub const PREC_IAU_1976_CTIES: f64 = 2.0;
pub const PREC_IAU_2000_CTIES: f64 = 2.0;
pub const PREC_IAU_2006_CTIES: f64 = 75.0;
pub const HORIZONS_TJD0_DPSI_DEPS_IAU1980: f64 = 2437684.5;

/// The three astro_models entries the C dispatchers read from swed
/// (sweph.h `int32 astro_models[SEI_NMODELS]`), threaded explicitly
/// (same pattern as DeltatCtx): 0 means "use default".
pub const AstroModels = struct {
    prec_longterm: i32 = 0,
    prec_shortterm: i32 = 0,
    jplhora: i32 = 0,
    nut: i32 = 0,
    bias: i32 = 0,
    sidt: i32 = 0,
};

/// struct epsilon (sweph.h): mean obliquity of date holder.
pub const Eps = struct {
    teps: f64 = 0,
    eps: f64 = 0,
    seps: f64 = 0,
    ceps: f64 = 0,
};

pub fn swe_degnorm(x: f64) f64 {
    var y = swe_shim_fmod(x, 360.0);
    if (@abs(y) < 1e-13) y = 0.0;
    if (y < 0.0) y += 360.0;
    return y;
}

pub fn swe_difdeg2n(p1: f64, p2: f64) f64 {
    const dif = swe_degnorm(p1 - p2);
    if (dif >= 180.0) return dif - 360.0;
    return dif;
}

/// Reduce x modulo 2*PI
pub fn swi_mod2PI(x: f64) f64 {
    var y = swe_shim_fmod(x, TWOPI);
    if (y < 0.0) y += TWOPI;
    return y;
}

/// swephlib.c swi_kepler: solve Kepler equation.
/// Note the C source's deliberate avoidance of swi_mod2PI for small x
/// (workaround for an optimizer problem); preserved 1:1.
pub fn swi_kepler(E_in: f64, M: f64, ecce: f64) f64 {
    var dE: f64 = 1;
    var E = E_in;
    var E0: f64 = undefined;
    var x: f64 = undefined;
    // simple formula for small eccentricities
    if (ecce < 0.4) {
        while (dE > 1e-12) {
            E0 = E;
            E = M + ecce * swe_shim_sin(E0);
            dE = @abs(E - E0);
        }
        // complicated formula for high eccentricities
    } else {
        while (dE > 1e-12) {
            E0 = E;
            x = (M + ecce * swe_shim_sin(E0) - E0) / (1 - ecce * swe_shim_cos(E0));
            dE = @abs(x);
            if (dE < 1e-2) {
                E = E0 + x;
            } else {
                E = swi_mod2PI(E0 + x);
                dE = @abs(E - E0);
            }
        }
    }
    return E;
}

pub fn swi_cross_prod(a: *const [3]f64, b: *const [3]f64, x: *[3]f64) void {
    x[0] = a[1] * b[2] - a[2] * b[1];
    x[1] = a[2] * b[0] - a[0] * b[2];
    x[2] = a[0] * b[1] - a[1] * b[0];
}

/// slice-b variant (C: swi_cross_prod(xpos, xpos+3, xnorm))
pub fn swi_cross_prod_slice(a: *const [3]f64, b: []const f64, x: *[3]f64) void {
    x[0] = a[1] * b[2] - a[2] * b[1];
    x[1] = a[2] * b[0] - a[0] * b[2];
    x[2] = a[0] * b[1] - a[1] * b[0];
}

/// conversion between ecliptical and equatorial cartesian coordinates
/// (swephlib.c swi_coortrf; temp buffer because xpo == xpn is allowed)
pub fn swi_coortrf(xpo: *const [3]f64, xpn: *[3]f64, eps: f64) void {
    const sineps = swe_shim_sin(eps);
    const coseps = swe_shim_cos(eps);
    const x0 = xpo[0];
    const x1 = xpo[1] * coseps + xpo[2] * sineps;
    const x2 = -xpo[1] * sineps + xpo[2] * coseps;
    xpn[0] = x0;
    xpn[1] = x1;
    xpn[2] = x2;
}

/// like swi_coortrf, but with sin/cos of eps given
pub fn swi_coortrf2(xpo: *const [3]f64, xpn: *[3]f64, sineps: f64, coseps: f64) void {
    const x0 = xpo[0];
    const x1 = xpo[1] * coseps + xpo[2] * sineps;
    const x2 = -xpo[1] * sineps + xpo[2] * coseps;
    xpn[0] = x0;
    xpn[1] = x1;
    xpn[2] = x2;
}

/// conversion of cartesian (x[3]) to polar coordinates (l[3]).
/// x = l is allowed.
pub fn swi_cartpol(x: *const [3]f64, l: *[3]f64) void {
    if (x[0] == 0.0 and x[1] == 0.0 and x[2] == 0.0) {
        l[0] = 0.0;
        l[1] = 0.0;
        l[2] = 0.0;
        return;
    }
    var rxy = x[0] * x[0] + x[1] * x[1];
    const ll2 = std.math.sqrt(rxy + x[2] * x[2]);
    rxy = std.math.sqrt(rxy);
    const ll0 = swe_shim_atan2(x[1], x[0]);
    var ll1: f64 = undefined;
    const ll0n: f64 = if (ll0 < 0.0) ll0 + TWOPI else ll0;
    if (rxy == 0.0) {
        if (x[2] >= 0.0) ll1 = PI / 2.0 else ll1 = -(PI / 2.0);
    } else {
        ll1 = swe_shim_atan(x[2] / rxy);
    }
    l[0] = ll0n;
    l[1] = ll1;
    l[2] = ll2;
}

/// conversion from polar (l[3]) to cartesian coordinates (x[3]).
/// x = l is allowed.
pub fn swi_polcart(l: *const [3]f64, x: *[3]f64) void {
    const cosl1 = swe_shim_cos(l[1]);
    const xx0 = l[2] * cosl1 * swe_shim_cos(l[0]);
    const xx1 = l[2] * cosl1 * swe_shim_sin(l[0]);
    const xx2 = l[2] * swe_shim_sin(l[1]);
    x[0] = xx0;
    x[1] = xx1;
    x[2] = xx2;
}

// --- precession and ecliptic obliquity according to Vondrak et alii, 2011 ---
pub const AS2R: f64 = DEGTORAD / 3600.0;
const D2PI: f64 = TWOPI;
pub const EPS0: f64 = 84381.406 * AS2R;
const NPOL_PEPS: usize = 4;
const NPER_PEPS: usize = 10;
const NPOL_PECL: usize = 4;
const NPER_PECL: usize = 8;
const NPOL_PEQU: usize = 4;
const NPER_PEQU: usize = 14;

// for pre_peps(): polynomials
const pepol = [NPOL_PEPS][2]f64{
    .{ 8134.017132, 84028.206305 },
    .{ 5043.0520035, 0.3624445 },
    .{ -0.00710733, -0.00004039 },
    .{ 0.000000271, -0.000000110 },
};
// periodics
const peper = [5][NPER_PEPS]f64{
    .{ 409.90, 396.15, 537.22, 402.90, 417.15, 288.92, 4043.00, 306.00, 277.00, 203.00 },
    .{ -6908.287473, -3198.706291, 1453.674527, -857.748557, 1173.231614, -156.981465, 371.836550, -216.619040, 193.691479, 11.891524 },
    .{ 753.872780, -247.805823, 379.471484, -53.880558, -90.109153, -353.600190, -63.115353, -28.248187, 17.703387, 38.911307 },
    .{ -2845.175469, 449.844989, -1255.915323, 886.736783, 418.887514, 997.912441, -240.979710, 76.541307, -36.788069, -170.964086 },
    .{ -1704.720302, -862.308358, 447.832178, -889.571909, 190.402846, -56.564991, -296.222622, -75.859952, 67.473503, 3.014055 },
};

// for pre_pecl(): polynomials
const pqpol = [NPOL_PECL][2]f64{
    .{ 5851.607687, -1600.886300 },
    .{ -0.1189000, 1.1689818 },
    .{ -0.00028913, -0.00000020 },
    .{ 0.000000101, -0.000000437 },
};
// periodics (typo fixed according to A&A 541, C1 (2012))
const pqper = [5][NPER_PECL]f64{
    .{ 708.15, 2309, 1620, 492.2, 1183, 622, 882, 547 },
    .{ -5486.751211, -17.127623, -617.517403, 413.44294, 78.614193, -180.732815, -87.676083, 46.140315 },
    .{ -684.66156, 2446.28388, 399.671049, -356.652376, -186.387003, -316.80007, 198.296701, 101.135679 },
    .{ 667.66673, -2354.886252, -428.152441, 376.202861, 184.778874, 335.321713, -185.138669, -120.97283 },
    .{ -5523.863691, -549.74745, -310.998056, 421.535876, -36.776172, -145.278396, -34.74445, 22.885731 },
};

// for pre_pequ(): polynomials
const xypol = [NPOL_PEQU][2]f64{
    .{ 5453.282155, -73750.930350 },
    .{ 0.4252841, -0.7675452 },
    .{ -0.00037173, -0.00018725 },
    .{ -0.000000152, 0.000000231 },
};
// periodics
const xyper = [5][NPER_PEQU]f64{
    .{ 256.75, 708.15, 274.2, 241.45, 2309, 492.2, 396.1, 288.9, 231.1, 1610, 620, 157.87, 220.3, 1200 },
    .{ -819.940624, -8444.676815, 2600.009459, 2755.17563, -167.659835, 871.855056, 44.769698, -512.313065, -819.415595, -538.071099, -189.793622, -402.922932, 179.516345, -9.814756 },
    .{ 75004.344875, 624.033993, 1251.136893, -1102.212834, -2660.66498, 699.291817, 153.16722, -950.865637, 499.754645, -145.18821, 558.116553, -23.923029, -165.405086, 9.344131 },
    .{ 81491.287984, 787.163481, 1251.296102, -1257.950837, -2966.79973, 639.744522, 131.600209, -445.040117, 584.522874, -89.756563, 524.42963, -13.549067, -210.157124, -44.919798 },
    .{ 1558.515853, 7774.939698, -2219.534038, -2523.969396, 247.850422, -846.485643, -1393.124055, 368.526116, 749.045012, 444.704518, 235.934465, 374.049623, -171.33018, -22.899655 },
};

pub fn swi_ldp_peps(tjd: f64, dpre: ?*f64, deps: ?*f64) void {
    const npol: usize = NPOL_PEPS;
    const nper: usize = NPER_PEPS;
    const t = (tjd - J2000) / 36525.0;
    var p: f64 = 0;
    var q: f64 = 0;
    // periodic terms
    var i: usize = 0;
    while (i < nper) : (i += 1) {
        const w = D2PI * t;
        const a = w / peper[0][i];
        const s = swe_shim_sin(a);
        const c = swe_shim_cos(a);
        p += c * peper[1][i] + s * peper[3][i];
        q += c * peper[2][i] + s * peper[4][i];
    }
    // polynomial terms
    var w: f64 = 1;
    i = 0;
    while (i < npol) : (i += 1) {
        p += pepol[i][0] * w;
        q += pepol[i][1] * w;
        w *= t;
    }
    // both to radians
    p *= AS2R;
    q *= AS2R;
    if (dpre != null) dpre.?.* = p;
    if (deps != null) deps.?.* = q;
}

/// precession of the ecliptic (Vondrak et alii 2011)
fn pre_pecl(tjd: f64, vec: *[3]f64) void {
    const npol: usize = NPOL_PECL;
    const nper: usize = NPER_PECL;
    const t = (tjd - J2000) / 36525.0;
    var p: f64 = 0;
    var q: f64 = 0;
    // periodic terms
    var i: usize = 0;
    while (i < nper) : (i += 1) {
        const w = D2PI * t;
        const a = w / pqper[0][i];
        const s = swe_shim_sin(a);
        const c = swe_shim_cos(a);
        p += c * pqper[1][i] + s * pqper[3][i];
        q += c * pqper[2][i] + s * pqper[4][i];
    }
    // polynomial terms
    var w: f64 = 1;
    i = 0;
    while (i < npol) : (i += 1) {
        p += pqpol[i][0] * w;
        q += pqpol[i][1] * w;
        w *= t;
    }
    p *= AS2R;
    q *= AS2R;
    // ecliptic pole vector
    var z = 1 - p * p - q * q;
    if (z < 0) z = 0 else z = std.math.sqrt(z);
    const s = swe_shim_sin(EPS0);
    const c = swe_shim_cos(EPS0);
    vec[0] = p;
    vec[1] = -q * c - z * s;
    vec[2] = -q * s + z * c;
}

/// precession of the equator (Vondrak et alii 2011)
fn pre_pequ(tjd: f64, veq: *[3]f64) void {
    const npol: usize = NPOL_PEQU;
    const nper: usize = NPER_PEQU;
    const t = (tjd - J2000) / 36525.0;
    var x: f64 = 0;
    var y: f64 = 0;
    var i: usize = 0;
    while (i < nper) : (i += 1) {
        const w = D2PI * t;
        const a = w / xyper[0][i];
        const s = swe_shim_sin(a);
        const c = swe_shim_cos(a);
        x += c * xyper[1][i] + s * xyper[3][i];
        y += c * xyper[2][i] + s * xyper[4][i];
    }
    // polynomial terms
    var w: f64 = 1;
    i = 0;
    while (i < npol) : (i += 1) {
        x += xypol[i][0] * w;
        y += xypol[i][1] * w;
        w *= t;
    }
    x *= AS2R;
    y *= AS2R;
    // equator pole vector
    veq[0] = x;
    veq[1] = y;
    const w2 = x * x + y * y;
    if (w2 < 1) veq[2] = std.math.sqrt(1 - w2) else veq[2] = 0;
}

/// precession matrix (Vondrak)
fn pre_pmat(tjd: f64, rp: *[9]f64) void {
    var peqr: [3]f64 = undefined;
    var pecl: [3]f64 = undefined;
    var v: [3]f64 = undefined;
    var eqx: [3]f64 = undefined;
    // equator pole
    pre_pequ(tjd, &peqr);
    // ecliptic pole
    pre_pecl(tjd, &pecl);
    // equinox
    swi_cross_prod(&peqr, &pecl, &v);
    const w = std.math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    eqx[0] = v[0] / w;
    eqx[1] = v[1] / w;
    eqx[2] = v[2] / w;
    swi_cross_prod(&peqr, &eqx, &v);
    rp[0] = eqx[0];
    rp[1] = eqx[1];
    rp[2] = eqx[2];
    rp[3] = v[0];
    rp[4] = v[1];
    rp[5] = v[2];
    rp[6] = peqr[0];
    rp[7] = peqr[1];
    rp[8] = peqr[2];
}

// precession according to Owen 1990 (time range -18000 to 14000)
const owen_eps0_coef = [5][10]f64{
    .{ 23.699391439256386, 5.2330816033981775e-1, -5.6259493384864815e-2, -8.2033318431602032e-3, 6.6774163554156385e-4, 2.4931584012812606e-5, -3.1313623302407878e-6, 2.0343814827951515e-7, 2.9182026615852936e-8, -4.1118760893281951e-9 },
    .{ 24.124759551704588, -1.2094875596566286e-1, -8.3914869653015218e-2, 3.5357075322387405e-3, 6.4557467824807032e-4, -2.5092064378707704e-5, -1.7631607274450848e-6, 1.3363622791424094e-7, 1.5577817511054047e-8, -2.4613907093017122e-9 },
    .{ 23.439103144206208, -4.9386077073143590e-1, -2.3965445283267805e-4, 8.6637485629656489e-3, -5.2828151901367600e-5, -4.3951004595359217e-5, -1.1058785949914705e-6, 6.2431490022621172e-8, 3.4725376218710764e-8, 1.3658853127005757e-9 },
    .{ 22.724671295125046, -1.6041813558650337e-1, 7.0646783888132504e-2, 1.4967806745062837e-3, -6.6857270989190734e-4, 5.7578378071604775e-6, 3.3738508454638728e-6, -2.2917813537654764e-7, -2.1019907929218137e-8, 4.3139832091694682e-9 },
    .{ 22.914636050333696, 3.2123508304962416e-1, 3.6633220173792710e-2, -5.9228324767696043e-3, -1.882379107379328e-4, 3.2274552870236244e-5, 4.9052463646336507e-7, -5.9064298731578425e-8, -2.0485712675098837e-8, -6.2163304813908160e-10 },
};
pub const owen_psia_coef = [5][10]f64{
    .{ -218.57864954903122, 51.752257487741612, 1.3304715765661958e-1, 9.2048123521890745e-2, -6.0877528127241278e-3, -7.0013893644531700e-5, -4.9217728385458495e-5, -1.8578234189053723e-6, 7.4396426162029877e-7, -5.9157528981843864e-9 },
    .{ -111.94350527506128, 55.175558131675861, 4.7366115762797613e-1, -4.7701750975398538e-2, -9.2445765329325809e-3, 7.0962838707454917e-4, 1.5140455277814658e-4, -7.7813159018954928e-7, -2.4729402281953378e-6, -1.0898887008726418e-7 },
    .{ -2.041452011529441e-1, 55.969995858494106, -1.9295093699770936e-1, -5.6819574830421158e-3, 1.1073687302518981e-2, -9.0868489896815619e-5, -1.1999773777895820e-4, 9.9748697306154409e-6, 5.7911493603430550e-7, -2.3647526839778175e-7 },
    .{ 111.61366860604471, 56.404525305162447, 4.4403302410703782e-1, 7.1490030578883907e-2, -4.9184559079790816e-3, -1.3912698949042046e-3, -6.8490613661884005e-5, 1.2394328562905297e-6, 1.7719847841480384e-6, 2.4889095220628068e-7 },
    .{ 228.40683531269390, 60.056143904919826, 2.9583200718478960e-2, -1.5710838319490748e-1, -7.0017356811600801e-3, 3.3009615142224537e-3, 2.0318123852537664e-4, -6.5840216067828310e-5, -5.9077673352976153e-6, 1.3983942185303064e-6 },
};
pub const owen_oma_coef = [5][10]f64{
    .{ 25.541291140949806, 2.377889511272162e-1, -3.7337334723142133e-1, 2.4579295485161534e-2, 4.3840999514263623e-3, -3.1126873333599556e-4, -9.8443045771748915e-6, -7.9403103080496923e-7, 1.0840116743893556e-9, 9.2865105216887919e-9 },
    .{ 24.429357654237926, -9.5205745947740161e-1, 8.6738296270534816e-2, 3.0061543426062955e-2, -4.1532480523019988e-3, -3.7920928393860939e-4, 3.5117012399609737e-5, 4.6811877283079217e-6, -8.1836046585546861e-8, -6.1803706664211173e-8 },
    .{ 23.450465062489337, -9.7259278279739817e-2, 1.1082286925130981e-2, -3.1469883339372219e-2, -1.0041906996819648e-4, 5.6455168475133958e-4, -8.4403910211030209e-6, -3.826915737109844e-6, 3.1422585261198437e-7, 9.3481729116773404e-9 },
    .{ 22.581778052947806, -8.7069701538602037e-1, -9.8140710050197305e-2, 2.6025931340678079e-2, 4.8165322168786755e-3, -1.906558772193363e-4, -4.6838759635421777e-5, -1.6608525315998471e-6, -3.2347811293516124e-8, 2.8104728109642000e-9 },
    .{ 21.518861835737142, 2.0494789509441385e-1, 3.5193604846503161e-1, 1.5305977982348925e-2, -7.5015367726336455e-3, -4.0322553186065610e-4, 1.0655320434844041e-4, 7.1792339586935752e-6, -1.60387469754302e-6, -1.613563462813512e-7 },
};
pub const owen_chia_coef = [5][10]f64{
    .{ 8.2378850337329404e-1, -3.7443109739678667, 4.0143936898854026e-1, 8.1822830214590811e-2, -8.5978790792656293e-3, -2.8350488448426132e-5, -4.2474671728156727e-5, -1.6214840884656678e-6, 7.8560442001953050e-7, -1.032016641696707e-8 },
    .{ -2.1726062070318606, 7.8470515033132925e-1, 4.4044931004195718e-1, -8.0671247169971653e-2, -8.9672662444325007e-3, 9.2248978383109719e-4, 1.5143472266372874e-4, -1.6387009056475679e-6, -2.4405558979328144e-6, -1.0148113464009015e-7 },
    .{ -4.8518673570735556e-1, 1.0016737299946743e-1, -4.7074888613099918e-1, -5.8604054305076092e-3, 1.4300208240553435e-2, -6.7127991650300028e-5, -1.3703764889645475e-4, 9.0505213684444634e-6, 6.0368690647808607e-7, -2.2135404747652171e-7 },
    .{ -2.0950740076326087, -9.4447359463206877e-1, 4.0940512860493755e-1, 1.0261699700263508e-1, -5.3133241571955160e-3, -1.6634631550720911e-3, -5.9477519536647907e-5, 2.9651387319208926e-6, 1.6434499452070584e-6, 2.3720647656961084e-7 },
    .{ 6.3315163285678715e-1, 3.5241082918420464, 2.1223076605364606e-1, -1.5648122502767368e-1, -9.1964075390801980e-3, 3.3896161239812413e-3, 2.1485178626085787e-4, -6.6261759864793735e-5, -5.9257969712852667e-6, 1.3918759086160525e-6 },
};

pub fn get_owen_t0_icof(tjd: f64, t0: *f64, icof: *i32) void {
    const t0s = [5]f64{ -3392455.5, -470455.5, 2451544.5, 5373544.5, 8295544.5 };
    var j: i32 = 0;
    t0.* = t0s[0];
    var i: usize = 1;
    while (i < 5) : (i += 1) {
        if (tjd < (t0s[i - 1] + t0s[i]) / 2) {
            // keep t0
        } else {
            t0.* = t0s[i];
            j += 1;
        }
    }
    icof.* = j;
}

/// precession matrix Owen 1990
pub fn owen_pre_matrix(tjd: f64, rp: *[9]f64, iflag: i32) void {
    var icof: i32 = 0;
    var chia: f64 = 0;
    var psia: f64 = 0;
    var oma: f64 = 0;
    var tau: [10]f64 = undefined;
    var k: [10]f64 = undefined;
    var t0: f64 = undefined;
    get_owen_t0_icof(tjd, &t0, &icof);
    tau[0] = 0;
    tau[1] = (tjd - t0) / 36525.0 / 40.0;
    var i: usize = 2;
    while (i <= 9) : (i += 1) {
        tau[i] = tau[1] * tau[i - 1];
    }
    k[0] = 1;
    k[1] = tau[1];
    k[2] = 2 * tau[2] - 1;
    k[3] = 4 * tau[3] - 3 * tau[1];
    k[4] = 8 * tau[4] - 8 * tau[2] + 1;
    k[5] = 16 * tau[5] - 20 * tau[3] + 5 * tau[1];
    k[6] = 32 * tau[6] - 48 * tau[4] + 18 * tau[2] - 1;
    k[7] = 64 * tau[7] - 112 * tau[5] + 56 * tau[3] - 7 * tau[1];
    k[8] = 128 * tau[8] - 256 * tau[6] + 160 * tau[4] - 32 * tau[2] + 1;
    k[9] = 256 * tau[9] - 576 * tau[7] + 432 * tau[5] - 120 * tau[3] + 9 * tau[1];
    i = 0;
    while (i < 10) : (i += 1) {
        psia += (k[i] * owen_psia_coef[@intCast(icof)][i]);
        oma += (k[i] * owen_oma_coef[@intCast(icof)][i]);
        chia += (k[i] * owen_chia_coef[@intCast(icof)][i]);
    }
    if ((iflag & (SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX)) != 0) {
        // fix offset in ecliptic longitude vs JPL Horizons
        psia += -0.000018560;
    }
    var eps0: f64 = @as(f64, 84381.448) / 3600.0;
    eps0 *= DEGTORAD;
    psia *= DEGTORAD;
    chia *= DEGTORAD;
    oma *= DEGTORAD;
    const coseps0 = swe_shim_cos(eps0);
    const sineps0 = swe_shim_sin(eps0);
    const coschia = swe_shim_cos(chia);
    const sinchia = swe_shim_sin(chia);
    const cospsia = swe_shim_cos(psia);
    const sinpsia = swe_shim_sin(psia);
    const cosoma = swe_shim_cos(oma);
    const sinoma = swe_shim_sin(oma);
    rp[0] = coschia * cospsia + sinchia * cosoma * sinpsia;
    rp[1] = (-coschia * sinpsia + sinchia * cosoma * cospsia) * coseps0 + sinchia * sinoma * sineps0;
    rp[2] = (-coschia * sinpsia + sinchia * cosoma * cospsia) * sineps0 - sinchia * sinoma * coseps0;
    rp[3] = -sinchia * cospsia + coschia * cosoma * sinpsia;
    rp[4] = (sinchia * sinpsia + coschia * cosoma * cospsia) * coseps0 + coschia * sinoma * sineps0;
    rp[5] = (sinchia * sinpsia + coschia * cosoma * cospsia) * sineps0 - coschia * sinoma * coseps0;
    rp[6] = sinoma * sinpsia;
    rp[7] = sinoma * cospsia * coseps0 - cosoma * sineps0;
    rp[8] = sinoma * cospsia * sineps0 + cosoma * coseps0;
}

fn epsiln_owen_1986(tjd: f64, eps: *f64) void {
    var icof: i32 = 0;
    var k: [10]f64 = undefined;
    var tau: [10]f64 = undefined;
    var t0: f64 = undefined;
    get_owen_t0_icof(tjd, &t0, &icof);
    eps.* = 0;
    tau[0] = 0;
    tau[1] = (tjd - t0) / 36525.0 / 40.0;
    var i: usize = 2;
    while (i <= 9) : (i += 1) {
        tau[i] = tau[1] * tau[i - 1];
    }
    k[0] = 1;
    k[1] = tau[1];
    k[2] = 2 * tau[2] - 1;
    k[3] = 4 * tau[3] - 3 * tau[1];
    k[4] = 8 * tau[4] - 8 * tau[2] + 1;
    k[5] = 16 * tau[5] - 20 * tau[3] + 5 * tau[1];
    k[6] = 32 * tau[6] - 48 * tau[4] + 18 * tau[2] - 1;
    k[7] = 64 * tau[7] - 112 * tau[5] + 56 * tau[3] - 7 * tau[1];
    k[8] = 128 * tau[8] - 256 * tau[6] + 160 * tau[4] - 32 * tau[2] + 1;
    k[9] = 256 * tau[9] - 576 * tau[7] + 432 * tau[5] - 120 * tau[3] + 9 * tau[1];
    i = 0;
    while (i < 10) : (i += 1) {
        eps.* += (k[i] * owen_eps0_coef[@intCast(icof)][i]);
    }
}

// correction of eps for JPL Horizons epoch range (swephlib.c 876-886)
const OFFSET_EPS_JPLHORIZONS: f64 = 35.95;
const DCOR_EPS_JPL_TJD0: f64 = 2437846.5;
const NDCOR_EPS_JPL: usize = 51;
const dcor_eps_jpl = [NDCOR_EPS_JPL]f64{
    36.726, 36.627, 36.595, 36.578, 36.640, 36.659, 36.731, 36.765,
    36.662, 36.555, 36.335, 36.321, 36.354, 36.227, 36.289, 36.348,
    36.257, 36.163, 35.979, 35.896, 35.842, 35.825, 35.912, 35.950,
    36.093, 36.191, 36.009, 35.943, 35.875, 35.771, 35.788, 35.753,
    35.822, 35.866, 35.771, 35.732, 35.543, 35.498, 35.449, 35.409,
    35.497, 35.556, 35.672, 35.760, 35.596, 35.565, 35.510, 35.394,
    35.385, 35.375, 35.415,
};

/// Obliquity of the ecliptic at Julian date J (swephlib.c swi_epsiln)
pub fn swi_epsiln(J: f64, iflag: i32, models: AstroModels) f64 {
    var eps: f64 = undefined;
    var tofs: f64 = undefined;
    var dofs: f64 = undefined;
    var t0: f64 = undefined;
    var t1: f64 = undefined;
    var prec_model = models.prec_longterm;
    var prec_model_short = models.prec_shortterm;
    var jplhora_model = models.jplhora;
    var is_jplhor = false;
    if (prec_model == 0) prec_model = SEMOD_PREC_DEFAULT;
    if (prec_model_short == 0) prec_model_short = SEMOD_PREC_DEFAULT_SHORT;
    if (jplhora_model == 0) jplhora_model = SEMOD_JPLHORA_DEFAULT;
    if ((iflag & SEFLG_JPLHOR) != 0)
        is_jplhor = true;
    if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and
        jplhora_model == SEMOD_JPLHORA_3 and
        J <= HORIZONS_TJD0_DPSI_DEPS_IAU1980)
        is_jplhor = true;
    const T = (J - 2451545.0) / 36525.0;
    if (is_jplhor) {
        if (J > 2378131.5 and J < 2525323.5) {
            // between 1.1.1799 and 1.1.2202
            eps = (((1.813e-3 * T - 5.9e-4) * T - 46.8150) * T + 84381.448) * DEGTORAD / 3600;
        } else {
            epsiln_owen_1986(J, &eps);
            eps *= DEGTORAD;
        }
    } else if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and jplhora_model == SEMOD_JPLHORA_2) {
        eps = (((1.813e-3 * T - 5.9e-4) * T - 46.8150) * T + 84381.448) * DEGTORAD / 3600;
    } else if (prec_model_short == SEMOD_PREC_IAU_1976 and @abs(T) <= PREC_IAU_1976_CTIES) {
        eps = (((1.813e-3 * T - 5.9e-4) * T - 46.8150) * T + 84381.448) * DEGTORAD / 3600;
    } else if (prec_model == SEMOD_PREC_IAU_1976) {
        eps = (((1.813e-3 * T - 5.9e-4) * T - 46.8150) * T + 84381.448) * DEGTORAD / 3600;
    } else if (prec_model_short == SEMOD_PREC_IAU_2000 and @abs(T) <= PREC_IAU_2000_CTIES) {
        eps = (((1.813e-3 * T - 5.9e-4) * T - 46.84024) * T + 84381.406) * DEGTORAD / 3600;
    } else if (prec_model == SEMOD_PREC_IAU_2000) {
        eps = (((1.813e-3 * T - 5.9e-4) * T - 46.84024) * T + 84381.406) * DEGTORAD / 3600;
    } else if (prec_model_short == SEMOD_PREC_IAU_2006 and @abs(T) <= PREC_IAU_2006_CTIES) {
        eps = (((((-4.34e-8 * T - 5.76e-7) * T + 2.0034e-3) * T - 1.831e-4) * T - 46.836769) * T + 84381.406) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_NEWCOMB) {
        const Tn = (J - 2396758.0) / 36525.0;
        eps = (0.0017 * Tn * Tn * Tn - 0.0085 * Tn * Tn - 46.837 * Tn + 84451.68) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_IAU_2006) {
        eps = (((((-4.34e-8 * T - 5.76e-7) * T + 2.0034e-3) * T - 1.831e-4) * T - 46.836769) * T + 84381.406) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_BRETAGNON_2003) {
        eps = ((((((-3e-11 * T - 2.48e-8) * T - 5.23e-7) * T + 1.99911e-3) * T - 1.667e-4) * T - 46.836051) * T + 84381.40880) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_SIMON_1994) {
        eps = (((((2.5e-8 * T - 5.1e-7) * T + 1.9989e-3) * T - 1.52e-4) * T - 46.80927) * T + 84381.412) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_WILLIAMS_1994) {
        eps = ((((-1.0e-6 * T + 2.0e-3) * T - 1.74e-4) * T - 46.833960) * T + 84381.409) * DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_LASKAR_1986 or prec_model == SEMOD_PREC_WILL_EPS_LASK) {
        var T10 = T / 10.0;
        _ = &T10;
        eps = (((((((((2.45e-10 * T10 + 5.79e-9) * T10 + 2.787e-7) * T10 +
            7.12e-7) * T10 - 3.905e-5) * T10 - 2.4967e-3) * T10 -
            5.138e-3) * T10 + 1.99925) * T10 - 0.0155) * T10 - 468.093) * T10 +
            84381.448;
        eps *= DEGTORAD / 3600.0;
    } else if (prec_model == SEMOD_PREC_OWEN_1990) {
        epsiln_owen_1986(J, &eps);
        eps *= DEGTORAD;
    } else { // SEMOD_PREC_VONDRAK_2011
        swi_ldp_peps(J, null, &eps);
        if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and jplhora_model != SEMOD_JPLHORA_2) {
            tofs = (J - DCOR_EPS_JPL_TJD0) / 365.25;
            dofs = OFFSET_EPS_JPLHORIZONS;
            if (tofs < 0) {
                tofs = 0;
                dofs = dcor_eps_jpl[0];
            } else if (tofs >= @as(f64, @floatFromInt(NDCOR_EPS_JPL - 1))) {
                tofs = @floatFromInt(NDCOR_EPS_JPL);
                dofs = dcor_eps_jpl[NDCOR_EPS_JPL - 1];
            } else {
                t0 = @trunc(tofs);
                t1 = t0 + 1;
                dofs = dcor_eps_jpl[@intFromFloat(t0)];
                dofs = (tofs - t0) * (dcor_eps_jpl[@intFromFloat(t0)] - dcor_eps_jpl[@intFromFloat(t1)]) + dcor_eps_jpl[@intFromFloat(t0)];
            }
            dofs /= (1000.0 * 3600.0);
            eps += dofs * DEGTORAD;
        }
    }
    return eps;
}

fn precess_1(R: *[3]f64, J: f64, direction: i32, prec_method: i32) i32 {
    var Z: f64 = 0;
    var z: f64 = 0;
    var TH: f64 = 0;
    var x: [3]f64 = undefined;
    if (J == J2000)
        return 0;
    var T = (J - J2000) / 36525.0;
    if (prec_method == SEMOD_PREC_IAU_1976) {
        Z = ((0.017998 * T + 0.30188) * T + 2306.2181) * T * DEGTORAD / 3600;
        z = ((0.018203 * T + 1.09468) * T + 2306.2181) * T * DEGTORAD / 3600;
        TH = ((-0.041833 * T - 0.42665) * T + 2004.3109) * T * DEGTORAD / 3600;
    } else if (prec_method == SEMOD_PREC_IAU_2000) {
        Z = (((((-0.0000002 * T - 0.0000327) * T + 0.0179663) * T + 0.3019015) * T + 2306.0809506) * T + 2.5976176) * DEGTORAD / 3600;
        z = (((((-0.0000003 * T - 0.000047) * T + 0.0182237) * T + 1.0947790) * T + 2306.0803226) * T - 2.5976176) * DEGTORAD / 3600;
        TH = ((((-0.0000001 * T - 0.0000601) * T - 0.0418251) * T - 0.4269353) * T + 2004.1917476) * T * DEGTORAD / 3600;
    } else if (prec_method == SEMOD_PREC_IAU_2006) {
        T = (J - J2000) / 36525.0;
        Z = (((((-0.0000003173 * T - 0.000005971) * T + 0.01801828) * T + 0.2988499) * T + 2306.083227) * T + 2.650545) * DEGTORAD / 3600;
        z = (((((-0.0000002904 * T - 0.000028596) * T + 0.01826837) * T + 1.0927348) * T + 2306.077181) * T - 2.650545) * DEGTORAD / 3600;
        TH = ((((-0.00000011274 * T - 0.000007089) * T - 0.04182264) * T - 0.4294934) * T + 2004.191903) * T * DEGTORAD / 3600;
    } else if (prec_method == SEMOD_PREC_BRETAGNON_2003) {
        Z = ((((((-0.00000000013 * T - 0.0000003040) * T - 0.000005708) * T + 0.01801752) * T + 0.3023262) * T + 2306.080472) * T + 2.72767) * DEGTORAD / 3600;
        z = ((((((-0.00000000005 * T - 0.0000002486) * T - 0.000028276) * T + 0.01826676) * T + 1.0956768) * T + 2306.076070) * T - 2.72767) * DEGTORAD / 3600;
        TH = ((((((0.000000000009 * T + 0.00000000036) * T - 0.0000001127) * T - 0.000007291) * T - 0.04182364) * T - 0.4266980) * T + 2004.190936) * T * DEGTORAD / 3600;
    } else if (prec_method == SEMOD_PREC_NEWCOMB) {
        const mills: f64 = 365242.198782; // trop. millennia
        const t1 = (J2000 - B1850) / mills;
        const t2 = (J - B1850) / mills;
        T = t2 - t1;
        const T2 = T * T;
        const T3 = T2 * T;
        const Z1 = 23035.5548 + 139.720 * t1 + 0.069 * t1 * t1;
        Z = Z1 * T + (30.242 - 0.269 * t1) * T2 + 17.996 * T3;
        z = Z1 * T + (109.478 - 0.387 * t1) * T2 + 18.324 * T3;
        TH = (20051.125 - 85.294 * t1 - 0.365 * t1 * t1) * T + (-42.647 - 0.365 * t1) * T2 - 41.802 * T3;
        Z *= (DEGTORAD / 3600.0);
        z *= (DEGTORAD / 3600.0);
        TH *= (DEGTORAD / 3600.0);
    } else {
        return 0;
    }
    const sinth = swe_shim_sin(TH);
    const costh = swe_shim_cos(TH);
    const sinZ = swe_shim_sin(Z);
    const cosZ = swe_shim_cos(Z);
    const sinz = swe_shim_sin(z);
    const cosz = swe_shim_cos(z);
    const A = cosZ * costh;
    const B = sinZ * costh;
    if (direction < 0) { // From J2000.0 to J
        x[0] = (A * cosz - sinZ * sinz) * R[0] - (B * cosz + cosZ * sinz) * R[1] - sinth * cosz * R[2];
        x[1] = (A * sinz + sinZ * cosz) * R[0] - (B * sinz - cosZ * cosz) * R[1] - sinth * sinz * R[2];
        x[2] = cosZ * sinth * R[0] - sinZ * sinth * R[1] + costh * R[2];
    } else { // From J to J2000.0
        x[0] = (A * cosz - sinZ * sinz) * R[0] + (A * sinz + sinZ * cosz) * R[1] + cosZ * sinth * R[2];
        x[1] = -(B * cosz + cosZ * sinz) * R[0] - (B * sinz - cosZ * cosz) * R[1] - sinZ * sinth * R[2];
        x[2] = -sinth * cosz * R[0] - sinth * sinz * R[1] + costh * R[2];
    }
    var i: usize = 0;
    while (i < 3) : (i += 1)
        R[i] = x[i];
    return 0;
}

// SEMOD_PREC_WILLIAMS_1994
const pAcof_williams = [_]f64{ -8.66e-10, -4.759e-8, 2.424e-7, 1.3095e-5, 1.7451e-4, -1.8055e-3, -0.235316, 0.076, 110.5407, 50287.70000 };
const nodecof_williams = [_]f64{ 6.6402e-16, -2.69151e-15, -1.547021e-12, 7.521313e-12, 1.9e-10, -3.54e-9, -1.8103e-7, 1.26e-7, 7.436169e-5, -0.04207794833, 3.052115282424 };
const inclcof_williams = [_]f64{ 1.2147e-16, 7.3759e-17, -8.26287e-14, 2.503410e-13, 2.4650839e-11, -5.4000441e-11, 1.32115526e-9, -6.012e-7, -1.62442e-5, 0.00227850649, 0.0 };

// SEMOD_PREC_SIMON_1994
const pAcof_simon = [_]f64{ -8.66e-10, -4.759e-8, 2.424e-7, 1.3095e-5, 1.7451e-4, -1.8055e-3, -0.235316, 0.07732, 111.2022, 50288.200 };
const nodecof_simon = [_]f64{ 6.6402e-16, -2.69151e-15, -1.547021e-12, 7.521313e-12, 1.9e-10, -3.54e-9, -1.8103e-7, 2.579e-8, 7.4379679e-5, -0.0420782900, 3.0521126906 };
const inclcof_simon = [_]f64{ 1.2147e-16, 7.3759e-17, -8.26287e-14, 2.503410e-13, 2.4650839e-11, -5.4000441e-11, 1.32115526e-9, -5.99908e-7, -1.624383e-5, 0.002278492868, 0.0 };

// SEMOD_PREC_LASKAR_1986
const pAcof_laskar = [_]f64{ -8.66e-10, -4.759e-8, 2.424e-7, 1.3095e-5, 1.7451e-4, -1.8055e-3, -0.235316, 0.07732, 111.1971, 50290.966 };
const nodecof_laskar = [_]f64{ 6.6402e-16, -2.69151e-15, -1.547021e-12, 7.521313e-12, 6.3190131e-10, -3.48388152e-9, -1.813065896e-7, 2.75036225e-8, 7.4394531426e-5, -0.042078604317, 3.052112654975 };
const inclcof_laskar = [_]f64{ 1.2147e-16, 7.3759e-17, -8.26287e-14, 2.503410e-13, 2.4650839e-11, -5.4000441e-11, 1.32115526e-9, -5.998737027e-7, -1.6242797091e-5, 0.002278495537, 0.0 };

fn precess_2(R: *[3]f64, J: f64, iflag: i32, direction: i32, prec_method: i32, models: AstroModels) i32 {
    var x: [3]f64 = undefined;
    var pAcof: []const f64 = undefined;
    var inclcof: []const f64 = undefined;
    var nodecof: []const f64 = undefined;
    if (J == J2000)
        return 0;
    if (prec_method == SEMOD_PREC_LASKAR_1986) {
        pAcof = &pAcof_laskar;
        nodecof = &nodecof_laskar;
        inclcof = &inclcof_laskar;
    } else if (prec_method == SEMOD_PREC_SIMON_1994) {
        pAcof = &pAcof_simon;
        nodecof = &nodecof_simon;
        inclcof = &inclcof_simon;
    } else if (prec_method == SEMOD_PREC_WILLIAMS_1994) {
        pAcof = &pAcof_williams;
        nodecof = &nodecof_williams;
        inclcof = &inclcof_williams;
    } else { // default, to satisfy compiler
        pAcof = &pAcof_laskar;
        nodecof = &nodecof_laskar;
        inclcof = &inclcof_laskar;
    }
    var T = (J - J2000) / 36525.0;
    // Implementation by elementary rotations using Laskar's expansions.
    // First rotate about the x axis from the initial equator
    // to the ecliptic. (The input is equatorial.)
    var eps: f64 = undefined;
    if (direction == 1)
        eps = swi_epsiln(J, iflag, models) // To J2000
    else
        eps = swi_epsiln(J2000, iflag, models); // From J2000
    const sineps = swe_shim_sin(eps);
    const coseps = swe_shim_cos(eps);
    x[0] = R[0];
    var z = coseps * R[1] + sineps * R[2];
    x[2] = -sineps * R[1] + coseps * R[2];
    x[1] = z;
    // Precession in longitude
    T /= 10.0; // thousands of years
    var pA = pAcof[0];
    {
        var i: usize = 1;
        while (i <= 9) : (i += 1) {
            pA = pA * T + pAcof[i];
        }
    }
    pA *= DEGTORAD / 3600 * T;
    // Node of the moving ecliptic on the J2000 ecliptic.
    var W = nodecof[0];
    {
        var i: usize = 1;
        while (i <= 10) : (i += 1)
            W = W * T + nodecof[i];
    }
    // Rotate about z axis to the node.
    if (direction == 1)
        z = W + pA
    else
        z = W;
    var B = swe_shim_cos(z);
    var A = swe_shim_sin(z);
    z = B * x[0] + A * x[1];
    x[1] = -A * x[0] + B * x[1];
    x[0] = z;
    // Rotate about new x axis by the inclination of the moving
    // ecliptic on the J2000 ecliptic.
    z = inclcof[0];
    {
        var i: usize = 1;
        while (i <= 10) : (i += 1)
            z = z * T + inclcof[i];
    }
    if (direction == 1)
        z = -z;
    B = swe_shim_cos(z);
    A = swe_shim_sin(z);
    z = B * x[1] + A * x[2];
    x[2] = -A * x[1] + B * x[2];
    x[1] = z;
    // Rotate about new z axis back from the node.
    if (direction == 1)
        z = -W
    else
        z = -W - pA;
    B = swe_shim_cos(z);
    A = swe_shim_sin(z);
    z = B * x[0] + A * x[1];
    x[1] = -A * x[0] + B * x[1];
    x[0] = z;
    // Rotate about x axis to final equator.
    if (direction == 1)
        eps = swi_epsiln(J2000, iflag, models)
    else
        eps = swi_epsiln(J, iflag, models);
    const sineps2 = swe_shim_sin(eps);
    const coseps2 = swe_shim_cos(eps);
    z = coseps2 * x[1] - sineps2 * x[2];
    x[2] = sineps2 * x[1] + coseps2 * x[2];
    x[1] = z;
    var i: usize = 0;
    while (i < 3) : (i += 1)
        R[i] = x[i];
    return 0;
}

fn precess_3(R: *[3]f64, J: f64, direction: i32, iflag: i32, prec_meth: i32) i32 {
    var x: [3]f64 = undefined;
    var pmat: [9]f64 = undefined;
    if (J == J2000)
        return 0;
    if (prec_meth == SEMOD_PREC_OWEN_1990)
        owen_pre_matrix(J, &pmat, iflag)
    else
        pre_pmat(J, &pmat);
    if (direction == -1) {
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            const j = i * 3;
            x[i] = R[0] * pmat[j + 0] + R[1] * pmat[j + 1] + R[2] * pmat[j + 2];
        }
    } else {
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            x[i] = R[0] * pmat[i + 0] + R[1] * pmat[i + 3] + R[2] * pmat[i + 6];
        }
    }
    var i: usize = 0;
    while (i < 3) : (i += 1)
        R[i] = x[i];
    return 0;
}

/// Precession of the equinox and ecliptic (swephlib.c swi_precess)
pub fn swi_precess(R: *[3]f64, J: f64, iflag: i32, direction: i32, models: AstroModels) i32 {
    const T = (J - J2000) / 36525.0;
    var prec_model = models.prec_longterm;
    var prec_model_short = models.prec_shortterm;
    var jplhora_model = models.jplhora;
    var is_jplhor = false;
    if (prec_model == 0) prec_model = SEMOD_PREC_DEFAULT;
    if (prec_model_short == 0) prec_model_short = SEMOD_PREC_DEFAULT_SHORT;
    if (jplhora_model == 0) jplhora_model = SEMOD_JPLHORA_DEFAULT;
    if ((iflag & SEFLG_JPLHOR) != 0)
        is_jplhor = true;
    if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and
        jplhora_model == SEMOD_JPLHORA_3 and
        J <= HORIZONS_TJD0_DPSI_DEPS_IAU1980)
        is_jplhor = true;
    // JPL Horizons uses precession IAU 1976 and nutation IAU 1980 plus
    // some correction to nutation, arriving at extremely high precision
    if (is_jplhor) {
        if (J > 2378131.5 and J < 2525323.5) { // between 1.1.1799 and 1.1.2202
            return precess_1(R, J, direction, SEMOD_PREC_IAU_1976);
        } else {
            return precess_3(R, J, direction, iflag, SEMOD_PREC_OWEN_1990);
        }
        // Use IAU 1976 formula for a few centuries.
    } else if (prec_model_short == SEMOD_PREC_IAU_1976 and @abs(T) <= PREC_IAU_1976_CTIES) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_1976);
    } else if (prec_model == SEMOD_PREC_IAU_1976) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_1976);
    } else if (prec_model_short == SEMOD_PREC_IAU_2000 and @abs(T) <= PREC_IAU_2000_CTIES) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_2000);
    } else if (prec_model == SEMOD_PREC_IAU_2000) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_2000);
    } else if (prec_model_short == SEMOD_PREC_IAU_2006 and @abs(T) <= PREC_IAU_2006_CTIES) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_2006);
    } else if (prec_model == SEMOD_PREC_IAU_2006) {
        return precess_1(R, J, direction, SEMOD_PREC_IAU_2006);
    } else if (prec_model == SEMOD_PREC_BRETAGNON_2003) {
        return precess_1(R, J, direction, SEMOD_PREC_BRETAGNON_2003);
    } else if (prec_model == SEMOD_PREC_NEWCOMB) {
        return precess_1(R, J, direction, SEMOD_PREC_NEWCOMB);
    } else if (prec_model == SEMOD_PREC_LASKAR_1986) {
        return precess_2(R, J, iflag, direction, SEMOD_PREC_LASKAR_1986, models);
    } else if (prec_model == SEMOD_PREC_SIMON_1994) {
        return precess_2(R, J, iflag, direction, SEMOD_PREC_SIMON_1994, models);
    } else if (prec_model == SEMOD_PREC_WILLIAMS_1994 or prec_model == SEMOD_PREC_WILL_EPS_LASK) {
        return precess_2(R, J, iflag, direction, SEMOD_PREC_WILLIAMS_1994, models);
    } else if (prec_model == SEMOD_PREC_OWEN_1990) {
        return precess_3(R, J, direction, iflag, SEMOD_PREC_OWEN_1990);
    } else { // SEMOD_PREC_VONDRAK_2011
        return precess_3(R, J, direction, iflag, SEMOD_PREC_VONDRAK_2011);
    }
}

// ---------------------------------------------------------------------------
// Nutation (swephlib.c 1487-2158)
const nt = [1008]i16{
    0,   0,   0,   0,   2,   2062, 2,      -895, 5,    -2,  0,  2,   0,    1,   46,   0,    -24, 0,  2,     0,  -2,   0,   0,   11,   0,    0,   0,   -2,  0,   2,   0,
    2,   -3,  0,   1,   0,   1,    -1,     0,    -1,   0,   -3, 0,   0,    0,   0,    -2,   2,   -2, 1,     -2, 0,    1,   0,   2,    0,    -2,  0,   1,   1,   0,   0,
    0,   0,   0,   2,   -2,  2,    -13187, -16,  5736, -31, 0,  1,   0,    0,   0,    1426, -34, 54, -1,    0,  1,    2,   -2,  2,    -517, 12,  224, -6,  0,   -1,  2,
    -2,  2,   217, -5,  -95, 3,    0,      0,    2,    -2,  1,  129, 1,    -70, 0,    2,    0,   0,  -2,    0,  48,   0,   1,   0,    0,    0,   2,   -2,  0,   -22, 0,
    0,   0,   0,   2,   0,   0,    0,      17,   -1,   0,   0,  0,   1,    0,   0,    1,    -15, 0,  9,     0,  0,    2,   2,   -2,   2,    -16, 1,   7,   0,   0,   -1,
    0,   0,   1,   -12, 0,   6,    0,      -2,   0,    0,   2,  1,   -6,   0,   3,    0,    0,   -1, 2,     -2, 1,    -5,  0,   3,    0,    2,   0,   0,   -2,  1,   4,
    0,   -2,  0,   0,   1,   2,    -2,     1,    4,    0,   -2, 0,   1,    0,   0,    -1,   0,   -4, 0,     0,  0,    2,   1,   0,    -2,   0,   1,   0,   0,   0,   0,
    0,   -2,  2,   1,   1,   0,    0,      0,    0,    1,   -2, 2,   0,    -1,  0,    0,    0,   0,  1,     0,  0,    2,   1,   0,    0,    0,   -1,  0,   0,   1,   1,
    1,   0,   0,   0,   0,   1,    2,      -2,   0,    -1,  0,  0,   0,    0,   0,    2,    0,   2,  -2274, -2, 977,  -5,  1,   0,    0,    0,   0,   712, 1,   -7,  0,
    0,   0,   2,   0,   1,   -386, -4,     200,  0,    1,   0,  2,   0,    2,   -301, 0,    129, -1, 1,     0,  0,    -2,  0,   -158, 0,    -1,  0,   -1,  0,   2,   0,
    2,   123, 0,   -53, 0,   0,    0,      0,    2,    0,   63, 0,   -2,   0,   1,    0,    0,   0,  1,     63, 1,    -33, 0,   -1,   0,    0,   0,   1,   -58, -1,  32,
    0,   -1,  0,   2,   2,   2,    -59,    0,    26,   0,   1,  0,   2,    0,   1,    -51,  0,   27, 0,     0,  0,    2,   2,   2,    -38,  0,   16,  0,   2,   0,   0,
    0,   0,   29,  0,   -1,  0,    1,      0,    2,    -2,  2,  29,  0,    -12, 0,    2,    0,   2,  0,     2,  -31,  0,   13,  0,    0,    0,   2,   0,   0,   26,  0,
    -1,  0,   -1,  0,   2,   0,    1,      21,   0,    -10, 0,  -1,  0,    0,   2,    1,    16,  0,  -8,    0,  1,    0,   0,   -2,   1,    -13, 0,   7,   0,   -1,  0,
    2,   2,   1,   -10, 0,   5,    0,      1,    1,    0,   -2, 0,   -7,   0,   0,    0,    0,   1,  2,     0,  2,    7,   0,   -3,   0,    0,   -1,  2,   0,   2,   -7,
    0,   3,   0,   1,   0,   2,    2,      2,    -8,   0,   3,  0,   1,    0,   0,    2,    0,   6,  0,     0,  0,    2,   0,   2,    -2,   2,   6,   0,   -3,  0,   0,
    0,   0,   2,   1,   -6,  0,    3,      0,    0,    0,   2,  2,   1,    -7,  0,    3,    0,   1,  0,     2,  -2,   1,   6,   0,    -3,   0,   0,   0,   0,   -2,  1,
    -5,  0,   3,   0,   1,   -1,   0,      0,    0,    5,   0,  0,   0,    2,   0,    2,    0,   1,  -5,    0,  3,    0,   0,   1,    0,    -2,  0,   -4,  0,   0,   0,
    1,   0,   -2,  0,   0,   4,    0,      0,    0,    0,   0,  0,   1,    0,   -4,   0,    0,   0,  1,     1,  0,    0,   0,   -3,   0,    0,   0,   1,   0,   2,   0,
    0,   3,   0,   0,   0,   1,    -1,     2,    0,    2,   -3, 0,   1,    0,   -1,   -1,   2,   2,  2,     -3, 0,    1,   0,   -2,   0,    0,   0,   1,   -2,  0,   1,
    0,   3,   0,   2,   0,   2,    -3,     0,    1,    0,   0,  -1,  2,    2,   2,    -3,   0,   1,  0,     1,  1,    2,   0,   2,    2,    0,   -1,  0,   -1,  0,   2,
    -2,  1,   -2,  0,   1,   0,    2,      0,    0,    0,   1,  2,   0,    -1,  0,    1,    0,   0,  0,     2,  -2,   0,   1,   0,    3,    0,   0,   0,   0,   2,   0,
    0,   0,   0,   0,   2,   1,    2,      2,    0,    -1,  0,  -1,  0,    0,   0,    2,    1,   0,  -1,    0,  1,    0,   0,   -4,   0,    -1,  0,   0,   0,   -2,  0,
    2,   2,   2,   1,   0,   -1,   0,      -1,   0,    2,   4,  2,   -2,   0,   1,    0,    2,   0,  0,     -4, 0,    -1,  0,   0,    0,    1,   1,   2,   -2,  2,   1,
    0,   -1,  0,   1,   0,   2,    2,      1,    -1,   0,   1,  0,   -2,   0,   2,    4,    2,   -1, 0,     1,  0,    -1,  0,   4,    0,    2,   1,   0,   0,   0,   1,
    -1,  0,   -2,  0,   1,   0,    0,      0,    2,    0,   2,  -2,  1,    1,   0,    -1,   0,   2,  0,     2,  2,    2,   -1,  0,    0,    0,   1,   0,   0,   2,   1,
    -1,  0,   0,   0,   0,   0,    4,      -2,   2,    1,   0,  0,   0,    3,   0,    2,    -2,  2,  1,     0,  0,    0,   1,   0,    2,    -2,  0,   -1,  0,   0,   0,
    0,   1,   2,   0,   1,   1,    0,      0,    0,    -1,  -1, 0,   2,    1,   1,    0,    0,   0,  0,     0,  -2,   0,   1,   -1,   0,    0,   0,   0,   0,   2,   -1,
    2,   -1,  0,   0,   0,   0,    1,      0,    2,    0,   -1, 0,   0,    0,   1,    0,    -2,  -2, 0,     -1, 0,    0,   0,   0,    -1,   2,   0,   1,   -1,  0,   0,
    0,   1,   1,   0,   -2,  1,    -1,     0,    0,    0,   1,  0,   -2,   2,   0,    -1,   0,   0,  0,     2,  0,    0,   2,   0,    1,    0,   0,   0,   0,   0,   2,
    4,   2,   -1,  0,   0,   0,    0,      1,    0,    1,   0,  1,   0,    0,   0,    101,  0,   0,  0,     1,  -725, 0,   213, 0,    101,  1,   0,   0,   0,   523, 0,
    208, 0,   101, 0,   2,   -2,   2,      102,  0,    -41, 0,  101, 0,    2,   0,    2,    -81, 0,  32,    0,  102,  0,   0,   0,    1,    417, 0,   224, 0,   102, 1,
    0,   0,   0,   61,  0,   -24,  0,      102,  0,    2,   -2, 2,   -118, 0,   -47,  0,
};

const nls = [3390]i16{
    0,  0,  0,  0,  1,  0,  0,  2,  -2, 2,  0,  0,  2,  0,  2,  0,  0,  0,  0,  2,  0,  1,  0,  0,  0,  0,  1,  2,  -2, 2,  1,  0,  0,  0,
    0,  0,  0,  2,  0,  1,  1,  0,  2,  0,  2,  0,  -1, 2,  -2, 2,  0,  0,  2,  -2, 1,  -1, 0,  2,  0,  2,  -1, 0,  0,  2,  0,  1,  0,  0,
    0,  1,  -1, 0,  0,  0,  1,  -1, 0,  2,  2,  2,  1,  0,  2,  0,  1,  -2, 0,  2,  0,  1,  0,  0,  0,  2,  0,  0,  0,  2,  2,  2,  0,  -2,
    2,  -2, 2,  -2, 0,  0,  2,  0,  2,  0,  2,  0,  2,  1,  0,  2,  -2, 2,  -1, 0,  2,  0,  1,  2,  0,  0,  0,  0,  0,  0,  2,  0,  0,  0,
    1,  0,  0,  1,  -1, 0,  0,  2,  1,  0,  2,  2,  -2, 2,  0,  0,  -2, 2,  0,  1,  0,  0,  -2, 1,  0,  -1, 0,  0,  1,  -1, 0,  2,  2,  1,
    0,  2,  0,  0,  0,  1,  0,  2,  2,  2,  -2, 0,  2,  0,  0,  0,  1,  2,  0,  2,  0,  0,  2,  2,  1,  0,  -1, 2,  0,  2,  0,  0,  0,  2,
    1,  1,  0,  2,  -2, 1,  2,  0,  2,  -2, 2,  -2, 0,  0,  2,  1,  2,  0,  2,  0,  1,  0,  -1, 2,  -2, 1,  0,  0,  0,  -2, 1,  -1, -1, 0,
    2,  0,  2,  0,  0,  -2, 1,  1,  0,  0,  2,  0,  0,  1,  2,  -2, 1,  1,  -1, 0,  0,  0,  -2, 0,  2,  0,  2,  3,  0,  2,  0,  2,  0,  -1,
    0,  2,  0,  1,  -1, 2,  0,  2,  0,  0,  0,  1,  0,  -1, -1, 2,  2,  2,  -1, 0,  2,  0,  0,  0,  -1, 2,  2,  2,  -2, 0,  0,  0,  1,  1,
    1,  2,  0,  2,  2,  0,  0,  0,  1,  -1, 1,  0,  1,  0,  1,  1,  0,  0,  0,  1,  0,  2,  0,  0,  -1, 0,  2,  -2, 1,  1,  0,  0,  0,  2,
    -1, 0,  0,  1,  0,  0,  0,  2,  1,  2,  -1, 0,  2,  4,  2,  -1, 1,  0,  1,  1,  0,  -2, 2,  -2, 1,  1,  0,  2,  2,  1,  -2, 0,  2,  2,
    2,  -1, 0,  0,  0,  2,  1,  1,  2,  -2, 2,  -2, 0,  2,  4,  2,  -1, 0,  4,  0,  2,  2,  0,  2,  -2, 1,  2,  0,  2,  2,  2,  1,  0,  0,
    2,  1,  3,  0,  0,  0,  0,  3,  0,  2,  -2, 2,  0,  0,  4,  -2, 2,  0,  1,  2,  0,  1,  0,  0,  -2, 2,  1,  0,  0,  2,  -2, 3,  -1, 0,
    0,  4,  0,  2,  0,  -2, 0,  1,  -2, 0,  0,  4,  0,  -1, -1, 0,  2,  1,  -1, 0,  0,  1,  1,  0,  1,  0,  0,  2,  0,  0,  -2, 0,  1,  0,
    -1, 2,  0,  1,  0,  0,  2,  -1, 2,  0,  0,  2,  4,  2,  -2, -1, 0,  2,  0,  1,  1,  0,  -2, 1,  -1, 1,  0,  2,  0,  -1, 1,  0,  1,  2,
    1,  -1, 0,  0,  1,  1,  -1, 2,  2,  2,  -1, 1,  2,  2,  2,  3,  0,  2,  0,  1,  0,  1,  -2, 2,  0,  -1, 0,  0,  -2, 1,  0,  1,  2,  2,
    2,  -1, -1, 2,  2,  1,  0,  -1, 0,  0,  2,  1,  0,  2,  -4, 1,  -1, 0,  -2, 2,  0,  0,  -1, 2,  2,  1,  2,  -1, 2,  0,  2,  0,  0,  0,
    2,  2,  1,  -1, 2,  0,  1,  -1, 1,  2,  0,  2,  0,  1,  0,  2,  0,  0,  -1, -2, 2,  0,  0,  3,  2,  -2, 2,  0,  0,  0,  1,  1,  -1, 0,
    2,  2,  0,  2,  1,  2,  0,  2,  1,  1,  0,  0,  1,  1,  1,  2,  0,  1,  2,  0,  0,  2,  0,  1,  0,  -2, 2,  0,  -1, 0,  0,  2,  2,  0,
    1,  0,  1,  0,  0,  1,  0,  -2, 1,  -1, 0,  2,  -2, 2,  0,  0,  0,  -1, 1,  -1, 1,  0,  0,  1,  1,  0,  2,  -1, 2,  1,  -1, 0,  2,  0,
    0,  0,  0,  4,  0,  1,  0,  2,  1,  2,  0,  0,  2,  1,  1,  1,  0,  0,  -2, 2,  -1, 0,  2,  4,  1,  1,  0,  -2, 0,  1,  1,  1,  2,  -2,
    1,  0,  0,  2,  2,  0,  -1, 0,  2,  -1, 1,  -2, 0,  2,  2,  1,  4,  0,  2,  0,  2,  2,  -1, 0,  0,  0,  2,  1,  2,  -2, 2,  0,  1,  2,
    1,  2,  1,  0,  4,  -2, 2,  -1, -1, 0,  0,  1,  0,  1,  0,  2,  1,  -2, 0,  2,  4,  1,  2,  0,  2,  0,  0,  1,  0,  0,  1,  0,  -1, 0,
    0,  4,  1,  -1, 0,  4,  0,  1,  2,  0,  2,  2,  1,  0,  0,  2,  -3, 2,  -1, -2, 0,  2,  0,  2,  1,  0,  0,  0,  0,  0,  4,  0,  2,  0,
    0,  0,  0,  3,  0,  3,  0,  0,  0,  0,  0,  2,  -4, 1,  0,  -1, 0,  2,  1,  0,  0,  0,  4,  1,  -1, -1, 2,  4,  2,  1,  0,  2,  4,  2,
    -2, 2,  0,  2,  0,  -2, -1, 2,  0,  1,  -2, 0,  0,  2,  2,  -1, -1, 2,  0,  2,  0,  0,  4,  -2, 1,  3,  0,  2,  -2, 1,  -2, -1, 0,  2,
    1,  1,  0,  0,  -1, 1,  0,  -2, 0,  2,  0,  -2, 0,  0,  4,  1,  -3, 0,  0,  0,  1,  1,  1,  2,  2,  2,  0,  0,  2,  4,  1,  3,  0,  2,
    2,  2,  -1, 1,  2,  -2, 1,  2,  0,  0,  -4, 1,  0,  0,  0,  -2, 2,  2,  0,  2,  -4, 1,  -1, 1,  0,  2,  1,  0,  0,  2,  -1, 1,  0,  -2,
    2,  2,  2,  2,  0,  0,  2,  1,  4,  0,  2,  -2, 2,  2,  0,  0,  -2, 2,  0,  2,  0,  0,  1,  1,  0,  0,  -4, 1,  0,  2,  2,  -2, 1,  -3,
    0,  0,  4,  0,  -1, 1,  2,  0,  1,  -1, -1, 0,  4,  0,  -1, -2, 2,  2,  2,  -2, -1, 2,  4,  2,  1,  -1, 2,  2,  1,  -2, 1,  0,  2,  0,
    -2, 1,  2,  0,  1,  2,  1,  0,  -2, 1,  -3, 0,  2,  0,  1,  -2, 0,  2,  -2, 1,  -1, 1,  0,  2,  2,  0,  -1, 2,  -1, 2,  -1, 0,  4,  -2,
    2,  0,  -2, 2,  0,  2,  -1, 0,  2,  1,  2,  2,  0,  0,  0,  2,  0,  0,  2,  0,  3,  -2, 0,  4,  0,  2,  -1, 0,  -2, 0,  1,  -1, 1,  2,
    2,  1,  3,  0,  0,  0,  1,  -1, 0,  2,  3,  2,  2,  -1, 2,  0,  1,  0,  1,  2,  2,  1,  0,  -1, 2,  4,  2,  2,  -1, 2,  2,  2,  0,  2,
    -2, 2,  0,  -1, -1, 2,  -1, 1,  0,  -2, 0,  0,  1,  1,  0,  2,  -4, 2,  1,  -1, 0,  -2, 1,  -1, -1, 2,  0,  1,  1,  -1, 2,  -2, 2,  -2,
    -1, 0,  4,  0,  -1, 0,  0,  3,  0,  -2, -1, 2,  2,  2,  0,  2,  2,  0,  2,  1,  1,  0,  2,  0,  2,  0,  2,  -1, 2,  1,  0,  2,  1,  1,
    4,  0,  0,  0,  0,  2,  1,  2,  0,  1,  3,  -1, 2,  0,  2,  -2, 2,  0,  2,  1,  1,  0,  2,  -3, 1,  1,  1,  2,  -4, 1,  -1, -1, 2,  -2,
    1,  0,  -1, 0,  -1, 1,  0,  -1, 0,  -2, 1,  -2, 0,  0,  0,  2,  -2, 0,  -2, 2,  0,  -1, 0,  -2, 4,  0,  1,  -2, 0,  0,  0,  0,  1,  0,
    1,  1,  -1, 2,  0,  2,  0,  1,  -1, 2,  -2, 1,  1,  2,  2,  -2, 2,  2,  -1, 2,  -2, 2,  1,  0,  2,  -1, 1,  2,  1,  2,  -2, 1,  -2, 0,
    0,  -2, 1,  1,  -2, 2,  0,  2,  0,  1,  2,  1,  1,  1,  0,  4,  -2, 1,  -2, 0,  4,  2,  2,  1,  1,  2,  1,  2,  1,  0,  0,  4,  0,  1,
    0,  2,  2,  0,  2,  0,  2,  1,  2,  3,  1,  2,  0,  2,  4,  0,  2,  0,  1,  -2, -1, 2,  0,  0,  0,  1,  -2, 2,  1,  1,  0,  -2, 1,  0,
    0,  -1, -2, 2,  1,  2,  -1, 0,  -2, 1,  -1, 0,  2,  -1, 2,  1,  0,  2,  -3, 2,  0,  1,  2,  -2, 3,  0,  0,  2,  -3, 1,  -1, 0,  -2, 2,
    1,  0,  0,  2,  -4, 2,  -2, 1,  0,  0,  1,  -1, 0,  0,  -1, 1,  2,  0,  2,  -4, 2,  0,  0,  4,  -4, 4,  0,  0,  4,  -4, 2,  -1, -2, 0,
    2,  1,  -2, 0,  0,  3,  0,  1,  0,  -2, 2,  1,  -3, 0,  2,  2,  2,  -3, 0,  2,  2,  1,  -2, 0,  2,  2,  0,  2,  -1, 0,  0,  1,  -2, 1,
    2,  2,  2,  1,  1,  0,  1,  0,  0,  1,  4,  -2, 2,  -1, 1,  0,  -2, 1,  0,  0,  0,  -4, 1,  1,  -1, 0,  2,  1,  1,  1,  0,  2,  1,  -1,
    2,  2,  2,  2,  3,  1,  2,  -2, 2,  0,  -1, 0,  4,  0,  2,  -1, 0,  2,  0,  0,  0,  4,  0,  1,  2,  0,  4,  -2, 2,  -1, -1, 2,  4,  1,
    1,  0,  0,  4,  1,  1,  -2, 2,  2,  2,  0,  0,  2,  3,  2,  -1, 1,  2,  4,  2,  3,  0,  0,  2,  0,  -1, 0,  4,  2,  2,  1,  1,  2,  2,
    1,  -2, 0,  2,  6,  2,  2,  1,  2,  2,  2,  -1, 0,  2,  6,  2,  1,  0,  2,  4,  1,  2,  0,  2,  4,  2,  1,  1,  -2, 1,  0,  -3, 1,  2,
    1,  2,  2,  0,  -2, 0,  2,  -1, 0,  0,  1,  2,  -4, 0,  2,  2,  1,  -1, -1, 0,  1,  0,  0,  0,  -2, 2,  2,  1,  0,  0,  -1, 2,  0,  -1,
    2,  -2, 3,  -2, 1,  2,  0,  0,  0,  0,  2,  -2, 4,  -2, -2, 0,  2,  0,  -2, 0,  -2, 4,  0,  0,  -2, -2, 2,  0,  1,  2,  0,  -2, 1,  3,
    0,  0,  -4, 1,  -1, 1,  2,  -2, 2,  1,  -1, 2,  -4, 1,  1,  1,  0,  -2, 2,  -3, 0,  2,  0,  0,  -3, 0,  2,  0,  2,  -2, 0,  0,  1,  0,
    0,  0,  -2, 1,  0,  -3, 0,  0,  2,  1,  -1, -1, -2, 2,  0,  0,  1,  2,  -4, 1,  2,  1,  0,  -4, 1,  0,  2,  0,  -2, 1,  1,  0,  0,  -3,
    1,  -2, 0,  2,  -2, 2,  -2, -1, 0,  0,  1,  -4, 0,  0,  2,  0,  1,  1,  0,  -4, 1,  -1, 0,  2,  -4, 1,  0,  0,  4,  -4, 1,  0,  3,  2,
    -2, 2,  -3, -1, 0,  4,  0,  -3, 0,  0,  4,  1,  1,  -1, -2, 2,  0,  -1, -1, 0,  2,  2,  1,  -2, 0,  0,  1,  1,  -1, 0,  0,  2,  0,  0,
    0,  1,  2,  -1, -1, 2,  0,  0,  1,  -2, 2,  -2, 2,  0,  -1, 2,  -1, 1,  -1, 0,  2,  0,  3,  1,  1,  0,  0,  2,  -1, 1,  2,  0,  0,  1,
    2,  0,  0,  0,  -1, 2,  2,  0,  2,  -1, 0,  4,  -2, 1,  3,  0,  2,  -4, 2,  1,  2,  2,  -2, 1,  1,  0,  4,  -4, 2,  -2, -1, 0,  4,  1,
    0,  -1, 0,  2,  2,  -2, 1,  0,  4,  0,  -2, -1, 2,  2,  1,  2,  0,  -2, 2,  0,  1,  0,  0,  1,  1,  0,  1,  0,  2,  2,  1,  -1, 2,  -1,
    2,  -2, 0,  4,  0,  1,  2,  1,  0,  0,  1,  0,  1,  2,  0,  0,  0,  -1, 4,  -2, 2,  0,  0,  4,  -2, 4,  0,  2,  2,  0,  1,  -3, 0,  0,
    6,  0,  -1, -1, 0,  4,  1,  1,  -2, 0,  2,  0,  -1, 0,  0,  4,  2,  -1, -2, 2,  2,  1,  -1, 0,  0,  -2, 2,  1,  0,  -2, -2, 1,  0,  0,
    -2, -2, 1,  -2, 0,  -2, 0,  1,  0,  0,  0,  3,  1,  0,  0,  0,  3,  0,  -1, 1,  0,  4,  0,  -1, -1, 2,  2,  0,  -2, 0,  2,  3,  2,  1,
    0,  0,  2,  2,  0,  -1, 2,  1,  2,  3,  -1, 0,  0,  0,  2,  0,  0,  1,  0,  1,  -1, 2,  0,  0,  0,  0,  2,  1,  0,  1,  0,  2,  0,  3,
    3,  1,  0,  0,  0,  3,  -1, 2,  -2, 2,  2,  0,  2,  -1, 1,  1,  1,  2,  0,  0,  0,  0,  4,  -1, 2,  1,  2,  2,  0,  2,  -2, 0,  0,  6,
    0,  0,  -1, 0,  4,  1,  -2, -1, 2,  4,  1,  0,  -2, 2,  2,  1,  0,  -1, 2,  2,  0,  -1, 0,  2,  3,  1,  -2, 1,  2,  4,  2,  2,  0,  0,
    2,  2,  2,  -2, 2,  0,  2,  -1, 1,  2,  3,  2,  3,  0,  2,  -1, 2,  4,  0,  2,  -2, 1,  -1, 0,  0,  6,  0,  -1, -2, 2,  4,  2,  -3, 0,
    2,  6,  2,  -1, 0,  2,  4,  0,  3,  0,  0,  2,  1,  3,  -1, 2,  0,  1,  3,  0,  2,  0,  0,  1,  0,  4,  0,  2,  5,  0,  2,  -2, 2,  0,
    -1, 2,  4,  1,  2,  -1, 2,  2,  1,  0,  1,  2,  4,  2,  1,  -1, 2,  4,  2,  3,  -1, 2,  2,  2,  3,  0,  2,  2,  1,  5,  0,  2,  0,  2,
    0,  0,  2,  6,  2,  4,  0,  2,  2,  2,  0,  -1, 1,  -1, 1,  -1, 0,  1,  0,  3,  0,  -2, 2,  -2, 3,  1,  0,  -1, 0,  1,  2,  -2, 0,  -2,
    1,  -1, 0,  1,  0,  2,  -1, 0,  1,  0,  1,  -1, -1, 2,  -1, 2,  -2, 2,  0,  2,  2,  -1, 0,  1,  0,  0,  -4, 1,  2,  2,  2,  -3, 0,  2,
    1,  1,  -2, -1, 2,  0,  2,  1,  0,  -2, 1,  1,  2,  -1, -2, 0,  1,  -4, 0,  2,  2,  0,  -3, 1,  0,  3,  0,  -1, 0,  -1, 2,  0,  0,  -2,
    0,  0,  2,  0,  -2, 0,  0,  2,  -3, 0,  0,  3,  0,  -2, -1, 0,  2,  2,  -1, 0,  -2, 3,  0,  -4, 0,  0,  4,  0,  2,  1,  -2, 0,  1,  2,
    -1, 0,  -2, 2,  0,  0,  1,  -1, 0,  -1, 2,  0,  1,  0,  -2, 1,  2,  0,  2,  1,  1,  0,  -1, 1,  1,  0,  1,  -2, 1,  0,  2,  0,  0,  2,
    1,  -1, 2,  -3, 1,  -1, 1,  2,  -1, 1,  -2, 0,  4,  -2, 2,  -2, 0,  4,  -2, 1,  -2, -2, 0,  2,  1,  -2, 0,  -2, 4,  0,  1,  2,  2,  -4,
    1,  1,  1,  2,  -4, 2,  -1, 2,  2,  -2, 1,  2,  0,  0,  -3, 1,  -1, 2,  0,  0,  1,  0,  0,  0,  -2, 0,  -1, -1, 2,  -2, 2,  -1, 1,  0,
    0,  2,  0,  0,  0,  -1, 2,  -2, 1,  0,  1,  0,  1,  -2, 0,  -2, 1,  1,  0,  -2, 0,  2,  -3, 1,  0,  2,  0,  -1, 1,  -2, 2,  0,  -1, -1,
    0,  0,  2,  -3, 0,  0,  2,  0,  -3, -1, 0,  2,  0,  2,  0,  2,  -6, 1,  0,  1,  2,  -4, 2,  2,  0,  0,  -4, 2,  -2, 1,  2,  -2, 1,  0,
    -1, 2,  -4, 1,  0,  1,  0,  -2, 2,  -1, 0,  0,  -2, 0,  2,  0,  -2, -2, 1,  -4, 0,  2,  0,  1,  -1, -1, 0,  -1, 1,  0,  0,  -2, 0,  2,
    -3, 0,  0,  1,  0,  -1, 0,  -2, 1,  0,  -2, 0,  -2, 2,  1,  0,  0,  -4, 2,  0,  -2, -1, -2, 2,  0,  1,  0,  2,  -6, 1,  -1, 0,  2,  -4,
    2,  1,  0,  0,  -4, 2,  2,  1,  2,  -4, 2,  2,  1,  2,  -4, 1,  0,  1,  4,  -4, 4,  0,  1,  4,  -4, 2,  -1, -1, -2, 4,  0,  -1, -3, 0,
    2,  0,  -1, 0,  -2, 4,  1,  -2, -1, 0,  3,  0,  0,  0,  -2, 3,  0,  -2, 0,  0,  3,  1,  0,  -1, 0,  1,  0,  -3, 0,  2,  2,  0,  1,  1,
    -2, 2,  0,  -1, 1,  0,  2,  2,  1,  -2, 2,  -2, 1,  0,  0,  1,  0,  2,  0,  0,  1,  0,  1,  0,  0,  1,  0,  0,  -1, 2,  0,  2,  1,  0,
    0,  2,  0,  2,  -2, 0,  2,  0,  2,  2,  0,  0,  -1, 1,  3,  0,  0,  -2, 1,  1,  0,  2,  -2, 3,  1,  2,  0,  0,  1,  2,  0,  2,  -3, 2,
    -1, 1,  4,  -2, 2,  -2, -2, 0,  4,  0,  0,  -3, 0,  2,  0,  0,  0,  -2, 4,  0,  -1, -1, 0,  3,  0,  -2, 0,  0,  4,  2,  -1, 0,  0,  3,
    1,  2,  -2, 0,  0,  0,  1,  -1, 0,  1,  0,  -1, 0,  0,  2,  0,  0,  -2, 2,  0,  1,  -1, 0,  1,  2,  1,  -1, 1,  0,  3,  0,  -1, -1, 2,
    1,  2,  0,  -1, 2,  0,  0,  -2, 1,  2,  2,  1,  2,  -2, 2,  -2, 2,  1,  1,  0,  1,  1,  1,  0,  1,  0,  1,  1,  0,  1,  0,  0,  0,  2,
    0,  2,  0,  2,  -1, 2,  -2, 1,  0,  -1, 4,  -2, 1,  0,  0,  4,  -2, 3,  0,  1,  4,  -2, 1,  4,  0,  2,  -4, 2,  2,  2,  2,  -2, 2,  2,
    0,  4,  -4, 2,  -1, -2, 0,  4,  0,  -1, -3, 2,  2,  2,  -3, 0,  2,  4,  2,  -3, 0,  2,  -2, 1,  -1, -1, 0,  -2, 1,  -3, 0,  0,  0,  2,
    -3, 0,  -2, 2,  0,  0,  1,  0,  -4, 1,  -2, 1,  0,  -2, 1,  -4, 0,  0,  0,  1,  -1, 0,  0,  -4, 1,  -3, 0,  0,  -2, 1,  0,  0,  0,  3,
    2,  -1, 1,  0,  4,  1,  1,  -2, 2,  0,  1,  0,  1,  0,  3,  0,  -1, 0,  2,  2,  3,  0,  0,  2,  2,  2,  -2, 0,  2,  2,  2,  -1, 1,  2,
    2,  0,  3,  0,  0,  0,  2,  2,  1,  0,  1,  0,  2,  -1, 2,  -1, 2,  0,  0,  2,  0,  1,  0,  0,  3,  0,  3,  0,  0,  3,  0,  2,  -1, 2,
    2,  2,  1,  -1, 0,  4,  0,  0,  1,  2,  2,  0,  1,  3,  1,  2,  -2, 1,  1,  1,  4,  -2, 2,  -2, -1, 0,  6,  0,  0,  -2, 0,  4,  0,  -2,
    0,  0,  6,  1,  -2, -2, 2,  4,  2,  0,  -3, 2,  2,  2,  0,  0,  0,  4,  2,  -1, -1, 2,  3,  2,  -2, 0,  2,  4,  0,  2,  -1, 0,  2,  1,
    1,  0,  0,  3,  0,  0,  1,  0,  4,  1,  0,  1,  0,  4,  0,  1,  -1, 2,  1,  2,  0,  0,  2,  2,  3,  1,  0,  2,  2,  2,  -1, 0,  2,  2,
    2,  -2, 0,  4,  2,  1,  2,  1,  0,  2,  1,  2,  1,  0,  2,  0,  2,  -1, 2,  0,  0,  1,  0,  2,  1,  0,  0,  1,  2,  2,  0,  2,  0,  2,
    0,  3,  3,  0,  2,  0,  2,  1,  0,  2,  0,  2,  1,  0,  3,  0,  3,  1,  1,  2,  1,  1,  0,  2,  2,  2,  2,  2,  1,  2,  0,  0,  2,  0,
    4,  -2, 1,  4,  1,  2,  -2, 2,  -1, -1, 0,  6,  0,  -3, -1, 2,  6,  2,  -1, 0,  0,  6,  1,  -3, 0,  2,  6,  1,  1,  -1, 0,  4,  1,  1,
    -1, 0,  4,  0,  -2, 0,  2,  5,  2,  1,  -2, 2,  2,  1,  3,  -1, 0,  2,  0,  1,  -1, 2,  2,  0,  0,  0,  2,  3,  1,  -1, 1,  2,  4,  1,
    0,  1,  2,  3,  2,  -1, 0,  4,  2,  1,  2,  0,  2,  1,  1,  5,  0,  0,  0,  0,  2,  1,  2,  1,  2,  1,  0,  4,  0,  1,  3,  1,  2,  0,
    1,  3,  0,  4,  -2, 2,  -2, -1, 2,  6,  2,  0,  0,  0,  6,  0,  0,  -2, 2,  4,  2,  -2, 0,  2,  6,  1,  2,  0,  0,  4,  1,  2,  0,  0,
    4,  0,  2,  -2, 2,  2,  2,  0,  0,  2,  4,  0,  1,  0,  2,  3,  2,  4,  0,  0,  2,  0,  2,  0,  2,  2,  0,  0,  0,  4,  2,  2,  4,  -1,
    2,  0,  2,  3,  0,  2,  1,  2,  2,  1,  2,  2,  1,  4,  1,  2,  0,  2,  -1, -1, 2,  6,  2,  -1, 0,  2,  6,  1,  1,  -1, 2,  4,  1,  1,
    1,  2,  4,  2,  3,  1,  2,  2,  2,  5,  0,  2,  0,  1,  2,  -1, 2,  4,  2,  2,  0,  2,  4,  1,
};

const cls = [4068]i32{
    -172064161, -174666, 33386, 92052331, 9086, 15377, -13170906, -1675, -13696, 5730336, -3015, -4587,
    -2276413,   -234,    2796,  978459,   -485, 1374,  2074554,   207,   -698,   -897492, 470,   -291,
    1475877,    -3633,   11817, 73871,    -184, -1924, -516821,   1226,  -524,   224386,  -677,  -174,
    711159,     73,      -872,  -6750,    0,    358,   -387298,   -367,  380,    200728,  18,    318,
    -301461,    -36,     816,   129025,   -63,  367,   215829,    -494,  111,    -95929,  299,   132,
    128227,     137,     181,   -68982,   -9,   39,    123457,    11,    19,     -53311,  32,    -4,
    156994,     10,      -168,  -1235,    0,    82,    63110,     63,    27,     -33228,  0,     -9,
    -57976,     -63,     -189,  31429,    0,    -75,   -59641,    -11,   149,    25543,   -11,   66,
    -51613,     -42,     129,   26366,    0,    78,    45893,     50,    31,     -24236,  -10,   20,
    63384,      11,      -150,  -1220,    0,    29,    -38571,    -1,    158,    16452,   -11,   68,
    32481,      0,       0,     -13870,   0,    0,     -47722,    0,     -18,    477,     0,     -25,
    -31046,     -1,      131,   13238,    -11,  59,    28593,     0,     -1,     -12338,  10,    -3,
    20441,      21,      10,    -10758,   0,    -3,    29243,     0,     -74,    -609,    0,     13,
    25887,      0,       -66,   -550,     0,    11,    -14053,    -25,   79,     8551,    -2,    -45,
    15164,      10,      11,    -8001,    0,    -1,    -15794,    72,    -16,    6850,    -42,   -5,
    21783,      0,       13,    -167,     0,    13,    -12873,    -10,   -37,    6953,    0,     -14,
    -12654,     11,      63,    6415,     0,    26,    -10204,    0,     25,     5222,    0,     15,
    16707,      -85,     -10,   168,      -1,   10,    -7691,     0,     44,     3268,    0,     19,
    -11024,     0,       -14,   104,      0,    2,     7566,      -21,   -11,    -3250,   0,     -5,
    -6637,      -11,     25,    3353,     0,    14,    -7141,     21,    8,      3070,    0,     4,
    -6302,      -11,     2,     3272,     0,    4,     5800,      10,    2,      -3045,   0,     -1,
    6443,       0,       -7,    -2768,    0,    -4,    -5774,     -11,   -15,    3041,    0,     -5,
    -5350,      0,       21,    2695,     0,    12,    -4752,     -11,   -3,     2719,    0,     -3,
    -4940,      -11,     -21,   2720,     0,    -9,    7350,      0,     -8,     -51,     0,     4,
    4065,       0,       6,     -2206,    0,    1,     6579,      0,     -24,    -199,    0,     2,
    3579,       0,       5,     -1900,    0,    1,     4725,      0,     -6,     -41,     0,     3,
    -3075,      0,       -2,    1313,     0,    -1,    -2904,     0,     15,     1233,    0,     7,
    4348,       0,       -10,   -81,      0,    2,     -2878,     0,     8,      1232,    0,     4,
    -4230,      0,       5,     -20,      0,    -2,    -2819,     0,     7,      1207,    0,     3,
    -4056,      0,       5,     40,       0,    -2,    -2647,     0,     11,     1129,    0,     5,
    -2294,      0,       -10,   1266,     0,    -4,    2481,      0,     -7,     -1062,   0,     -3,
    2179,       0,       -2,    -1129,    0,    -2,    3276,      0,     1,      -9,      0,     0,
    -3389,      0,       5,     35,       0,    -2,    3339,      0,     -13,    -107,    0,     1,
    -1987,      0,       -6,    1073,     0,    -2,    -1981,     0,     0,      854,     0,     0,
    4026,       0,       -353,  -553,     0,    -139,  1660,      0,     -5,     -710,    0,     -2,
    -1521,      0,       9,     647,      0,    4,     1314,      0,     0,      -700,    0,     0,
    -1283,      0,       0,     672,      0,    0,     -1331,     0,     8,      663,     0,     4,
    1383,       0,       -2,    -594,     0,    -2,    1405,      0,     4,      -610,    0,     2,
    1290,       0,       0,     -556,     0,    0,     -1214,     0,     5,      518,     0,     2,
    1146,       0,       -3,    -490,     0,    -1,    1019,      0,     -1,     -527,    0,     -1,
    -1100,      0,       9,     465,      0,    4,     -970,      0,     2,      496,     0,     1,
    1575,       0,       -6,    -50,      0,    0,     934,       0,     -3,     -399,    0,     -1,
    922,        0,       -1,    -395,     0,    -1,    815,       0,     -1,     -422,    0,     -1,
    834,        0,       2,     -440,     0,    1,     1248,      0,     0,      -170,    0,     1,
    1338,       0,       -5,    -39,      0,    0,     716,       0,     -2,     -389,    0,     -1,
    1282,       0,       -3,    -23,      0,    1,     742,       0,     1,      -391,    0,     0,
    1020,       0,       -25,   -495,     0,    -10,   715,       0,     -4,     -326,    0,     2,
    -666,       0,       -3,    369,      0,    -1,    -667,      0,     1,      346,     0,     1,
    -704,       0,       0,     304,      0,    0,     -694,      0,     5,      294,     0,     2,
    -1014,      0,       -1,    4,        0,    -1,    -585,      0,     -2,     316,     0,     -1,
    -949,       0,       1,     8,        0,    -1,    -595,      0,     0,      258,     0,     0,
    528,        0,       0,     -279,     0,    0,     -590,      0,     4,      252,     0,     2,
    570,        0,       -2,    -244,     0,    -1,    -502,      0,     3,      250,     0,     2,
    -875,       0,       1,     29,       0,    0,     -492,      0,     -3,     275,     0,     -1,
    535,        0,       -2,    -228,     0,    -1,    -467,      0,     1,      240,     0,     1,
    591,        0,       0,     -253,     0,    0,     -453,      0,     -1,     244,     0,     -1,
    766,        0,       1,     9,        0,    0,     -446,      0,     2,      225,     0,     1,
    -488,       0,       2,     207,      0,    1,     -468,      0,     0,      201,     0,     0,
    -421,       0,       1,     216,      0,    1,     463,       0,     0,      -200,    0,     0,
    -673,       0,       2,     14,       0,    0,     658,       0,     0,      -2,      0,     0,
    -438,       0,       0,     188,      0,    0,     -390,      0,     0,      205,     0,     0,
    639,        -11,     -2,    -19,      0,    0,     412,       0,     -2,     -176,    0,     -1,
    -361,       0,       0,     189,      0,    0,     360,       0,     -1,     -185,    0,     -1,
    588,        0,       -3,    -24,      0,    0,     -578,      0,     1,      5,       0,     0,
    -396,       0,       0,     171,      0,    0,     565,       0,     -1,     -6,      0,     0,
    -335,       0,       -1,    184,      0,    -1,    357,       0,     1,      -154,    0,     0,
    321,        0,       1,     -174,     0,    0,     -301,      0,     -1,     162,     0,     0,
    -334,       0,       0,     144,      0,    0,     493,       0,     -2,     -15,     0,     0,
    494,        0,       -2,    -19,      0,    0,     337,       0,     -1,     -143,    0,     -1,
    280,        0,       -1,    -144,     0,    0,     309,       0,     1,      -134,    0,     0,
    -263,       0,       2,     131,      0,    1,     253,       0,     1,      -138,    0,     0,
    245,        0,       0,     -128,     0,    0,     416,       0,     -2,     -17,     0,     0,
    -229,       0,       0,     128,      0,    0,     231,       0,     0,      -120,    0,     0,
    -259,       0,       2,     109,      0,    1,     375,       0,     -1,     -8,      0,     0,
    252,        0,       0,     -108,     0,    0,     -245,      0,     1,      104,     0,     0,
    243,        0,       -1,    -104,     0,    0,     208,       0,     1,      -112,    0,     0,
    199,        0,       0,     -102,     0,    0,     -208,      0,     1,      105,     0,     0,
    335,        0,       -2,    -14,      0,    0,     -325,      0,     1,      7,       0,     0,
    -187,       0,       0,     96,       0,    0,     197,       0,     -1,     -100,    0,     0,
    -192,       0,       2,     94,       0,    1,     -188,      0,     0,      83,      0,     0,
    276,        0,       0,     -2,       0,    0,     -286,      0,     1,      6,       0,     0,
    186,        0,       -1,    -79,      0,    0,     -219,      0,     0,      43,      0,     0,
    276,        0,       0,     2,        0,    0,     -153,      0,     -1,     84,      0,     0,
    -156,       0,       0,     81,       0,    0,     -154,      0,     1,      78,      0,     0,
    -174,       0,       1,     75,       0,    0,     -163,      0,     2,      69,      0,     1,
    -228,       0,       0,     1,        0,    0,     91,        0,     -4,     -54,     0,     -2,
    175,        0,       0,     -75,      0,    0,     -159,      0,     0,      69,      0,     0,
    141,        0,       0,     -72,      0,    0,     147,       0,     0,      -75,     0,     0,
    -132,       0,       0,     69,       0,    0,     159,       0,     -28,    -54,     0,     11,
    213,        0,       0,     -4,       0,    0,     123,       0,     0,      -64,     0,     0,
    -118,       0,       -1,    66,       0,    0,     144,       0,     -1,     -61,     0,     0,
    -121,       0,       1,     60,       0,    0,     -134,      0,     1,      56,      0,     1,
    -105,       0,       0,     57,       0,    0,     -102,      0,     0,      56,      0,     0,
    120,        0,       0,     -52,      0,    0,     101,       0,     0,      -54,     0,     0,
    -113,       0,       0,     59,       0,    0,     -106,      0,     0,      61,      0,     0,
    -129,       0,       1,     55,       0,    0,     -114,      0,     0,      57,      0,     0,
    113,        0,       -1,    -49,      0,    0,     -102,      0,     0,      44,      0,     0,
    -94,        0,       0,     51,       0,    0,     -100,      0,     -1,     56,      0,     0,
    87,         0,       0,     -47,      0,    0,     161,       0,     0,      -1,      0,     0,
    96,         0,       0,     -50,      0,    0,     151,       0,     -1,     -5,      0,     0,
    -104,       0,       0,     44,       0,    0,     -110,      0,     0,      48,      0,     0,
    -100,       0,       1,     50,       0,    0,     92,        0,     -5,     12,      0,     -2,
    82,         0,       0,     -45,      0,    0,     82,        0,     0,      -45,     0,     0,
    -78,        0,       0,     41,       0,    0,     -77,       0,     0,      43,      0,     0,
    2,          0,       0,     54,       0,    0,     94,        0,     0,      -40,     0,     0,
    -93,        0,       0,     40,       0,    0,     -83,       0,     10,     40,      0,     -2,
    83,         0,       0,     -36,      0,    0,     -91,       0,     0,      39,      0,     0,
    128,        0,       0,     -1,       0,    0,     -79,       0,     0,      34,      0,     0,
    -83,        0,       0,     47,       0,    0,     84,        0,     0,      -44,     0,     0,
    83,         0,       0,     -43,      0,    0,     91,        0,     0,      -39,     0,     0,
    -77,        0,       0,     39,       0,    0,     84,        0,     0,      -43,     0,     0,
    -92,        0,       1,     39,       0,    0,     -92,       0,     1,      39,      0,     0,
    -94,        0,       0,     0,        0,    0,     68,        0,     0,      -36,     0,     0,
    -61,        0,       0,     32,       0,    0,     71,        0,     0,      -31,     0,     0,
    62,         0,       0,     -34,      0,    0,     -63,       0,     0,      33,      0,     0,
    -73,        0,       0,     32,       0,    0,     115,       0,     0,      -2,      0,     0,
    -103,       0,       0,     2,        0,    0,     63,        0,     0,      -28,     0,     0,
    74,         0,       0,     -32,      0,    0,     -103,      0,     -3,     3,       0,     -1,
    -69,        0,       0,     30,       0,    0,     57,        0,     0,      -29,     0,     0,
    94,         0,       0,     -4,       0,    0,     64,        0,     0,      -33,     0,     0,
    -63,        0,       0,     26,       0,    0,     -38,       0,     0,      20,      0,     0,
    -43,        0,       0,     24,       0,    0,     -45,       0,     0,      23,      0,     0,
    47,         0,       0,     -24,      0,    0,     -48,       0,     0,      25,      0,     0,
    45,         0,       0,     -26,      0,    0,     56,        0,     0,      -25,     0,     0,
    88,         0,       0,     2,        0,    0,     -75,       0,     0,      0,       0,     0,
    85,         0,       0,     0,        0,    0,     49,        0,     0,      -26,     0,     0,
    -74,        0,       -3,    -1,       0,    -1,    -39,       0,     0,      21,      0,     0,
    45,         0,       0,     -20,      0,    0,     51,        0,     0,      -22,     0,     0,
    -40,        0,       0,     21,       0,    0,     41,        0,     0,      -21,     0,     0,
    -42,        0,       0,     24,       0,    0,     -51,       0,     0,      22,      0,     0,
    -42,        0,       0,     22,       0,    0,     39,        0,     0,      -21,     0,     0,
    46,         0,       0,     -18,      0,    0,     -53,       0,     0,      22,      0,     0,
    82,         0,       0,     -4,       0,    0,     81,        0,     -1,     -4,      0,     0,
    47,         0,       0,     -19,      0,    0,     53,        0,     0,      -23,     0,     0,
    -45,        0,       0,     22,       0,    0,     -44,       0,     0,      -2,      0,     0,
    -33,        0,       0,     16,       0,    0,     -61,       0,     0,      1,       0,     0,
    28,         0,       0,     -15,      0,    0,     -38,       0,     0,      19,      0,     0,
    -33,        0,       0,     21,       0,    0,     -60,       0,     0,      0,       0,     0,
    48,         0,       0,     -10,      0,    0,     27,        0,     0,      -14,     0,     0,
    38,         0,       0,     -20,      0,    0,     31,        0,     0,      -13,     0,     0,
    -29,        0,       0,     15,       0,    0,     28,        0,     0,      -15,     0,     0,
    -32,        0,       0,     15,       0,    0,     45,        0,     0,      -8,      0,     0,
    -44,        0,       0,     19,       0,    0,     28,        0,     0,      -15,     0,     0,
    -51,        0,       0,     0,        0,    0,     -36,       0,     0,      20,      0,     0,
    44,         0,       0,     -19,      0,    0,     26,        0,     0,      -14,     0,     0,
    -60,        0,       0,     2,        0,    0,     35,        0,     0,      -18,     0,     0,
    -27,        0,       0,     11,       0,    0,     47,        0,     0,      -1,      0,     0,
    36,         0,       0,     -15,      0,    0,     -36,       0,     0,      20,      0,     0,
    -35,        0,       0,     19,       0,    0,     -37,       0,     0,      19,      0,     0,
    32,         0,       0,     -16,      0,    0,     35,        0,     0,      -14,     0,     0,
    32,         0,       0,     -13,      0,    0,     65,        0,     0,      -2,      0,     0,
    47,         0,       0,     -1,       0,    0,     32,        0,     0,      -16,     0,     0,
    37,         0,       0,     -16,      0,    0,     -30,       0,     0,      15,      0,     0,
    -32,        0,       0,     16,       0,    0,     -31,       0,     0,      13,      0,     0,
    37,         0,       0,     -16,      0,    0,     31,        0,     0,      -13,     0,     0,
    49,         0,       0,     -2,       0,    0,     32,        0,     0,      -13,     0,     0,
    23,         0,       0,     -12,      0,    0,     -43,       0,     0,      18,      0,     0,
    26,         0,       0,     -11,      0,    0,     -32,       0,     0,      14,      0,     0,
    -29,        0,       0,     14,       0,    0,     -27,       0,     0,      12,      0,     0,
    30,         0,       0,     0,        0,    0,     -11,       0,     0,      5,       0,     0,
    -21,        0,       0,     10,       0,    0,     -34,       0,     0,      15,      0,     0,
    -10,        0,       0,     6,        0,    0,     -36,       0,     0,      0,       0,     0,
    -9,         0,       0,     4,        0,    0,     -12,       0,     0,      5,       0,     0,
    -21,        0,       0,     5,        0,    0,     -29,       0,     0,      -1,      0,     0,
    -15,        0,       0,     3,        0,    0,     -20,       0,     0,      0,       0,     0,
    28,         0,       0,     0,        0,    -2,    17,        0,     0,      0,       0,     0,
    -22,        0,       0,     12,       0,    0,     -14,       0,     0,      7,       0,     0,
    24,         0,       0,     -11,      0,    0,     11,        0,     0,      -6,      0,     0,
    14,         0,       0,     -6,       0,    0,     24,        0,     0,      0,       0,     0,
    18,         0,       0,     -8,       0,    0,     -38,       0,     0,      0,       0,     0,
    -31,        0,       0,     0,        0,    0,     -16,       0,     0,      8,       0,     0,
    29,         0,       0,     0,        0,    0,     -18,       0,     0,      10,      0,     0,
    -10,        0,       0,     5,        0,    0,     -17,       0,     0,      10,      0,     0,
    9,          0,       0,     -4,       0,    0,     16,        0,     0,      -6,      0,     0,
    22,         0,       0,     -12,      0,    0,     20,        0,     0,      0,       0,     0,
    -13,        0,       0,     6,        0,    0,     -17,       0,     0,      9,       0,     0,
    -14,        0,       0,     8,        0,    0,     0,         0,     0,      -7,      0,     0,
    14,         0,       0,     0,        0,    0,     19,        0,     0,      -10,     0,     0,
    -34,        0,       0,     0,        0,    0,     -20,       0,     0,      8,       0,     0,
    9,          0,       0,     -5,       0,    0,     -18,       0,     0,      7,       0,     0,
    13,         0,       0,     -6,       0,    0,     17,        0,     0,      0,       0,     0,
    -12,        0,       0,     5,        0,    0,     15,        0,     0,      -8,      0,     0,
    -11,        0,       0,     3,        0,    0,     13,        0,     0,      -5,      0,     0,
    -18,        0,       0,     0,        0,    0,     -35,       0,     0,      0,       0,     0,
    9,          0,       0,     -4,       0,    0,     -19,       0,     0,      10,      0,     0,
    -26,        0,       0,     11,       0,    0,     8,         0,     0,      -4,      0,     0,
    -10,        0,       0,     4,        0,    0,     10,        0,     0,      -6,      0,     0,
    -21,        0,       0,     9,        0,    0,     -15,       0,     0,      0,       0,     0,
    9,          0,       0,     -5,       0,    0,     -29,       0,     0,      0,       0,     0,
    -19,        0,       0,     10,       0,    0,     12,        0,     0,      -5,      0,     0,
    22,         0,       0,     -9,       0,    0,     -10,       0,     0,      5,       0,     0,
    -20,        0,       0,     11,       0,    0,     -20,       0,     0,      0,       0,     0,
    -17,        0,       0,     7,        0,    0,     15,        0,     0,      -3,      0,     0,
    8,          0,       0,     -4,       0,    0,     14,        0,     0,      0,       0,     0,
    -12,        0,       0,     6,        0,    0,     25,        0,     0,      0,       0,     0,
    -13,        0,       0,     6,        0,    0,     -14,       0,     0,      8,       0,     0,
    13,         0,       0,     -5,       0,    0,     -17,       0,     0,      9,       0,     0,
    -12,        0,       0,     6,        0,    0,     -10,       0,     0,      5,       0,     0,
    10,         0,       0,     -6,       0,    0,     -15,       0,     0,      0,       0,     0,
    -22,        0,       0,     0,        0,    0,     28,        0,     0,      -1,      0,     0,
    15,         0,       0,     -7,       0,    0,     23,        0,     0,      -10,     0,     0,
    12,         0,       0,     -5,       0,    0,     29,        0,     0,      -1,      0,     0,
    -25,        0,       0,     1,        0,    0,     22,        0,     0,      0,       0,     0,
    -18,        0,       0,     0,        0,    0,     15,        0,     0,      3,       0,     0,
    -23,        0,       0,     0,        0,    0,     12,        0,     0,      -5,      0,     0,
    -8,         0,       0,     4,        0,    0,     -19,       0,     0,      0,       0,     0,
    -10,        0,       0,     4,        0,    0,     21,        0,     0,      -9,      0,     0,
    23,         0,       0,     -1,       0,    0,     -16,       0,     0,      8,       0,     0,
    -19,        0,       0,     9,        0,    0,     -22,       0,     0,      10,      0,     0,
    27,         0,       0,     -1,       0,    0,     16,        0,     0,      -8,      0,     0,
    19,         0,       0,     -8,       0,    0,     9,         0,     0,      -4,      0,     0,
    -9,         0,       0,     4,        0,    0,     -9,        0,     0,      4,       0,     0,
    -8,         0,       0,     4,        0,    0,     18,        0,     0,      -9,      0,     0,
    16,         0,       0,     -1,       0,    0,     -10,       0,     0,      4,       0,     0,
    -23,        0,       0,     9,        0,    0,     16,        0,     0,      -1,      0,     0,
    -12,        0,       0,     6,        0,    0,     -8,        0,     0,      4,       0,     0,
    30,         0,       0,     -2,       0,    0,     24,        0,     0,      -10,     0,     0,
    10,         0,       0,     -4,       0,    0,     -16,       0,     0,      7,       0,     0,
    -16,        0,       0,     7,        0,    0,     17,        0,     0,      -7,      0,     0,
    -24,        0,       0,     10,       0,    0,     -12,       0,     0,      5,       0,     0,
    -24,        0,       0,     11,       0,    0,     -23,       0,     0,      9,       0,     0,
    -13,        0,       0,     5,        0,    0,     -15,       0,     0,      7,       0,     0,
    0,          0,       -1988, 0,        0,    -1679, 0,         0,     -63,    0,       0,     -27,
    -4,         0,       0,     0,        0,    0,     0,         0,     5,      0,       0,     4,
    5,          0,       0,     -3,       0,    0,     0,         0,     364,    0,       0,     176,
    0,          0,       -1044, 0,        0,    -891,  -3,        0,     0,      1,       0,     0,
    4,          0,       0,     -2,       0,    0,     0,         0,     330,    0,       0,     0,
    5,          0,       0,     -2,       0,    0,     3,         0,     0,      -2,      0,     0,
    -3,         0,       0,     1,        0,    0,     -5,        0,     0,      2,       0,     0,
    3,          0,       0,     -1,       0,    0,     3,         0,     0,      0,       0,     0,
    3,          0,       0,     0,        0,    0,     0,         0,     5,      0,       0,     0,
    0,          0,       0,     1,        0,    0,     4,         0,     0,      -2,      0,     0,
    6,          0,       0,     0,        0,    0,     5,         0,     0,      -2,      0,     0,
    -7,         0,       0,     0,        0,    0,     -12,       0,     0,      0,       0,     0,
    5,          0,       0,     -3,       0,    0,     3,         0,     0,      -1,      0,     0,
    -5,         0,       0,     0,        0,    0,     3,         0,     0,      0,       0,     0,
    -7,         0,       0,     3,        0,    0,     7,         0,     0,      -4,      0,     0,
    0,          0,       -12,   0,        0,    -10,   4,         0,     0,      -2,      0,     0,
    3,          0,       0,     -2,       0,    0,     -3,        0,     0,      2,       0,     0,
    -7,         0,       0,     3,        0,    0,     -4,        0,     0,      2,       0,     0,
    -3,         0,       0,     1,        0,    0,     0,         0,     0,      0,       0,     0,
    -3,         0,       0,     1,        0,    0,     7,         0,     0,      -3,      0,     0,
    -4,         0,       0,     2,        0,    0,     4,         0,     0,      -2,      0,     0,
    -5,         0,       0,     3,        0,    0,     5,         0,     0,      0,       0,     0,
    -5,         0,       0,     2,        0,    0,     5,         0,     0,      -2,      0,     0,
    -8,         0,       0,     3,        0,    0,     9,         0,     0,      0,       0,     0,
    6,          0,       0,     -3,       0,    0,     -5,        0,     0,      2,       0,     0,
    3,          0,       0,     0,        0,    0,     -7,        0,     0,      0,       0,     0,
    -3,         0,       0,     1,        0,    0,     5,         0,     0,      0,       0,     0,
    3,          0,       0,     0,        0,    0,     -3,        0,     0,      2,       0,     0,
    4,          0,       0,     -2,       0,    0,     3,         0,     0,      -1,      0,     0,
    -5,         0,       0,     2,        0,    0,     4,         0,     0,      -2,      0,     0,
    9,          0,       0,     -3,       0,    0,     4,         0,     0,      0,       0,     0,
    4,          0,       0,     -2,       0,    0,     -3,        0,     0,      2,       0,     0,
    -4,         0,       0,     2,        0,    0,     9,         0,     0,      -3,      0,     0,
    -4,         0,       0,     0,        0,    0,     -4,        0,     0,      0,       0,     0,
    3,          0,       0,     -2,       0,    0,     8,         0,     0,      0,       0,     0,
    3,          0,       0,     0,        0,    0,     -3,        0,     0,      2,       0,     0,
    3,          0,       0,     -1,       0,    0,     3,         0,     0,      -1,      0,     0,
    -3,         0,       0,     1,        0,    0,     6,         0,     0,      -3,      0,     0,
    3,          0,       0,     0,        0,    0,     -3,        0,     0,      1,       0,     0,
    -7,         0,       0,     0,        0,    0,     9,         0,     0,      0,       0,     0,
    -3,         0,       0,     2,        0,    0,     -3,        0,     0,      0,       0,     0,
    -4,         0,       0,     0,        0,    0,     -5,        0,     0,      3,       0,     0,
    -13,        0,       0,     0,        0,    0,     -7,        0,     0,      0,       0,     0,
    10,         0,       0,     0,        0,    0,     3,         0,     0,      -1,      0,     0,
    10,         0,       13,    6,        0,    -5,    0,         0,     30,     0,       0,     14,
    0,          0,       -162,  0,        0,    -138,  0,         0,     75,     0,       0,     0,
    -7,         0,       0,     4,        0,    0,     -4,        0,     0,      2,       0,     0,
    4,          0,       0,     -2,       0,    0,     5,         0,     0,      -2,      0,     0,
    5,          0,       0,     -3,       0,    0,     -3,        0,     0,      0,       0,     0,
    -3,         0,       0,     2,        0,    0,     -4,        0,     0,      2,       0,     0,
    -5,         0,       0,     2,        0,    0,     6,         0,     0,      0,       0,     0,
    9,          0,       0,     0,        0,    0,     5,         0,     0,      0,       0,     0,
    -7,         0,       0,     0,        0,    0,     -3,        0,     0,      1,       0,     0,
    -4,         0,       0,     2,        0,    0,     7,         0,     0,      0,       0,     0,
    -4,         0,       0,     0,        0,    0,     4,         0,     0,      0,       0,     0,
    -6,         0,       -3,    3,        0,    1,     0,         0,     -3,     0,       0,     -2,
    11,         0,       0,     0,        0,    0,     3,         0,     0,      -1,      0,     0,
    11,         0,       0,     0,        0,    0,     -3,        0,     0,      2,       0,     0,
    -1,         0,       3,     3,        0,    -1,    4,         0,     0,      -2,      0,     0,
    0,          0,       -13,   0,        0,    -11,   3,         0,     6,      0,       0,     0,
    -7,         0,       0,     0,        0,    0,     5,         0,     0,      -3,      0,     0,
    -3,         0,       0,     1,        0,    0,     3,         0,     0,      0,       0,     0,
    5,          0,       0,     -3,       0,    0,     -7,        0,     0,      3,       0,     0,
    8,          0,       0,     -3,       0,    0,     -4,        0,     0,      2,       0,     0,
    11,         0,       0,     0,        0,    0,     -3,        0,     0,      1,       0,     0,
    3,          0,       0,     -1,       0,    0,     -4,        0,     0,      2,       0,     0,
    8,          0,       0,     -4,       0,    0,     3,         0,     0,      -1,      0,     0,
    11,         0,       0,     0,        0,    0,     -6,        0,     0,      3,       0,     0,
    -4,         0,       0,     2,        0,    0,     -8,        0,     0,      4,       0,     0,
    -7,         0,       0,     3,        0,    0,     -4,        0,     0,      2,       0,     0,
    3,          0,       0,     -1,       0,    0,     6,         0,     0,      -3,      0,     0,
    -6,         0,       0,     3,        0,    0,     6,         0,     0,      0,       0,     0,
    6,          0,       0,     -1,       0,    0,     5,         0,     0,      -2,      0,     0,
    -5,         0,       0,     2,        0,    0,     -4,        0,     0,      0,       0,     0,
    -4,         0,       0,     2,        0,    0,     4,         0,     0,      0,       0,     0,
    6,          0,       0,     -3,       0,    0,     -4,        0,     0,      2,       0,     0,
    0,          0,       -26,   0,        0,    -11,   0,         0,     -10,    0,       0,     -5,
    5,          0,       0,     -3,       0,    0,     -13,       0,     0,      0,       0,     0,
    3,          0,       0,     -2,       0,    0,     4,         0,     0,      -2,      0,     0,
    7,          0,       0,     -3,       0,    0,     4,         0,     0,      0,       0,     0,
    5,          0,       0,     0,        0,    0,     -3,        0,     0,      2,       0,     0,
    -6,         0,       0,     2,        0,    0,     -5,        0,     0,      2,       0,     0,
    -7,         0,       0,     3,        0,    0,     5,         0,     0,      -2,      0,     0,
    13,         0,       0,     0,        0,    0,     -4,        0,     0,      2,       0,     0,
    -3,         0,       0,     0,        0,    0,     5,         0,     0,      -2,      0,     0,
    -11,        0,       0,     0,        0,    0,     5,         0,     0,      -2,      0,     0,
    4,          0,       0,     0,        0,    0,     4,         0,     0,      -2,      0,     0,
    -4,         0,       0,     2,        0,    0,     6,         0,     0,      -3,      0,     0,
    3,          0,       0,     -2,       0,    0,     -12,       0,     0,      0,       0,     0,
    4,          0,       0,     0,        0,    0,     -3,        0,     0,      0,       0,     0,
    -4,         0,       0,     0,        0,    0,     3,         0,     0,      0,       0,     0,
    3,          0,       0,     -1,       0,    0,     -3,        0,     0,      1,       0,     0,
    0,          0,       -5,    0,        0,    -2,    -7,        0,     0,      4,       0,     0,
    6,          0,       0,     -3,       0,    0,     -3,        0,     0,      0,       0,     0,
    5,          0,       0,     -3,       0,    0,     3,         0,     0,      -1,      0,     0,
    3,          0,       0,     0,        0,    0,     -3,        0,     0,      1,       0,     0,
    -5,         0,       0,     3,        0,    0,     -3,        0,     0,      2,       0,     0,
    -3,         0,       0,     2,        0,    0,     12,        0,     0,      0,       0,     0,
    3,          0,       0,     -1,       0,    0,     -4,        0,     0,      2,       0,     0,
    4,          0,       0,     0,        0,    0,     6,         0,     0,      0,       0,     0,
    5,          0,       0,     -3,       0,    0,     4,         0,     0,      -2,      0,     0,
    -6,         0,       0,     3,        0,    0,     4,         0,     0,      -2,      0,     0,
    6,          0,       0,     -3,       0,    0,     6,         0,     0,      0,       0,     0,
    -6,         0,       0,     3,        0,    0,     3,         0,     0,      -2,      0,     0,
    7,          0,       0,     -4,       0,    0,     4,         0,     0,      -2,      0,     0,
    -5,         0,       0,     2,        0,    0,     5,         0,     0,      0,       0,     0,
    -6,         0,       0,     3,        0,    0,     -6,        0,     0,      3,       0,     0,
    -4,         0,       0,     2,        0,    0,     10,        0,     0,      0,       0,     0,
    -4,         0,       0,     2,        0,    0,     7,         0,     0,      0,       0,     0,
    7,          0,       0,     -3,       0,    0,     4,         0,     0,      0,       0,     0,
    11,         0,       0,     0,        0,    0,     5,         0,     0,      -2,      0,     0,
    -6,         0,       0,     2,        0,    0,     4,         0,     0,      -2,      0,     0,
    3,          0,       0,     -2,       0,    0,     5,         0,     0,      -2,      0,     0,
    -4,         0,       0,     2,        0,    0,     -4,        0,     0,      2,       0,     0,
    -3,         0,       0,     2,        0,    0,     4,         0,     0,      -2,      0,     0,
    3,          0,       0,     -1,       0,    0,     -3,        0,     0,      1,       0,     0,
    -3,         0,       0,     1,        0,    0,     -3,        0,     0,      2,       0,     0,
};

const npl = [9618]i16{
    0,  0,   0,  0,   0,   0,  0,   8,   -16, 4,  5,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  -8, 16,  -4, -5,  0,   0,   2,   0,  0,   0,   0,   0,
    0,  0,   8,  -16, 4,   5,  0,   0,   2,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  -1, 2,  2,   0,  0,   0,   0,   0,   0,  0,   -4,  8,   -1,
    -5, 0,   0,  2,   0,   0,  0,   0,   0,   0,  0,   4,   -8,  3,  0,  0,  0,  1,  0,   0,  1,  -1, 1,   0,  0,   3,   -8,  3,   0,  0,   0,   0,   -1,
    0,  0,   0,  0,   0,   10, -3,  0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  -2,  6,  -3,  0,   2,   0,   0,  0,   0,   0,   0,
    0,  4,   -8, 3,   0,   0,  0,   0,   0,   0,  1,   -1,  1,   0,  0,  -5, 8,  -3, 0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  -4,  8,   -3,  0,
    0,  0,   1,  0,   0,   0,  0,   0,   0,   0,  4,   -8,  1,   5,  0,  0,  2,  0,  0,   0,  0,  0,  0,   -5, 6,   4,   0,   0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   2,   -5,  0,  0,   2,   0,   0,  0,  0,  0,  0,  0,   0,  0,  2,  -5,  0,  0,   1,   0,   0,   1,  -1,  1,   0,   0,
    -1, 0,   2,  -5,  0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  2,  -5, 0,   0,  0,  0,  0,   1,  -1,  1,   0,   0,   -1, 0,   -2,  5,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   -2,  5,   0,  0,  1,  0,  0,  0,   0,  0,  0,  0,   0,  0,   -2,  5,   0,   0,  2,   2,   0,   -1,
    -1, 0,   0,  0,   3,   -7, 0,   0,   0,   0,  0,   1,   0,   0,  -2, 0,  0,  19, -21, 3,  0,  0,  0,   0,  0,   0,   0,   1,   -1, 1,   0,   2,   -4,
    0,  -3,  0,  0,   0,   0,  1,   0,   0,   -1, 1,   0,   0,   -1, 0,  2,  0,  0,  0,   0,  0,  0,  1,   -1, 1,   0,   0,   -1,  0,  -4,  10,  0,   0,
    0,  -2,  0,  0,   2,   1,  0,   0,   2,   0,  0,   -5,  0,   0,  0,  0,  0,  0,  0,   0,  0,  3,  -7,  4,  0,   0,   0,   0,   0,  0,   0,   -1,  1,
    0,  0,   0,  1,   0,   1,  -1,  0,   0,   0,  -2,  0,   0,   2,  1,  0,  0,  2,  0,   -2, 0,  0,  0,   0,  -1,  0,   0,   0,   0,  0,   18,  -16, 0,
    0,  0,   0,  0,   0,   -2, 0,   1,   1,   2,  0,   0,   1,   0,  -2, 0,  0,  0,  0,   -1, 0,  1,  -1,  1,  0,   18,  -17, 0,   0,  0,   0,   0,   0,
    -1, 0,   0,  1,   1,   0,  0,   2,   -2,  0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  -8, 13, 0,   0,  0,   0,   0,   2,   0,  0,   2,   -2,  2,
    0,  -8,  11, 0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  -8, 13, 0,  0,   0,  0,  0,  1,   0,  0,   1,   -1,  1,   0,  -8,  12,  0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  8,   -13, 0,   0,  0,  0,  0,  0,  0,   0,  1,  -1, 1,   0,  8,   -14, 0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   8,  -13, 0,   0,   0,  0,   0,   1,   -2, 0,  0,  2,  1,  0,   0,  2,  0,  -4,  5,  0,   0,   0,   -2,  0,  0,   2,   2,   0,
    3,  -3,  0,  0,   0,   0,  0,   0,   -2,  0,  0,   2,   0,   0,  0,  2,  0,  -3, 1,   0,  0,  0,  0,   0,  0,   0,   1,   0,   3,  -5,  0,   2,   0,
    0,  0,   0,  -2,  0,   0,  2,   0,   0,   0,  2,   0,   -4,  3,  0,  0,  0,  0,  0,   -1, 1,  0,  0,   0,  0,   2,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   1,  0,   0,   -1, 2,   0,   0,   0,  0,   0,   0,   0,  1,  -1, 2,  0,  0,   -2, 2,  0,  0,   0,  0,   0,   -1,  0,   1,  0,   1,   0,   3,
    -5, 0,   0,  0,   0,   0,  0,   -1,  0,   0,  1,   0,   0,   3,  -4, 0,  0,  0,  0,   0,  0,  -2, 0,   0,  2,   0,   0,   0,   2,  0,   -2,  -2,  0,
    0,  0,   -2, 0,   2,   0,  2,   0,   0,   -5, 9,   0,   0,   0,  0,  0,  0,  0,  1,   -1, 1,  0,  0,   -1, 0,   0,   0,   -1,  0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   1,   0,  0,   0,   0,   1,  -1, 1,  0,  0,  -1,  0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   2,   1,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  2,   2,  -1, 0,  0,   1,  0,   0,   0,   3,   -4, 0,   0,   0,   0,
    0,  0,   0,  -1,  1,   0,  0,   0,   1,   0,  0,   2,   0,   0,  0,  0,  0,  1,  -1,  2,  0,  0,  -1,  0,  0,   2,   0,   0,   0,  0,   0,   0,   0,
    1,  0,   0,  -9,  17,  0,  0,   0,   0,   0,  0,   0,   0,   0,  2,  0,  -3, 5,  0,   0,  0,  0,  0,   0,  0,   0,   1,   -1,  1,  0,   0,   -1,  0,
    -1, 2,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  1,  -2, 0,  0,  0,   1,  0,  0,  -2,  0,  0,   17,  -16, 0,   -2, 0,   0,   0,   0,
    0,  0,   1,  -1,  1,   0,  0,   -1,  0,   1,  -3,  0,   0,   0,  -2, 0,  0,  2,  1,   0,  0,  5,  -6,  0,  0,   0,   0,   0,   0,  0,   -2,  2,   0,
    0,  0,   9,  -13, 0,   0,  0,   0,   0,   0,  0,   1,   -1,  2,  0,  0,  -1, 0,  0,   1,  0,  0,  0,   0,  0,   0,   0,   1,   0,  0,   0,   0,   0,
    1,  0,   0,  0,   0,   0,  -1,  1,   0,   0,  0,   1,   0,   0,  1,  0,  0,  0,  0,   0,  -2, 2,  0,   0,  5,   -6,  0,   0,   0,  0,   0,   0,   0,
    0,  -1,  1,  1,   0,   5,  -7,  0,   0,   0,  0,   0,   0,   -2, 0,  0,  2,  0,  0,   6,  -8, 0,  0,   0,  0,   0,   0,   2,   0,  1,   -3,  1,   0,
    -6, 7,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   2,   0,  0,  0,  0,  1,  0,   0,  0,  0,  0,   0,  -1,  1,   1,   0,   0,  1,   0,   1,   0,
    0,  0,   0,  0,   0,   1,  -1,  1,   0,   0,  -1,  0,   0,   0,  2,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   2,  0,   1,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   2,  0,   2,   0,   0,  0,  0,  0,  0,  0,   -8, 15, 0,  0,   0,  0,   2,   0,   0,   0,  0,   0,   0,   0,
    -8, 15,  0,  0,   0,   0,  1,   0,   0,   1,  -1,  1,   0,   0,  -9, 15, 0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   8,  -15, 0,   0,   0,
    0,  0,   1,  0,   -1,  -1, 0,   0,   0,   8,  -15, 0,   0,   0,  0,  0,  2,  0,  0,   -2, 0,  0,  2,   -5, 0,   0,   0,   0,   0,  0,   -2,  0,   0,
    2,  0,   0,  0,   2,   0,  -5,  5,   0,   0,  0,   2,   0,   0,  -2, 1,  0,  0,  -6,  8,  0,  0,  0,   0,  0,   2,   0,   0,   -2, 1,   0,   0,   -2,
    0,  3,   0,  0,   0,   0,  -2,  0,   1,   1,  0,   0,   0,   1,  0,  -3, 0,  0,  0,   0,  -2, 0,  1,   1,  1,   0,   0,   1,   0,  -3,  0,   0,   0,
    0,  -2,  0,  0,   2,   0,  0,   0,   2,   0,  -3,  0,   0,   0,  0,  -2, 0,  0,  2,   0,  0,  0,  6,   -8, 0,   0,   0,   0,   0,  -2,  0,   0,   2,
    0,  0,   0,  2,   0,   -1, -5,  0,   0,   0,  -1,  0,   0,   1,  0,  0,  0,  1,  0,   -1, 0,  0,  0,   0,  -1,  0,   1,   1,   1,  0,   -20, 20,  0,
    0,  0,   0,  0,   0,   1,  0,   0,   -2,  0,  0,   20,  -21, 0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   1,  0,   0,   8,   -15, 0,  0,   0,   0,   0,
    0,  0,   2,  -2,  1,   0,  0,   -10, 15,  0,  0,   0,   0,   0,  0,  0,  -1, 1,  0,   0,  0,  1,  0,   1,  0,   0,   0,   0,   0,  0,   0,   0,   1,
    0,  0,   0,  0,   1,   0,  0,   0,   0,   0,  0,   1,   -1,  2,  0,  0,  -1, 0,  1,   0,  0,  0,  0,   0,  0,   1,   -1,  1,   0,  0,   -1,  0,   -2,
    4,  0,   0,  0,   2,   0,  0,   -2,  1,   0,  -6,  8,   0,   0,  0,  0,  0,  0,  0,   0,  -2, 2,  1,   0,  5,   -6,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   -1, 0,   0,   1,   0,  0,  1,  -1, 1,  0,   0,  -1, 0,  0,   -1, 0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   1,   0,  0,   0,   0,   0,  1,   -1,  1,   0,  0,  -1, 0,  0,  1,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   1,
    0,  0,   1,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   1,  0,  0,  2,  0,  0,   2,  -2, 1,  0,   0,  -9,  13,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   1,  0,   0,   7,  -13, 0,   0,   0,  0,   0,   -2,  0,  0,  2,  0,  0,  0,   5,  -6, 0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    9,  -17, 0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -9, 17, 0,  0,  0,   0,  2,  1,  0,   0,  -1,  1,   0,   0,   -3, 4,   0,   0,   0,
    0,  0,   1,  0,   0,   -1, 1,   0,   -3,  4,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  2,  0,  0,   -1, 2,   0,   0,   0,   0,  0,   0,   0,   -1,
    1,  1,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   0,   -2, 2,  0,  1,  0,  -2,  0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   3,   -5,
    0,  2,   0,  0,   0,   0,  -2,  0,   0,   2,  1,   0,   0,   2,  0,  -3, 1,  0,  0,   0,  -2, 0,  0,   2,  1,   0,   3,   -3,  0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   1,  0,   8,   -13, 0,  0,   0,   0,   0,  0,  0,  0,  -1, 1,   0,  0,  8,  -12, 0,  0,   0,   0,   0,   0,  0,   0,   2,   -2,
    1,  0,   -8, 11,  0,   0,  0,   0,   0,   0,  -1,  0,   0,   1,  0,  0,  0,  2,  -2,  0,  0,  0,  0,   0,  -1,  0,   0,   0,   1,  0,   18,  -16, 0,
    0,  0,   0,  0,   0,   0,  0,   1,   -1,  1,  0,   0,   -1,  0,  -1, 1,  0,  0,  0,   0,  0,  0,  0,   1,  0,   3,   -7,  4,   0,  0,   0,   0,   0,
    -2, 0,   1,  1,   1,   0,  0,   -3,  7,   0,  0,   0,   0,   0,  0,  0,  1,  -1, 2,   0,  0,  -1, 0,   -2, 5,   0,   0,   0,   0,  0,   0,   0,   1,
    0,  0,   0,  0,   -2,  5,  0,   0,   0,   0,  0,   0,   0,   1,  0,  0,  -4, 8,  -3,  0,  0,  0,  0,   1,  0,   0,   0,   1,   0,  -10, 3,   0,   0,
    0,  0,   0,  0,   0,   0,  2,   -2,  1,   0,  0,   -2,  0,   0,  0,  0,  0,  0,  -1,  0,  0,  0,  1,   0,  10,  -3,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  1,   0,   0,  4,   -8,  3,   0,  0,   0,   0,   0,  0,  0,  0,  1,  0,   0,  0,  0,  2,   -5, 0,   0,   0,   0,   0,  -1,  1,   0,   0,
    0,  1,   0,  2,   -5,  0,  0,   0,   2,   0,  -1,  -1,  1,   0,  0,  3,  -7, 0,  0,   0,  0,  0,  -2,  0,  0,   2,   0,   0,   0,  2,   0,   0,   -5,
    0,  0,   0,  0,   0,   0,  0,   1,   0,   -3, 7,   -4,  0,   0,  0,  0,  0,  -2, 0,   0,  2,  0,  0,   0,  2,   0,   -2,  0,   0,  0,   0,   1,   0,
    0,  0,   1,  0,   -18, 16, 0,   0,   0,   0,  0,   0,   -2,  0,  1,  1,  1,  0,  0,   1,  0,  -2, 0,   0,  0,   0,   0,   0,   1,  -1,  2,   0,   -8,
    12, 0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   1,   0,   -8, 13, 0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   1,  -2,  0,   0,   0,
    0,  1,   0,  0,   1,   -1, 1,   0,   0,   0,  -2,  0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   1,  -2,  0,   0,   0,   0,  0,   0,   0,   1,
    -1, 1,   0,  0,   -2,  2,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  -1,  2,  0,  0,  0,   0,  1,   -1,  0,   0,   1,  1,   0,   3,   -4,
    0,  0,   0,  0,   0,   0,  -1,  0,   0,   1,  1,   0,   0,   3,  -4, 0,  0,  0,  0,   0,  0,  0,  1,   -1, 1,   0,   0,   -1,  0,  0,   -2,  0,   0,
    0,  0,   0,  1,   -1,  1,  0,   0,   -1,  0,  0,   2,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   2,   0,   0,   1,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  2,   0,   0,   2,  0,   0,   1,   -1, 0,  0,  3,  -6, 0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   1,  0,   -3,  5,   0,
    0,  0,   0,  0,   0,   0,  0,   1,   -1,  2,  0,   -3,  4,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   1,  0,   0,   -2,  4,   0,  0,   0,   0,   0,
    0,  0,   2,  -2,  1,   0,  -5,  6,   0,   0,  0,   0,   0,   0,  0,  0,  -1, 1,  0,   0,  5,  -7, 0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   1,
    0,  5,   -8, 0,   0,   0,  0,   0,   0,   -2, 0,   0,   2,   1,  0,  6,  -8, 0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   1,   0,  0,   -8,  15,  0,
    0,  0,   0,  0,   -2,  0,  0,   2,   1,   0,  0,   2,   0,   -3, 0,  0,  0,  0,  -2,  0,  0,  2,  1,   0,  0,   6,   -8,  0,   0,  0,   0,   0,   1,
    0,  0,   -1, 1,   0,   0,  -1,  0,   1,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  3,   -5, 0,   0,   0,   0,   0,  1,   -1,  1,   0,
    0,  -1,  0,  -1,  0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  -1, 0,   0,  0,  1,  0,   0,  0,   0,   0,   0,   0,  0,   0,   1,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   1,   0,  0,  0,  1,  0,  0,   1,  -1, 1,  0,   0,  -1,  0,   1,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   1,   0,   0,  0,   1,   0,   0,  0,  0,  0,  0,  0,   0,  0,  1,  0,   0,  0,   2,   0,   0,   1,  -1,  2,   0,   0,
    -1, 0,   0,  -1,  0,   0,  0,   0,   0,   0,  0,   1,   0,   0,  0,  0,  0,  -1, 0,   0,  0,  0,  0,   -1, 1,   0,   0,   0,   1,  0,   0,   -1,  0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   -7, 13,  0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   7,  -13, 0,   0,   0,   0,  0,   2,   0,   0,
    -2, 1,   0,  0,   -5,  6,  0,   0,   0,   0,  0,   0,   0,   2,  -2, 1,  0,  0,  -8,  11, 0,  0,  0,   0,  0,   0,   0,   2,   -2, 1,   -1,  0,   2,
    0,  0,   0,  0,   0,   0,  -2,  0,   0,   2,  0,   0,   0,   4,  -4, 0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  2,   -2,  0,   0,
    0,  0,   0,  1,   -1,  1,  0,   0,   -1,  0,  0,   3,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   3,   0,   0,   1,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  3,   0,   0,   2,  -2,  0,   0,   2,  0,  0,  3,  -3, 0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   2,  0,   0,   -4,  8,
    -3, 0,   0,  0,   0,   0,  0,   0,   0,   2,  0,   0,   4,   -8, 3,  0,  0,  0,  0,   2,  0,  0,  -2,  1,  0,   0,   -2,  0,   2,  0,   0,   0,   0,
    0,  0,   1,  -1,  2,   0,  0,   -1,  0,   2,  0,   0,   0,   0,  0,  0,  1,  -1, 2,   0,  0,  0,  -2,  0,  0,   0,   0,   0,   0,  0,   0,   0,   1,
    0,  0,   1,  -2,  0,   0,  0,   0,   0,   0,  0,   -1,  1,   0,  0,  0,  2,  -2, 0,   0,  0,  0,  0,   0,  0,   -1,  1,   0,   0,  0,   1,   0,   0,
    -2, 0,   0,  0,   0,   0,  2,   -2,  1,   0,  0,   -2,  0,   0,  2,  0,  0,  0,  0,   0,  1,  -1, 1,   0,  3,   -6,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   3,  -5,  0,   0,   0,  0,   0,   1,   0,  0,  0,  0,  0,  0,   3,  -5, 0,  0,   0,  0,   0,   0,   0,   0,  1,   -1,  1,   0,
    -3, 4,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -3, 5,  0,  0,  0,   0,  0,  1,  0,   0,  0,   0,   0,   0,   -3, 5,   0,   0,   0,
    0,  0,   2,  0,   0,   2,  -2,  2,   0,   -3, 3,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   -3, 5,   0,   0,   0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   2,  -4,  0,   0,   0,  0,   1,   0,   0,  1,  -1, 1,  0,  0,   1,  -4, 0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    2,  -4,  0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -2, 4,  0,  0,  0,   0,  1,  0,  0,   1,  -1,  1,   0,   0,   -3, 4,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   -2, 4,   0,   0,   0,  0,  1,  0,  0,  0,   0,  0,  0,  0,   -2, 4,   0,   0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  -5,  8,   0,  0,   0,   0,   0,  2,   0,   0,   2,  -2, 2,  0,  -5, 6,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   -5,  8,
    0,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   -5,  8,  0,  0,  0,  0,  0,   1,  0,  0,  1,   -1, 1,   0,   -5,  7,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   -5,  8,   0,  0,   0,   0,   0,  1,  0,  0,  0,  0,   0,  0,  5,  -8,  0,  0,   0,   0,   0,   0,  0,   0,   1,   -1,
    2,  0,   0,  -1,  0,   -1, 0,   0,   0,   0,  0,   0,   0,   0,  1,  0,  0,  0,  0,   -1, 0,  0,  0,   0,  0,   0,   -1,  1,   0,  0,   0,   1,   0,
    -1, 0,   0,  0,   0,   0,  0,   2,   -2,  1,  0,   0,   -2,  0,  1,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   -6,  11,  0,  0,   0,   0,   2,
    0,  0,   0,  0,   0,   0,  0,   6,   -11, 0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   -1, 0,  4,  0,   0,  0,   0,   0,   2,   0,  0,   0,   0,   0,
    1,  0,   -4, 0,   0,   0,  0,   0,   0,   2,  0,   0,   -2,  1,  0,  -3, 3,  0,  0,   0,  0,  0,  0,   -2, 0,   0,   2,   0,   0,  0,   2,   0,   0,
    -2, 0,   0,  0,   0,   0,  2,   -2,  1,   0,  0,   -7,  9,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   4,   -5, 0,   0,   2,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  2,   0,  0,   0,   1,   0,   0,  1,   -1,  1,   0,
    0,  -1,  0,  2,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  2,  0,   0,  0,  1,  0,   0,  0,   0,   0,   0,   0,  0,   0,   2,   0,
    0,  0,   2,  0,   0,   2,  -2,  2,   0,   0,  -2,  0,   2,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   5,   0,  0,   2,   0,   0,
    0,  0,   1,  0,   3,   -5, 0,   0,   0,   0,  0,   0,   0,   0,  -1, 1,  0,  0,  3,   -4, 0,  0,  0,   0,  0,   0,   0,   0,   2,  -2,  1,   0,   -3,
    3,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   1,   0,   0,  2,  -4, 0,  0,  0,   0,  0,  0,  0,   2,  -2,  1,   0,   0,   -4, 4,   0,   0,   0,
    0,  0,   0,  0,   1,   -1, 2,   0,   -5,  7,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   3,  -6,  0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   -3,  6,  0,   0,   0,   0,  1,   0,   0,   1,  -1, 1,  0,  0,  -4,  6,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   -3,
    6,  0,   0,  0,   0,   1,  0,   0,   0,   0,  0,   0,   0,   -3, 6,  0,  0,  0,  0,   2,  0,  0,  -1,  1,  0,   0,   2,   -2,  0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   1,  0,   2,   -3,  0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  -5,  9,  0,   0,   0,   0,   2,  0,   0,   0,   0,
    0,  0,   0,  -5,  9,   0,  0,   0,   0,   1,  0,   0,   0,   0,  0,  0,  0,  5,  -9,  0,  0,  0,  0,   0,  0,   0,   -1,  1,   0,  0,   0,   1,   0,
    -2, 0,   0,  0,   0,   0,  0,   2,   -2,  1,  0,   0,   -2,  0,  2,  0,  0,  0,  0,   -2, 0,  1,  1,   1,  0,   0,   1,   0,   0,  0,   0,   0,   0,
    0,  0,   -2, 2,   0,   0,  3,   -3,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  -6, 10, 0,   0,  0,   0,   0,   1,   0,  0,   0,   0,   0,
    0,  -6,  10, 0,   0,   0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  -2, 3,  0,  0,   0,  0,  0,  2,   0,  0,   0,   0,   0,   0,  -2,  3,   0,   0,
    0,  0,   0,  1,   0,   0,  1,   -1,  1,   0,  -2,  2,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  2,   -3,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   2,  -3,  0,   0,   0,  0,   0,   1,   0,  0,  0,  0,  0,  0,   0,  0,  0,  3,   0,  0,   0,   1,   0,   0,  1,   -1,  1,   0,
    0,  -1,  0,  3,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  3,  0,   0,  0,  1,  0,   0,  0,   0,   0,   0,   0,  0,   0,   3,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   0,  4,   -8,  0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  -4,  8,   0,   0,   0,  0,   2,   0,   0,
    -2, 2,   0,  0,   0,   2,  0,   -2,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   -4, 7,  0,  0,   0,  0,   2,   0,   0,   0,  0,   0,   0,   0,
    -4, 7,   0,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   0,  4,  -7, 0,  0,  0,   0,  0,  0,  0,   0,  0,   1,   0,   -2,  3,  0,   0,   0,   0,
    0,  0,   0,  0,   2,   -2, 1,   0,   0,   -2, 0,   3,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   -5, 10,  0,   0,   0,   0,  2,   0,   0,   0,
    0,  1,   0,  -1,  2,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  4,  0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   -3,
    5,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   0,   -3, 5,  0,  0,  0,  0,   1,  0,  0,  0,   0,  0,   0,   0,   3,   -5, 0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   1,   -2,  0,  0,   0,   0,   0,  1,  0,  0,  1,  -1,  1,  0,  1,  -3,  0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   1,  -2,  0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  -1, 2,  0,   0,  0,  0,  0,   1,  0,   0,   0,   0,   0,  0,   -1,  2,   0,
    0,  0,   0,  0,   2,   0,  0,   0,   0,   0,  0,   -7,  11,  0,  0,  0,  0,  0,  2,   0,  0,  0,  0,   0,  0,   -7,  11,  0,   0,  0,   0,   0,   1,
    0,  0,   -2, 2,   0,   0,  4,   -4,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  2,  -3,  0,  0,   0,   0,   0,   0,  0,   2,   -2,  1,
    0,  -4,  4,  0,   0,   0,  0,   0,   0,   0,  0,   -1,  1,   0,  0,  4,  -5, 0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   1,   -1,  0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  -4,  7,   0,   0,  0,  0,  0,  1,  0,   0,  1,  -1, 1,   0,  -4,  6,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   -4, 7,   0,   0,   0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   -4, 6,  0,  0,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    -4, 6,   0,  0,   0,   0,  0,   1,   0,   0,  1,   -1,  1,   0,  -4, 5,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   -4, 6,   0,   0,   0,
    0,  0,   1,  0,   0,   0,  0,   0,   0,   4,  -6,  0,   0,   0,  0,  0,  0,  -2, 0,   0,  2,  0,  0,   2,  -2,  0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   0,  -1, 1,  0,  0,  1,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   1,   0,   1,
    -1, 0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -1, 0,  5,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   1,  -3,  0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   -1, 3,   0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   -7, 12,  0,   0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  -1,  1,   0,  0,   0,   0,   0,  2,   0,   0,   0,  0,  0,  0,  -1, 1,   0,  0,  0,  0,   0,  1,   0,   0,   1,   -1, 1,   0,   -1,  0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   1,   -1, 0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   1,   -1,  0,  0,   0,   0,   0,
    1,  0,   0,  1,   -1,  1,  0,   1,   -2,  0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  -2,  5,  0,   0,   0,   0,   2,  0,   0,   0,   0,
    0,  0,   0,  -1,  0,   4,  0,   0,   0,   2,  0,   0,   0,   0,  0,  0,  0,  1,  0,   -4, 0,  0,  0,   0,  0,   0,   0,   0,   1,  0,   -1,  1,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   -6,  10, 0,  0,  0,  0,  2,   0,  0,  0,  0,   0,  0,   0,   -6,  10,  0,  0,   0,   0,   0,
    0,  0,   2,  -2,  1,   0,  0,   -3,  0,   3,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  -3, 7,   0,  0,   0,   0,   2,   -2, 0,   0,   2,   0,
    0,  4,   -4, 0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  -5, 8,  0,   0,  0,  0,  2,   0,  0,   0,   0,   0,   0,  0,   5,   -8,  0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   -1,  0,   3,  0,  0,  0,  2,  0,   0,  0,  0,  0,   0,  0,   -1,  0,   3,   0,  0,   0,   1,   0,
    0,  0,   0,  0,   0,   0,  1,   0,   -3,  0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   2,  -4, 0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    -2, 4,   0,  0,   0,   0,  0,   1,   0,   0,  1,   -1,  1,   0,  -2, 3,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   -2, 4,   0,   0,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   -6, 9,   0,   0,   0,  0,  0,  2,  0,  0,   0,  0,  0,  0,   -6, 9,   0,   0,   0,   0,  0,   1,   0,   0,
    0,  0,   0,  0,   6,   -9, 0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  1,  0,  0,   1,  0,  -2, 0,   0,  0,   0,   0,   0,   2,  -2,  1,   0,   -2,
    2,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -4, 6,  0,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   4,  -6,  0,   0,   0,
    0,  0,   0,  0,   0,   0,  1,   0,   3,   -4, 0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   -1, 0,   2,   0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  0,   1,   0,  -2,  0,   0,   0,  0,   0,   0,   0,  0,  1,  0,  0,  1,   0,  -1, 0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   -5,  9,
    0,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   0,   3,  -4, 0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   -3,  4,   0,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   -3,  4,   0,  0,   0,   0,   0,  1,  0,  0,  0,  0,   0,  0,  3,  -4,  0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   3,  -4,  0,   0,  0,   0,   0,   1,  0,   0,   0,   0,  1,  0,  0,  2,  -2,  0,  0,  0,  0,   0,  0,   0,   0,   0,   1,  0,   0,   -1,  0,
    2,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   1,   0,  0,  -3, 0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   1,   0,   1,  -5,  0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   -1,  0,   1,  0,   0,   0,   1,  0,  0,  0,  0,  0,   0,  0,  1,  0,   -1, 0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   1,  0,   -1,  0,  0,   0,   1,   0,  0,   0,   0,   0,  0,  0,  1,  0,  -3,  5,  0,  0,  0,   0,  0,   0,   0,   1,   0,  -3,  4,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   1,   0,   0,  -2, 0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   2,   -2,  0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  1,   0,   0,   -1, 0,   0,   0,   0,  0,  0,  0,  1,  0,   0,  -1, 0,  1,   0,  0,   0,   0,   0,   0,  0,   0,   1,   0,
    0,  -2,  2,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -8, 14, 0,  0,  0,   0,  0,  2,  0,   0,  0,   0,   0,   0,   0,  1,   0,   2,   -5,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  5,   -8,  3,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  5,   -8,  3,   0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   -1, 0,   0,   0,   0,  0,   1,   0,   0,  0,  0,  0,  0,  0,   1,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    3,  -8,  3,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -3, 8,  -3, 0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   1,  0,   -2,  5,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   -8,  12, 0,   0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  -8,  12, 0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   1,   0,  1,   -2,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  1,   0,  0,  1,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  2,  0,  0,  0,  0,   2,  0,  0,  0,   0,  0,   0,   0,   1,   0,  0,   2,   0,   0,
    2,  0,   0,  2,   -2,  1,  0,   -5,  5,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  1,   0,  1,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  1,   0,   1,  0,   0,   0,   1,  0,   0,   0,   0,  0,  0,  0,  1,  0,   1,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   3,   -6,  0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   -3,  6,   0,  0,  0,  0,  0,  1,   0,  0,  0,  0,   0,  0,   -3,  6,   0,   0,  0,   0,   0,   2,
    0,  0,   0,  0,   0,   0,  0,   -1,  4,   0,  0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  -5, 7,  0,   0,  0,   0,   0,   2,   0,  0,   0,   0,   0,
    0,  -5,  7,  0,   0,   0,  0,   0,   1,   0,  0,   1,   -1,  1,  0,  -5, 6,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  5,   -7,  0,   0,
    0,  0,   0,  0,   0,   0,  2,   -2,  1,   0,  0,   -1,  0,   1,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   -1,  0,   1,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   -1,  0,  3,   0,   0,   0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   0,  1,  0,  2,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    0,  -2,  6,  0,   0,   0,  0,   2,   0,   0,  0,   0,   1,   0,  2,  -2, 0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  -6,  9,   0,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   0,  6,   -9,  0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   -2, 2,   0,   0,   0,   0,  0,   1,   0,   0,
    1,  -1,  1,  0,   -2,  1,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  2,   -2, 0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   2,
    -2, 0,   0,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   0,  1,  0,  3,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   -5, 7,   0,   0,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   0,   5,  -7,  0,   0,   0,  0,  0,  0,  0,  0,   0,  1,  0,  -2,  2,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   4,   -5, 0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  1,  -3,  0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   -1,  3,
    0,  0,   0,  0,   0,   1,  0,   0,   1,   -1, 1,   0,   -1,  2,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   -1,  3,   0,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   -7,  10,  0,  0,   0,   0,   0,  2,  0,  0,  0,  0,   0,  0,  -7, 10,  0,  0,   0,   0,   0,   1,  0,   0,   0,   0,
    0,  0,   0,  3,   -3,  0,  0,   0,   0,   0,  0,   0,   0,   0,  0,  0,  -4, 8,  0,   0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   -4,  5,   0,
    0,  0,   0,  0,   2,   0,  0,   0,   0,   0,  0,   -4,  5,   0,  0,  0,  0,  0,  1,   0,  0,  0,  0,   0,  0,   4,   -5,  0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   1,   1,   0,  0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  0,  -2, 0,   5,  0,   0,   0,   2,   0,  0,   0,   0,   0,
    0,  0,   0,  3,   0,   0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  1,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  1,   0,   0,   0,
    0,  0,   0,  2,   0,   0,  0,   0,   0,   0,  -9,  13,  0,   0,  0,  0,  0,  2,  0,   0,  0,  0,  0,   0,  0,   -1,  5,   0,   0,  0,   0,   2,   0,
    0,  0,   0,  0,   0,   0,  -2,  0,   4,   0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   0,  2,  0,  -4,  0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  -2,  7,  0,   0,   0,  0,   2,   0,   0,  0,   0,   0,   0,  0,  2,  0,  -3, 0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   -2, 5,   0,   0,   0,
    0,  0,   1,  0,   0,   0,  0,   0,   0,   -2, 5,   0,   0,   0,  0,  0,  2,  0,  0,   0,  0,  0,  0,   -6, 8,   0,   0,   0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   -6,  8,  0,   0,   0,   0,  0,   1,   0,   0,  0,  0,  0,  0,  6,   -8, 0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   1,   0,   0,
    2,  0,   -2, 0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  -3, 9,  0,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   5,  -6,  0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   5,  -6,  0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   2,  0,   -2,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   2,   0,  -2,  0,   0,   0,  1,   0,   0,   0,  0,  0,  0,  0,  2,   0,  -2, 0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   -5,  10,
    0,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   0,   4,  -4, 0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   4,   -4, 0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   -3,  3,   0,  0,   0,   0,   0,  1,  0,  0,  0,  0,   0,  0,  3,  -3,  0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   3,  -3,  0,   0,  0,   0,   0,   1,  0,   0,   0,   0,  0,  0,  3,  -3, 0,   0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   0,   2,   0,
    0,  -3,  0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   -5,  13, 0,  0,  0,  0,  2,   0,  0,  0,  0,   0,  0,   0,   2,   0,   -1, 0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   2,   0,   -1, 0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  0,  2,  0,   0,  -2,  0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   2,  0,   0,   -2, 0,   0,   1,   0,  0,   0,   0,   0,  0,  0,  3,  -2, 0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   3,   -2,  0,
    0,  0,   0,  2,   0,   0,  0,   0,   0,   0,  0,   2,   0,   0,  -1, 0,  0,  2,  0,   0,  0,  0,  0,   0,  0,   -6,  15,  0,   0,  0,   0,   2,   0,
    0,  0,   0,  0,   0,   -8, 15,  0,   0,   0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   -3, 9,  -4, 0,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    0,  2,   0,  2,   -5,  0,  0,   2,   0,   0,  0,   0,   0,   0,  0,  -2, 8,  -1, -5,  0,  0,  2,  0,   0,  0,   0,   0,   0,   0,  6,   -8,  3,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   0,  2,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   1,   0,   0,  1,  -1, 1,  0,  0,   1,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   0,  2,  0,  0,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   -6, 16,  -4,  -5,  0,
    0,  2,   0,  0,   0,   0,  0,   0,   0,   -2, 8,   -3,  0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   -2, 8,   -3,  0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  0,   6,   -8, 1,   5,   0,   0,  2,   0,   0,   0,  0,  0,  0,  0,  2,   0,  -2, 5,  0,   0,  2,   0,   0,   0,   0,  0,   0,   3,   -5,
    4,  0,   0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   -8,  11, 0,  0,  0,  0,  0,   2,  0,  0,  0,   0,  0,   0,   -8,  11,  0,  0,   0,   0,   0,
    1,  0,   0,  0,   0,   0,  0,   -8,  11,  0,  0,   0,   0,   0,  2,  0,  0,  0,  0,   0,  0,  0,  11,  0,  0,   0,   0,   0,   2,  0,   0,   0,   0,
    0,  0,   0,  2,   0,   0,  1,   0,   0,   2,  0,   0,   0,   0,  0,  0,  3,  -3, 0,   2,  0,  0,  0,   2,  0,   0,   2,   -2,  1,  0,   0,   4,   -8,
    3,  0,   0,  0,   0,   0,  0,   1,   -1,  0,  0,   0,   1,   0,  0,  0,  0,  0,  0,   0,  0,  2,  -2,  1,  0,   0,   -4,  8,   -3, 0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   1,   2,   0,  0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  0,  2,  0,   1,  0,   0,   0,   2,   0,  0,   0,   0,   0,
    0,  -3,  7,  0,   0,   0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  0,  0,  4,  0,   0,  0,  0,  2,   0,  0,   0,   0,   0,   0,  -5,  6,   0,   0,
    0,  0,   0,  2,   0,   0,  0,   0,   0,   0,  -5,  6,   0,   0,  0,  0,  0,  1,  0,   0,  0,  0,  0,   0,  5,   -6,  0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   5,  -6,  0,   0,   0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   0,  2,  0,  2,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    0,  -1,  6,  0,   0,   0,  0,   2,   0,   0,  0,   0,   0,   0,  0,  7,  -9, 0,  0,   0,  0,  2,  0,   0,  0,   0,   0,   0,   2,  -1,  0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   2,  -1,  0,   0,   0,  0,  0,  2,  0,  0,   0,  0,  0,  0,   0,  6,   -7,  0,   0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   5,  -5,  0,   0,   0,  0,   2,   0,   0,  0,  0,  0,  0,  -1,  4,  0,  0,  0,   0,  0,   1,   0,   0,   0,  0,   0,   0,   -1,
    4,  0,   0,  0,   0,   0,  2,   0,   0,   0,  0,   0,   0,   -7, 9,  0,  0,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   -7,  9,  0,   0,   0,   0,
    0,  1,   0,  0,   0,   0,  0,   0,   0,   4,  -3,  0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   3,  -1,  0,   0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  -4,  4,   0,  0,   0,   0,   0,  1,   0,   0,   0,  0,  0,  0,  4,  -4,  0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   4,   -4,
    0,  0,   0,  0,   0,   1,  0,   0,   0,   0,  0,   0,   4,   -4, 0,  0,  0,  0,  0,   2,  0,  0,  0,   0,  0,   0,   0,   2,   1,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   0,   -3,  0,  5,   0,   0,   0,  2,  0,  0,  0,  0,   0,  0,  1,  1,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   1,  1,   0,   0,  0,   0,   0,   1,  0,   0,   0,   0,  0,  0,  1,  1,  0,   0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   -9,  12,  0,
    0,  0,   0,  0,   2,   0,  0,   0,   0,   0,  0,   0,   3,   0,  -4, 0,  0,  0,  0,   0,  0,  2,  -2,  1,  0,   1,   -1,  0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   0,   0,  0,   7,   -8,  0,  0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  0,  3,  0,   -3, 0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   3,  0,   -3,  0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  -2, 6,  0,  0,   0,  0,  0,  2,   0,  0,   0,   0,   0,   0,  -6,  7,   0,   0,
    0,  0,   0,  1,   0,   0,  0,   0,   0,   0,  6,   -7,  0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   6,   -6,  0,   0,  0,   0,   2,   0,
    0,  0,   0,  0,   0,   0,  3,   0,   -2,  0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  3,  0,  -2,  0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    0,  5,   -4, 0,   0,   0,  0,   2,   0,   0,  0,   0,   0,   0,  3,  -2, 0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   3,  -2,  0,   0,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   0,  3,   0,   -1,  0,  0,  0,  2,  0,  0,   0,  0,  0,  0,   0,  3,   0,   -1,  0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   3,  0,   0,   -2,  0,  0,   2,   0,   0,  0,  0,  0,  0,  0,   4,  -2, 0,  0,   0,  0,   2,   0,   0,   0,  0,   0,   0,   0,
    3,  0,   0,  -1,  0,   0,  2,   0,   0,   2,  -2,  1,   0,   0,  1,  0,  -1, 0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   -8,  16, 0,   0,   0,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   0,   3,  0,   2,   -5,  0,  0,  2,  0,  0,  0,   0,  0,  0,  0,   7,  -8,  3,   0,   0,   0,  2,   0,   0,   0,
    0,  0,   0,  0,   -5,  16, -4,  -5,  0,   0,  2,   0,   0,   0,  0,  0,  0,  0,  3,   0,  0,  0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   -1,
    8,  -3,  0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   -8,  10, 0,  0,  0,  0,  0,   2,  0,  0,  0,   0,  0,   0,   -8,  10,  0,  0,   0,   0,   0,
    1,  0,   0,  0,   0,   0,  0,   -8,  10,  0,  0,   0,   0,   0,  2,  0,  0,  0,  0,   0,  0,  0,  2,   2,  0,   0,   0,   0,   2,  0,   0,   0,   0,
    0,  0,   0,  3,   0,   1,  0,   0,   0,   2,  0,   0,   0,   0,  0,  0,  -3, 8,  0,   0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   -5,  5,   0,
    0,  0,   0,  0,   1,   0,  0,   0,   0,   0,  0,   5,   -5,  0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   0,  0,   5,   -5,  0,   0,  0,   0,   0,   1,
    0,  0,   0,  0,   0,   0,  5,   -5,  0,   0,  0,   0,   0,   2,  0,  0,  0,  0,  0,   0,  2,  0,  0,   0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   1,   0,  0,   0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  2,   0,  0,   0,   0,   0,   0,  0,   7,   -7,  0,
    0,  0,   0,  2,   0,   0,  0,   0,   0,   0,  0,   7,   -7,  0,  0,  0,  0,  2,  0,   0,  0,  0,  0,   0,  0,   6,   -5,  0,   0,  0,   0,   2,   0,
    0,  0,   0,  0,   0,   7,  -8,  0,   0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  5,  -3, 0,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    4,  -3,  0,  0,   0,   0,  0,   2,   0,   0,  0,   0,   0,   0,  1,  2,  0,  0,  0,   0,  0,  2,  0,   0,  0,   0,   0,   0,   -9, 11,  0,   0,   0,
    0,  0,   2,  0,   0,   0,  0,   0,   0,   -9, 11,  0,   0,   0,  0,  0,  1,  0,  0,   0,  0,  0,  0,   0,  4,   0,   -4,  0,   0,  0,   2,   0,   0,
    0,  0,   0,  0,   0,   4,  0,   -3,  0,   0,  0,   2,   0,   0,  0,  0,  0,  0,  -6,  6,  0,  0,  0,   0,  0,   1,   0,   0,   0,  0,   0,   0,   6,
    -6, 0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   6,  -6, 0,  0,  0,  0,   0,  1,  0,  0,   0,  0,   0,   0,   0,   4,  0,   -2,  0,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   0,   6,  -4,  0,   0,   0,  0,  2,  0,  0,  0,   0,  0,  0,  3,   -1, 0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  3,   -1,  0,  0,   0,   0,   0,  1,   0,   0,   0,  0,  0,  0,  3,  -1,  0,  0,  0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   4,
    0,  -1,  0,  0,   0,   2,  0,   0,   0,   0,  0,   0,   0,   4,  0,  0,  -2, 0,  0,   2,  0,  0,  0,   0,  0,   0,   0,   5,   -2, 0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   0,   4,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  8,  -9,  0,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   5,  -4,  0,   0,  0,   0,   0,   2,  0,   0,   0,   0,  0,  0,  2,  1,  0,   0,  0,  0,  0,   2,  0,   0,   0,   0,   0,  0,   2,   1,   0,
    0,  0,   0,  0,   1,   0,  0,   0,   0,   0,  0,   2,   1,   0,  0,  0,  0,  0,  1,   0,  0,  0,  0,   0,  0,   -7,  7,   0,   0,  0,   0,   0,   1,
    0,  0,   0,  0,   0,   0,  7,   -7,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  4,  -2, 0,   0,  0,   0,   0,   1,   0,  0,   0,   0,   0,
    0,  4,   -2, 0,   0,   0,  0,   0,   2,   0,  0,   0,   0,   0,  0,  4,  -2, 0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   0,  4,   -2,  0,   0,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   5,   0,   -4, 0,  0,  0,  2,  0,   0,  0,  0,  0,   0,  0,   5,   0,   -3,  0,  0,   0,   2,   0,
    0,  0,   0,  0,   0,   0,  5,   0,   -2,  0,  0,   0,   2,   0,  0,  0,  0,  0,  0,   3,  0,  0,  0,   0,  0,   0,   2,   0,   0,  0,   0,   0,   0,
    -8, 8,   0,  0,   0,   0,  0,   1,   0,   0,  0,   0,   0,   0,  8,  -8, 0,  0,  0,   0,  0,  0,  0,   0,  0,   0,   0,   0,   5,  -3,  0,   0,   0,
    0,  0,   1,  0,   0,   0,  0,   0,   0,   5,  -3,  0,   0,   0,  0,  0,  2,  0,  0,   0,  0,  0,  0,   -9, 9,   0,   0,   0,   0,  0,   1,   0,   0,
    0,  0,   0,  0,   -9,  9,  0,   0,   0,   0,  0,   1,   0,   0,  0,  0,  0,  0,  -9,  9,  0,  0,  0,   0,  0,   1,   0,   0,   0,  0,   0,   0,   9,
    -9, 0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   6,  -4, 0,  0,  0,  0,   0,  1,  0,  0,   0,  0,   0,   0,   0,   6,  0,   0,   0,   0,
    0,  2,   0,  0,   0,   0,  0,   0,   0,   6,  0,   0,   0,   0,  0,  0,  0,  0,  0,   0,  0,  0,  0,   6,  0,   0,   0,   0,   0,  0,   0,   0,   0,
    0,  0,   0,  0,   6,   0,  0,   0,   0,   0,  1,   0,   0,   0,  0,  0,  0,  0,  6,   0,  0,  0,  0,   0,  2,   0,   0,   0,   0,  0,   0,   0,   6,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   6,  0,  0,  0,  0,  0,   1,  0,  0,  0,   0,  0,   0,   0,   6,   0,  0,   0,   0,   0,
    2,  0,   0,  0,   0,   0,  0,   0,   0,   0,  0,   0,   0,   0,  2,  1,  0,  0,  -2,  0,  0,  0,  2,   0,  -2,  0,   0,   0,   0,  1,   0,   0,   -2,
    0,  0,   2,  -2,  0,   0,  0,   0,   0,   0,  1,   0,   0,   -2, 0,  0,  0,  1,  0,   -1, 0,  0,  0,   0,  1,   0,   0,   -2,  0,  0,   1,   -1,  0,
    0,  0,   0,  0,   0,   -1, 0,   0,   0,   0,  0,   3,   -3,  0,  0,  0,  0,  0,  0,   -1, 0,  0,  0,   0,  0,   0,   2,   0,   -2, 0,   0,   0,   0,
    -1, 0,   0,  2,   0,   0,  0,   4,   -8,  3,  0,   0,   0,   0,  1,  0,  0,  -2, 0,   0,  0,  4,  -8,  3,  0,   0,   0,   0,   -2, 0,   0,   2,   0,
    0,  0,   4,  -8,  3,   0,  0,   0,   0,   -1, 0,   0,   0,   0,  0,  0,  2,  0,  -3,  0,  0,  0,  0,   -1, 0,   0,   0,   0,   0,  0,   1,   0,   -1,
    0,  0,   0,  0,   -1,  0,  0,   0,   0,   0,  1,   -1,  0,   0,  0,  0,  0,  0,  -1,  0,  0,  2,  0,   0,  2,   -2,  0,   0,   0,  0,   0,   0,   1,
    0,  -1,  1,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   -1, 0,  0,  2,  0,  0,   0,  2,  0,  -3,  0,  0,   0,   0,   -2,  0,  0,   0,   0,   0,
    0,  2,   0,  -3,  0,   0,  0,   0,   1,   0,  0,   0,   0,   0,  0,  4,  -8, 3,  0,   0,  0,  0,  -1,  0,  1,   -1,  1,   0,   0,  -1,  0,   0,   0,
    0,  0,   0,  1,   0,   1,  -1,  1,   0,   0,  -1,  0,   0,   0,  0,  0,  0,  -1, 0,   0,  0,  0,  0,   0,  4,   -8,  3,   0,   0,  0,   0,   -1,  0,
    0,  2,   1,  0,   0,   2,  0,   -2,  0,   0,  0,   0,   0,   0,  0,  0,  0,  0,  0,   2,  0,  -2, 0,   0,  0,   0,   -1,  0,   0,  2,   0,   0,   0,
    2,  0,   -2, 0,   0,   0,  0,   -1,  0,   0,  2,   0,   0,   3,  -3, 0,  0,  0,  0,   0,  0,  1,  0,   0,  -2,  1,   0,   0,   -2, 0,   2,   0,   0,
    0,  0,   1,  0,   2,   -2, 2,   0,   -3,  3,  0,   0,   0,   0,  0,  0,  1,  0,  2,   -2, 2,  0,  0,   -2, 0,   2,   0,   0,   0,  0,   1,   0,   0,
    0,  0,   0,  1,   -1,  0,  0,   0,   0,   0,  0,   1,   0,   0,  0,  0,  0,  0,  1,   0,  -1, 0,  0,   0,  0,   0,   0,   0,   -2, 0,   0,   2,   -2,
    0,  0,   0,  0,   0,   0,  0,   0,   0,   -2, 0,   0,   0,   1,  0,  -1, 0,  0,  0,   0,  0,  0,  2,   0,  2,   0,   -2,  2,   0,  0,   0,   0,   0,
    0,  0,   0,  2,   0,   2,  0,   0,   -1,  0,  1,   0,   0,   0,  0,  0,  0,  2,  0,   2,  0,  -1, 1,   0,  0,   0,   0,   0,   0,  0,   0,   2,   0,
    2,  0,   -2, 3,   0,   0,  0,   0,   0,   0,  0,   0,   0,   2,  0,  0,  0,  2,  0,   -2, 0,  0,  0,   0,  0,   0,   1,   1,   2,  0,   0,   1,   0,
    0,  0,   0,  0,   0,   1,  0,   2,   0,   2,  0,   0,   1,   0,  0,  0,  0,  0,  0,   -1, 0,  2,  0,   2,  0,   10,  -3,  0,   0,  0,   0,   0,   0,
    0,  0,   1,  1,   1,   0,  0,   1,   0,   0,  0,   0,   0,   0,  1,  0,  2,  0,  2,   0,  0,  1,  0,   0,  0,   0,   0,   0,   0,  0,   2,   0,   2,
    0,  0,   4,  -8,  3,   0,  0,   0,   0,   0,  0,   2,   0,   2,  0,  0,  -4, 8,  -3,  0,  0,  0,  0,   -1, 0,   2,   0,   2,   0,  0,   -4,  8,   -3,
    0,  0,   0,  0,   2,   0,  2,   -2,  2,   0,  0,   -2,  0,   3,  0,  0,  0,  0,  1,   0,  2,  0,  1,   0,  0,   -2,  0,   3,   0,  0,   0,   0,   0,
    0,  1,   1,  0,   0,   0,  1,   0,   0,   0,  0,   0,   0,   -1, 0,  2,  0,  1,  0,   0,  1,  0,  0,   0,  0,   0,   0,   -2,  0,  2,   2,   2,   0,
    0,  2,   0,  -2,  0,   0,  0,   0,   0,   0,  2,   0,   2,   0,  2,  -3, 0,  0,  0,   0,  0,  0,  0,   0,  2,   0,   2,   0,   1,  -1,  0,   0,   0,
    0,  0,   0,  0,   0,   2,  0,   2,   0,   0,  1,   0,   -1,  0,  0,  0,  0,  0,  0,   2,  0,  2,  0,   2,  -2,  0,   0,   0,   0,  0,   0,   -1,  0,
    2,  2,   2,  0,   0,   -1, 0,   1,   0,   0,  0,   0,   1,   0,  2,  0,  2,  0,  -1,  1,  0,  0,  0,   0,  0,   0,   -1,  0,   2,  2,   2,   0,   0,
    2,  0,   -3, 0,   0,   0,  0,   2,   0,   2,  0,   2,   0,   0,  2,  0,  -3, 0,  0,   0,  0,  1,  0,   2,  0,   2,   0,   0,   -4, 8,   -3,  0,   0,
    0,  0,   1,  0,   2,   0,  2,   0,   0,   4,  -8,  3,   0,   0,  0,  0,  1,  0,  1,   1,  1,  0,  0,   1,  0,   0,   0,   0,   0,  0,   0,   0,   2,
    0,  2,   0,  0,   1,   0,  0,   0,   0,   0,  0,   2,   0,   2,  0,  1,  0,  0,  1,   0,  0,  0,  0,   0,  0,   -1,  0,   2,   2,  2,   0,   0,   2,
    0,  -2,  0,  0,   0,   0,  -1,  0,   2,   2,  2,   0,   3,   -3, 0,  0,  0,  0,  0,   0,  1,  0,  2,   0,  2,   0,   1,   -1,  0,  0,   0,   0,   0,
    0,  0,   0,  2,   2,   2,  0,   0,   2,   0,  -2,  0,   0,   0,  0,
};

const icpl = [2748]i16{
    1440, 0,    0,    0,    56,   -117, -42, -40,  125,  -43,  0,    -54,  0,    5,    0,    0,    3,    -7,   -3,    0,    3,    0,    0,     -2,    -114,  0,     0,
    61,   -219, 89,   0,    0,    -3,   0,   0,    0,    -462, 1604, 0,    0,    99,   0,    0,    -53,  -3,   0,     0,    2,    0,    6,     2,     0,     3,     0,
    0,    0,    -12,  0,    0,    0,    14,  -218, 117,  8,    31,   -481, -257, -17,  -491, 128,  0,    0,    -3084, 5123, 2735, 1647, -1444, 2409,  -1286, -771,  11,
    -24,  -11,  -9,   26,   -9,   0,    0,   103,  -60,  0,    0,    0,    -13,  -7,   0,    -26,  -29,  -16,  14,    9,    -27,  -14,  -5,    12,    0,     0,     -6,
    -7,   0,    0,    0,    0,    24,   0,   0,    284,  0,    0,    -151, 226,  101,  0,    0,    0,    -8,   -2,    0,    0,    -6,   -3,    0,     5,     0,     0,
    -3,   -41,  175,  76,   17,   0,    15,  6,    0,    425,  212,  -133, 269,  1200, 598,  319,  -641, 235,  334,   0,    0,    11,   -12,   -7,    -6,    5,     -6,
    3,    3,    -5,   0,    0,    3,    6,   0,    0,    -3,   15,   0,    0,    0,    13,   0,    0,    -7,   -6,    -9,   0,    0,    266,   -78,   0,     0,     -460,
    -435, -232, 246,  0,    15,   7,    0,   -3,   0,    0,    2,    0,    131,  0,    0,    4,    0,    0,    0,     0,    3,    0,    0,     0,     4,     2,     0,
    0,    3,    0,    0,    -17,  -19,  -10, 9,    -9,   -11,  6,    -5,   -6,   0,    0,    3,    -16,  8,    0,     0,    0,    3,    0,     0,     11,    24,    11,
    -5,   -3,   -4,   -2,   1,    3,    0,   0,    -1,   0,    -8,   -4,   0,    0,    3,    0,    0,    0,    5,     0,    0,    0,    3,     2,     0,     -6,    4,
    2,    3,    -3,   -5,   0,    0,    -5,  0,    0,    2,    4,    24,   13,   -2,   -42,  20,   0,    0,    -10,   233,  0,    0,    -3,    0,     0,     1,     78,
    -18,  0,    0,    0,    3,    1,    0,   0,    -3,   -1,   0,    0,    -4,   -2,   1,    0,    -8,   -4,   -1,    0,    -5,   3,    0,     -7,    0,     0,     3,
    -14,  8,    3,    6,    0,    8,    -4,  0,    0,    19,   10,   0,    45,   -22,  0,    0,    -3,   0,    0,     0,    0,    -3,   0,     0,     0,     3,     0,
    0,    3,    5,    3,    -2,   89,   -16, -9,   -48,  0,    3,    0,    0,    -3,   7,    4,    2,    -349, -62,   0,    0,    -15,  22,    0,     0,     -3,    0,
    0,    0,    -53,  0,    0,    0,    5,   0,    0,    -3,   0,    -8,   0,    0,    15,   -7,   -4,   -8,   -3,    0,    0,    1,    -21,   -78,   0,     0,     20,
    -70,  -37,  -11,  0,    6,    3,    0,   5,    3,    2,    -2,   -17,  -4,   -2,   9,    0,    6,    3,    0,     32,   15,   -8,   17,    174,   84,    45,    -93,
    11,   56,   0,    0,    -66,  -12,  -6,  35,   47,   8,    4,    -25,  0,    8,    4,    0,    10,   -22,  -12,   -5,   -3,   0,    0,     2,     -24,   12,    0,
    0,    5,    -6,   0,    0,    3,    0,   0,    -2,   4,    3,    1,    -2,   0,    29,   15,   0,    -5,   -4,    -2,   2,    8,    -3,    -1,    -5,    0,     -3,
    0,    0,    10,   0,    0,    0,    3,   0,    0,    -2,   -5,   0,    0,    3,    46,   66,   35,   -25,  -14,   7,    0,    0,    0,     3,     2,     0,     -5,
    0,    0,    0,    -68,  -34,  -18,  36,  0,    14,   7,    0,    10,   -6,   -3,   -5,   -5,   -4,   -2,   3,     -3,   5,    2,    1,     76,    17,    9,     -41,
    84,   298,  159,  -45,  3,    0,    0,   -1,   -3,   0,    0,    2,    -3,   0,    0,    1,    -82,  292,  156,   44,   -73,  17,   9,     39,    -9,    -16,   0,
    0,    3,    0,    -1,   -2,   -3,   0,   0,    0,    -9,   -5,   -3,   5,    -439, 0,    0,    0,    57,   -28,   -15,  -30,  0,    -6,    -3,    0,     -4,    0,
    0,    2,    -40,  57,   30,   21,   23,  7,    3,    -13,  273,  80,   43,   -146, -449, 430,  0,    0,    -8,    -47,  -25,  4,    6,     47,    25,    -3,    0,
    23,   13,   0,    -3,   0,    0,    2,   3,    -4,   -2,   -2,   -48,  -110, -59,  26,   51,   114,  61,   -27,   -133, 0,    0,    57,    0,     4,     0,     0,
    -21,  -6,   -3,   11,   0,    -3,   -1,  0,    -11,  -21,  -11,  6,    -18,  -436, -233, 9,    35,   -7,   0,     0,    0,    5,    3,     0,     11,    -3,    -1,
    -6,   -5,   -3,   -1,   3,    -53,  -9,  -5,   28,   0,    3,    2,    1,    4,    0,    0,    -2,   0,    -4,    0,    0,    -50,  194,   103,   27,    -13,   52,
    28,   7,    -91,  248,  0,    0,    6,   49,   26,   -3,   -6,   -47,  -25,  3,    0,    5,    3,    0,    52,    23,   10,   -23,  -3,    0,     0,     1,     0,
    5,    3,    0,    -4,   0,    0,    0,   -4,   8,    3,    2,    10,   0,    0,    0,    3,    0,    0,    -2,    0,    8,    4,    0,     0,     8,     4,     1,
    -4,   0,    0,    0,    -4,   0,    0,   0,    -8,   4,    2,    4,    8,    -4,   -2,   -4,   0,    15,   7,     0,    -138, 0,    0,     0,     0,     -7,    -3,
    0,    0,    -7,   -3,   0,    54,   0,   0,    -29,  0,    10,   4,    0,    -7,   0,    0,    3,    -37,  35,    19,   20,   0,    4,     0,     0,     -4,    9,
    0,    0,    8,    0,    0,    -4,   -9,  -14,  -8,   5,    -3,   -9,   -5,   3,    -145, 47,   0,    0,    -10,   40,   21,   5,    11,    -49,   -26,   -7,    -2150,
    0,    0,    932,  -12,  0,    0,    5,   85,   0,    0,    -37,  4,    0,    0,    -2,   3,    0,    0,    -2,    -86,  153,  0,    0,     -6,    9,     5,     3,
    9,    -13,  -7,   -5,   -8,   12,   6,   4,    -51,  0,    0,    22,   -11,  -268, -116, 5,    0,    12,   5,     0,    0,    7,    3,     0,     31,    6,     3,
    -17,  140,  27,   14,   -75,  57,   11,  6,    -30,  -14,  -39,  0,    0,    0,    -6,   -2,   0,    4,    15,    8,    -2,   0,    4,     0,     0,     -3,    0,
    0,    1,    0,    11,   5,    0,    9,   6,    0,    0,    -4,   10,   4,    2,    5,    3,    0,    0,    16,    0,    0,    -9,   -3,    0,     0,     0,     0,
    3,    2,    -1,   7,    0,    0,    -3,  -25,  22,   0,    0,    42,   223,  119,  -22,  -27,  -143, -77,  14,    9,    49,   26,   -5,    -1166, 0,     0,     505,
    -5,   0,    0,    2,    -6,   0,    0,   3,    -8,   0,    1,    4,    0,    -4,   0,    0,    117,  0,    0,     -63,  -4,   8,    4,     2,     3,     0,     0,
    -2,   -5,   0,    0,    2,    0,    31,  0,    0,    -5,   0,    1,    3,    4,    0,    0,    -2,   -4,   0,     0,    2,    -24,  -13,   -6,    10,    3,     0,
    0,    0,    0,    -32,  -17,  0,    8,   12,   5,    -3,   3,    0,    0,    -1,   7,    13,   0,    0,    -3,    16,   0,    0,    50,    0,     0,     -27,   0,
    -5,   -3,   0,    13,   0,    0,    0,   0,    5,    3,    1,    24,   5,    2,    -11,  5,    -11,  -5,   -2,    30,   -3,   -2,   -16,   18,    0,     0,     -9,
    8,    614,  0,    0,    3,    -3,   -1,  -2,   6,    17,   9,    -3,   -3,   -9,   -5,   2,    0,    6,    3,     -1,   -127, 21,   9,     55,    3,     5,     0,
    0,    -6,   -10,  -4,   3,    5,    0,   0,    0,    16,   9,    4,    -7,   3,    0,    0,    -2,   0,    22,    0,    0,    0,    19,    10,    0,     7,     0,
    0,    -4,   0,    -5,   -2,   0,    0,   3,    1,    0,    -9,   3,    1,    4,    17,   0,    0,    -7,   0,     -3,   -2,   -1,   -20,   34,    0,     0,     -10,
    0,    1,    5,    -4,   0,    0,    2,   22,   -87,  0,    0,    -4,   0,    0,    2,    -3,   -6,   -2,   1,     -16,  -3,   -1,   7,     0,     -3,    -2,    0,
    4,    0,    0,    0,    -68,  39,   0,   0,    27,   0,    0,    -14,  0,    -4,   0,    0,    -25,  0,    0,     0,    -12,  -3,   -2,    6,     3,     0,     0,
    -1,   3,    66,   29,   -1,   490,  0,   0,    -213, -22,  93,   49,   12,   -7,   28,   15,   4,    -3,   13,    7,    2,    -46,  14,    0,     0,     -5,    0,
    0,    0,    2,    1,    0,    0,    0,   -3,   0,    0,    -28,  0,    0,    15,   5,    0,    0,    -2,   0,     3,    0,    0,    -11,   0,     0,     5,     0,
    3,    1,    0,    -3,   0,    0,    1,   25,   106,  57,   -13,  5,    21,   11,   -3,   1485, 0,    0,    0,     -7,   -32,  -17,  4,     0,     5,     3,     0,
    -6,   -3,   -2,   3,    30,   -6,   -2,  -13,  -4,   4,    0,    0,    -19,  0,    0,    10,   0,    4,    2,     -1,   0,    3,    0,     0,     4,     0,     0,
    -2,   0,    -3,   -1,   0,    -3,   0,   0,    0,    5,    3,    1,    -2,   0,    11,   0,    0,    118,  0,     0,    -52,  0,    -5,    -3,    0,     -28,   36,
    0,    0,    5,    -5,   0,    0,    14,  -59,  -31,  -8,   0,    9,    5,    1,    -458, 0,    0,    198,  0,     -45,  -20,  0,    9,     0,     0,     -5,    0,
    -3,   0,    0,    0,    -4,   -2,   -1,  11,   0,    0,    -6,   6,    0,    0,    -2,   -16,  23,   0,    0,     0,    -4,   -2,   0,     -5,    0,     0,     2,
    -166, 269,  0,    0,    15,   0,    0,   -8,   10,   0,    0,    -4,   -78,  45,   0,    0,    0,    -5,   -2,    0,    7,    0,    0,     -4,    -5,    328,   0,
    0,    3,    0,    0,    -2,   5,    0,   0,    -2,   0,    3,    1,    0,    -3,   0,    0,    0,    -3,   0,     0,    0,    0,    -4,    -2,    0,     -1223, -26,
    0,    0,    0,    7,    3,    0,    3,   0,    0,    0,    0,    3,    2,    0,    -6,   20,   0,    0,    -368,  0,    0,    0,    -75,   0,     0,     0,     11,
    0,    0,    -6,   3,    0,    0,    -2,  -3,   0,    0,    1,    -13,  -30,  0,    0,    21,   3,    0,    0,     -3,   0,    0,    1,     -4,    0,     0,     2,
    8,    -27,  0,    0,    -19,  -11,  0,   0,    -4,   0,    0,    2,    0,    5,    2,    0,    -6,   0,    0,     2,    -8,   0,    0,     0,     -1,    0,     0,
    0,    -14,  0,    0,    6,    6,    0,   0,    0,    -74,  0,    0,    32,   0,    -3,   -1,   0,    4,    0,     0,    -2,   8,    11,    0,     0,     0,     3,
    2,    0,    -262, 0,    0,    114,  0,   -4,   0,    0,    -7,   0,    0,    4,    0,    -27,  -12,  0,    -19,   -8,   -4,   8,    202,   0,     0,     -87,   -8,
    35,   19,   5,    0,    4,    2,    0,   16,   -5,   0,    0,    5,    0,    0,    -3,   0,    -3,   0,    0,     1,    0,    0,    0,     -35,   -48,   -21,   15,
    -3,   -5,   -2,   1,    6,    0,    0,   -3,   3,    0,    0,    -1,   0,    -5,   0,    0,    12,   55,   29,    -6,   0,    5,    3,     0,     -598,  0,     0,
    0,    -3,   -13,  -7,   1,    -5,   -7,  -3,   2,    3,    0,    0,    -1,   5,    -7,   0,    0,    4,    0,     0,    -2,   16,   -6,    0,     0,     8,     -3,
    0,    0,    8,    -31,  -16,  -4,   0,   3,    1,    0,    113,  0,    0,    -49,  0,    -24,  -10,  0,    4,     0,    0,    -2,   27,    0,     0,     0,     -3,
    0,    0,    1,    0,    -4,   -2,   0,   5,    0,    0,    -2,   0,    -3,   0,    0,    -13,  0,    0,    6,     5,    0,    0,    -2,    -18,   -10,   -4,    8,
    -4,   -28,  0,    0,    -5,   6,    3,   2,    -3,   0,    0,    1,    -5,   -9,   -4,   2,    17,   0,    0,     -7,   11,   4,    0,     0,     0,     -6,    -2,
    0,    83,   15,   0,    0,    -4,   0,   0,    2,    0,    -114, -49,  0,    117,  0,    0,    -51,  -5,   19,    10,   2,    -3,   0,     0,     0,     -3,    0,
    0,    2,    0,    -3,   -1,   0,    3,   0,    0,    0,    0,    -6,   -2,   0,    393,  3,    0,    0,    -4,    21,   11,   2,    -6,    0,     -1,    3,     -3,
    8,    4,    1,    8,    0,    0,    0,   18,   -29,  -13,  -8,   8,    34,   18,   -4,   89,   0,    0,    0,     3,    12,   6,    -1,    54,    -15,   -7,    -24,
    0,    3,    0,    0,    3,    0,    0,   -1,   0,    35,   0,    0,    -154, -30,  -13,  67,   15,   0,    0,     0,    0,    4,    2,     0,     0,     9,     0,
    0,    80,   -71,  -31,  -35,  0,    -20, -9,   0,    11,   5,    2,    -5,   61,   -96,  -42,  -27,  14,   9,     4,    -6,   -11,  -6,    -3,    5,     0,     -3,
    -1,   0,    123,  -415, -180, -53,  0,   0,    0,    -35,  -5,   0,    0,    0,    7,    -32,  -17,  -4,   0,     -9,   -5,   0,    0,     -4,    2,     0,     -89,
    0,    0,    38,   0,    -86,  -19,  -6,  0,    0,    -19,  6,    -123, -416, -180, 53,   0,    -3,   -1,   0,     12,   -6,   -3,   -5,    -13,   9,     4,     6,
    0,    -15,  -7,   0,    3,    0,    0,   -1,   -62,  -97,  -42,  27,   -11,  5,    2,    5,    0,    -19,  -8,    0,    -3,   0,    0,     1,     0,     4,     2,
    0,    0,    3,    0,    0,    0,    4,   2,    0,    -85,  -70,  -31,  37,   163,  -12,  -5,   -72,  -63,  -16,   -7,   28,   -21,  -32,   -14,   9,     0,     -3,
    -1,   0,    3,    0,    0,    -2,   0,   8,    0,    0,    3,    10,   4,    -1,   3,    0,    0,    -1,   0,     -7,   -3,   0,    0,     -4,    -2,    0,     6,
    19,   0,    0,    5,    -173, -75,  -2,  0,    -7,   -3,   0,    7,    -12,  -5,   -3,   -3,   0,    0,    2,     3,    -4,   -2,   -1,    74,    0,     0,     -32,
    -3,   12,   6,    2,    26,   -14,  -6,  -11,  19,   0,    0,    -8,   6,    24,   13,   -3,   83,   0,    0,     0,    0,    -10,  -5,    0,     11,    -3,    -1,
    -5,   3,    0,    1,    -1,   3,    0,   0,    -1,   -4,   0,    0,    0,    5,    -23,  -12,  -3,   -339, 0,     0,    147,  0,    -10,   -5,    0,     5,     0,
    0,    0,    3,    0,    0,    -1,   0,   -4,   -2,   0,    18,   -3,   0,    0,    9,    -11,  -5,   -4,   -8,    0,    0,    4,    3,     0,     0,     -1,    0,
    9,    0,    0,    6,    -9,   -4,   -2,  -4,   -12,  0,    0,    67,   -91,  -39,  -29,  30,   -18,  -8,   -13,   0,    0,    0,    0,     0,     -114,  -50,   0,
    0,    0,    0,    23,   517,  16,   7,   -224, 0,    -7,   -3,   0,    143,  -3,   -1,   -62,  29,   0,    0,     -13,  -4,   0,    0,     2,     -6,    0,     0,
    3,    5,    12,   5,    -2,   -25,  0,   0,    11,   -3,   0,    0,    1,    0,    4,    2,    0,    -22,  12,    5,    10,   50,   0,     0,     -22,   0,     7,
    4,    0,    0,    3,    1,    0,    -4,  4,    2,    2,    -5,   -11,  -5,   2,    0,    4,    2,    0,    4,     17,   9,    -2,   59,    0,     0,     0,     0,
    -4,   -2,   0,    -8,   0,    0,    4,   -3,   0,    0,    0,    4,    -15,  -8,   -2,   370,  -8,   0,    -160,  0,    0,    -3,   0,     0,     3,     1,     0,
    -6,   3,    1,    3,    0,    6,    0,   0,    -10,  0,    0,    4,    0,    9,    4,    0,    4,    17,   7,     -2,   34,   0,    0,     -15,   0,     5,     3,
    0,    -5,   0,    0,    2,    -37,  -7,  -3,   16,   3,    13,   7,    -2,   40,   0,    0,    0,    0,    -3,    -2,   0,    -184, -3,    -1,    80,    -3,    0,
    0,    1,    -3,   0,    0,    0,    0,   -10,  -6,   -1,   31,   -6,   0,    -13,  -3,   -32,  -14,  1,    -7,    0,    0,    3,    0,     -8,    -4,    0,     3,
    -4,   0,    0,    0,    4,    0,    0,   0,    3,    1,    0,    19,   -23,  -10,  2,    0,    0,    0,    -10,   0,    3,    2,    0,     0,     9,     5,     -1,
    28,   0,    0,    0,    0,    -7,   -4,  0,    8,    -4,   0,    -4,   0,    0,    -2,   0,    0,    3,    0,     0,    -3,   0,    0,     1,     -9,    0,     1,
    4,    3,    12,   5,    -1,   17,   -3,  -1,   0,    0,    7,    4,    0,    19,   0,    0,    0,    0,    -5,    -3,   0,    14,   -3,    0,     -1,    0,     0,
    -1,   0,    0,    0,    0,    -5,   0,   5,    3,    0,    13,   0,    0,    0,    0,    -3,   -2,   0,    2,     9,    4,    3,    0,     0,     0,     -4,    8,
    0,    0,    0,    0,    4,    2,    0,   6,    0,    0,    -3,   6,    0,    0,    0,    0,    3,    1,    0,     5,    0,    0,    -2,    3,     0,     0,     -1,
    -3,   0,    0,    0,    6,    0,    0,   0,    7,    0,    0,    0,    -4,   0,    0,    0,    4,    0,    0,     0,    6,    0,    0,     0,     0,     -4,    0,
    0,    0,    -4,   0,    0,    5,    0,   0,    0,    -3,   0,    0,    0,    4,    0,    0,    0,    -5,   0,     0,    0,    4,    0,     0,     0,     0,     3,
    0,    0,    13,   0,    0,    0,    21,  11,   0,    0,    0,    -5,   0,    0,    0,    -5,   -2,   0,    0,     5,    3,    0,    0,     -5,    0,     0,     -3,
    0,    0,    2,    20,   10,   0,    0,   -34,  0,    0,    0,    -19,  0,    0,    0,    3,    0,    0,    -2,    -3,   0,    0,    1,     -6,    0,     0,     3,
    -4,   0,    0,    0,    3,    0,    0,   0,    3,    0,    0,    0,    4,    0,    0,    0,    3,    0,    0,     -1,   6,    0,    0,     -3,    -8,    0,     0,
    3,    0,    3,    1,    0,    -3,   0,   0,    0,    0,    -3,   -2,   0,    126,  -63,  -27,  -55,  -5,   0,     1,    2,    -3,   28,    15,    2,     5,     0,
    1,    -2,   0,    9,    4,    1,    0,   9,    4,    -1,   -126, -63,  -27,  55,   3,    0,    0,    -1,   21,    -11,  -6,   -11,  0,     -4,    0,     0,     -21,
    -11,  -6,   11,   -3,   0,    0,    1,   0,    3,    1,    0,    8,    0,    0,    -4,   -6,   0,    0,    3,     -3,   0,    0,    1,     3,     0,     0,     -1,
    -3,   0,    0,    1,    -5,   0,    0,   2,    24,   -12,  -5,   -11,  0,    3,    1,    0,    0,    3,    1,     0,    0,    3,    2,     0,     -24,   -12,   -5,
    10,   4,    0,    -1,   -2,   13,   0,   0,    -6,   7,    0,    0,    -3,   3,    0,    0,    -1,   3,    0,     0,    -1,
};

const stcf = [66]f64{
    2640.96, -0.39, 63.52, -0.02, 11.75, 0.01, 11.21, 0.01, -4.55, 0.0, 2.02, 0.0, 1.98,  0.0, -1.72, 0.0,
    -1.41,   -0.01, -1.26, -0.01, -0.63, 0.0,  -0.63, 0.0,  0.46,  0.0, 0.45, 0.0, 0.36,  0.0, -0.24, -0.12,
    0.32,    0.0,   0.28,  0.0,   0.27,  0.0,  0.26,  0.0,  -0.21, 0.0, 0.19, 0.0, 0.18,  0.0, -0.1,  0.05,
    0.15,    0.0,   -0.14, 0.0,   0.14,  0.0,  -0.14, 0.0,  0.14,  0.0, 0.13, 0.0, -0.11, 0.0, 0.11,  0.0,
    0.11,    0.0,
};

const stfarg = [462]i32{
    0, 0, 0,  0,  1,  0, 0,  0,  0, 0, 0,  0,  0, 0, 0,   0, 0,  0,  2,  0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 0, 2,  -2, 3,  0, 0,
    0, 0, 0,  0,  0,  0, 0,  0,  0, 2, -2, 1,  0, 0, 0,   0, 0,  0,  0,  0, 0,  0, 0, 2, -2, 2,  0, 0, 0, 0, 0,  0,  0,  0, 0,
    0, 0, 2,  0,  3,  0, 0,  0,  0, 0, 0,  0,  0, 0, 0,   0, 2,  0,  1,  0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 0, 0,  0,  3,  0, 0,
    0, 0, 0,  0,  0,  0, 0,  0,  1, 0, 0,  1,  0, 0, 0,   0, 0,  0,  0,  0, 0,  0, 1, 0, 0,  -1, 0, 0, 0, 0, 0,  0,  0,  0, 0,
    1, 0, 0,  0,  -1, 0, 0,  0,  0, 0, 0,  0,  0, 0, 1,   0, 0,  0,  1,  0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 1, 2,  -2, 3,  0, 0,
    0, 0, 0,  0,  0,  0, 0,  0,  1, 2, -2, 1,  0, 0, 0,   0, 0,  0,  0,  0, 0,  0, 0, 4, -4, 4,  0, 0, 0, 0, 0,  0,  0,  0, 0,
    0, 0, 1,  -1, 1,  0, -8, 12, 0, 0, 0,  0,  0, 0, 0,   0, 2,  0,  0,  0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 0, 2,  0,  2,  0, 0,
    0, 0, 0,  0,  0,  0, 0,  1,  0, 2, 0,  3,  0, 0, 0,   0, 0,  0,  0,  0, 0,  1, 0, 2, 0,  1,  0, 0, 0, 0, 0,  0,  0,  0, 0,
    0, 0, 2,  -2, 0,  0, 0,  0,  0, 0, 0,  0,  0, 0, 0,   1, -2, 2,  -3, 0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 1, -2, 2,  -1, 0, 0,
    0, 0, 0,  0,  0,  0, 0,  0,  0, 0, 0,  0,  0, 8, -13, 0, 0,  0,  0,  0, -1, 0, 0, 0, 2,  0,  0, 0, 0, 0, 0,  0,  0,  0, 0,
    2, 0, -2, 0,  -1, 0, 0,  0,  0, 0, 0,  0,  0, 0, 1,   0, 0,  -2, 1,  0, 0,  0, 0, 0, 0,  0,  0, 0, 0, 1, 2,  -2, 2,  0, 0,
    0, 0, 0,  0,  0,  0, 0,  1,  0, 0, -2, -1, 0, 0, 0,   0, 0,  0,  0,  0, 0,  0, 0, 4, -2, 4,  0, 0, 0, 0, 0,  0,  0,  0, 0,
    0, 0, 2,  -2, 4,  0, 0,  0,  0, 0, 0,  0,  0, 0, 1,   0, -2, 0,  -3, 0, 0,  0, 0, 0, 0,  0,  0, 0, 1, 0, -2, 0,  -1, 0, 0,
    0, 0, 0,  0,  0,  0, 0,
};

const dcor_ra_jpl = [51]f64{
    -51.257, -51.103, -51.065, -51.503, -51.224, -50.796, -51.161, -51.181, -50.932, -51.064, -51.182,
    -51.386, -51.416, -51.428, -51.586, -51.766, -52.038, -52.37,  -52.553, -52.397, -52.34,  -52.676,
    -52.348, -51.964, -52.444, -52.364, -51.988, -52.212, -52.37,  -52.523, -52.541, -52.496, -52.59,
    -52.629, -52.788, -53.014, -53.053, -52.902, -52.85,  -53.087, -52.635, -52.185, -52.588, -52.292,
    -51.796, -51.961, -52.055, -52.134, -52.165, -52.141, -52.255,
};

// ---------------------------------------------------------------------------

// IAU 1980 nutation series (swephlib.c nt[]); 112 rows x 9 shorts.
// Row layout: MM, MS, FF, DD, OM, LS, LS2, OC, OC2 (units 0.0001"/0.00001");
// rows with first value >= 100 are Herring (1987) correction rows.
const ENDMARK: i16 = -99;

pub fn swe_radnorm(x: f64) f64 {
    var y = swe_shim_fmod(x, TWOPI);
    if (@abs(y) < 1e-13) y = 0.0; // Alois fix 11-dec-1999
    if (y < 0.0) y += TWOPI;
    return y;
}

pub fn swe_deg_midp(x1: f64, x0: f64) f64 {
    const d = swe_difdeg2n(x1, x0); // arc from x0 to x1
    return swe_degnorm(x0 + d / 2);
}

pub fn swe_rad_midp(x1: f64, x0: f64) f64 {
    return DEGTORAD * swe_deg_midp(x1 * RADTODEG, x0 * RADTODEG);
}

pub fn swi_angnorm(x: f64) f64 {
    if (x < 0.0)
        return x + TWOPI;
    if (x >= TWOPI)
        return x - TWOPI;
    return x;
}

pub fn swi_echeb(x: f64, coef: []const f64) f64 {
    const x2 = x * 2.0;
    var br: f64 = 0.0;
    var brp2: f64 = 0.0; // dummy assign to silence gcc warning
    var brpp: f64 = 0.0;
    var j: usize = coef.len;
    while (j > 0) {
        j -= 1;
        brp2 = brpp;
        brpp = br;
        br = x2 * brpp - brp2 + coef[j];
    }
    return (br - brp2) * 0.5;
}

pub fn swi_edcheb(x: f64, coef: []const f64) f64 {
    const x2 = x * 2.0;
    var bf: f64 = 0.0;
    var bj: f64 = 0.0;
    var xjp2: f64 = 0.0;
    var xjpl: f64 = 0.0;
    var bjp2: f64 = 0.0;
    var bjpl: f64 = 0.0;
    var j: usize = coef.len;
    while (j > 1) {
        j -= 1;
        const dj: f64 = @floatFromInt(j + j);
        const xj = coef[j] * dj + xjp2;
        bj = x2 * bjpl - bjp2 + xj;
        bf = bjp2;
        bjp2 = bjpl;
        bjpl = bj;
        xjp2 = xjpl;
        xjpl = xj;
    }
    return (bj - bf) * 0.5;
}

pub fn swi_dot_prod_unit(x: *const [3]f64, y: *const [3]f64) f64 {
    var dop = x[0] * y[0] + x[1] * y[1] + x[2] * y[2];
    const e1 = std.math.sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2]);
    const e2 = std.math.sqrt(y[0] * y[0] + y[1] * y[1] + y[2] * y[2]);
    dop /= e1;
    dop /= e2;
    if (dop > 1)
        dop = 1;
    if (dop < -1)
        dop = -1;
    return dop;
}

/// Nutation IAU 1980 model (swephlib.c calc_nutation_iau1980)
fn calc_nutation_iau1980(J: f64, nutlo: *[2]f64, models: AstroModels) i32 {
    // arrays to hold sines and cosines of multiple angles
    var ss: [5][8]f64 = undefined;
    var cc: [5][8]f64 = undefined;
    var nut_model = models.nut;
    if (nut_model == 0) nut_model = SEMOD_NUT_DEFAULT;
    // Julian centuries from 2000 January 1.5, barycentric dynamical time
    const T = (J - 2451545.0) / 36525.0;
    const T2 = T * T;
    // Fundamental arguments in the FK5 reference system (in degrees)
    var OM = -6962890.539 * T + 450160.280 + (0.008 * T + 7.455) * T2;
    OM = swe_degnorm(OM / 3600) * DEGTORAD;
    var MS = 129596581.224 * T + 1287099.804 - (0.012 * T + 0.577) * T2;
    MS = swe_degnorm(MS / 3600) * DEGTORAD;
    var MM = 1717915922.633 * T + 485866.733 + (0.064 * T + 31.310) * T2;
    MM = swe_degnorm(MM / 3600) * DEGTORAD;
    var FF = 1739527263.137 * T + 335778.877 + (0.011 * T - 13.257) * T2;
    FF = swe_degnorm(FF / 3600) * DEGTORAD;
    var DD = 1602961601.328 * T + 1072261.307 + (0.019 * T - 6.891) * T2;
    DD = swe_degnorm(DD / 3600) * DEGTORAD;
    const args = [5]f64{ MM, MS, FF, DD, OM };
    const ns = [5]usize{ 3, 2, 4, 4, 2 };
    // Calculate sin( i*MM ), etc. for needed multiple angles
    var k: usize = 0;
    while (k <= 4) : (k += 1) {
        const arg = args[k];
        const n = ns[k];
        const su = swe_shim_sin(arg);
        const cu = swe_shim_cos(arg);
        ss[k][0] = su;
        cc[k][0] = cu;
        var sv = 2.0 * su * cu;
        var cv = cu * cu - su * su;
        ss[k][1] = sv;
        cc[k][1] = cv;
        var i: usize = 2;
        while (i < n) : (i += 1) {
            const s = su * cv + cu * sv;
            cv = cu * cv - su * sv;
            sv = s;
            ss[k][i] = sv;
            cc[k][i] = cv;
        }
    }
    // first terms, not in table:
    var C = (-0.01742 * T - 17.1996) * ss[4][0]; // sin(OM)
    var D = (0.00089 * T + 9.2025) * cc[4][0]; // cos(OM)
    // walk the series table, 9 shorts per row
    var row: usize = 0;
    while (row < nt.len / 9) : (row += 1) {
        const p0 = nt[row * 9 + 0];
        if (p0 == ENDMARK)
            break;
        if (nut_model != SEMOD_NUT_IAU_CORR_1987 and (p0 == 101 or p0 == 102))
            continue;
        // argument of sine and cosine
        var k1: i32 = 0;
        var cv: f64 = 0.0;
        var sv: f64 = 0.0;
        var m: usize = 0;
        while (m < 5) : (m += 1) {
            var j: i32 = nt[row * 9 + m];
            if (j > 100)
                j = 0; // p[0] is a flag
            if (j != 0) {
                var kk = j;
                if (j < 0)
                    kk = -kk;
                var su = ss[m][@intCast(kk - 1)]; // sin(k*angle)
                if (j < 0)
                    su = -su;
                const cu = cc[m][@intCast(kk - 1)];
                if (k1 == 0) { // set first angle
                    sv = su;
                    cv = cu;
                    k1 = 1;
                } else { // combine angles
                    const sw = su * cv + cu * sv;
                    cv = cu * cv - su * sv;
                    sv = sw;
                }
            }
        }
        // longitude coefficient, in 0.0001"
        var f: f64 = @as(f64, @floatFromInt(nt[row * 9 + 5])) * 0.0001;
        if (nt[row * 9 + 6] != 0)
            f += 0.00001 * T * @as(f64, @floatFromInt(nt[row * 9 + 6]));
        // obliquity coefficient, in 0.0001"
        var g: f64 = @as(f64, @floatFromInt(nt[row * 9 + 7])) * 0.0001;
        if (nt[row * 9 + 8] != 0)
            g += 0.00001 * T * @as(f64, @floatFromInt(nt[row * 9 + 8]));
        if (p0 >= 100) { // coefficients in 0.00001"
            f *= 0.1;
            g *= 0.1;
        }
        // accumulate the terms
        if (p0 != 102) {
            C += f * sv;
            D += g * cv;
        } else { // cos for nutl and sin for nuto
            C += f * cv;
            D += g * sv;
        }
    }
    // Save answers, expressed in radians
    nutlo[0] = DEGTORAD * C / 3600.0;
    nutlo[1] = DEGTORAD * D / 3600.0;
    return 0;
}

/// Nutation IAU 2000A model (MHB2000, without free core nutation)
/// (swephlib.c calc_nutation_iau2000ab)
fn calc_nutation_iau2000ab(J: f64, nutlo: *[2]f64, models: AstroModels) i32 {
    var dpsi: f64 = 0;
    var deps: f64 = 0;
    const T = (J - J2000) / 36525.0;
    var nut_model = models.nut;
    if (nut_model == 0) nut_model = SEMOD_NUT_DEFAULT;
    // luni-solar nutation; fundamental arguments, Simon et al. (1994)
    const M = swe_degnorm((485868.249036 +
        T * (1717915923.2178 +
            T * (31.8792 +
                T * (0.051635 +
                    T * (-0.00024470))))) / 3600.0) * DEGTORAD;
    const SM = swe_degnorm((1287104.79305 +
        T * (129596581.0481 +
            T * (-0.5532 +
                T * (0.000136 +
                    T * (-0.00001149))))) / 3600.0) * DEGTORAD;
    const F = swe_degnorm((335779.526232 +
        T * (1739527262.8478 +
            T * (-12.7512 +
                T * (-0.001037 +
                    T * (0.00000417))))) / 3600.0) * DEGTORAD;
    const D = swe_degnorm((1072260.70369 +
        T * (1602961601.2090 +
            T * (-6.3706 +
                T * (0.006593 +
                    T * (-0.00003169))))) / 3600.0) * DEGTORAD;
    const OM = swe_degnorm((450160.398036 +
        T * (-6962890.5431 +
            T * (7.4722 +
                T * (0.007702 +
                    T * (-0.00005939))))) / 3600.0) * DEGTORAD;
    // luni-solar nutation series, in reverse order, starting with small terms
    const inls: usize = if (nut_model == SEMOD_NUT_IAU_2000B) NLS_2000B else NLS;
    var i: usize = inls;
    while (i > 0) {
        i -= 1;
        const j = i * 5;
        const darg = swe_radnorm(@as(f64, @floatFromInt(nls[j + 0])) * M +
            @as(f64, @floatFromInt(nls[j + 1])) * SM +
            @as(f64, @floatFromInt(nls[j + 2])) * F +
            @as(f64, @floatFromInt(nls[j + 3])) * D +
            @as(f64, @floatFromInt(nls[j + 4])) * OM);
        const sinarg = swe_shim_sin(darg);
        const cosarg = swe_shim_cos(darg);
        const k = i * 6;
        dpsi += (@as(f64, @floatFromInt(cls[k + 0])) + @as(f64, @floatFromInt(cls[k + 1])) * T) * sinarg + @as(f64, @floatFromInt(cls[k + 2])) * cosarg;
        deps += (@as(f64, @floatFromInt(cls[k + 3])) + @as(f64, @floatFromInt(cls[k + 4])) * T) * cosarg + @as(f64, @floatFromInt(cls[k + 5])) * sinarg;
    }
    nutlo[0] = dpsi * O1MAS2DEG;
    nutlo[1] = deps * O1MAS2DEG;
    if (nut_model == SEMOD_NUT_IAU_2000A) {
        // planetary nutation (MHB2000; different Delaunay arguments than
        // the luni-solar case, faithfully reproduced)
        const AL = swe_radnorm(2.35555598 + 8328.6914269554 * T);
        const ALSU = swe_radnorm(6.24006013 + 628.301955 * T);
        const AF = swe_radnorm(1.627905234 + 8433.466158131 * T);
        const AD = swe_radnorm(5.198466741 + 7771.3771468121 * T);
        const AOM = swe_radnorm(2.18243920 - 33.757045 * T);
        const ALME = swe_radnorm(4.402608842 + 2608.7903141574 * T);
        const ALVE = swe_radnorm(3.176146697 + 1021.3285546211 * T);
        const ALEA = swe_radnorm(1.753470314 + 628.3075849991 * T);
        const ALMA = swe_radnorm(6.203480913 + 334.0612426700 * T);
        const ALJU = swe_radnorm(0.599546497 + 52.9690962641 * T);
        const ALSA = swe_radnorm(0.874016757 + 21.3299104960 * T);
        const ALUR = swe_radnorm(5.481293871 + 7.4781598567 * T);
        const ALNE = swe_radnorm(5.321159000 + 3.8127774000 * T);
        // General accumulated precession in longitude.
        const APA = (0.02438175 + 0.00000538691 * T) * T;
        // planetary nutation series (in reverse order)
        dpsi = 0;
        deps = 0;
        i = NPL;
        while (i > 0) {
            i -= 1;
            const j = i * 14;
            const darg = swe_radnorm(@as(f64, @floatFromInt(npl[j + 0])) * AL +
                @as(f64, @floatFromInt(npl[j + 1])) * ALSU +
                @as(f64, @floatFromInt(npl[j + 2])) * AF +
                @as(f64, @floatFromInt(npl[j + 3])) * AD +
                @as(f64, @floatFromInt(npl[j + 4])) * AOM +
                @as(f64, @floatFromInt(npl[j + 5])) * ALME +
                @as(f64, @floatFromInt(npl[j + 6])) * ALVE +
                @as(f64, @floatFromInt(npl[j + 7])) * ALEA +
                @as(f64, @floatFromInt(npl[j + 8])) * ALMA +
                @as(f64, @floatFromInt(npl[j + 9])) * ALJU +
                @as(f64, @floatFromInt(npl[j + 10])) * ALSA +
                @as(f64, @floatFromInt(npl[j + 11])) * ALUR +
                @as(f64, @floatFromInt(npl[j + 12])) * ALNE +
                @as(f64, @floatFromInt(npl[j + 13])) * APA);
            const k = i * 4;
            const sinarg = swe_shim_sin(darg);
            const cosarg = swe_shim_cos(darg);
            dpsi += @as(f64, @floatFromInt(icpl[k + 0])) * sinarg + @as(f64, @floatFromInt(icpl[k + 1])) * cosarg;
            deps += @as(f64, @floatFromInt(icpl[k + 2])) * sinarg + @as(f64, @floatFromInt(icpl[k + 3])) * cosarg;
        }
        nutlo[0] += dpsi * O1MAS2DEG;
        nutlo[1] += deps * O1MAS2DEG;
        // changes required by adoption of P03 precession
        // (Capitaine et al. A & A 412, 366 (2005) = IAU 2006)
        dpsi = -8.1 * swe_shim_sin(OM) - 0.6 * swe_shim_sin(2 * F - 2 * D + 2 * OM);
        dpsi += T * (47.8 * swe_shim_sin(OM) + 3.7 * swe_shim_sin(2 * F - 2 * D + 2 * OM) + 0.6 * swe_shim_sin(2 * F + 2 * OM) - 0.6 * swe_shim_sin(2 * OM));
        deps = T * (-25.6 * swe_shim_cos(OM) - 1.6 * swe_shim_cos(2 * F - 2 * D + 2 * OM));
        nutlo[0] += dpsi / (3600.0 * 1000000.0);
        nutlo[1] += deps / (3600.0 * 1000000.0);
    }
    nutlo[0] *= DEGTORAD;
    nutlo[1] *= DEGTORAD;
    return 0;
}

/// an incomplete implementation of nutation Woolard 1953
/// (swephlib.c calc_nutation_woolard)
fn calc_nutation_woolard(J: f64, nutlo: *[2]f64) i32 {
    const mjd = J - J1900;
    const t = mjd / 36525.0;
    const t2 = t * t;
    var a = 100.0021358 * t;
    var b = 360.0 * (a - @trunc(a));
    const ls = 279.697 + 0.000303 * t2 + b;
    a = 1336.855231 * t;
    b = 360.0 * (a - @trunc(a));
    const ld = 270.434 - 0.001133 * t2 + b;
    a = 99.99736056000026 * t;
    b = 360.0 * (a - @trunc(a));
    var ms = 358.476 - 0.00015 * t2 + b;
    a = 13255523.59 * t;
    b = 360.0 * (a - @trunc(a));
    var md = 296.105 + 0.009192 * t2 + b;
    a = 5.372616667 * t;
    b = 360.0 * (a - @trunc(a));
    var nm = 259.183 + 0.002078 * t2 - b;
    // convert to radian forms for use with trig functions.
    const tls = 2 * ls * DEGTORAD;
    nm = nm * DEGTORAD;
    const tnm = 2 * nm;
    ms = ms * DEGTORAD;
    const tld = 2 * ld * DEGTORAD;
    md = md * DEGTORAD;
    // find delta psi and eps, in arcseconds.
    var dpsi = (-17.2327 - 0.01737 * t) * swe_shim_sin(nm) + (-1.2729 - 0.00013 * t) * swe_shim_sin(tls) + 0.2088 * swe_shim_sin(tnm) - 0.2037 * swe_shim_sin(tld) + (0.1261 - 0.00031 * t) * swe_shim_sin(ms) + 0.0675 * swe_shim_sin(md) - (0.0497 - 0.00012 * t) * swe_shim_sin(tls + ms) - 0.0342 * swe_shim_sin(tld - nm) - 0.0261 * swe_shim_sin(tld + md) + 0.0214 * swe_shim_sin(tls - ms) - 0.0149 * swe_shim_sin(tls - tld + md) + 0.0124 * swe_shim_sin(tls - nm) + 0.0114 * swe_shim_sin(tld - md);
    var deps = (9.21 + 0.00091 * t) * swe_shim_cos(nm) + (0.5522 - 0.00029 * t) * swe_shim_cos(tls) - 0.0904 * swe_shim_cos(tnm) + 0.0884 * swe_shim_cos(tld) + 0.0216 * swe_shim_cos(tls + ms) + 0.0183 * swe_shim_cos(tld - nm) + 0.0113 * swe_shim_cos(tld + md) - 0.0093 * swe_shim_cos(tls - ms) - 0.0066 * swe_shim_cos(tls - nm);
    // convert to radians.
    dpsi = dpsi / 3600.0 * DEGTORAD;
    deps = deps / 3600.0 * DEGTORAD;
    nutlo[1] = deps;
    nutlo[0] = dpsi;
    return OK;
}

/// Bessel's interpolation formula (swephlib.c bessel); the EOP arrays
/// this interpolates are threaded explicitly.
pub fn bessel(v: []const f64, t: f64) f64 {
    const n: i32 = @intCast(v.len);
    var ans: f64 = undefined;
    if (t <= 0) {
        return v[0];
    }
    if (t >= @as(f64, @floatFromInt(n - 1))) {
        return v[@intCast(n - 1)];
    }
    const p0 = std.math.floor(t);
    const iy: i32 = @intFromFloat(t);
    // Zeroth order estimate is value at start of year
    ans = v[@intCast(iy)];
    var k: i32 = iy + 1;
    if (k >= n)
        return ans;
    // The fraction of tabulation interval
    const p = t - p0;
    ans += p * (v[@intCast(k)] - v[@intCast(iy)]);
    if ((iy - 1 < 0) or (iy + 2 >= n))
        return ans; // can't do second differences
    // Make table of first differences
    var d: [5]f64 = undefined;
    k = iy - 2;
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        if ((k < 0) or (k + 1 >= n))
            d[@intCast(i)] = 0
        else
            d[@intCast(i)] = v[@intCast(k + 1)] - v[@intCast(k)];
        k += 1;
    }
    // Compute second differences
    i = 0;
    while (i < 4) : (i += 1)
        d[@intCast(i)] = d[@intCast(i + 1)] - d[@intCast(i)];
    var B = 0.25 * p * (p - 1.0);
    ans += B * (d[1] + d[2]);
    if (iy + 2 >= n)
        return ans;
    // Compute third differences
    i = 0;
    while (i < 3) : (i += 1)
        d[@intCast(i)] = d[@intCast(i + 1)] - d[@intCast(i)];
    B = 2.0 * B / 3.0;
    ans += (p - 0.5) * B * d[1];
    if ((iy - 2 < 0) or (iy + 3 > n))
        return ans;
    // Compute fourth differences
    i = 0;
    while (i < 2) : (i += 1)
        d[@intCast(i)] = d[@intCast(i + 1)] - d[@intCast(i)];
    B = 0.125 * B * (p + 1.0) * (p - 2.0);
    ans += B * (d[0] + d[1]);
    return ans;
}

/// nutation dispatcher (swephlib.c calc_nutation); EOP corrections are
/// not part of this port yet (no eop.txt machinery) — the SEFLG_JPLHOR
/// branch applies only the constant IAU1980_TJD0 offsets, matching the
/// library behaviour with no EOP file loaded.
fn calc_nutation(J: f64, iflag: i32, nutlo: *[2]f64, models: AstroModels) i32 {
    var nut_model = models.nut;
    var jplhora_model = models.jplhora;
    var is_jplhor = false;
    if (nut_model == 0) nut_model = SEMOD_NUT_DEFAULT;
    if (jplhora_model == 0) jplhora_model = SEMOD_JPLHORA_DEFAULT;
    if ((iflag & SEFLG_JPLHOR) != 0)
        is_jplhor = true;
    if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and
        jplhora_model == SEMOD_JPLHORA_3 and
        J <= HORIZONS_TJD0_DPSI_DEPS_IAU1980)
        is_jplhor = true;
    if (is_jplhor) {
        _ = calc_nutation_iau1980(J, nutlo, models);
        if ((iflag & SEFLG_JPLHOR) != 0) {
            // EOP corrections require eop.txt (loaded with a JPL file);
            // not ported yet — see plan.
            unreachable;
        } else {
            nutlo[0] += DPSI_IAU1980_TJD0 / 3600.0 * DEGTORAD;
            nutlo[1] += DEPS_IAU1980_TJD0 / 3600.0 * DEGTORAD;
        }
    } else if (nut_model == SEMOD_NUT_IAU_1980 or nut_model == SEMOD_NUT_IAU_CORR_1987) {
        _ = calc_nutation_iau1980(J, nutlo, models);
    } else if (nut_model == SEMOD_NUT_IAU_2000A or nut_model == SEMOD_NUT_IAU_2000B) {
        _ = calc_nutation_iau2000ab(J, nutlo, models);
        if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and jplhora_model == SEMOD_JPLHORA_2) {
            // f64-typed sequential ops: C folds these in double semantics
            nutlo[0] += @as(f64, -41.7750) / 3600.0 / 1000.0 * DEGTORAD;
            nutlo[1] += @as(f64, -6.8192) / 3600.0 / 1000.0 * DEGTORAD;
        }
    } else if (nut_model == SEMOD_NUT_WOOLARD) {
        _ = calc_nutation_woolard(J, nutlo);
    }
    return OK;
}

fn quadratic_intp(ym: f64, y0: f64, yp: f64, x: f64) f64 {
    const c = y0;
    const b = (yp - ym) / 2.0;
    const a = (yp + ym) / 2.0 - c;
    return a * x * x + b * x + c;
}

/// struct interpol (sweph.h): nutation interpolation state
pub const Interp = struct {
    tjd_nut0: f64 = 0,
    tjd_nut2: f64 = 0,
    nut_dpsi0: f64 = 0,
    nut_dpsi1: f64 = 0,
    nut_dpsi2: f64 = 0,
    nut_deps0: f64 = 0,
    nut_deps1: f64 = 0,
    nut_deps2: f64 = 0,
};

/// Nutation in longitude and obliquity, in radians (swephlib.c swi_nutation).
/// interp == null mirrors swed.do_interpolate_nut == FALSE.
pub fn swi_nutation(tjd: f64, iflag: i32, nutlo: *[2]f64, models: AstroModels, interp: ?*Interp) i32 {
    if (interp == null) {
        return calc_nutation(tjd, iflag, nutlo, models);
    }
    // from interpolation, with three data points in 1-day steps;
    // maximum error is about 3 mas
    const ip = interp.?;
    if (tjd < ip.tjd_nut2 and tjd > ip.tjd_nut0) {
        // precalculated data points available
        const dx = (tjd - ip.tjd_nut0) - 1.0;
        nutlo[0] = quadratic_intp(ip.nut_dpsi0, ip.nut_dpsi1, ip.nut_dpsi2, dx);
        nutlo[1] = quadratic_intp(ip.nut_deps0, ip.nut_deps1, ip.nut_deps2, dx);
    } else {
        var dnut: [2]f64 = undefined;
        ip.tjd_nut0 = tjd - 1.0; // one day earlier
        ip.tjd_nut2 = tjd + 1.0; // one day later
        var retc = calc_nutation(ip.tjd_nut0, iflag, &dnut, models);
        if (retc == ERR) return ERR;
        ip.nut_dpsi0 = dnut[0];
        ip.nut_deps0 = dnut[1];
        retc = calc_nutation(ip.tjd_nut2, iflag, &dnut, models);
        if (retc == ERR) return ERR;
        ip.nut_dpsi2 = dnut[0];
        ip.nut_deps2 = dnut[1];
        retc = calc_nutation(tjd, iflag, nutlo, models);
        if (retc == ERR) return ERR;
        ip.nut_dpsi1 = nutlo[0];
        ip.nut_deps1 = nutlo[1];
    }
    return OK;
}

// correction of RA for JPL Horizons (swephlib.c 2160-2204)
const OFFSET_JPLHORIZONS: f64 = -52.3;
const DCOR_RA_JPL_TJD0: f64 = 2437846.5;
const NDCOR_RA_JPL: usize = 51;

fn swi_approx_jplhor(x: *[3]f64, tjd: f64, iflag: i32, backward: bool, models: AstroModels) void {
    var t = (tjd - DCOR_RA_JPL_TJD0) / 365.25;
    var dofs = OFFSET_JPLHORIZONS;
    var jplhora_model = models.jplhora;
    if (jplhora_model == 0) jplhora_model = SEMOD_JPLHORA_DEFAULT;
    if ((iflag & SEFLG_JPLHOR_APPROX) == 0)
        return;
    if (jplhora_model == SEMOD_JPLHORA_2)
        return;
    if (t < 0) {
        t = 0;
        dofs = dcor_ra_jpl[0];
    } else if (t >= @as(f64, @floatFromInt(NDCOR_RA_JPL - 1))) {
        t = @floatFromInt(NDCOR_RA_JPL);
        dofs = dcor_ra_jpl[NDCOR_RA_JPL - 1];
    } else {
        const t0 = @trunc(t);
        const t1 = t0 + 1;
        dofs = dcor_ra_jpl[@intFromFloat(t0)];
        dofs = (t - t0) * (dcor_ra_jpl[@intFromFloat(t0)] - dcor_ra_jpl[@intFromFloat(t1)]) + dcor_ra_jpl[@intFromFloat(t0)];
    }
    dofs /= (1000.0 * 3600.0);
    swi_cartpol(x, x);
    if (backward)
        x[0] -= dofs * DEGTORAD
    else
        x[0] += dofs * DEGTORAD;
    swi_polcart(x, x);
}

/// GCRS to J2000 frame bias (swephlib.c swi_bias)
pub fn swi_bias(x: *[6]f64, tjd: f64, iflag: i32, backward: bool, models: AstroModels) void {
    var xx: [6]f64 = undefined;
    var rb: [3][3]f64 = undefined;
    var bias_model = models.bias;
    var jplhora_model = models.jplhora;
    if (bias_model == 0) bias_model = SEMOD_BIAS_DEFAULT;
    if (jplhora_model == 0) jplhora_model = SEMOD_JPLHORA_DEFAULT;
    if (bias_model == SEMOD_BIAS_NONE)
        return;
    if ((iflag & SEFLG_JPLHOR_APPROX) != 0) {
        if (jplhora_model == SEMOD_JPLHORA_2)
            return;
        if (jplhora_model == SEMOD_JPLHORA_3 and tjd < HORIZONS_TJD0_DPSI_DEPS_IAU1980)
            return;
    }
    // frame bias 2006 vs 2000
    if (bias_model == SEMOD_BIAS_IAU2006) {
        rb[0][0] = 0.99999999999999412;
        rb[1][0] = -0.00000007078368961;
        rb[2][0] = 0.00000008056213978;
        rb[0][1] = 0.00000007078368695;
        rb[1][1] = 0.99999999999999700;
        rb[2][1] = 0.00000003306428553;
        rb[0][2] = -0.00000008056214212;
        rb[1][2] = -0.00000003306427981;
        rb[2][2] = 0.99999999999999634;
    } else {
        rb[0][0] = 0.9999999999999942;
        rb[1][0] = -0.0000000707827974;
        rb[2][0] = 0.0000000805621715;
        rb[0][1] = 0.0000000707827948;
        rb[1][1] = 0.9999999999999969;
        rb[2][1] = 0.0000000330604145;
        rb[0][2] = -0.0000000805621738;
        rb[1][2] = -0.0000000330604088;
        rb[2][2] = 0.9999999999999962;
    }
    if (backward) {
        swi_approx_jplhor(x[0..3], tjd, iflag, true, models);
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            xx[i] = x[0] * rb[i][0] +
                x[1] * rb[i][1] +
                x[2] * rb[i][2];
            if ((iflag & SEFLG_SPEED) != 0)
                xx[i + 3] = x[3] * rb[i][0] +
                    x[4] * rb[i][1] +
                    x[5] * rb[i][2];
        }
    } else {
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            xx[i] = x[0] * rb[0][i] +
                x[1] * rb[1][i] +
                x[2] * rb[2][i];
            if ((iflag & SEFLG_SPEED) != 0)
                xx[i + 3] = x[3] * rb[0][i] +
                    x[4] * rb[1][i] +
                    x[5] * rb[2][i];
        }
        swi_approx_jplhor(xx[0..3], tjd, iflag, false, models);
    }
    var i: usize = 0;
    while (i <= 2) : (i += 1)
        x[i] = xx[i];
    if ((iflag & SEFLG_SPEED) != 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            x[i] = xx[i];
    }
}

/// FK4 to FK5 (swephlib.c swi_FK4_FK5)
pub fn swi_FK4_FK5(xp: *[6]f64, tjd: f64) void {
    var correct_speed = true;
    if (xp[0] == 0 and xp[1] == 0 and xp[2] == 0)
        return;
    // with zero speed, we assume that it should be really zero
    if (xp[3] == 0)
        correct_speed = false;
    swi_cartpol_sp(xp, xp);
    // according to Expl.Suppl., p. 167f.
    xp[0] += (@as(f64, 0.035) + @as(f64, 0.085) * (tjd - B1950) / @as(f64, 36524.2198782)) / @as(f64, 3600) * @as(f64, 15) * DEGTORAD;
    if (correct_speed)
        xp[3] += (@as(f64, 0.085) / @as(f64, 36524.2198782)) / @as(f64, 3600) * @as(f64, 15) * DEGTORAD;
    swi_polcart_sp(xp, xp);
}

/// GCRS to FK5 (swephlib.c swi_icrs2fk5)
pub fn swi_icrs2fk5(x: *[6]f64, iflag: i32, backward: bool) void {
    var xx: [6]f64 = undefined;
    const rb = [3][3]f64{
        .{ 0.9999999999999928, 0.0000001110223287, 0.0000000441180557 },
        .{ -0.0000001110223330, 0.9999999999999891, 0.0000000964779176 },
        .{ -0.0000000441180450, -0.0000000964779225, 0.9999999999999943 },
    };
    if (backward) {
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            xx[i] = x[0] * rb[i][0] +
                x[1] * rb[i][1] +
                x[2] * rb[i][2];
            if ((iflag & SEFLG_SPEED) != 0)
                xx[i + 3] = x[3] * rb[i][0] +
                    x[4] * rb[i][1] +
                    x[5] * rb[i][2];
        }
    } else {
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            xx[i] = x[0] * rb[0][i] +
                x[1] * rb[1][i] +
                x[2] * rb[2][i];
            if ((iflag & SEFLG_SPEED) != 0)
                xx[i + 3] = x[3] * rb[0][i] +
                    x[4] * rb[1][i] +
                    x[5] * rb[2][i];
        }
    }
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        x[i] = xx[i];
}

// ---------------------------------------------------------------------------
// Sidereal time (swephlib.c 3285-3594)
// ---------------------------------------------------------------------------

const DeltatCtx = @import("deltat").DeltatCtx;
const swe_deltat_ex = @import("deltat").swe_deltat_ex;

/// sidtime_long_term (swephlib.c): ERA-based GST, valid far from 1850..2050
fn sidtime_long_term(tjd_ut: f64, eps: f64, nut: f64, models: AstroModels, dctx: *DeltatCtx, interp: ?*Interp) f64 {
    var xs: [3]f64 = undefined;
    var xobl: [3]f64 = undefined;
    var nutlo: [2]f64 = undefined;
    const dlt = AUNIT / CLIGHT / 86400.0;
    const tjd_et = tjd_ut + swe_deltat_ex(dctx, tjd_ut, -1);
    const t = (tjd_et - J2000) / 365250.0;
    const t2 = t * t;
    const t3 = t * t2;
    // mean longitude of earth J2000
    var dlon = 100.46645683 + (1295977422.83429 * t - 2.04411 * t2 - 0.00523 * t3) / 3600.0;
    // light time sun-earth
    dlon = swe_degnorm(dlon - dlt * 360.0 / 365.2425);
    xs[0] = dlon * DEGTORAD;
    xs[1] = 0;
    xs[2] = 1;
    // to mean equator J2000, cartesian
    xobl[0] = 23.45;
    xobl[1] = swi_epsiln(J2000 + swe_deltat_ex(dctx, J2000, -1), 0, models) * RADTODEG;
    swi_polcart(&xs, &xs);
    swi_coortrf(&xs, &xs, -xobl[1] * DEGTORAD);
    // precess to mean equinox of date
    _ = swi_precess(&xs, tjd_et, 0, -1, models);
    // to mean equinox of date
    xobl[1] = swi_epsiln(tjd_et, 0, models) * RADTODEG;
    _ = swi_nutation(tjd_et, 0, &nutlo, models, interp);
    xobl[0] = xobl[1] + nutlo[1] * RADTODEG;
    xobl[2] = nutlo[0] * RADTODEG;
    swi_coortrf(&xs, &xs, xobl[1] * DEGTORAD);
    swi_cartpol(&xs, &xs);
    xs[0] *= RADTODEG;
    const dhour = swe_shim_fmod(tjd_ut - 0.5, 1) * 360;
    // mean to true (if nut != 0)
    if (eps == 0)
        xs[0] += xobl[2] * swe_shim_cos(xobl[0] * DEGTORAD)
    else
        xs[0] += nut * swe_shim_cos(eps * DEGTORAD);
    // add hour
    xs[0] = swe_degnorm(xs[0] + dhour);
    return xs[0] / 15;
}

// IAU 2006 nutation series for GST (swephlib.c 3340-3412)
const SIDTNTERM: usize = 33;
const SIDTNARG: usize = 14;
// sidtime_non_polynomial_part (swephlib.c)
fn sidtime_non_polynomial_part(tt: f64) f64 {
    var delm: [SIDTNARG]f64 = undefined;
    // L Mean anomaly of the Moon.
    delm[0] = swe_radnorm(2.35555598 + 8328.6914269554 * tt);
    // LSU Mean anomaly of the Sun.
    delm[1] = swe_radnorm(6.24006013 + 628.301955 * tt);
    // F Mean argument of the latitude of the Moon.
    delm[2] = swe_radnorm(1.627905234 + 8433.466158131 * tt);
    // D Mean elongation of the Moon from the Sun.
    delm[3] = swe_radnorm(5.198466741 + 7771.3771468121 * tt);
    // OM Mean longitude of the ascending node of the Moon.
    delm[4] = swe_radnorm(2.18243920 - 33.757045 * tt);
    // Planetary longitudes, Mercury through Neptune (Souchay et al. 1999).
    delm[5] = swe_radnorm(4.402608842 + 2608.7903141574 * tt);
    delm[6] = swe_radnorm(3.176146697 + 1021.3285546211 * tt);
    delm[7] = swe_radnorm(1.753470314 + 628.3075849991 * tt);
    delm[8] = swe_radnorm(6.203480913 + 334.0612426700 * tt);
    delm[9] = swe_radnorm(0.599546497 + 52.9690962641 * tt);
    delm[10] = swe_radnorm(0.874016757 + 21.3299104960 * tt);
    delm[11] = swe_radnorm(5.481293871 + 7.4781598567 * tt);
    delm[12] = swe_radnorm(5.321159000 + 3.8127774000 * tt);
    // PA General accumulated precession in longitude.
    delm[13] = (0.02438175 + 0.00000538691 * tt) * tt;
    var dadd = -0.87 * swe_shim_sin(delm[4]) * tt;
    var i: usize = 0;
    while (i < SIDTNTERM) : (i += 1) {
        var darg: f64 = 0;
        var j: usize = 0;
        while (j < SIDTNARG) : (j += 1) {
            darg += @as(f64, @floatFromInt(stfarg[i * SIDTNARG + j])) * delm[j];
        }
        dadd += stcf[i * 2] * swe_shim_sin(darg) + stcf[i * 2 + 1] * swe_shim_cos(darg);
    }
    dadd /= (3600.0 * 1000000.0);
    return dadd;
}

// sidtime_long_term() is not used between the following two dates
const SIDT_LTERM_T0: f64 = 2396758.5; // 1 Jan 1850
const SIDT_LTERM_T1: f64 = 2469807.5; // 1 Jan 2050
const SIDT_LTERM_OFS0: f64 = 0.000378172 / 15.0;
const SIDT_LTERM_OFS1: f64 = 0.001385646 / 15.0;

/// Apparent Sidereal Time at Greenwich (swephlib.c swe_sidtime0);
/// returns sidereal time in hours. `eps`/`nut` are explicit inputs
/// (degrees); eps == 0 lets the function use its own nutation.
pub fn swe_sidtime0(tjd: f64, eps: f64, nut: f64, models: AstroModels, dctx: *DeltatCtx, interp: ?*Interp) f64 {
    var gmst: f64 = undefined;
    var prec_model_short = models.prec_shortterm;
    var sidt_model = models.sidt;
    if (prec_model_short == 0) prec_model_short = SEMOD_PREC_DEFAULT_SHORT;
    if (sidt_model == 0) sidt_model = SEMOD_SIDT_DEFAULT;
    if (sidt_model == SEMOD_SIDT_LONGTERM) {
        if (tjd <= SIDT_LTERM_T0 or tjd >= SIDT_LTERM_T1) {
            gmst = sidtime_long_term(tjd, eps, nut, models, dctx, interp);
            if (tjd <= SIDT_LTERM_T0)
                gmst -= SIDT_LTERM_OFS0
            else if (tjd >= SIDT_LTERM_T1)
                gmst -= SIDT_LTERM_OFS1;
            if (gmst >= 24) gmst -= 24;
            if (gmst < 0) gmst += 24;
            return gmst;
        }
    }
    // Julian day at given UT
    const jd = tjd;
    var jd0 = std.math.floor(jd);
    var secs = tjd - jd0;
    if (secs < 0.5) {
        jd0 -= 0.5;
        secs += 0.5;
    } else {
        jd0 += 0.5;
        secs -= 0.5;
    }
    secs *= 86400.0;
    const tu = (jd0 - J2000) / 36525.0; // UT1 in centuries after J2000
    if (sidt_model == SEMOD_SIDT_IERS_CONV_2010 or sidt_model == SEMOD_SIDT_LONGTERM) {
        // ERA-based expression for Greenwich Sidereal Time (GST) based
        // on the IAU 2006 precession
        const jdrel = tjd - J2000;
        const tt = (tjd + swe_deltat_ex(dctx, tjd, -1) - J2000) / 36525.0;
        gmst = swe_degnorm((0.7790572732640 + 1.00273781191135448 * jdrel) * 360);
        gmst += (0.014506 + tt * (4612.156534 + tt * (1.3915817 + tt * (-0.00000044 + tt * (-0.000029956 + tt * -0.0000000368))))) / 3600.0;
        const dadd = sidtime_non_polynomial_part(tt);
        gmst = swe_degnorm(gmst + dadd);
        gmst = gmst / 15.0 * 3600.0;
        // sidt_model == SEMOD_SIDT_IAU_2006, older standards according to precession model
    } else if (sidt_model == SEMOD_SIDT_IAU_2006) {
        const tt = (jd0 + swe_deltat_ex(dctx, jd0, -1) - J2000) / 36525.0; // TT in centuries after J2000
        gmst = (((-0.000000002454 * tt - 0.00000199708) * tt - 0.0000002926) * tt + 0.092772110) * tt * tt + 307.4771013 * (tt - tu) + 8640184.79447825 * tu + 24110.5493771;
        // mean solar days per sidereal day at date tu;
        // for the derivative of gmst, we can assume UT1 =~ TT
        const msday = 1 + ((((-0.000000012270 * tt - 0.00000798832) * tt - 0.0000008778) * tt + 0.185544220) * tt + 8640184.79447825) / (86400.0 * 36525.0);
        gmst += msday * secs;
        // SEMOD_SIDT_IAU_1976
    } else { // IAU 1976 formula
        // Greenwich Mean Sidereal Time at 0h UT of date
        gmst = ((-6.2e-6 * tu + 9.3104e-2) * tu + 8640184.812866) * tu + 24110.54841;
        // mean solar days per sidereal day at date tu, = 1.00273790934 in 1986
        const msday = 1.0 + ((-1.86e-5 * tu + 0.186208) * tu + 8640184.812866) / (86400.0 * 36525.0);
        gmst += msday * secs;
    }
    // Local apparent sidereal time at given UT at Greenwich
    const eqeq = 240.0 * nut * swe_shim_cos(eps * DEGTORAD);
    gmst = gmst + eqeq;
    // Sidereal seconds modulo 1 sidereal day
    gmst = gmst - 86400.0 * std.math.floor(gmst / 86400.0);
    // return in hours
    gmst /= 3600;
    return gmst;
}

/// sidereal time, without eps and nut as parameters (swephlib.c swe_sidtime);
/// tjd must be UT.
pub fn swe_sidtime(tjd_ut: f64, models: AstroModels, dctx: *DeltatCtx, interp: ?*Interp) f64 {
    var nutlo: [2]f64 = undefined;
    // delta t adjusted to default tidal acceleration of the moon
    const tjde = tjd_ut + swe_deltat_ex(dctx, tjd_ut, -1);
    const eps = swi_epsiln(tjde, 0, models) * RADTODEG;
    _ = swi_nutation(tjde, 0, &nutlo, models, interp);
    var i: usize = 0;
    while (i < 2) : (i += 1)
        nutlo[i] *= RADTODEG;
    return swe_sidtime0(tjd_ut, eps + nutlo[1], nutlo[0], models, dctx, interp);
}

/// conversion of position and speed: cartesian (x[6]) to polar (l[6]).
/// x = l is allowed. (swephlib.c swi_cartpol_sp)
pub fn swi_cartpol_sp(x: *[6]f64, l: *[6]f64) void {
    var xx: [6]f64 = undefined;
    var ll: [6]f64 = undefined;
    // zero position
    if (x[0] == 0 and x[1] == 0 and x[2] == 0) {
        ll[0] = 0;
        ll[1] = 0;
        ll[3] = 0;
        ll[4] = 0;
        ll[5] = std.math.sqrt(x[3] * x[3] + x[4] * x[4] + x[5] * x[5]);
        swi_cartpol(x[3..6], ll[0..3]);
        ll[2] = 0;
        for (0..6) |i| l[i] = ll[i];
        return;
    }
    // zero speed
    if (x[3] == 0 and x[4] == 0 and x[5] == 0) {
        l[3] = 0;
        l[4] = 0;
        l[5] = 0;
        swi_cartpol(x[0..3], l[0..3]);
        return;
    }
    // position
    var rxy = x[0] * x[0] + x[1] * x[1];
    ll[2] = std.math.sqrt(rxy + x[2] * x[2]);
    rxy = std.math.sqrt(rxy);
    ll[0] = swe_shim_atan2(x[1], x[0]);
    if (ll[0] < 0.0) ll[0] += TWOPI;
    ll[1] = swe_shim_atan(x[2] / rxy);
    // speed: rotate by longitude of position about z-axis
    const coslon = x[0] / rxy; // cos(l[0])
    const sinlon = x[1] / rxy; // sin(l[0])
    const coslat = rxy / ll[2]; // cos(l[1])
    const sinlat = x[2] / ll[2]; // sin(ll[1])
    xx[3] = x[3] * coslon + x[4] * sinlon;
    xx[4] = -x[3] * sinlon + x[4] * coslon;
    l[3] = xx[4] / rxy; // speed in longitude
    xx[4] = -sinlat * xx[3] + coslat * x[5];
    xx[5] = coslat * xx[3] + sinlat * x[5];
    l[4] = xx[4] / ll[2]; // speed in latitude
    l[5] = xx[5]; // speed in radius
    l[0] = ll[0]; // return position
    l[1] = ll[1];
    l[2] = ll[2];
}

/// conversion of position and speed: polar (l[6]) to cartesian (x[6]).
/// x = l is allowed (swephlib.c swi_polcart_sp)
pub fn swi_polcart_sp(l: *[6]f64, x: *[6]f64) void {
    var xx: [6]f64 = undefined;
    // zero speed
    if (l[3] == 0 and l[4] == 0 and l[5] == 0) {
        x[3] = 0;
        x[4] = 0;
        x[5] = 0;
        swi_polcart(l[0..3], x[0..3]);
        return;
    }
    // position
    const coslon = swe_shim_cos(l[0]);
    const sinlon = swe_shim_sin(l[0]);
    const coslat = swe_shim_cos(l[1]);
    const sinlat = swe_shim_sin(l[1]);
    xx[0] = l[2] * coslat * coslon;
    xx[1] = l[2] * coslat * sinlon;
    xx[2] = l[2] * sinlat;
    // speed
    const rxyz = l[2];
    const rxy = std.math.sqrt(xx[0] * xx[0] + xx[1] * xx[1]);
    xx[5] = l[5];
    xx[4] = l[4] * rxyz;
    x[5] = sinlat * xx[5] + coslat * xx[4]; // speed z
    xx[3] = coslat * xx[5] - sinlat * xx[4];
    xx[4] = l[3] * rxy;
    x[3] = coslon * xx[3] - sinlon * xx[4]; // speed x
    x[4] = sinlon * xx[3] + coslon * xx[4]; // speed y
    x[0] = xx[0]; // return position
    x[1] = xx[1];
    x[2] = xx[2];
}

pub fn swe_difrad2n(p1: f64, p2: f64) f64 {
    const dif = swe_radnorm(p1 - p2);
    if (dif >= TWOPI / 2) return dif - TWOPI;
    return dif;
}

// ---------------------------------------------------------------------------
// string / CRC helpers used by the sweph file machinery (swephlib.c)
// ---------------------------------------------------------------------------

/// swephlib.c swi_cutstr: split s at cutlist characters, in place.
/// C semantics: cpos[0] = s; each cut char is NUL'd; consecutive cut chars
/// are skipped; the \n/\r check applies to the last cut char of a run.
pub fn swi_cutstr(s: []u8, cutlist: []const u8, cpos: [*][]u8, nmax: usize) usize {
    var n: usize = 1;
    cpos[0] = s[0..];
    var i: usize = 0; // C's s pointer
    while (i < s.len and s[i] != 0) {
        var is_cut = false;
        for (cutlist) |cl| {
            if (cl != 0 and cl == s[i]) {
                is_cut = true;
                break;
            }
        }
        if (is_cut and n < nmax) {
            s[i] = 0;
            // C: while (*(s+1) != 0 && strchr(cutlist, *(s+1))) s++;
            while (i + 1 < s.len and s[i + 1] != 0 and cutlistContains(cutlist, s[i + 1])) i += 1;
            // C: cpos[n++] = s + 1  — the slice starts AFTER the last cut char
            if (i + 1 < s.len) {
                cpos[n] = s[i + 1 .. s.len];
                n += 1;
            } else {
                cpos[n] = s[s.len..s.len];
                n += 1;
            }
        }
        if (s[i] == '\n' or s[i] == '\r') {
            s[i] = 0;
            break;
        }
        i += 1;
    }
    if (n < nmax) cpos[n] = s[s.len..s.len];
    return n;
}

fn cutlistContains(cutlist: []const u8, c: u8) bool {
    for (cutlist) |cl| {
        if (cl != 0 and cl == c) return true;
    }
    return false;
}

threadlocal var crc32_table: [256]u32 = [_]u32{0} ** 256;
threadlocal var crc32_table_done: bool = false;
const CRC32_POLY: u32 = 0x04c11db7; // AUTODIN II, Ethernet, & FDDI

fn init_crc32() void {
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        var c: u32 = i << 24;
        var j: i32 = 8;
        while (j > 0) : (j -= 1) {
            if (c & 0x80000000 != 0)
                c = (c << 1) ^ CRC32_POLY
            else
                c = (c << 1);
        }
        crc32_table[i] = c;
    }
}

/// swephlib.c swi_crc32
pub fn swi_crc32(buf: []const u8) u32 {
    if (!crc32_table_done) {
        init_crc32();
        crc32_table_done = true;
    }
    var crc: u32 = 0xffffffff;
    for (buf) |b| {
        crc = (crc << 8) ^ crc32_table[(crc >> 24) ^ b];
    }
    return ~crc;
}

const SE_AST_OFFSET_LIB: usize = 10000;

/// swephlib.c swi_gen_filename: builds the ephemeris file name for a body
pub fn swi_gen_filename(tjd: f64, ipli: usize, fname: *[256]u8) void {
    const ncties: i32 = 6;
    var jyear: i32 = 0;
    var base: []const u8 = "";
    var is_single = false;
    switch (ipli) {
        1 => base = "semo", // SEI_MOON
        0 => base = "sepl", // SEI_EMB
        2...9, 10 => base = "sepl", // SEI_MERCURY..SEI_PLUTO, SEI_SUNBARY
        12...17 => base = "seas", // SEI_CERES..SEI_PHOLUS
        else => is_single = true,
    }
    if (is_single) {
        if (ipli > 9000 and ipli < 10000) {
            if (std.fmt.bufPrint(fname, "sat{c}sepm{d}.{s}", .{ '/', ipli, "se1" })) |written| {
                fname[written.len] = 0;
            } else |_| {}
        } else {
            if (std.fmt.bufPrint(fname, "ast{d}{c}se{d:0>5}.{s}", .{ @divTrunc(ipli - 10000, 1000), '/', ipli - 10000, "se1" })) |written| {
                fname[written.len] = 0;
            } else |_| {}
        }
        return;
    }
    const swedate = @import("swedate");
    const gregflag: i32 = if (tjd >= 2305447.5) 1 else 0;
    const rv = swedate.swe_revjul(tjd, gregflag);
    jyear = rv.year;
    var sgn: i32 = undefined;
    if (jyear < 0) {
        sgn = -1;
    } else {
        sgn = 1;
    }
    var icty = @divTrunc(jyear, 100);
    if (sgn < 0 and @rem(jyear, 100) != 0)
        icty -= 1;
    while (@rem(icty, ncties) != 0)
        icty -= 1;
    @memcpy(fname[0..base.len], base);
    var flen = base.len;
    if (icty < 0) {
        fname[flen] = 'm';
    } else {
        fname[flen] = '_';
    }
    flen += 1;
    const tail = if (std.fmt.bufPrint(fname[flen..], "{d:0>2}.{s}", .{ @abs(icty), "se1" })) |w| blk: {
        const r = w;
        fname[flen + r.len] = 0;
        break :blk r;
    } else |_| "";
    flen += tail.len;
    fname[flen] = 0;
}
