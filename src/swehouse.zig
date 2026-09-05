// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port --- swehouse module.
// Translated 1:1 from swehouse.c to preserve exact floating-point
// operation order, differential-tested against the C oracle.
const std = @import("std");
const lib = @import("swephlib");

// Platform libm via shim or pure std.math (see libmshim.c / -Dpure)
const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;
const swe_shim_tan = lib.swe_shim_tan;
const swe_shim_asin = lib.swe_shim_asin;
const swe_shim_acos = lib.swe_shim_acos;
const swe_shim_atan = lib.swe_shim_atan;
const swe_shim_atan2 = lib.swe_shim_atan2;
const swe_shim_pow = lib.swe_shim_pow;
const swe_shim_fmod = lib.swe_shim_fmod;

pub const VERY_SMALL: f64 = 1e-10;
pub const VERY_SMALL_PLAC_ITER: f64 = 1.0 / 360000.0;
pub const MILLIARCSEC: f64 = 1.0 / 3600000.0;
pub const SOLAR_YEAR: f64 = 365.24219893;
pub const ARMCS: f64 = (SOLAR_YEAR + 1.0) / SOLAR_YEAR * 360.0;
pub const SUNSHINE_KEEP_MC_SOUTH: i32 = 0;
pub const ERR: i32 = -1;
pub const OK: i32 = 0;
/// Sunshine-house memo (was swehouse.c file static saved_sundec; TLS in C).
/// Lives beside the API: each caller owns one (SweState.house in the ABI).
pub const HouseCtx = struct {
    saved_sundec: f64 = 99.0,
};

pub const DEGTORAD: f64 = std.math.pi / 180.0;
pub const RADTODEG: f64 = 180.0 / std.math.pi;

pub const Houses = struct {
    cusp: [37]f64,
    cusp_speed: [37]f64,
    ac: f64,
    ac_speed: f64,
    mc: f64,
    mc_speed: f64,
    armc_speed: f64,
    vertex: f64,
    vertex_speed: f64,
    equasc: f64,
    equasc_speed: f64,
    coasc1: f64,
    coasc1_speed: f64,
    coasc2: f64,
    coasc2_speed: f64,
    polasc: f64,
    polasc_speed: f64,
    sundec: f64,
    do_speed: bool,
    do_hspeed: bool,
    do_interpol: bool,
    serr: [256]u8,
};

fn sind(x: f64) f64 {
    return swe_shim_sin(x * DEGTORAD);
}
fn cosd(x: f64) f64 {
    return swe_shim_cos(x * DEGTORAD);
}
fn tand(x: f64) f64 {
    return swe_shim_tan(x * DEGTORAD);
}
fn asind(x: f64) f64 {
    return swe_shim_asin(x) * RADTODEG;
}
pub fn acosd(x: f64) f64 {
    return swe_shim_acos(x) * RADTODEG;
}
fn atand(x: f64) f64 {
    return swe_shim_atan(x) * RADTODEG;
}
fn atan2d(y: f64, x: f64) f64 {
    return swe_shim_atan2(y, x) * RADTODEG;
}

pub fn swe_degnorm(x: f64) f64 {
    var y = fmod(x, 360.0);
    if (@abs(y) < 1e-13) y = 0.0;
    if (y < 0.0) y += 360.0;
    return y;
}

pub fn swe_radnorm(x: f64) f64 {
    var y = fmod(x, 2.0 * std.math.pi);
    if (@abs(y) < 1e-13) y = 0.0;
    if (y < 0.0) y += 2.0 * std.math.pi;
    return y;
}

pub fn swe_difdegn(p1: f64, p2: f64) f64 {
    return swe_degnorm(p1 - p2);
}

pub fn swe_difdeg2n(p1: f64, p2: f64) f64 {
    const dif = swe_degnorm(p1 - p2);
    if (dif >= 180.0) return dif - 360.0;
    return dif;
}

pub fn swe_difrad2n(p1: f64, p2: f64) f64 {
    const dif = swe_radnorm(p1 - p2);
    if (dif >= std.math.pi) return dif - 2.0 * std.math.pi;
    return dif;
}

fn fmod(x: f64, y: f64) f64 {
    return swe_shim_fmod(x, y);
}

fn upper8(hsys: i32) u8 {
    return std.ascii.toUpper(@as(u8, @truncate(@as(u32, @bitCast(hsys)))));
}

fn setSerr(buf: *[256]u8, msg: []const u8) void {
    @memcpy(buf[0..msg.len], msg);
    buf[msg.len] = 0;
}

fn serrFailed(buf: *[256]u8, hsys: i32) void {
    const s = std.fmt.bufPrintZ(buf, "swe_house_pos(): failed for system {c}", .{@as(u8, @truncate(@as(u32, @bitCast(hsys))))}) catch return;
    _ = s;
}

fn serrSimplified(buf: *[256]u8, hsys: i32) void {
    const s = std.fmt.bufPrintZ(buf, "swe_house_pos(): using simplified algorithm for system {c}\n", .{@as(u8, @truncate(@as(u32, @bitCast(hsys))))}) catch return;
    _ = s;
}

fn Asc1(x1_in: f64, f: f64, sine: f64, cose: f64) f64 {
    const x1 = swe_degnorm(x1_in);
    var ass: f64 = undefined;
    const n: i32 = @intFromFloat(x1 / 90.0 + 1.0);
    if (@abs(90.0 - f) < VERY_SMALL) {
        return 180.0;
    }
    if (@abs(90.0 + f) < VERY_SMALL) {
        return 0.0;
    }
    if (n == 1) {
        ass = Asc2(x1, f, sine, cose);
    } else if (n == 2) {
        ass = 180.0 - Asc2(180.0 - x1, -f, sine, cose);
    } else if (n == 3) {
        ass = 180.0 + Asc2(x1 - 180.0, -f, sine, cose);
    } else {
        ass = 360.0 - Asc2(360.0 - x1, f, sine, cose);
    }
    ass = swe_degnorm(ass);
    if (@abs(ass - 90.0) < VERY_SMALL)
        ass = 90.0;
    if (@abs(ass - 180.0) < VERY_SMALL)
        ass = 180.0;
    if (@abs(ass - 270.0) < VERY_SMALL)
        ass = 270.0;
    if (@abs(ass - 360.0) < VERY_SMALL)
        ass = 0.0;
    return ass;
}

fn Asc2(x: f64, f: f64, sine: f64, cose: f64) f64 {
    var ass = -tand(f) * sine + cose * cosd(x);
    if (@abs(ass) < VERY_SMALL)
        ass = 0.0;
    var sinx = sind(x);
    if (@abs(sinx) < VERY_SMALL)
        sinx = 0.0;
    if (sinx == 0.0) {
        if (ass < 0.0)
            ass = -VERY_SMALL
        else
            ass = VERY_SMALL;
    } else if (ass == 0.0) {
        if (sinx < 0.0)
            ass = -90.0
        else
            ass = 90.0;
    } else {
        ass = atand(sinx / ass);
    }
    if (ass < 0.0)
        ass = 180.0 + ass;
    return ass;
}

fn AscDash(x: f64, f: f64, sine: f64, cose: f64) f64 {
    const cosx = cosd(x);
    const sinx = sind(x);
    const sinx2 = sinx * sinx;
    const c = cose * cosx - tand(f) * sine;
    const d = sinx2 + c * c;
    var dudt: f64 = undefined;
    if (d > VERY_SMALL) {
        dudt = (cosx * c + cose * sinx2) / d;
    } else {
        dudt = 0.0;
    }
    return dudt * ARMCS;
}

pub fn armc_to_mc(armc: f64, eps: f64) f64 {
    const cose = cosd(eps);
    var mc: f64 = undefined;
    var tant: f64 = undefined;
    if (!(@abs(armc - 90.0) < VERY_SMALL) and
        !(@abs(armc - 270.0) < VERY_SMALL))
    {
        tant = tand(armc);
        mc = swe_degnorm(atand(tant / cose));
        if (armc > 90.0 and armc <= 270.0)
            mc = swe_degnorm(mc + 180.0);
    } else {
        if (@abs(armc - 90.0) < VERY_SMALL)
            mc = 90.0
        else
            mc = 270.0;
    }
    return mc;
}

fn fix_asc_polar(asc: f64, armc: f64, eps: f64, geolat: f64) f64 {
    var asc2 = asc;
    const demc = atand(sind(armc) * tand(eps));
    if (geolat >= 0.0 and 90.0 - geolat + demc < 0.0)
        asc2 = swe_degnorm(asc2 + 180.0);
    if (geolat < 0.0 and -90.0 - geolat + demc > 0.0)
        asc2 = swe_degnorm(asc2 + 180.0);
    return asc2;
}

fn sunshine_init(lat: f64, dec: f64, xh: []f64) i32 {
    var ad: f64 = undefined;
    var nsa: f64 = undefined;
    var dsa: f64 = undefined;
    const arg = tand(dec) * tand(lat);
    if (arg >= 1.0) {
        ad = 90.0 - VERY_SMALL;
    } else if (arg <= -1.0) {
        ad = -90.0 + VERY_SMALL;
    } else {
        ad = asind(arg);
    }
    nsa = 90.0 - ad;
    dsa = 90.0 + ad;
    xh[2] = -2.0 * nsa / 3.0;
    xh[3] = -1.0 * nsa / 3.0;
    xh[5] = 1.0 * nsa / 3.0;
    xh[6] = 2.0 * nsa / 3.0;
    xh[8] = -2.0 * dsa / 3.0;
    xh[9] = -1.0 * dsa / 3.0;
    xh[11] = 1.0 * dsa / 3.0;
    xh[12] = 2.0 * dsa / 3.0;
    if (@abs(arg) >= 1.0)
        return ERR;
    return OK;
}

