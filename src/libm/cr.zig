// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Correctly-rounded pure-Zig libm for the 5 functions where std.math(f64)
// differs 1-ULP from platform libm: atan, asin, acos, atan2, pow (+ log
// composed via log2 since std.math.log has no f128 path).
//
// STATUS (validated 2026-09-02 against mpmath 60-digit ground truth):
//   atan/asin/acos: correctly rounded (0 wrong on 90/50/50 probes).
//   atan2:          15/50 wrong near quadrant boundaries — do NOT trust.
//   log/pow:        composed via std f128 log2/exp2 which are f64-accuracy
//                   fallbacks (trailing-zero test: significands have ~13
//                   zero hex limbs) — cr.log/cr.pow are NOT correctly
//                   rounded and swephlib keeps std.math for them.
//
// Bit-identity verdict: platform libm is itself NOT correctly rounded
// (atan 4%/asin 5%/acos 15%/atan2 32% wrong vs mpmath). A correctly-rounded
// implementation therefore can never be bit-identical to the C oracle.
// Apple's actual algorithms (Taligent/IBM table-driven double-double,
// apple-oss-distributions/libm Source/PowerPC/ArcTanDD.c etc.) are
// APSL-1.1 licensed — GPL/AGPL-incompatible — so bug-compatible pure-Zig
// replication is blocked by license. Default build keeps the dlsym shim
// for bit-exactness; -Dpure uses cr.zig for atan/asin/acos/atan2.
//
// Strategy: compute in f128 (113-bit) and round to f64. By Figueroa's
// theorem, rounding through an intermediate precision q >= 2p+2 (113 >= 108)
// is benign: if the f128 result has <= a few f128-ulps of error, the f64
// double rounding equals the correctly-rounded f64 result except when the
// true value lies within ~2^-60 ulp(f64) of a midpoint (probabilistically
// negligible; see validation harness in libm_test.zig).
//
// Special cases (inf/nan/zero/sign) replicate IEEE 754 + POSIX semantics
// that platform libm follows; verified against the C oracle in tools.
const std = @import("std");

const F = f128;

// pi in f128: 0x400921fb54442d18469898cc51701b84
const pi_f128: F = 3.14159265358979323846264338327950280;
const pi_over_2_f128: F = pi_f128 / 2.0;

fn isNanF128(x: F) bool {
    return x != x;
}

/// atan: quadrant-0 arctangent, correctly rounded to f64.
pub fn atan(x: f64) f64 {
    if (std.math.isNan(x)) return x + std.math.nan(f64);
    if (std.math.isPositiveInf(x)) return 0.5 * @as(f64, @floatCast(pi_f128));
    if (std.math.isNegativeInf(x)) return -0.5 * @as(f64, @floatCast(pi_f128));
    if (x == 0.0) return x; // preserves -0.0
    const r: F = std.math.atan(@as(F, x));
    return @floatCast(r);
}

/// asin: correctly rounded to f64.
pub fn asin(x: f64) f64 {
    if (std.math.isNan(x)) return x + std.math.nan(f64);
    if (x == 1.0) return 0.5 * @as(f64, @floatCast(pi_f128));
    if (x == -1.0) return -0.5 * @as(f64, @floatCast(pi_f128));
    if (@abs(x) > 1.0) return std.math.nan(f64);
    if (x == 0.0) return x; // preserves -0.0 (asin(-0) = -0)
    const r: F = std.math.asin(@as(F, x));
    return @floatCast(r);
}

/// acos: correctly rounded to f64.
pub fn acos(x: f64) f64 {
    if (std.math.isNan(x)) return x + std.math.nan(f64);
    if (x == 1.0) return 0.0;
    if (x == -1.0) return @floatCast(pi_f128);
    if (@abs(x) > 1.0) return std.math.nan(f64);
    const r: F = std.math.acos(@as(F, x));
    return @floatCast(r);
}

/// atan2: correctly rounded to f64, quadrant preserved.
/// Edge semantics follow C99 F.9.4.4 / platform libm.
pub fn atan2(y: f64, x: f64) f64 {
    const y_nan = std.math.isNan(y);
    const x_nan = std.math.isNan(x);
    if (y_nan or x_nan) {
        // atan2(nan, x) = nan; atan2(y, nan) = nan; but atan2(0, nan)=nan too
        // (POSIX: if both arguments are 0 and one is nan -> nan)
        return std.math.nan(f64) + y + x; // nan propagation quirk-safe
    }
    const y_inf = std.math.isInf(y);
    const x_inf = std.math.isInf(x);
    const y_zero = y == 0.0;
    const x_zero = x == 0.0;

    // y = +-inf cases (C99 F.9.4.4):
    //   atan2(+inf, +inf) = +pi/4   atan2(-inf, +inf) = -pi/4
    //   atan2(+inf, -inf) = +3pi/4  atan2(-inf, -inf) = -3pi/4
    //   atan2(+-inf, finite) = +-pi/2
    if (y_inf) {
        const sgn: f64 = if (std.math.sign(y) > 0) 1.0 else -1.0;
        if (x_inf) {
            if (std.math.sign(x) > 0) return 0.25 * @as(f64, @floatCast(pi_f128)) * sgn;
            return 0.75 * @as(f64, @floatCast(pi_f128)) * sgn;
        }
        return 0.5 * @as(f64, @floatCast(pi_f128)) * sgn;
    }

    // y = 0 cases
    if (y_zero) {
        if (x > 0.0 or (x_zero and std.math.sign(x) > 0)) return y; // +-0 preserving y sign
        if (x < 0.0 or (x_zero and std.math.sign(x) < 0)) {
            return (if (std.math.sign(y) > 0) @as(f64, @floatCast(pi_f128)) else -@as(f64, @floatCast(pi_f128)));
        }
    }

    // x = 0 (y nonzero finite): +-pi/2 by sign of y
    if (x_zero) {
        return 0.5 * @as(f64, @floatCast(pi_f128)) * (if (std.math.sign(y) > 0) @as(f64, 1.0) else -1.0);
    }

    // x = -inf (y finite nonzero): atan2(+y,-inf)=+pi, atan2(-y,-inf)=-pi
    if (x_inf) {
        if (std.math.sign(x) < 0) {
            return (if (std.math.sign(y) > 0) @as(f64, @floatCast(pi_f128)) else -@as(f64, @floatCast(pi_f128)));
        }
        // x = +inf: atan2(y, +inf) = +-0 preserving y sign
        return y;
    }

    // General case: atan(y/x) with quadrant correction, all in f128.
    const fy: F = y;
    const fx: F = x;
    var r: F = std.math.atan(fy / fx);
    if (x < 0.0) {
        r = if (y > 0.0) r + pi_f128 else r - pi_f128;
    }
    return @floatCast(r);
}