fn sunshine_solution_makransky(ramc: f64, lat: f64, ecl: f64, hsp: *Houses) i32 {
    var xh: [13]f64 = undefined;
    var md: f64 = undefined;
    var zd: f64 = undefined;
    var pole: f64 = undefined;
    var q: f64 = undefined;
    var w: f64 = undefined;
    var a: f64 = undefined;
    var b: f64 = undefined;
    var c: f64 = undefined;
    var f: f64 = undefined;
    var cu: f64 = undefined;
    var r: f64 = 0.0;
    var rah: f64 = undefined;
    const sinlat = sind(lat);
    const coslat = cosd(lat);
    const tanlat = tand(lat);
    const tandec = tand(hsp.sundec);
    const sinecl = sind(ecl);
    const dec = hsp.sundec;
    var ih: i32 = undefined;
    if (sunshine_init(lat, dec, &xh) == ERR)
        return ERR;
    ih = 1;
    while (ih <= 12) : (ih += 1) {
        var z: f64 = 0.0;
        if (@rem(ih - 1, 3) == 0) continue;
        md = @abs(xh[@intCast(ih)]);
        if (ih <= 6) {
            rah = swe_degnorm(ramc + 180.0 + xh[@intCast(ih)]);
        } else {
            rah = swe_degnorm(ramc + xh[@intCast(ih)]);
        }
        if (lat < 0.0) {
            rah = swe_degnorm(180.0 + rah);
        }
        if (md == 90.0) {
            zd = 90.0 - atand(sinlat * tandec);
        } else {
            if (md < 90.0) {
                a = atand(coslat * tand(md));
            } else {
                a = atand(tand(md - 90.0) / coslat);
            }
            b = atand(tanlat * cosd(md));
            if (ih <= 6) {
                c = b + dec;
            } else {
                c = b - dec;
            }
            f = atand(sinlat * sind(md) * tand(c));
            zd = a + f;
        }
        pole = asind(sind(zd) * sinlat);
        q = asind(tandec * tand(pole));
        if (ih <= 3 or ih >= 11) {
            w = swe_degnorm(rah - q);
        } else {
            w = swe_degnorm(rah + q);
        }
        if (w == 90.0) {
            r = atand(sind(ecl) * tand(pole));
            if (ih <= 3 or ih >= 11) {
                cu = 90.0 + r;
            } else {
                cu = 90.0 - r;
            }
        } else if (w == 270.0) {
            r = atand(sinecl * tand(pole));
            if (ih <= 3 or ih >= 11) {
                cu = 270.0 - r;
            } else {
                cu = 270.0 + r;
            }
        } else {
            const m = atand(@abs(tand(pole) / cosd(w)));
            if (ih <= 3 or ih >= 11) {
                if (w > 90.0 and w < 270.0) {
                    z = m - ecl;
                } else {
                    z = m + ecl;
                }
            } else {
                if (w > 90.0 and w < 270.0) {
                    z = m + ecl;
                } else {
                    z = m - ecl;
                }
            }
            if (z == 90.0) {
                if (w < 180.0) {
                    cu = 90.0;
                } else {
                    cu = 270.0;
                }
            } else {
                r = atand(@abs(cosd(m) * tand(w) / cosd(z)));
                if (w < 90.0) {
                    cu = r;
                } else if (w > 90.0 and w < 180.0) {
                    cu = 180.0 - r;
                } else if (w > 180.0 and w < 270.0) {
                    cu = 180.0 + r;
                } else {
                    cu = 360.0 - r;
                }
            }
            if (z > 90.0) {
                if (w < 90.0) {
                    cu = 180.0 - r;
                } else if (w > 90.0 and w < 180.0) {
                    cu = r;
                } else if (w > 180.0 and w < 270.0) {
                    cu = 360.0 - r;
                } else {
                    cu = 180.0 + r;
                }
            }
        }
        if (lat < 0.0) {
            cu = swe_degnorm(cu + 180.0);
        }
        hsp.cusp[@intCast(ih)] = cu;
    }
    return OK;
}

fn sunshine_solution_treindl(ramc: f64, lat: f64, ecl: f64, hsp: *Houses) i32 {
    var xh: [13]f64 = undefined;
    var mcdec: f64 = undefined;
    var sinlat: f64 = undefined;
    var coslat: f64 = undefined;
    var cosdec: f64 = undefined;
    var tandec: f64 = undefined;
    var sinecl: f64 = undefined;
    var cosecl: f64 = undefined;
    var xhs: f64 = undefined;
    var pole: f64 = undefined;
    var cosa: f64 = undefined;
    var alph: f64 = undefined;
    var alpha2: f64 = undefined;
    var c: f64 = undefined;
    var cosc: f64 = undefined;
    var b: f64 = undefined;
    var sinzd: f64 = undefined;
    var zd: f64 = undefined;
    var rax: f64 = undefined;
    var hc: f64 = undefined;
    var retval: i32 = OK;
    var mc_under_horizon: bool = undefined;
    const dec = hsp.sundec;
    var ih: i32 = undefined;
    sinlat = sind(lat);
    coslat = cosd(lat);
    cosdec = cosd(dec);
    tandec = tand(dec);
    sinecl = sind(ecl);
    cosecl = cosd(ecl);
    _ = sunshine_init(lat, dec, &xh);
    mcdec = atand(sind(ramc) * tand(ecl));
    mc_under_horizon = @abs(lat - mcdec) > 90.0;
    if (mc_under_horizon and SUNSHINE_KEEP_MC_SOUTH != 0) {
        ih = 2;
        while (ih <= 12) : (ih += 1) {
            if (@rem(ih - 1, 3) == 0) continue;
            xh[@intCast(ih)] = -xh[@intCast(ih)];
        }
    }
    ih = 1;
    while (ih <= 12) : (ih += 1) {
        if (@rem(ih - 1, 3) == 0) continue;
        xhs = 2.0 * asind(cosdec * sind(xh[@intCast(ih)] / 2.0));
        cosa = tandec * tand(xhs / 2.0);
        alph = acosd(cosa);
        if (ih > 7) {
            alpha2 = 180.0 - alph;
            b = 90.0 - lat + dec;
        } else {
            alpha2 = alph;
            b = 90.0 - lat - dec;
        }
        cosc = cosd(xhs) * cosd(b) + sind(xhs) * sind(b) * cosd(alpha2);
        c = acosd(cosc);
        if (c < 1e-6) {
            // C: sprintf(hsp->serr, "Sunshine house %d c=%le very small", ih, c)
            const s = std.fmt.bufPrintZ(&hsp.serr, "Sunshine house {d} c={e} very small", .{ ih, c }) catch return ERR;
            _ = s;
            retval = ERR;
        }
        sinzd = sind(xhs) * sind(alpha2) / sind(c);
        zd = asind(sinzd);
        rax = atand(coslat * tand(zd));
        pole = asind(sinzd * sinlat);
        var a2: f64 = undefined;
        if (ih <= 6) {
            pole = -pole;
            a2 = swe_degnorm(rax + ramc + 180.0);
        } else {
            a2 = swe_degnorm(ramc + rax);
        }
        hc = Asc1(a2, pole, sinecl, cosecl);
        hsp.cusp[@intCast(ih)] = hc;
    }
    if (mc_under_horizon and SUNSHINE_KEEP_MC_SOUTH == 0) {
        ih = 2;
        while (ih <= 12) : (ih += 1) {
            if (@rem(ih - 1, 3) == 0) continue;
            hsp.cusp[@intCast(ih)] = swe_degnorm(hsp.cusp[@intCast(ih)] + 180.0);
        }
    }
    return retval;
}

fn CalcH(th_in: f64, fi_in: f64, ekl: f64, hsy_in: u8, hsp: *Houses) i32 {
    var th = th_in;
    var fi = fi_in;
    var hsy = hsy_in;
    var tane: f64 = undefined;
    var tanfi: f64 = undefined;
    var cosfi: f64 = undefined;
    var sinfi: f64 = undefined;
    var tant: f64 = undefined;
    var sina: f64 = undefined;
    var cosa: f64 = undefined;
    var th2: f64 = undefined;
    var a: f64 = undefined;
    var c: f64 = undefined;
    var f: f64 = undefined;
    var fh1: f64 = undefined;
    var fh2: f64 = undefined;
    var xh1: f64 = undefined;
    var xh2: f64 = undefined;
    var xs1: f64 = undefined;
    var xs2: f64 = undefined;
    var rectasc: f64 = undefined;
    var ad3: f64 = undefined;
    var acmc: f64 = undefined;
    var vemc: f64 = undefined;
    var i: i32 = undefined;
    var ih: i32 = undefined;
    var ih2: i32 = undefined;
    var retc: i32 = OK;
    var sine: f64 = undefined;
    var cose: f64 = undefined;
    var x: [3]f64 = undefined;
    var krHorizonLon: f64 = undefined;
    const niter_max: i32 = 100;
    var cuspsv: f64 = undefined;
    hsp.serr[0] = 0;
    hsp.do_interpol = false;
    cose = cosd(ekl);
    sine = sind(ekl);
    tane = tand(ekl);
    if (@abs(@abs(fi) - 90.0) < VERY_SMALL) {
        if (fi < 0.0)
            fi = -90.0 + VERY_SMALL
        else
            fi = 90.0 - VERY_SMALL;
    }
    tanfi = tand(fi);
    if (!(@abs(th - 90.0) < VERY_SMALL) and
        !(@abs(th - 270.0) < VERY_SMALL))
    {
        tant = tand(th);
        hsp.mc = atand(tant / cose);
        if (th > 90.0 and th <= 270.0)
            hsp.mc = swe_degnorm(hsp.mc + 180.0);
    } else {
        if (@abs(th - 90.0) < VERY_SMALL)
            hsp.mc = 90.0
        else
            hsp.mc = 270.0;
    }
    hsp.mc = swe_degnorm(hsp.mc);
    if (hsp.do_speed) hsp.mc_speed = AscDash(th, 0.0, sine, cose);
    hsp.ac = Asc1(th + 90.0, fi, sine, cose);
    if (hsp.do_speed)
        hsp.ac_speed = AscDash(th + 90.0, fi, sine, cose);
    if (hsp.do_hspeed) {
        i = 0;
        while (i <= 12) : (i += 1)
            hsp.cusp_speed[@intCast(i)] = 0.0;
    }
    hsp.armc_speed = ARMCS;
    hsp.cusp[1] = hsp.ac;
    hsp.cusp[10] = hsp.mc;
    if (hsp.do_hspeed) {
        hsp.cusp_speed[1] = hsp.ac_speed;
        hsp.cusp_speed[10] = hsp.mc_speed;
    }
    if (hsy > 95 and hsy != 'i') {
        const prefix = "use of lower case letters like ";
        const suffix = " for house systems is deprecated";
        @memcpy(hsp.serr[0..prefix.len], prefix);
        hsp.serr[prefix.len] = hsy;
        @memcpy(hsp.serr[prefix.len + 1 .. prefix.len + 1 + suffix.len], suffix);
        hsp.serr[prefix.len + 1 + suffix.len] = 0;
        hsy = @as(u8, @intCast(hsy - 32));
    }
    sw: switch (hsy) {
        'A', 'E' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
            }
            i = 2;
            while (i <= 12) : (i += 1) {
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[1] + @as(f64, i - 1) * 30.0);
            }
            if (hsp.do_hspeed) {
                i = 1;
                while (i <= 12) : (i += 1) {
                    hsp.cusp_speed[@intCast(i)] = hsp.ac_speed;
                }
            }
        },
        'D' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            hsp.cusp[10] = hsp.mc;
            i = 11;
            while (i <= 12) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[10] + @as(f64, i - 10) * 30.0);
            i = 1;
            while (i <= 9) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[10] + @as(f64, i + 2) * 30.0);
            if (hsp.do_hspeed) {
                i = 1;
                while (i <= 12) : (i += 1) {
                    hsp.cusp_speed[@intCast(i)] = hsp.mc_speed;
                }
            }
        },
        'C' => {
            fh1 = asind(sind(fi) / 2.0);
            fh2 = asind(std.math.sqrt(3.0) / 2.0 * sind(fi));
            cosfi = cosd(fi);
            if (@abs(cosfi) == 0.0) {
                if (fi > 0.0) {
                    xh1 = 90.0;
                    xh2 = 90.0;
                } else {
                    xh1 = 270.0;
                    xh2 = 270.0;
                }
            } else {
                xh1 = atand(std.math.sqrt(3.0) / cosfi);
                xh2 = atand(1.0 / @sqrt(@as(f64, 3.0)) / cosfi);
            }
            hsp.cusp[11] = Asc1(th + 90.0 - xh1, fh1, sine, cose);
            hsp.cusp[12] = Asc1(th + 90.0 - xh2, fh2, sine, cose);
            hsp.cusp[2] = Asc1(th + 90.0 + xh2, fh2, sine, cose);
            hsp.cusp[3] = Asc1(th + 90.0 + xh1, fh1, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(th + 90.0 - xh1, fh1, sine, cose);
                hsp.cusp_speed[12] = AscDash(th + 90.0 - xh2, fh2, sine, cose);
                hsp.cusp_speed[2] = AscDash(th + 90.0 + xh2, fh2, sine, cose);
                hsp.cusp_speed[3] = AscDash(th + 90.0 + xh1, fh1, sine, cose);
            }
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1) {
                        if (i >= 4 and i < 10) continue;
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                    }
                }
            }
        },
        'H' => {
            if (fi > 0.0)
                fi = 90.0 - fi
            else
                fi = -90.0 - fi;
            if (@abs(@abs(fi) - 90.0) < VERY_SMALL) {
                if (fi < 0.0)
                    fi = -90.0 + VERY_SMALL
                else
                    fi = 90.0 - VERY_SMALL;
            }
            th = swe_degnorm(th + 180.0);
            fh1 = asind(sind(fi) / 2.0);
            fh2 = asind(std.math.sqrt(3.0) / 2.0 * sind(fi));
            cosfi = cosd(fi);
            if (@abs(cosfi) == 0.0) {
                if (fi > 0.0) {
                    xh1 = 90.0;
                    xh2 = 90.0;
                } else {
                    xh1 = 270.0;
                    xh2 = 270.0;
                }
            } else {
                xh1 = atand(std.math.sqrt(3.0) / cosfi);
                xh2 = atand(1.0 / @sqrt(@as(f64, 3.0)) / cosfi);
            }
            hsp.cusp[11] = Asc1(th + 90.0 - xh1, fh1, sine, cose);
            hsp.cusp[12] = Asc1(th + 90.0 - xh2, fh2, sine, cose);
            hsp.cusp[1] = Asc1(th + 90.0, fi, sine, cose);
            hsp.cusp[2] = Asc1(th + 90.0 + xh2, fh2, sine, cose);
            hsp.cusp[3] = Asc1(th + 90.0 + xh1, fh1, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(th + 90.0 - xh1, fh1, sine, cose);
                hsp.cusp_speed[12] = AscDash(th + 90.0 - xh2, fh2, sine, cose);
                hsp.cusp_speed[1] = AscDash(th + 90.0, fi, sine, cose);
                hsp.cusp_speed[2] = AscDash(th + 90.0 + xh2, fh2, sine, cose);
                hsp.cusp_speed[3] = AscDash(th + 90.0 + xh1, fh1, sine, cose);
            }
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1) {
                        if (i >= 4 and i < 10) continue;
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                    }
                }
            }
            i = 1;
            while (i <= 3) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
            i = 11;
            while (i <= 12) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
            if (fi > 0.0)
                fi = 90.0 - fi
            else
                fi = -90.0 - fi;
            th = swe_degnorm(th + 180.0);
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
        },
        'I', 'i' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
                if (SUNSHINE_KEEP_MC_SOUTH == 0 and hsy == 'I') {
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    hsp.cusp[10] = hsp.mc;
                }
            }
            hsp.cusp[4] = swe_degnorm(hsp.cusp[10] + 180.0);
            hsp.cusp[7] = swe_degnorm(hsp.cusp[1] + 180.0);
            if (hsy == 'I') {
                retc = sunshine_solution_treindl(th, fi, ekl, hsp);
            } else {
                retc = sunshine_solution_makransky(th, fi, ekl, hsp);
            }
            if (retc == ERR) {
                setSerr(&hsp.serr, "within polar circle, switched to Porphyry");
                hsy = 'O';
                continue :sw 'O';
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'J' => {
            sinfi = sind(fi);
            cosfi = cosd(fi);
            if (@abs(fi) < VERY_SMALL) {
                xs2 = 1.0 / 3.0;
                xs1 = 2.0 / 3.0;
            } else {
                xs2 = sind(fi / 3.0) / sinfi;
                xs1 = sind(2.0 * fi / 3.0) / sinfi;
            }
            xs2 = asind(xs2);
            xs1 = asind(xs1);
            if (cosfi == 0.0) {
                if (fi > 0.0) {
                    xh1 = 90.0;
                    xh2 = 90.0;
                } else {
                    xh1 = 270.0;
                    xh2 = 270.0;
                }
            } else {
                xh1 = atand(tand(xs1) / cosfi);
                xh2 = atand(tand(xs2) / cosfi);
            }
            fh1 = asind(sind(fi) * sind(90.0 - xs1));
            fh2 = asind(sind(fi) * sind(90.0 - xs2));
            hsp.cusp[12] = Asc1(th + 90.0 - xh2, fh2, sine, cose);
            hsp.cusp[11] = Asc1(th + 90.0 - xh1, fh1, sine, cose);
            hsp.cusp[2] = Asc1(th + 90.0 + xh2, fh2, sine, cose);
            hsp.cusp[3] = Asc1(th + 90.0 + xh1, fh1, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(th + 90.0 - xh1, fh1, sine, cose);
                hsp.cusp_speed[12] = AscDash(th + 90.0 - xh2, fh2, sine, cose);
                hsp.cusp_speed[3] = AscDash(th + 90.0 + xh1, fh1, sine, cose);
                hsp.cusp_speed[2] = AscDash(th + 90.0 + xh2, fh2, sine, cose);
            }
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1) {
                        if (i >= 4 and i < 10) continue;
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                    }
                }
            }
        },
        'K' => {
            if (@abs(fi) >= 90.0 - ekl) {
                retc = ERR;
                setSerr(&hsp.serr, "within polar circle, switched to Porphyry");
                continue :sw 'O';
            }
            sina = sind(hsp.mc) * sine / cosd(fi);
            if (sina > 1.0) sina = 1.0;
            if (sina < -1.0) sina = -1.0;
            cosa = std.math.sqrt(1.0 - sina * sina);
            c = atand(tanfi / cosa);
            ad3 = asind(sind(c) * sina) / 3.0;
            hsp.cusp[11] = Asc1(th + 30.0 - 2.0 * ad3, fi, sine, cose);
            hsp.cusp[12] = Asc1(th + 60.0 - ad3, fi, sine, cose);
            hsp.cusp[2] = Asc1(th + 120.0 + ad3, fi, sine, cose);
            hsp.cusp[3] = Asc1(th + 150.0 + 2.0 * ad3, fi, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(th + 30.0 - 2.0 * ad3, fi, sine, cose);
                hsp.cusp_speed[12] = AscDash(th + 60.0 - ad3, fi, sine, cose);
                hsp.cusp_speed[2] = AscDash(th + 120.0 + ad3, fi, sine, cose);
                hsp.cusp_speed[3] = AscDash(th + 150.0 + 2.0 * ad3, fi, sine, cose);
            }
        },
        'L' => {
            var d: f64 = undefined;
            var q1: f64 = undefined;
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            }
            q1 = 180.0 - acmc;
            d = (acmc - 90.0) / 4.0;
            if (acmc <= 30.0) {
                hsp.cusp[11] = swe_degnorm(hsp.mc + acmc / 2.0);
                hsp.cusp[12] = hsp.cusp[11];
            } else {
                hsp.cusp[11] = swe_degnorm(hsp.mc + 30.0 + d);
                hsp.cusp[12] = swe_degnorm(hsp.mc + 60.0 + 3.0 * d);
            }
            d = (q1 - 90.0) / 4.0;
            if (q1 <= 30.0) {
                hsp.cusp[2] = swe_degnorm(hsp.ac + q1 / 2.0);
                hsp.cusp[3] = hsp.cusp[2];
            } else {
                hsp.cusp[2] = swe_degnorm(hsp.ac + 30.0 + d);
                hsp.cusp[3] = swe_degnorm(hsp.ac + 60.0 + 3.0 * d);
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'N' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            i = 1;
            while (i <= 12) : (i += 1)
                hsp.cusp[@intCast(i)] = @as(f64, i - 1) * 30.0;
        },
        'O' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            }
            hsp.cusp[1] = hsp.ac;
            hsp.cusp[10] = hsp.mc;
            hsp.cusp[2] = swe_degnorm(hsp.ac + (180.0 - acmc) / 3.0);
            hsp.cusp[3] = swe_degnorm(hsp.ac + (180.0 - acmc) / 3.0 * 2.0);
            hsp.cusp[11] = swe_degnorm(hsp.mc + acmc / 3.0);
            hsp.cusp[12] = swe_degnorm(hsp.mc + acmc / 3.0 * 2.0);
            if (hsp.do_hspeed) {
                const q1_speed = hsp.ac_speed - hsp.mc_speed;
                hsp.cusp_speed[1] = hsp.ac_speed;
                hsp.cusp_speed[10] = hsp.mc_speed;
                hsp.cusp_speed[2] = hsp.ac_speed - q1_speed / 3.0;
                hsp.cusp_speed[3] = hsp.ac_speed - q1_speed / 3.0 * 2.0;
                hsp.cusp_speed[11] = hsp.ac_speed + q1_speed / 3.0;
                hsp.cusp_speed[12] = hsp.ac_speed + q1_speed / 3.0 * 2.0;
            }
        },
        'Q' => {
            var q: f64 = undefined;
            var cq: f64 = undefined;
            var csq: f64 = undefined;
            var ccr: f64 = undefined;
            var cqx: f64 = undefined;
            var two23: f64 = undefined;
            var third: f64 = undefined;
            var r: f64 = undefined;
            var r1: f64 = undefined;
            var r2: f64 = undefined;
            var xq: f64 = undefined;
            var xr: f64 = undefined;
            var xr3: f64 = undefined;
            var xr4: f64 = undefined;
            third = 1.0 / 3.0;
            two23 = swe_shim_pow(2.0 * 2.0, third);
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            }
            q = acmc;
            if (q > 90.0) q = 180.0 - q;
            if (q < 1e-30) {
                xq = 0.0;
                xr = 0.0;
                xr3 = 0.0;
                xr4 = 180.0;
            } else {
                cq = (180.0 - q) / q;
                csq = cq * cq;
                ccr = swe_shim_pow(csq - cq, third);
                cqx = std.math.sqrt(two23 * ccr + 1.0);
                r1 = 0.5 * cqx;
                r2 = 0.5 * std.math.sqrt(-2.0 * (1.0 - 2.0 * cq) / cqx - two23 * ccr + 2.0);
                r = r1 + r2 - 0.5;
                xq = q / (2.0 * r + 1.0);
                xr = r * xq;
                xr3 = xr * r * r;
                xr4 = xr3 * r;
            }
            if (acmc > 90.0) {
                hsp.cusp[11] = swe_degnorm(hsp.mc + xr3);
                hsp.cusp[12] = swe_degnorm(hsp.cusp[11] + xr4);
                hsp.cusp[2] = swe_degnorm(hsp.ac + xr);
                hsp.cusp[3] = swe_degnorm(hsp.cusp[2] + xq);
            } else {
                hsp.cusp[11] = swe_degnorm(hsp.mc + xr);
                hsp.cusp[12] = swe_degnorm(hsp.cusp[11] + xq);
                hsp.cusp[2] = swe_degnorm(hsp.ac + xr3);
                hsp.cusp[3] = swe_degnorm(hsp.cusp[2] + xr4);
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'R' => {
            fh1 = atand(tanfi * 0.5);
            fh2 = atand(tanfi * cosd(30.0));
            hsp.cusp[11] = Asc1(30.0 + th, fh1, sine, cose);
            hsp.cusp[12] = Asc1(60.0 + th, fh2, sine, cose);
            hsp.cusp[2] = Asc1(120.0 + th, fh2, sine, cose);
            hsp.cusp[3] = Asc1(150.0 + th, fh1, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(30.0 + th, fh1, sine, cose);
                hsp.cusp_speed[12] = AscDash(60.0 + th, fh2, sine, cose);
                hsp.cusp_speed[2] = AscDash(120.0 + th, fh2, sine, cose);
                hsp.cusp_speed[3] = AscDash(150.0 + th, fh1, sine, cose);
            }
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1) {
                        if (i >= 4 and i < 10) continue;
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                    }
                }
            }
        },
        'S' => {
            var s1: f64 = undefined;
            var s4: f64 = undefined;
            var q1_2: f64 = undefined;
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            }
            q1_2 = 180.0 - acmc;
            s1 = q1_2 / 3.0;
            s4 = acmc / 3.0;
            hsp.cusp[1] = swe_degnorm(hsp.ac - s4 * 0.5);
            hsp.cusp[2] = swe_degnorm(hsp.ac + s1 * 0.5);
            hsp.cusp[3] = swe_degnorm(hsp.ac + s1 * 1.5);
            hsp.cusp[10] = swe_degnorm(hsp.mc - s1 * 0.5);
            hsp.cusp[11] = swe_degnorm(hsp.mc + s4 * 0.5);
            hsp.cusp[12] = swe_degnorm(hsp.mc + s4 * 1.5);
            hsp.do_interpol = hsp.do_hspeed;
        },
        'T' => {
            fh1 = atand(tanfi / 3.0);
            fh2 = atand(tanfi * 2.0 / 3.0);
            hsp.cusp[11] = Asc1(30.0 + th, fh1, sine, cose);
            hsp.cusp[12] = Asc1(60.0 + th, fh2, sine, cose);
            hsp.cusp[2] = Asc1(120.0 + th, fh2, sine, cose);
            hsp.cusp[3] = Asc1(150.0 + th, fh1, sine, cose);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[11] = AscDash(30.0 + th, fh1, sine, cose);
                hsp.cusp_speed[12] = AscDash(60.0 + th, fh2, sine, cose);
                hsp.cusp_speed[2] = AscDash(120.0 + th, fh2, sine, cose);
                hsp.cusp_speed[3] = AscDash(150.0 + th, fh1, sine, cose);
            }
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1)
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                }
            }
        },
        'U' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            x[0] = hsp.ac;
            x[1] = 0.0;
            x[2] = 1.0;
            swe_cotrans(&x, &x, -ekl);
            x[0] = x[0] - (th - 90.0);
            swe_cotrans(&x, &x, -(90.0 - fi));
            krHorizonLon = x[0];
            x[0] = x[0] - x[0];
            swe_cotrans(&x, &x, -90.0);
            i = 0;
            while (i < 6) : (i += 1) {
                x[0] = 30.0 * @as(f64, @floatFromInt(i));
                x[1] = 0.0;
                swe_cotrans(&x, &x, 90.0);
                x[0] = x[0] + krHorizonLon;
                swe_cotrans(&x, &x, 90.0 - fi);
                x[0] = swe_degnorm(x[0] + (th - 90.0));
                hsp.cusp[@intCast(i + 1)] = atand(tand(x[0]) / cose);
                if (x[0] > 90.0 and x[0] <= 270.0)
                    hsp.cusp[@intCast(i + 1)] = swe_degnorm(hsp.cusp[@intCast(i + 1)] + 180.0);
                hsp.cusp[@intCast(i + 1)] = swe_degnorm(hsp.cusp[@intCast(i + 1)]);
                hsp.cusp[@intCast(i + 7)] = swe_degnorm(hsp.cusp[@intCast(i + 1)] + 180.0);
            }
        },
        'V' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            hsp.cusp[1] = swe_degnorm(hsp.ac - 15.0);
            i = 2;
            while (i <= 12) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[1] + @as(f64, i - 1) * 30.0);
            if (hsp.do_hspeed) {
                i = 1;
                while (i <= 12) : (i += 1) {
                    hsp.cusp_speed[@intCast(i)] = hsp.ac_speed;
                }
            }
        },
        'W' => {
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
            }
            hsp.cusp[1] = hsp.ac - fmod(hsp.ac, 30.0);
            i = 2;
            while (i <= 12) : (i += 1)
                hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[1] + @as(f64, i - 1) * 30.0);
        },
        'X' => {
            var j: i32 = undefined;
            a = th;
            i = 1;
            while (i <= 12) : (i += 1) {
                j = i + 10;
                if (j > 12) j -= 12;
                a = swe_degnorm(a + 30.0);
                if (@abs(a - 90.0) > VERY_SMALL and
                    @abs(a - 270.0) > VERY_SMALL)
                {
                    tant = tand(a);
                    hsp.cusp[@intCast(j)] = atand(tant / cose);
                    if (a > 90.0 and a <= 270.0)
                        hsp.cusp[@intCast(j)] = swe_degnorm(hsp.cusp[@intCast(j)] + 180.0);
                } else {
                    if (@abs(a - 90.0) <= VERY_SMALL)
                        hsp.cusp[@intCast(j)] = 90.0
                    else
                        hsp.cusp[@intCast(j)] = 270.0;
                }
                hsp.cusp[@intCast(j)] = swe_degnorm(hsp.cusp[@intCast(j)]);
            }
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'M' => {
            var j: i32 = undefined;
            a = th;
            i = 1;
            while (i <= 12) : (i += 1) {
                j = i + 10;
                if (j > 12) j -= 12;
                a = swe_degnorm(a + 30.0);
                x[0] = a;
                x[1] = 0.0;
                swe_cotrans(&x, &x, ekl);
                hsp.cusp[@intCast(j)] = x[0];
            }
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'F' => {
            var ra: f64 = undefined;
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
            }
            x[0] = hsp.ac;
            x[1] = 0.0;
            swe_cotrans(&x, &x, -ekl);
            a = x[0];
            i = 2;
            while (i <= 12) : (i += 1) {
                if (i <= 3 or i >= 10) {
                    ra = swe_degnorm(a + @as(f64, i - 1) * 30.0);
                    if (@abs(ra - 90.0) > VERY_SMALL and
                        @abs(ra - 270.0) > VERY_SMALL)
                    {
                        tant = tand(ra);
                        hsp.cusp[@intCast(i)] = atand(tant / cose);
                        if (ra > 90.0 and ra <= 270.0)
                            hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                    } else {
                        if (@abs(ra - 90.0) <= VERY_SMALL)
                            hsp.cusp[@intCast(i)] = 90.0
                        else
                            hsp.cusp[@intCast(i)] = 270.0;
                    }
                    hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)]);
                }
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        'B' => {
            var dek: f64 = undefined;
            var r: f64 = undefined;
            var sna: f64 = undefined;
            var sda: f64 = undefined;
            var sd3: f64 = undefined;
            var sn3: f64 = undefined;
            acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            if (acmc < 0.0) {
                hsp.ac = swe_degnorm(hsp.ac + 180.0);
                hsp.cusp[1] = hsp.ac;
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
            }
            dek = asind(sind(hsp.ac) * sine);
            r = -tanfi * tand(dek);
            if (r > 1.0) r = 1.0;
            if (r < -1.0) r = -1.0;
            sda = acosd(r);
            sna = 180.0 - sda;
            sd3 = sda / 3.0;
            sn3 = sna / 3.0;
            rectasc = swe_degnorm(th + sd3);
            hsp.cusp[11] = Asc1(rectasc, 0.0, sine, cose);
            rectasc = swe_degnorm(th + 2.0 * sd3);
            hsp.cusp[12] = Asc1(rectasc, 0.0, sine, cose);
            rectasc = swe_degnorm(th + 180.0 - 2.0 * sn3);
            hsp.cusp[2] = Asc1(rectasc, 0.0, sine, cose);
            rectasc = swe_degnorm(th + 180.0 - sn3);
            hsp.cusp[3] = Asc1(rectasc, 0.0, sine, cose);
            hsp.do_interpol = hsp.do_hspeed;
        },
        'G' => {
            i = 1;
            while (i <= 36) : (i += 1) {
                hsp.cusp[@intCast(i)] = 0.0;
                hsp.cusp_speed[@intCast(i)] = 0.0;
            }
            if (@abs(fi) >= 90.0 - ekl) {
                retc = ERR;
                setSerr(&hsp.serr, "within polar circle, switched to Porphyry");
                hsy = 'O';
                continue :sw 'O';
            }
            a = asind(tanfi * tane);
            ih = 2;
            while (ih <= 9) : (ih += 1) {
                ih2 = 10 - ih;
                fh1 = atand(sind(a * @as(f64, @floatFromInt(ih2)) / 9.0) / tane);
                rectasc = swe_degnorm((90.0 / 9.0) * @as(f64, @floatFromInt(ih2)) + th);
                tant = tand(asind(sine * sind(Asc1(rectasc, fh1, sine, cose))));
                if (@abs(tant) < VERY_SMALL) {
                    hsp.cusp[@intCast(ih)] = rectasc;
                    if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = hsp.armc_speed;
                } else {
                    f = atand(sind(asind(tanfi * tant) * @as(f64, @floatFromInt(ih2)) / 9.0) / tant);
                    hsp.cusp[@intCast(ih)] = Asc1(rectasc, f, sine, cose);
                    cuspsv = 0.0;
                    i = 1;
                    while (i <= niter_max) : (i += 1) {
                        tant = tand(asind(sine * sind(hsp.cusp[@intCast(ih)])));
                        if (@abs(tant) < VERY_SMALL) {
                            hsp.cusp[@intCast(ih)] = rectasc;
                            if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = hsp.armc_speed;
                            break;
                        }
                        f = atand(sind(asind(tanfi * tant) * @as(f64, @floatFromInt(ih2)) / 9.0) / tant);
                        hsp.cusp[@intCast(ih)] = Asc1(rectasc, f, sine, cose);
                        if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[@intCast(ih)], cuspsv)) < VERY_SMALL_PLAC_ITER)
                            break;
                        cuspsv = hsp.cusp[@intCast(ih)];
                    }
                    if (i >= niter_max) {
                        retc = ERR;
                        setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                        hsy = 'O';
                        continue :sw 'O';
                    }
                    if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = AscDash(rectasc, f, sine, cose);
                }
                hsp.cusp[@intCast(ih + 18)] = swe_degnorm(hsp.cusp[@intCast(ih)] + 180.0);
                if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih + 18)] = hsp.cusp_speed[@intCast(ih)];
            }
            ih = 29;
            while (ih <= 36) : (ih += 1) {
                ih2 = ih - 28;
                fh1 = atand(sind(a * @as(f64, @floatFromInt(ih2)) / 9.0) / tane);
                rectasc = swe_degnorm(180.0 - @as(f64, @floatFromInt(ih2)) * 90.0 / 9.0 + th);
                tant = tand(asind(sine * sind(Asc1(rectasc, fh1, sine, cose))));
                if (@abs(tant) < VERY_SMALL) {
                    hsp.cusp[@intCast(ih)] = rectasc;
                    if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = hsp.armc_speed;
                } else {
                    f = atand(sind(asind(tanfi * tant) * @as(f64, @floatFromInt(ih2)) / 9.0) / tant);
                    hsp.cusp[@intCast(ih)] = Asc1(rectasc, f, sine, cose);
                    cuspsv = 0.0;
                    i = 1;
                    while (i <= niter_max) : (i += 1) {
                        tant = tand(asind(sine * sind(hsp.cusp[@intCast(ih)])));
                        if (@abs(tant) < VERY_SMALL) {
                            hsp.cusp[@intCast(ih)] = rectasc;
                            if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = hsp.armc_speed;
                            break;
                        }
                        f = atand(sind(asind(tanfi * tant) * @as(f64, @floatFromInt(ih2)) / 9.0) / tant);
                        hsp.cusp[@intCast(ih)] = Asc1(rectasc, f, sine, cose);
                        if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[@intCast(ih)], cuspsv)) < VERY_SMALL_PLAC_ITER)
                            break;
                        cuspsv = hsp.cusp[@intCast(ih)];
                    }
                    if (i >= niter_max) {
                        retc = ERR;
                        setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                        hsy = 'O';
                        continue :sw 'O';
                    }
                    if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih)] = AscDash(rectasc, f, sine, cose);
                }
                hsp.cusp[@intCast(ih - 18)] = swe_degnorm(hsp.cusp[@intCast(ih)] + 180.0);
                if (hsp.do_hspeed) hsp.cusp_speed[@intCast(ih - 18)] = hsp.cusp_speed[@intCast(ih)];
            }
            hsp.cusp[1] = hsp.ac;
            hsp.cusp[10] = hsp.mc;
            hsp.cusp[19] = swe_degnorm(hsp.ac + 180.0);
            hsp.cusp[28] = swe_degnorm(hsp.mc + 180.0);
            if (hsp.do_hspeed) {
                hsp.cusp_speed[1] = hsp.ac_speed;
                hsp.cusp_speed[10] = hsp.mc_speed;
                hsp.cusp_speed[19] = hsp.ac_speed;
                hsp.cusp_speed[28] = hsp.mc_speed;
            }
        },
        'Y' => {
            i = 1;
            while (i <= 12) : (i += 1) {
                hsp.cusp[@intCast(i)] = apc_sector(i, fi * DEGTORAD, ekl * DEGTORAD, th * DEGTORAD);
            }
            hsp.cusp[10] = hsp.mc;
            hsp.cusp[4] = swe_degnorm(hsp.mc + 180.0);
            if (@abs(fi) >= 90.0 - ekl) {
                acmc = swe_difdeg2n(hsp.ac, hsp.mc);
                if (acmc < 0.0) {
                    hsp.ac = swe_degnorm(hsp.ac + 180.0);
                    hsp.mc = swe_degnorm(hsp.mc + 180.0);
                    i = 1;
                    while (i <= 12) : (i += 1)
                        hsp.cusp[@intCast(i)] = swe_degnorm(hsp.cusp[@intCast(i)] + 180.0);
                }
            }
            hsp.do_interpol = hsp.do_hspeed;
        },
        else => {
            if (@abs(fi) >= 90.0 - ekl) {
                retc = ERR;
                setSerr(&hsp.serr, "within polar circle, switched to Porphyry");
                continue :sw 'O';
            }
            a = asind(tand(fi) * tane);
            fh1 = atand(sind(a / 3.0) / tane);
            fh2 = atand(sind(a * 2.0 / 3.0) / tane);
            // house 11
            rectasc = swe_degnorm(30.0 + th);
            tant = tand(asind(sine * sind(Asc1(rectasc, fh1, sine, cose))));
            if (@abs(tant) < VERY_SMALL) {
                hsp.cusp[11] = rectasc;
                if (hsp.do_hspeed) hsp.cusp_speed[11] = hsp.armc_speed;
            } else {
                f = atand(sind(asind(tanfi * tant) / 3.0) / tant);
                hsp.cusp[11] = Asc1(rectasc, f, sine, cose);
                cuspsv = 0.0;
                i = 1;
                while (i <= niter_max) : (i += 1) {
                    tant = tand(asind(sine * sind(hsp.cusp[11])));
                    if (@abs(tant) < VERY_SMALL) {
                        hsp.cusp[11] = rectasc;
                        if (hsp.do_hspeed) hsp.cusp_speed[11] = hsp.armc_speed;
                        break;
                    }
                    f = atand(sind(asind(tanfi * tant) / 3.0) / tant);
                    hsp.cusp[11] = Asc1(rectasc, f, sine, cose);
                    if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[11], cuspsv)) < VERY_SMALL_PLAC_ITER)
                        break;
                    cuspsv = hsp.cusp[11];
                }
                if (i >= niter_max) {
                    retc = ERR;
                    setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                    continue :sw 'O';
                }
                if (hsp.do_hspeed) hsp.cusp_speed[11] = AscDash(rectasc, f, sine, cose);
            }
            // house 12
            rectasc = swe_degnorm(60.0 + th);
            tant = tand(asind(sine * sind(Asc1(rectasc, fh2, sine, cose))));
            if (@abs(tant) < VERY_SMALL) {
                hsp.cusp[12] = rectasc;
                if (hsp.do_hspeed) hsp.cusp_speed[12] = hsp.armc_speed;
            } else {
                f = atand(sind(asind(tanfi * tant) / 1.5) / tant);
                hsp.cusp[12] = Asc1(rectasc, f, sine, cose);
                cuspsv = 0.0;
                i = 1;
                while (i <= niter_max) : (i += 1) {
                    tant = tand(asind(sine * sind(hsp.cusp[12])));
                    if (@abs(tant) < VERY_SMALL) {
                        hsp.cusp[12] = rectasc;
                        if (hsp.do_hspeed) hsp.cusp_speed[12] = hsp.armc_speed;
                        break;
                    }
                    f = atand(sind(asind(tanfi * tant) / 1.5) / tant);
                    hsp.cusp[12] = Asc1(rectasc, f, sine, cose);
                    if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[12], cuspsv)) < VERY_SMALL_PLAC_ITER)
                        break;
                    cuspsv = hsp.cusp[12];
                }
                if (i >= niter_max) {
                    retc = ERR;
                    setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                    continue :sw 'O';
                }
                if (hsp.do_hspeed) hsp.cusp_speed[12] = AscDash(rectasc, f, sine, cose);
            }
            // house 2
            rectasc = swe_degnorm(120.0 + th);
            tant = tand(asind(sine * sind(Asc1(rectasc, fh2, sine, cose))));
            if (@abs(tant) < VERY_SMALL) {
                hsp.cusp[2] = rectasc;
                if (hsp.do_hspeed) hsp.cusp_speed[2] = hsp.armc_speed;
            } else {
                f = atand(sind(asind(tanfi * tant) / 1.5) / tant);
                hsp.cusp[2] = Asc1(rectasc, f, sine, cose);
                cuspsv = 0.0;
                i = 1;
                while (i <= niter_max) : (i += 1) {
                    tant = tand(asind(sine * sind(hsp.cusp[2])));
                    if (@abs(tant) < VERY_SMALL) {
                        hsp.cusp[2] = rectasc;
                        if (hsp.do_hspeed) hsp.cusp_speed[2] = hsp.armc_speed;
                        break;
                    }
                    f = atand(sind(asind(tanfi * tant) / 1.5) / tant);
                    hsp.cusp[2] = Asc1(rectasc, f, sine, cose);
                    if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[2], cuspsv)) < VERY_SMALL_PLAC_ITER)
                        break;
                    cuspsv = hsp.cusp[2];
                }
                if (i >= niter_max) {
                    retc = ERR;
                    setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                    continue :sw 'O';
                }
                if (hsp.do_hspeed) hsp.cusp_speed[2] = AscDash(rectasc, f, sine, cose);
            }
            // house 3
            rectasc = swe_degnorm(150.0 + th);
            tant = tand(asind(sine * sind(Asc1(rectasc, fh1, sine, cose))));
            if (@abs(tant) < VERY_SMALL) {
                hsp.cusp[3] = rectasc;
                if (hsp.do_hspeed) hsp.cusp_speed[3] = hsp.armc_speed;
            } else {
                f = atand(sind(asind(tanfi * tant) / 3.0) / tant);
                hsp.cusp[3] = Asc1(rectasc, f, sine, cose);
                cuspsv = 0.0;
                i = 1;
                while (i <= niter_max) : (i += 1) {
                    tant = tand(asind(sine * sind(hsp.cusp[3])));
                    if (@abs(tant) < VERY_SMALL) {
                        hsp.cusp[3] = rectasc;
                        if (hsp.do_hspeed) hsp.cusp_speed[3] = hsp.armc_speed;
                        break;
                    }
                    f = atand(sind(asind(tanfi * tant) / 3.0) / tant);
                    hsp.cusp[3] = Asc1(rectasc, f, sine, cose);
                    if (i > 1 and @abs(swe_difdeg2n(hsp.cusp[3], cuspsv)) < VERY_SMALL_PLAC_ITER)
                        break;
                    cuspsv = hsp.cusp[3];
                }
                if (i >= niter_max) {
                    retc = ERR;
                    setSerr(&hsp.serr, "very close to polar circle, switched to Porphyry");
                    continue :sw 'O';
                }
                if (hsp.do_hspeed) hsp.cusp_speed[3] = AscDash(rectasc, f, sine, cose);
            }
        },
    }
    if (hsy != 'G' and hsy != 'Y' and std.ascii.toUpper(hsy) != 'I') {
        hsp.cusp[4] = swe_degnorm(hsp.cusp[10] + 180.0);
        hsp.cusp[5] = swe_degnorm(hsp.cusp[11] + 180.0);
        hsp.cusp[6] = swe_degnorm(hsp.cusp[12] + 180.0);
        hsp.cusp[7] = swe_degnorm(hsp.cusp[1] + 180.0);
        hsp.cusp[8] = swe_degnorm(hsp.cusp[2] + 180.0);
        hsp.cusp[9] = swe_degnorm(hsp.cusp[3] + 180.0);
        if (hsp.do_hspeed and !hsp.do_interpol) {
            hsp.cusp_speed[4] = hsp.cusp_speed[10];
            hsp.cusp_speed[5] = hsp.cusp_speed[11];
            hsp.cusp_speed[6] = hsp.cusp_speed[12];
            hsp.cusp_speed[7] = hsp.cusp_speed[1];
            hsp.cusp_speed[8] = hsp.cusp_speed[2];
            hsp.cusp_speed[9] = hsp.cusp_speed[3];
        }
    }
    if (fi >= 0.0)
        f = 90.0 - fi
    else
        f = -90.0 - fi;
    hsp.vertex = Asc1(th - 90.0, f, sine, cose);
    if (hsp.do_speed) hsp.vertex_speed = AscDash(th - 90.0, f, sine, cose);
    if (@abs(fi) <= ekl) {
        vemc = swe_difdeg2n(hsp.vertex, hsp.mc);
        if (vemc > 0.0)
            hsp.vertex = swe_degnorm(hsp.vertex + 180.0);
    }
    th2 = swe_degnorm(th + 90.0);
    if (@abs(th2 - 90.0) > VERY_SMALL and
        @abs(th2 - 270.0) > VERY_SMALL)
    {
        tant = tand(th2);
        hsp.equasc = atand(tant / cose);
        if (th2 > 90.0 and th2 <= 270.0)
            hsp.equasc = swe_degnorm(hsp.equasc + 180.0);
    } else {
        if (@abs(th2 - 90.0) <= VERY_SMALL)
            hsp.equasc = 90.0
        else
            hsp.equasc = 270.0;
    }
    hsp.equasc = swe_degnorm(hsp.equasc);
    if (hsp.do_speed) hsp.equasc_speed = AscDash(th + 90.0, 0.0, sine, cose);
    hsp.coasc1 = swe_degnorm(Asc1(th - 90.0, fi, sine, cose) + 180.0);
    if (hsp.do_speed) hsp.coasc1_speed = AscDash(th - 90.0, fi, sine, cose);
    if (fi >= 0.0) {
        hsp.coasc2 = Asc1(th + 90.0, 90.0 - fi, sine, cose);
        if (hsp.do_speed) hsp.coasc2_speed = AscDash(th + 90.0, 90.0 - fi, sine, cose);
    } else {
        hsp.coasc2 = Asc1(th + 90.0, -90.0 - fi, sine, cose);
        if (hsp.do_speed) hsp.coasc2_speed = AscDash(th + 90.0, -90.0 - fi, sine, cose);
    }
    hsp.polasc = Asc1(th - 90.0, fi, sine, cose);
    if (hsp.do_speed) hsp.polasc_speed = AscDash(th - 90.0, fi, sine, cose);
    return retc;
}