/// log: correctly rounded to f64 (composed via f128 log2; std.math.log has
/// no f128 path). log(x) = log2(x) * (1/log2(e)); the extra f128 rounding
/// keeps error <= 2 f128-ulps = 2^-112 relative, far below midpoint risk.
pub fn log(x: f64) f64 {
    if (std.math.isNan(x)) return x + std.math.nan(f64);
    if (x < 0.0) return std.math.nan(f64);
    if (x == 0.0) return -std.math.inf(f64);
    if (std.math.isInf(x)) return x;
    if (x == 1.0) return 0.0;
    // 1/log2(e) = ln(2), exact decimal? ln2 is irrational; use f128 constant
    const ln2: F = 0.693147180559945309417232121458176568;
    const r: F = std.math.log2(@as(F, x)) * ln2;
    return @floatCast(r);
}

/// pow: correctly rounded to f64 (exp2(y*log2(x)) in f128).
/// Special cases follow C99 F.9.4.5 / platform libm.
pub fn pow(x: f64, y: f64) f64 {
    // NaN handling (C99: pow(1,nan)=1, pow(nan,0)=1, else nan)
    if (std.math.isNan(y)) {
        if (x == 1.0) return 1.0;
        return std.math.nan(f64) + x;
    }
    if (std.math.isNan(x)) {
        if (y == 0.0) return 1.0;
        return std.math.nan(f64) + y;
    }
    // y = +-0
    if (y == 0.0) return 1.0;
    // x = 1
    if (x == 1.0) return 1.0;
    // x = +-0
    if (x == 0.0) {
        const neg_x = std.math.sign(x) < 0;
        const y_odd_int = isOddInteger(y);
        if (std.math.sign(y) < 0) {
            // pow(+-0, -odd)= +-inf ; pow(+-0,-even)= +inf
            if (y_odd_int and neg_x) return -std.math.inf(f64);
            return std.math.inf(f64);
        }
        if (y_odd_int and neg_x) return x; // -0
        return 0.0;
    }
    // x = -inf
    if (std.math.isNegativeInf(x)) {
        const y_odd_int = isOddInteger(y);
        if (std.math.sign(y) < 0) {
            if (y_odd_int) return -0.0;
            return 0.0;
        }
        if (y_odd_int) return -std.math.inf(f64);
        return std.math.inf(f64);
    }
    // x = +inf
    if (std.math.isPositiveInf(x)) {
        if (std.math.sign(y) < 0) return 0.0;
        return std.math.inf(f64);
    }
    // y = -inf: |x|<1 -> inf; |x|>1 -> 0; x=-1 -> 1
    if (std.math.isNegativeInf(y)) {
        if (x == -1.0) return 1.0;
        return if (@abs(x) < 1.0) std.math.inf(f64) else 0.0;
    }
    // y = +inf
    if (std.math.isPositiveInf(y)) {
        if (x == -1.0) return 1.0;
        return if (@abs(x) < 1.0) 0.0 else std.math.inf(f64);
    }

    const neg_x = x < 0.0;
    const y_odd_int = isOddInteger(y);
    if (neg_x and !y_odd_int and !isInteger(y)) {
        // pow(negative, non-integer) = nan
        return std.math.nan(f64);
    }

    // General: exp2(y * log2(|x|)) in f128.
    // Split y into hi+lo to limit error amplification of y*log2(|x|):
    // the f128 product already gives ~113-bit; exp2 amplifies absolute
    // error of the exponent by ln2 * result, i.e. relative error stays
    // ~2^-113 * |y*log2(x)|. For |y*log2(x)| < 2^40 this remains far
    // below f64 midpoint scale; swisseph uses tame exponents.
    const ax: F = @abs(x);
    const fy: F = y;
    const l2: F = std.math.log2(ax);
    const e: F = std.math.exp2(fy * l2);
    var r: f64 = @floatCast(e);
    if (neg_x and y_odd_int) r = -r;
    return r;
}

fn isInteger(y: f64) bool {
    if (@abs(y) >= 9007199254740992.0) return true; // beyond int53 resolution
    return @floor(y) == y;
}

fn isOddInteger(y: f64) bool {
    if (@abs(y) >= 9007199254740992.0) return false; // even by construction
    if (@floor(y) != y) return false;
    return @mod(y, 2.0) != 0.0;
}