pub fn swe_cotrans(xpo: []const f64, xpn: []f64, eps: f64) void {
    var x: [3]f64 = undefined;
    x[0] = xpo[0] * DEGTORAD;
    x[1] = xpo[1] * DEGTORAD;
    x[2] = 1.0;
    lib.swi_polcart(&x, &x);
    lib.swi_coortrf(&x, &x, eps * DEGTORAD);
    lib.swi_cartpol(&x, &x);
    xpn[0] = x[0] * RADTODEG;
    xpn[1] = x[1] * RADTODEG;
    xpn[2] = xpo[2];
}

pub fn swe_houses_armc(
    armc: f64,
    geolat: f64,
    eps: f64,
    hsys: i32,
    cusp: *[37]f64,
    ascmc: *[10]f64,
    hctx: *HouseCtx,
) i32 {
    return swe_houses_armc_ex2(armc, geolat, eps, hsys, cusp, ascmc, null, null, null, hctx);
}

pub fn swe_houses_armc_ex2(
    armc: f64,
    geolat: f64,
    eps: f64,
    hsys: i32,
    cusp: *[37]f64,
    ascmc: *[10]f64,
    cusp_speed: ?*[37]f64,
    ascmc_speed: ?*[10]f64,
    serr: ?*[256]u8,
    hctx: *HouseCtx,
) i32 {
    var h: Houses = undefined;
    var hm1: Houses = undefined;
    var hp1: Houses = undefined;
    var i: usize = 0;
    var retc: i32 = 0;
    var rm1: i32 = 0;
    var rp1: i32 = 0;
    var ito: usize = 12;
    if (upper8(hsys) == 'G')
        ito = 36;
    const armc_norm = swe_degnorm(armc);
    h.do_speed = false;
    h.do_hspeed = false;
    if (ascmc_speed != null or cusp_speed != null)
        h.do_speed = true;
    if (cusp_speed != null)
        h.do_hspeed = true;
    if (upper8(hsys) == 'I') {
        if (ascmc[9] == 99.0) {
            h.sundec = 0.0;
            if (hctx.saved_sundec != 99.0) h.sundec = hctx.saved_sundec;
        } else {
            h.sundec = ascmc[9];
            hctx.saved_sundec = h.sundec;
        }
        if (h.sundec < -24.0 or h.sundec > 24.0) {
            if (serr != null) {
                setSerr(serr.?, "House system I (Sunshine) needs valid Sun declination in ascmc[9]");
            }
            return ERR;
        }
    }
    retc = CalcH(armc_norm, geolat, eps, @as(u8, @intCast(hsys)), &h);
    cusp[0] = 0.0;
    if (h.do_hspeed) cusp_speed.?[0] = 0.0;
    if (retc < 0) {
        ito = 12;
        if (serr != null) @memcpy(serr.?[0..], h.serr[0..]);
    }
    i = 1;
    while (i <= ito) {
        cusp[i] = h.cusp[i];
        if (h.do_hspeed) cusp_speed.?[i] = h.cusp_speed[i];
        i += 1;
    }
    ascmc[0] = h.ac;
    ascmc[1] = h.mc;
    ascmc[2] = armc_norm;
    ascmc[3] = h.vertex;
    ascmc[4] = h.equasc;
    ascmc[5] = h.coasc1;
    ascmc[6] = h.coasc2;
    ascmc[7] = h.polasc;
    i = 8;
    while (i < 10) {
        ascmc[i] = 0.0;
        i += 1;
    }
    if (upper8(hsys) == 'I')
        ascmc[9] = h.sundec;
    if (h.do_speed and ascmc_speed != null) {
        ascmc_speed.?[0] = h.ac_speed;
        ascmc_speed.?[1] = h.mc_speed;
        ascmc_speed.?[2] = h.armc_speed;
        ascmc_speed.?[3] = h.vertex_speed;
        ascmc_speed.?[4] = h.equasc_speed;
        ascmc_speed.?[5] = h.coasc1_speed;
        ascmc_speed.?[6] = h.coasc2_speed;
        ascmc_speed.?[7] = h.polasc_speed;
        i = 8;
        while (i < 10) {
            ascmc_speed.?[i] = 0.0;
            i += 1;
        }
    }
    if (h.do_interpol) {
        var dt: f64 = 1.0 / 86400.0;
        const darmc: f64 = dt * ARMCS;
        hm1.do_speed = false;
        hm1.do_hspeed = false;
        hp1.do_speed = false;
        hp1.do_hspeed = false;
        if (upper8(hsys) == 'I') {
            hm1.sundec = h.sundec;
            hp1.sundec = h.sundec;
        }
        rm1 = CalcH(armc_norm - darmc, geolat, eps, @as(u8, @intCast(hsys)), &hm1);
        rp1 = CalcH(armc_norm + darmc, geolat, eps, @as(u8, @intCast(hsys)), &hp1);
        if (rp1 >= 0 and rm1 >= 0) {
            if (@abs(swe_difdeg2n(hp1.ac, h.ac)) > 90.0) {
                hp1 = h;
                dt = dt / 2.0;
            } else if (@abs(swe_difdeg2n(hm1.ac, h.ac)) > 90.0) {
                hm1 = h;
                dt = dt / 2.0;
            }
            i = 1;
            while (i <= 12) {
                const dx = swe_difdeg2n(hp1.cusp[i], hm1.cusp[i]);
                cusp_speed.?[i] = dx / 2.0 / dt;
                i += 1;
            }
        }
    }
    return retc;
}

pub fn swe_house_name(hsys: i32) [*:0]const u8 {
    const h: i32 = if (hsys != 'i') upper8(hsys) else hsys;
    return switch (h) {
        'A' => "equal",
        'B' => "Alcabitius",
        'C' => "Campanus",
        'D' => "equal (MC)",
        'E' => "equal",
        'F' => "Carter poli-equ.",
        'G' => "Gauquelin sectors",
        'H' => "horizon/azimut",
        'I' => "Sunshine",
        'i' => "Sunshine/alt.",
        'J' => "Savard-A",
        'K' => "Koch",
        'L' => "Pullen SD",
        'M' => "Morinus",
        'N' => "equal/1=Aries",
        'O' => "Porphyry",
        'Q' => "Pullen SR",
        'R' => "Regiomontanus",
        'S' => "Sripati",
        'T' => "Polich/Page",
        'U' => "Krusinski-Pisa-Goelzer",
        'V' => "equal/Vehlow",
        'W' => "equal/ whole sign",
        'X' => "axial rotation system/Meridian houses",
        'Y' => "APC houses",
        else => "Placidus",
    };
}

fn apc_sector(n: i32, ph: f64, e: f64, az: f64) f64 {
    var is_below_hor: i32 = 0;
    var kv: f64 = undefined;
    var a: f64 = undefined;
    var dasc: f64 = undefined;
    var dret: f64 = undefined;
    if (@abs(ph * RADTODEG) > 90.0 - VERY_SMALL) {
        kv = 0.0;
        dasc = 0.0;
    } else {
        kv = swe_shim_atan(swe_shim_tan(ph) * swe_shim_tan(e) * swe_shim_cos(az) / (1.0 + swe_shim_tan(ph) * swe_shim_tan(e) * swe_shim_sin(az)));
        if (@abs(ph * RADTODEG) < VERY_SMALL) {
            dasc = (90.0 - VERY_SMALL) * DEGTORAD;
            if (ph < 0.0)
                dasc = -dasc;
        } else {
            dasc = swe_shim_atan(swe_shim_sin(kv) / swe_shim_tan(ph));
        }
    }
    var k: i32 = undefined;
    if (n < 8) {
        is_below_hor = 1;
        k = n - 1;
    } else {
        k = n - 13;
    }
    if (is_below_hor != 0) {
        a = kv + az + std.math.pi / 2.0 + @as(f64, k) * (std.math.pi / 2.0 - kv) / 3.0;
    } else {
        a = kv + az + std.math.pi / 2.0 + @as(f64, k) * (std.math.pi / 2.0 + kv) / 3.0;
    }
    a = swe_radnorm(a);
    dret = swe_shim_atan2(
        swe_shim_tan(dasc) * swe_shim_tan(ph) * swe_shim_sin(az) + swe_shim_sin(a),
        swe_shim_cos(e) * (swe_shim_tan(dasc) * swe_shim_tan(ph) * swe_shim_cos(az) + swe_shim_cos(a)) + swe_shim_sin(e) * swe_shim_tan(ph) * swe_shim_sin(az - a),
    );
    return swe_degnorm(dret * RADTODEG);
}

pub fn swe_house_pos(
    armc: f64,
    geolat_in: f64,
    eps: f64,
    hsys: i32,
    xpin: *const [6]f64,
    serr: ?*[256]u8,
    hctx: *HouseCtx,
) f64 {
    var geolat = geolat_in;
    var xp: [6]f64 = undefined;
    var xeq: [6]f64 = undefined;
    var ra: f64 = undefined;
    var de: f64 = undefined;
    var mdd: f64 = undefined;
    var mdn: f64 = undefined;
    var sad: f64 = undefined;
    var san: f64 = undefined;
    var hpos: f64 = undefined;
    var sinad: f64 = undefined;
    var ad: f64 = undefined;
    var a: f64 = undefined;
    var admc: f64 = undefined;
    var adp: f64 = undefined;
    var samc: f64 = undefined;
    var asc: f64 = undefined;
    var mc: f64 = undefined;
    var acmc: f64 = undefined;
    var tant: f64 = undefined;
    var fh: f64 = undefined;
    var ra0: f64 = undefined;
    var tanfi: f64 = undefined;
    var sinfi: f64 = undefined;
    var fac: f64 = undefined;
    var dfac: f64 = undefined;
    var tanx: f64 = undefined;
    var x: [3]f64 = undefined;
    var xasc: [3]f64 = undefined;
    var xs1: f64 = undefined;
    var xs2: f64 = undefined;
    var raep: f64 = undefined;
    var raaz: f64 = undefined;
    var oblaz: f64 = undefined;
    var xtemp: f64 = undefined;
    var hcusp: [37]f64 = undefined;
    var ascmc: [10]f64 = undefined;
    const sine = sind(eps);
    const cose = cosd(eps);
    var c1: f64 = undefined;
    var c2: f64 = undefined;
    var d: f64 = undefined;
    var hsize: f64 = undefined;
    var dsun: f64 = 0.0;
    var darmc: f64 = undefined;
    var harmc: f64 = undefined;
    var y: f64 = undefined;
    var sinpsi: f64 = undefined;
    var sa: f64 = undefined;
    var is_western_half: bool = false;
    var is_above_hor: bool = false;
    var is_invalid: bool = false;
    var is_circumpolar: bool = false;
    var i: usize = 0;
    var j: usize = 0;
    var nloop: i32 = 0;
    const hsys_upper = upper8(hsys);
    if (true) {
        ascmc[9] = 99.0;
        if (swe_houses_armc_ex2(armc, geolat, eps, hsys_upper, &hcusp, &ascmc, null, null, serr, hctx) == ERR) {
            if (serr != null)
                serrFailed(serr.?, hsys);
        } else {
            hpos = 0.0;
            i = 1;
            while (i <= 12) {
                if (@abs(swe_difdeg2n(xpin[0], hcusp[i])) < MILLIARCSEC and xpin[1] == 0.0) {
                    hpos = @as(f64, @floatFromInt(i));
                }
                i += 1;
            }
            i = 1;
            while (i <= 12) : (i += 3) {
                if (@abs(swe_difdeg2n(xpin[0], hcusp[i])) < MILLIARCSEC and xpin[1] == 0.0) {
                    xp[0] = @as(f64, @floatFromInt(i));
                }
            }
            if (hpos > 0.0)
                return hpos;
            if (hsys_upper == 'I')
                dsun = ascmc[9];
            if (hsys_upper == 'Y') {
                xeq[0] = ascmc[0];
                xeq[1] = 0.0;
                xeq[2] = 1.0;
                swe_cotrans(&xeq, &xeq, -eps);
                dsun = xeq[1];
            }
        }
    }
    if (serr != null)
        serr.?[0] = 0;
    xeq[0] = xpin[0];
    xeq[1] = xpin[1];
    xeq[2] = 1.0;
    swe_cotrans(&xeq, &xeq, -eps);
    ra = xeq[0];
    de = xeq[1];
    mdd = swe_degnorm(ra - armc);
    mdn = swe_degnorm(mdd + 180.0);
    if (mdd >= 180.0) mdd -= 360.0;
    if (mdn >= 180.0) mdn -= 360.0;
    switch (hsys_upper) {
        'N' => {
            xp[0] = xpin[0];
            hpos = xp[0] / 30.0 + 1.0;
        },
        'A', 'E', 'D', 'V', 'W' => {
            asc = Asc1(swe_degnorm(armc + 90.0), geolat, sine, cose);
            mc = armc_to_mc(armc, eps);
            asc = fix_asc_polar(asc, armc, eps, geolat);
            xp[0] = swe_degnorm(xpin[0] - asc);
            if (hsys_upper == 'V')
                xp[0] = swe_degnorm(xp[0] + 15.0);
            if (hsys_upper == 'W')
                xp[0] = swe_degnorm(xp[0] + fmod(asc, 30.0));
            if (hsys_upper == 'D')
                xp[0] = swe_degnorm(xpin[0] - mc - 90.0);
            xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            hpos = xp[0] / 30.0 + 1.0;
        },
        'O', 'B', 'S' => {
            asc = Asc1(swe_degnorm(armc + 90.0), geolat, sine, cose);
            mc = armc_to_mc(armc, eps);
            asc = fix_asc_polar(asc, armc, eps, geolat);
            if (hsys_upper == 'O' or hsys_upper == 'S') {
                xp[0] = swe_degnorm(xpin[0] - asc);
                xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
                if (xp[0] < 180.0)
                    hpos = 1.0
                else {
                    hpos = 7.0;
                    xp[0] -= 180.0;
                }
                acmc = swe_difdeg2n(asc, mc);
                if (xp[0] < 180.0 - acmc)
                    hpos += xp[0] * 3.0 / (180.0 - acmc)
                else
                    hpos += 3.0 + (xp[0] - 180.0 + acmc) * 3.0 / acmc;
                if (hsys_upper == 'S') {
                    hpos += 0.5;
                    if (hpos > 12.0) hpos = 1.0;
                }
            } else {
                const dek: f64 = asind(sind(asc) * sine);
                tanfi = tand(geolat);
                const r_val: f64 = -tanfi * tand(dek);
                const sda: f64 = swe_shim_acos(r_val) * RADTODEG;
                san = 180.0 - sda;
                if (mdd > 0.0) {
                    if (mdd < sda)
                        hpos = mdd * 90.0 / sda
                    else
                        hpos = 90.0 + (mdd - sda) * 90.0 / san;
                } else {
                    if (mdd > -san)
                        hpos = 360.0 + mdd * 90.0 / san
                    else
                        hpos = 270.0 + (mdd + san) * 90.0 / sda;
                }
                hpos = swe_degnorm(hpos - 90.0) / 30.0 + 1.0;
                if (hpos >= 13.0) hpos -= 12.0;
            }
        },
        'X' => {
            hpos = swe_degnorm(mdd - 90.0) / 30.0 + 1.0;
        },
        'F' => {
            x[0] = Asc1(swe_degnorm(armc + 90.0), geolat, sine, cose);
            x[0] = fix_asc_polar(x[0], armc, eps, geolat);
            x[1] = 0.0;
            swe_cotrans(&x, &x, -eps);
            hpos = swe_degnorm(ra - x[0]) / 30.0 + 1.0;
        },
        'M' => {
            const a_val: f64 = xpin[0];
            if (@abs(a_val - 90.0) > VERY_SMALL and
                @abs(a_val - 270.0) > VERY_SMALL)
            {
                tant = tand(a_val);
                hpos = atand(tant / cose);
                if (a_val > 90.0 and a_val <= 270.0)
                    hpos = swe_degnorm(hpos + 180.0);
            } else {
                if (@abs(a_val - 90.0) <= VERY_SMALL)
                    hpos = 90.0
                else
                    hpos = 270.0;
            }
            hpos = swe_degnorm(hpos - armc - 90.0);
            hpos = hpos / 30.0 + 1.0;
        },
        'K' => {
            is_invalid = false;
            is_circumpolar = false;
            if (90.0 - geolat < de or -90.0 - geolat > de) {
                adp = 90.0;
                is_circumpolar = true;
            } else if (geolat - 90.0 > de or geolat + 90.0 < de) {
                adp = -90.0;
                is_circumpolar = true;
            } else {
                adp = asind(tand(geolat) * tand(de));
            }
            admc = tand(eps) * tand(geolat) * sind(armc);
            if (@abs(admc) > 1.0) {
                if (admc > 1.0) admc = 1.0 else admc = -1.0;
                is_circumpolar = true;
            }
            admc = asind(admc);
            samc = 90.0 + admc;
            if (samc == 0.0)
                is_invalid = true;
            if (@abs(samc) > 0.0) {
                if (mdd >= 0.0) {
                    dfac = (mdd - adp + admc) / samc;
                    xp[0] = swe_degnorm((dfac - 1.0) * 90.0);
                    xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
                    if (dfac > 2.0 or dfac < 0.0)
                        is_invalid = true;
                } else {
                    dfac = (mdd + 180.0 + adp + admc) / samc;
                    xp[0] = swe_degnorm((dfac + 1.0) * 90.0);
                    xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
                    if (dfac > 2.0 or dfac < 0.0)
                        is_invalid = true;
                }
            }
            if (is_invalid) {
                xp[0] = 0.0;
                hpos = 0.0;
                if (serr != null)
                    setSerr(serr.?, "Koch house position failed in circumpolar area");
            } else {
                if (is_circumpolar) {
                    if (serr != null)
                        setSerr(serr.?, "Koch house position, doubtful result in circumpolar area");
                }
                hpos = xp[0] / 30.0 + 1.0;
            }
        },
        'C' => {
            xeq[0] = swe_degnorm(mdd - 90.0);
            swe_cotrans(&xeq, &xp, -geolat);
            xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            hpos = xp[0] / 30.0 + 1.0;
        },
        'J' => {
            sinfi = sind(geolat);
            if (@abs(geolat) < VERY_SMALL) {
                xs2 = 1.0 / 3.0;
                xs1 = 2.0 / 3.0;
            } else {
                xs2 = sind(geolat / 3.0) / sinfi;
                xs1 = sind(2.0 * geolat / 3.0) / sinfi;
            }
            xs2 = asind(xs2);
            xs1 = asind(xs1);
            hcusp[1] = 0.0;
            hcusp[2] = xs2;
            hcusp[3] = xs1;
            hcusp[4] = 90.0;
            hcusp[5] = 180.0 - xs1;
            hcusp[6] = 180.0 - xs2;
            hcusp[7] = 180.0;
            hcusp[8] = 180.0 + xs2;
            hcusp[9] = 180.0 + xs1;
            hcusp[10] = 270.0;
            hcusp[11] = 360.0 - xs1;
            hcusp[12] = 360.0 - xs2;
            xeq[0] = swe_degnorm(mdd - 90.0);
            swe_cotrans(&xeq, &xp, -geolat);
            a = xp[0];
            if (swe_difdeg2n(hcusp[6], hcusp[1]) > 0.0) {
                d = swe_degnorm(a - hcusp[1]);
                i = 1;
                while (i <= 12) {
                    j = i + 1;
                    if (j > 12)
                        c2 = 360.0
                    else
                        c2 = swe_degnorm(hcusp[j] - hcusp[1]);
                    if (d < c2) break;
                    i += 1;
                }
                c1 = swe_degnorm(hcusp[i] - hcusp[1]);
            } else {
                d = swe_degnorm(hcusp[1] - a);
                i = 1;
                while (i <= 12) {
                    j = i + 1;
                    if (j > 12)
                        c2 = 360.0
                    else
                        c2 = swe_degnorm(hcusp[1] - hcusp[j]);
                    if (d < c2) break;
                    i += 1;
                }
                c1 = swe_degnorm(hcusp[1] - hcusp[i]);
            }
            hsize = c2 - c1;
            if (hsize == 0.0) {
                hpos = @as(f64, @floatFromInt(i));
            } else {
                hpos = @as(f64, @floatFromInt(i)) + (d - c1) / hsize;
            }
        },
        'U' => {
            if (@abs(geolat) < VERY_SMALL) {
                if (geolat >= 0.0) geolat = VERY_SMALL else geolat = -VERY_SMALL;
            }
            asc = Asc1(swe_degnorm(armc + 90.0), geolat, sine, cose);
            asc = fix_asc_polar(asc, armc, eps, geolat);
            x[0] = asc;
            x[1] = 0.0;
            x[2] = 1.0;
            swe_cotrans(&x, &x, -eps);
            raep = swe_degnorm(armc + 90.0);
            x[0] = swe_degnorm(raep - x[0]);
            swe_cotrans(&x, &x, -(90.0 - geolat));
            tanx = tand(x[0]);
            if (geolat == 0.0) {
                xtemp = if (tanx >= 0.0) 90.0 else -90.0;
            } else {
                xtemp = atand(tanx / cosd(90.0 - geolat));
            }
            if (x[0] > 90.0 and x[0] <= 270.0)
                xtemp = swe_degnorm(xtemp + 180.0);
            x[0] = swe_degnorm(xtemp);
            raaz = swe_degnorm(raep - x[0]);
            x[0] = raaz;
            x[1] = 0.0;
            x[0] = swe_degnorm(raep - x[0]);
            swe_cotrans(&x, &x, -(90.0 - geolat));
            x[1] = x[1] + 90.0;
            swe_cotrans(&x, &x, 90.0 - geolat);
            oblaz = x[1];
            xasc[0] = asc;
            xasc[1] = 0.0;
            xasc[2] = 1.0;
            swe_cotrans(&xasc, &xasc, -eps);
            xasc[0] = swe_degnorm(xasc[0] - raaz);
            xtemp = atand(tand(xasc[0]) / cosd(oblaz));
            if (xasc[0] > 90.0 and xasc[0] <= 270.0)
                xtemp = swe_degnorm(xtemp + 180.0);
            xasc[0] = swe_degnorm(xtemp);
            xp[0] = swe_degnorm(xeq[0] - raaz);
            xtemp = atand(tand(xp[0]) / cosd(oblaz));
            if (xp[0] > 90.0 and xp[0] <= 270.0)
                xtemp = swe_degnorm(xtemp + 180.0);
            xp[0] = swe_degnorm(xtemp);
            xp[0] = swe_degnorm(xp[0] - xasc[0]);
            x[0] = xeq[0];
            x[1] = xeq[1];
            swe_cotrans(&x, &x, oblaz);
            xp[1] = xeq[1] - x[1];
            xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            hpos = xp[0] / 30.0 + 1.0;
        },
        'H' => {
            xeq[0] = swe_degnorm(mdd - 90.0);
            swe_cotrans(&xeq, &xp, 90.0 - geolat);
            xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            hpos = xp[0] / 30.0 + 1.0;
        },
        'R' => {
            if (@abs(mdd) < VERY_SMALL)
                xp[0] = 270.0
            else if (180.0 - @abs(mdd) < VERY_SMALL)
                xp[0] = 90.0
            else {
                if (90.0 - @abs(geolat) < VERY_SMALL) {
                    if (geolat > 0.0) geolat = 90.0 - VERY_SMALL else geolat = -90.0 + VERY_SMALL;
                }
                if (90.0 - @abs(de) < VERY_SMALL) {
                    if (de > 0.0) de = 90.0 - VERY_SMALL else de = -90.0 + VERY_SMALL;
                }
                a = tand(geolat) * tand(de) + cosd(mdd);
                xp[0] = swe_degnorm(atand(-a / sind(mdd)));
                if (mdd < 0.0) xp[0] += 180.0;
                xp[0] = swe_degnorm(xp[0]);
                xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            }
            hpos = xp[0] / 30.0 + 1.0;
        },
        'I', 'i', 'Y' => {
            if (geolat > 90.0 - MILLIARCSEC)
                geolat = 90.0 - MILLIARCSEC;
            if (geolat < -90.0 + MILLIARCSEC)
                geolat = -90.0 + MILLIARCSEC;
            if (90.0 - @abs(de) < VERY_SMALL) {
                if (de > 0.0) de = 90.0 - VERY_SMALL else de = -90.0 + VERY_SMALL;
            }
            a = tand(geolat) * tand(de) + cosd(mdd);
            xp[0] = swe_degnorm(atand(-a / sind(mdd)));
            if (mdd < 0.0) xp[0] += 180.0;
            xp[0] = swe_degnorm(xp[0]);
            sinad = tand(de) * tand(geolat);
            a = sinad + cosd(mdd);
            if (a >= 0.0) is_above_hor = true;
            harmc = 90.0 - geolat;
            if (geolat < 0.0) harmc = 90.0 + geolat;
            darmc = swe_degnorm(xp[0] - 270.0);
            if (darmc > 180.0) {
                is_western_half = true;
                darmc = 360.0 - darmc;
            }
            sinad = tand(dsun) * tand(geolat);
            if (sinad >= 1.0) {
                ad = 90.0;
            } else if (sinad <= -1.0) {
                ad = -90.0;
            } else {
                ad = asind(sinad);
            }
            sad = 90.0 + ad;
            san = 90.0 - ad;
            if (sad == 0.0 and is_above_hor) {
                xp[0] = 270.0;
            } else if (san == 0.0 and !is_above_hor) {
                xp[0] = 90.0;
            } else {
                sa = sad;
                if (!is_above_hor) {
                    dsun = -dsun;
                    sa = san;
                    darmc = 180.0 - darmc;
                    is_western_half = !is_western_half;
                }
                a = acosd(cosd(harmc) * cosd(darmc));
                if (a < VERY_SMALL) a = VERY_SMALL;
                sinpsi = sind(harmc) / sind(a);
                if (sinpsi > 1.0) sinpsi = 1.0;
                if (sinpsi < -1.0) sinpsi = -1.0;
                y = sind(dsun) / sinpsi;
                if (y > 1.0)
                    y = 90.0 - VERY_SMALL
                else if (y < -1.0)
                    y = -(90.0 - VERY_SMALL)
                else
                    y = asind(y);
                d = acosd(cosd(y) / cosd(dsun));
                if (dsun < 0.0) d = -d;
                if (geolat < 0.0) d = -d;
                darmc += d;
                if (is_western_half)
                    xp[0] = 270.0 - (darmc / sa) * 90.0
                else
                    xp[0] = 270.0 + (darmc / sa) * 90.0;
                if (!is_above_hor)
                    xp[0] = swe_degnorm(xp[0] + 180.0);
            }
            xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            hpos = xp[0] / 30.0 + 1.0;
        },
        'T' => {
            fh = geolat;
            if (fh > 89.999) fh = 89.999;
            if (fh < -89.999) fh = -89.999;
            mdd = swe_degnorm(mdd);
            if (de > 90.0 - VERY_SMALL) de = 90.0 - VERY_SMALL;
            if (de < -90.0 + VERY_SMALL) de = -90.0 + VERY_SMALL;
            sinad = tand(de) * tand(fh);
            if (sinad > 1.0) sinad = 1.0;
            if (sinad < -1.0) sinad = -1.0;
            a = sinad + cosd(mdd);
            if (a >= 0.0) is_above_hor = true;
            if (!is_above_hor) {
                ra = swe_degnorm(ra + 180.0);
                de = -de;
                mdd = swe_degnorm(mdd + 180.0);
            }
            if (mdd > 180.0) {
                ra = swe_degnorm(armc - mdd);
            }
            tanfi = tand(fh);
            ra0 = swe_degnorm(armc + 90.0);
            xp[1] = 1.0;
            xeq[1] = de;
            fac = 2.0;
            nloop = 0;
            while (@abs(xp[1]) > 0.000001 and nloop < 1000) {
                if (xp[1] > 0.0) {
                    fh = atand(tand(fh) - tanfi / fac);
                    ra0 -= 90.0 / fac;
                } else {
                    fh = atand(tand(fh) + tanfi / fac);
                    ra0 += 90.0 / fac;
                }
                xeq[0] = swe_degnorm(ra - ra0);
                swe_cotrans(&xeq, &xp, 90.0 - fh);
                fac *= 2.0;
                nloop += 1;
            }
            hpos = swe_degnorm(ra0 - armc);
            if (mdd > 180.0)
                hpos = swe_degnorm(-hpos);
            if (!is_above_hor)
                hpos = swe_degnorm(hpos + 180.0);
            hpos = swe_degnorm(hpos - 90.0) / 30.0 + 1.0;
        },
        'P', 'G' => {
            if (90.0 - @abs(de) <= @abs(geolat)) {
                if (de * geolat < 0.0)
                    xp[0] = swe_degnorm(90.0 + mdn / 2.0)
                else
                    xp[0] = swe_degnorm(270.0 + mdd / 2.0);
                if (serr != null)
                    setSerr(serr.?, "Otto Ludwig procedure within circumpolar regions.");
            } else {
                sinad = tand(de) * tand(geolat);
                ad = asind(sinad);
                a = sinad + cosd(mdd);
                if (a >= 0.0) is_above_hor = true;
                sad = 90.0 + ad;
                san = 90.0 - ad;
                if (is_above_hor)
                    xp[0] = (mdd / sad + 3.0) * 90.0
                else
                    xp[0] = (mdn / san + 1.0) * 90.0;
                xp[0] = swe_degnorm(xp[0] + MILLIARCSEC);
            }
            if (hsys_upper == 'G') {
                xp[0] = 360.0 - xp[0];
                hpos = xp[0] / 10.0 + 1.0;
            } else {
                hpos = xp[0] / 30.0 + 1.0;
            }
        },
        else => {
            hpos = 0.0;
            if (swe_houses_armc_ex2(armc, geolat, eps, hsys_upper, &hcusp, &ascmc, null, null, serr, hctx) == ERR) {
                if (serr != null)
                    serrFailed(serr.?, hsys);
            } else {
                if (swe_difdeg2n(hcusp[6], hcusp[1]) > 0.0) {
                    d = swe_degnorm(xpin[0] - hcusp[1]);
                    i = 1;
                    while (i <= 12) {
                        j = i + 1;
                        if (j > 12)
                            c2 = 360.0
                        else
                            c2 = swe_degnorm(hcusp[j] - hcusp[1]);
                        if (d < c2) break;
                        i += 1;
                    }
                    c1 = swe_degnorm(hcusp[i] - hcusp[1]);
                } else {
                    d = swe_degnorm(hcusp[1] - xpin[0]);
                    i = 1;
                    while (i <= 12) {
                        j = i + 1;
                        if (j > 12)
                            c2 = 360.0
                        else
                            c2 = swe_degnorm(hcusp[1] - hcusp[j]);
                        if (d < c2) break;
                        i += 1;
                    }
                    c1 = swe_degnorm(hcusp[1] - hcusp[i]);
                }
                hsize = c2 - c1;
                if (hsize == 0.0) {
                    hpos = @as(f64, @floatFromInt(i));
                } else {
                    hpos = @as(f64, @floatFromInt(i)) + (d - c1) / hsize;
                }
                if (serr != null)
                    serrSimplified(serr.?, hsys);
            }
        },
    }
    return hpos;
}

test {
    std.testing.refAllDecls(@This());
}
