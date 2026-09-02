// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port --- Delta-T module.
// Translated 1:1 from swephlib.c (swe_deltat_ex / calc_deltat and the
// delta-T model + tidal-acceleration helpers) to preserve exact operation
// order, differential-tested against the C oracle.
const std = @import("std");
const tbl = @import("tables_deltat.zig");

pub const SEFLG_JPLEPH: i32 = 1;
pub const SEFLG_SWIEPH: i32 = 2;
pub const SEFLG_MOSEPH: i32 = 4;
pub const SEFLG_EPHMASK: i32 = SEFLG_JPLEPH | SEFLG_SWIEPH | SEFLG_MOSEPH;
pub const J2000: f64 = 2451545.0;

pub const SE_TIDAL_DE200: f64 = -23.8946;
pub const SE_TIDAL_DE403: f64 = -25.580;
pub const SE_TIDAL_DE404: f64 = -25.580;
pub const SE_TIDAL_DE405: f64 = -25.826;
pub const SE_TIDAL_DE406: f64 = -25.826;
pub const SE_TIDAL_DE421: f64 = -25.85;
pub const SE_TIDAL_DE422: f64 = -25.85;
pub const SE_TIDAL_DE430: f64 = -25.82;
pub const SE_TIDAL_DE431: f64 = -25.80;
pub const SE_TIDAL_DE441: f64 = -25.936;
pub const SE_TIDAL_26: f64 = -26.0;
pub const SE_TIDAL_STEPHENSON_2016: f64 = -25.85;
pub const SE_TIDAL_DEFAULT: f64 = SE_TIDAL_DE431;
pub const SE_DE_NUMBER: i32 = 431;

pub const SEMOD_DELTAT_STEPHENSON_MORRISON_1984: i32 = 1;
pub const SEMOD_DELTAT_STEPHENSON_1997: i32 = 2;
pub const SEMOD_DELTAT_STEPHENSON_MORRISON_2004: i32 = 3;
pub const SEMOD_DELTAT_ESPENAK_MEEUS_2006: i32 = 4;
pub const SEMOD_DELTAT_STEPHENSON_ETC_2016: i32 = 5;
pub const SEMOD_DELTAT_DEFAULT: i32 = SEMOD_DELTAT_STEPHENSON_ETC_2016;

const TABSTART: i32 = 1620;
const TABEND: i32 = 2028;
const TABSIZ: i32 = TABEND - TABSTART + 1;
const TAB2_START: i32 = -1000;
const TAB2_END: i32 = 1600;
const TAB2_STEP: i32 = 100;
const TAB97_START: i32 = -500;
const TAB97_END: i32 = 1600;
const TAB97_STEP: i32 = 50;
const NDTCF16: i32 = 54;

/// Minimal model of the `swed` global that the Delta-T code touches.
pub const DeltatCtx = struct {
    delta_t_userdef_is_set: bool = false,
    delta_t_userdef: f64 = 0.0,
    astro_model_deltat: i32 = 0, // swed.astro_models[SE_MODEL_DELTAT]
    is_tid_acc_manual: bool = false,
    tid_acc: f64 = 0.0,
    init_dt_done: bool = false,
    jpl_file_is_open: bool = false,
    jpldenum: i32 = 0,
    sweph_denum: i32 = 0, // swed.fidat[SEI_FILE_MOON].sweph_denum (0 = no file open)
};

pub fn swe_deltat_ex(ctx: *DeltatCtx, tjd: f64, iflag: i32) f64 {
    if (ctx.delta_t_userdef_is_set)
        return ctx.delta_t_userdef;
    const dt = calc_deltat(ctx, tjd, iflag);
    return dt.deltat;
}

const CalcResult = struct { deltat: f64, iflag: i32 };

fn calc_deltat(ctx: *DeltatCtx, tjd: f64, iflag_in: i32) CalcResult {
    var iflag: i32 = iflag_in;
    var ans: f64 = 0;
    var B: f64 = 0;
    var Y: f64 = 0;
    var Ygreg: f64 = 0;
    var dd: f64 = 0;
    var iy: i32 = 0;
    var retc: i32 = 0;
    var deltat_model: i32 = ctx.astro_model_deltat;
    var tid_acc: f64 = 0;
    var denumret: i32 = 0;
    var epheflag: i32 = 0;
    var otherflag: i32 = 0;
    if (deltat_model == 0) deltat_model = SEMOD_DELTAT_DEFAULT;
    epheflag = iflag & SEFLG_EPHMASK;
    otherflag = iflag & ~SEFLG_EPHMASK;
    if (iflag == -1) {
        retc = swi_get_tid_acc(ctx, tjd, 0, 9999, &denumret, &tid_acc);
    } else {
        var denum: i32 = ctx.jpldenum;
        if (epheflag & SEFLG_SWIEPH != 0) denum = ctx.sweph_denum;
        retc = swi_set_tid_acc_path(ctx, tjd, epheflag, denum);
        tid_acc = ctx.tid_acc;
    }
    iflag = otherflag | retc;
    Y = 2000.0 + (tjd - J2000) / 365.25;
    Ygreg = 2000.0 + (tjd - J2000) / 365.2425;
    if (deltat_model == SEMOD_DELTAT_STEPHENSON_ETC_2016 and tjd < 2435108.5) {
        ans = deltat_stephenson_etc_2016(tjd, tid_acc);
        if (tjd >= 2434108.5)
            ans += (1.0 - (2435108.5 - tjd) / 1000.0) * 0.6610218 / 86400.0;
        return .{ .deltat = ans, .iflag = iflag };
    }
    if (deltat_model == SEMOD_DELTAT_ESPENAK_MEEUS_2006 and tjd < 2317746.13090277789) {
        ans = deltat_espenak_meeus_1620(tjd, tid_acc);
        return .{ .deltat = ans, .iflag = iflag };
    }
    if (deltat_model == SEMOD_DELTAT_STEPHENSON_MORRISON_2004 and Y < @as(f64, @floatFromInt(TABSTART))) {
        if (Y < @as(f64, @floatFromInt(TAB2_END))) {
            ans = deltat_stephenson_morrison_2004_1600(tjd, tid_acc);
            return .{ .deltat = ans, .iflag = iflag };
        } else {
            if (Y >= @as(f64, @floatFromInt(TAB2_END))) {
                B = @as(f64, @floatFromInt(TABSTART - TAB2_END));
                iy = @divTrunc(TAB2_END - TAB2_START, TAB2_STEP);
                dd = (Y - @as(f64, @floatFromInt(TAB2_END))) / B;
                ans = @as(f64, @floatFromInt(tbl.dt2[@intCast(iy)])) + dd * (tbl.dt[0] - @as(f64, @floatFromInt(tbl.dt2[@intCast(iy)])));
                ans = adjust_for_tidacc(ans, Ygreg, tid_acc, SE_TIDAL_26, false);
                return .{ .deltat = ans / 86400.0, .iflag = iflag };
            }
        }
    }
    if (deltat_model == SEMOD_DELTAT_STEPHENSON_1997 and Y < @as(f64, @floatFromInt(TABSTART))) {
        if (Y < @as(f64, @floatFromInt(TAB97_END))) {
            ans = deltat_stephenson_morrison_1997_1600(tjd, tid_acc);
            return .{ .deltat = ans, .iflag = iflag };
        } else {
            if (Y >= @as(f64, @floatFromInt(TAB97_END))) {
                B = @as(f64, @floatFromInt(TABSTART - TAB97_END));
                iy = @divTrunc(TAB97_END - TAB97_START, TAB97_STEP);
                dd = (Y - @as(f64, @floatFromInt(TAB97_END))) / B;
                ans = @as(f64, @floatFromInt(tbl.dt97[@intCast(iy)])) + dd * (tbl.dt[0] - @as(f64, @floatFromInt(tbl.dt97[@intCast(iy)])));
                ans = adjust_for_tidacc(ans, Ygreg, tid_acc, SE_TIDAL_26, false);
                return .{ .deltat = ans / 86400.0, .iflag = iflag };
            }
        }
    }
    if (deltat_model == SEMOD_DELTAT_STEPHENSON_MORRISON_1984 and Y < @as(f64, @floatFromInt(TABSTART))) {
        if (Y >= 948.0) {
            B = 0.01 * (Y - 2000.0);
            ans = (23.58 * B + 100.3) * B + 101.6;
        } else {
            B = 0.01 * (Y - 2000.0) + 3.75;
            ans = 35.0 * B * B + 40.0;
        }
        return .{ .deltat = ans / 86400.0, .iflag = iflag };
    }
    if (Y >= @as(f64, @floatFromInt(TABSTART))) {
        ans = deltat_aa(ctx, tjd, tid_acc);
        return .{ .deltat = ans, .iflag = iflag };
    }
    return .{ .deltat = ans / 86400.0, .iflag = iflag };
}

fn swi_get_tid_acc(ctx: *DeltatCtx, tjd_ut: f64, iflag: i32, denum_in: i32, denumret: *i32, tid_acc: *f64) i32 {
    _ = tjd_ut;
    var ifl2: i32 = iflag & SEFLG_EPHMASK;
    if (ctx.is_tid_acc_manual) {
        tid_acc.* = ctx.tid_acc;
        return ifl2;
    }
    var denum: i32 = denum_in;
    if (denum == 0) {
        if (ifl2 & SEFLG_MOSEPH != 0) {
            tid_acc.* = SE_TIDAL_DE404;
            denumret.* = 404;
            return ifl2;
        }
        if (ifl2 & SEFLG_JPLEPH != 0) {
            if (ctx.jpl_file_is_open)
                denum = ctx.jpldenum;
        }
        if (ifl2 & SEFLG_SWIEPH != 0) {
            if (ctx.sweph_denum != 0)
                denum = ctx.sweph_denum;
        }
    }
    switch (denum) {
        200 => tid_acc.* = SE_TIDAL_DE200,
        403 => tid_acc.* = SE_TIDAL_DE403,
        404 => tid_acc.* = SE_TIDAL_DE404,
        405 => tid_acc.* = SE_TIDAL_DE405,
        406 => tid_acc.* = SE_TIDAL_DE406,
        421 => tid_acc.* = SE_TIDAL_DE421,
        422 => tid_acc.* = SE_TIDAL_DE422,
        430 => tid_acc.* = SE_TIDAL_DE430,
        431 => tid_acc.* = SE_TIDAL_DE431,
        440 => tid_acc.* = SE_TIDAL_DE441,
        441 => tid_acc.* = SE_TIDAL_DE441,
        else => {
            denum = SE_DE_NUMBER;
            tid_acc.* = SE_TIDAL_DEFAULT;
        },
    }
    denumret.* = denum;
    ifl2 &= SEFLG_EPHMASK;
    return ifl2;
}

fn swi_set_tid_acc_path(ctx: *DeltatCtx, tjd_ut: f64, iflag: i32, denum: i32) i32 {
    var retc: i32 = iflag;
    var denumret: i32 = 0;
    if (ctx.is_tid_acc_manual)
        return retc;
    retc = swi_get_tid_acc(ctx, tjd_ut, iflag, denum, &denumret, &ctx.tid_acc);
    return retc;
}

fn adjust_for_tidacc(ans: f64, Y: f64, tid_acc: f64, tid_acc0: f64, adjust_after_1955: bool) f64 {
    var ans2 = ans;
    if (Y < 1955.0 or adjust_after_1955) {
        const B = Y - 1955.0;
        ans2 += -0.000091 * (tid_acc - tid_acc0) * B * B;
    }
    return ans2;
}

fn init_dt(ctx: *DeltatCtx) i32 {
    if (!ctx.init_dt_done) {
        ctx.init_dt_done = true;
        // External swe_deltat.txt is not loaded in the port harness, matching
        // the oracle's swi_fopen()==NULL stub: use the built-in table.
        return TABSIZ;
    }
    return TABSIZ;
}

fn deltat_aa(ctx: *DeltatCtx, tjd: f64, tid_acc: f64) f64 {
    var ans: f64 = 0;
    var ans2: f64 = 0;
    var ans3: f64 = 0;
    var p: f64 = 0;
    var B: f64 = 0;
    var B2: f64 = 0;
    var Y: f64 = 0;
    var dd: f64 = 0;
    var d: [6]f64 = undefined;
    var i: usize = 0;
    var iy: i32 = 0;
    var k: i32 = 0;
    const tabsiz = init_dt(ctx);
    const tabend = TABSTART + tabsiz - 1;
    var deltat_model: i32 = ctx.astro_model_deltat;
    if (deltat_model == 0) deltat_model = SEMOD_DELTAT_DEFAULT;
    Y = 2000.0 + (tjd - 2451544.5) / 365.25;
    if (Y <= @as(f64, @floatFromInt(tabend))) {
        p = @floor(Y);
        iy = @intFromFloat(p - @as(f64, @floatFromInt(TABSTART)));
        ans = tbl.dt[@intCast(iy)];
        k = iy + 1;
        if (!(k >= tabsiz)) {
            p = Y - p;
            ans += p * (tbl.dt[@intCast(k)] - tbl.dt[@intCast(iy)]);
            if (!((iy - 1 < 0) or (iy + 2 >= tabsiz))) {
                k = iy - 2;
                i = 0;
                while (i < 5) : (i += 1) {
                    if ((k < 0) or (k + 1 >= tabsiz))
                        d[i] = 0
                    else
                        d[i] = tbl.dt[@intCast(k + 1)] - tbl.dt[@intCast(k)];
                    k += 1;
                }
                i = 0;
                while (i < 4) : (i += 1) d[i] = d[i + 1] - d[i];
                B = 0.25 * p * (p - 1.0);
                ans += B * (d[1] + d[2]);
                if (!(iy + 2 >= tabsiz)) {
                    i = 0;
                    while (i < 3) : (i += 1) d[i] = d[i + 1] - d[i];
                    B = 2.0 * B / 3.0;
                    ans += (p - 0.5) * B * d[1];
                    if (!((iy - 2 < 0) or (iy + 3 > tabsiz))) {
                        i = 0;
                        while (i < 2) : (i += 1) d[i] = d[i + 1] - d[i];
                        B = 0.125 * B * (p + 1.0) * (p - 2.0);
                        ans += B * (d[0] + d[1]);
                    }
                }
            }
        }
        ans = adjust_for_tidacc(ans, Y, tid_acc, SE_TIDAL_26, false);
        return ans / 86400.0;
    }
    if (deltat_model == SEMOD_DELTAT_STEPHENSON_ETC_2016) {
        B = Y - 2000.0;
        if (Y < 2500.0) {
            ans = B * B * B * 121.0 / 30000000.0 + B * B / 1250.0 + B * 521.0 / 3000.0 + 64.0;
            B2 = @as(f64, @floatFromInt(tabend)) - 2000.0;
            ans2 = B2 * B2 * B2 * 121.0 / 30000000.0 + B2 * B2 / 1250.0 + B2 * 521.0 / 3000.0 + 64.0;
        } else {
            B = 0.01 * (Y - 2000.0);
            ans = B * B * 32.5 + 42.5;
        }
    } else {
        B = 0.01 * (Y - 1820.0);
        ans = -20 + 31 * B * B;
        B2 = 0.01 * (@as(f64, @floatFromInt(tabend)) - 1820.0);
        ans2 = -20 + 31 * B2 * B2;
    }
    if (Y <= @as(f64, @floatFromInt(tabend)) + 100.0) {
        ans3 = tbl.dt[@intCast(tabsiz - 1)];
        dd = ans2 - ans3;
        ans += dd * (Y - (@as(f64, @floatFromInt(tabend)) + 100.0)) * 0.01;
    }
    return ans / 86400.0;
}

fn deltat_stephenson_etc_2016(tjd: f64, tid_acc: f64) f64 {
    var dt: f64 = 0;
    var t: f64 = 0;
    var Ygreg: f64 = 0;
    var irec: i32 = -1;
    Ygreg = 2000.0 + (tjd - J2000) / 365.2425;
    blk: {
        var i: usize = 0;
        while (i < @as(usize, @intCast(NDTCF16))) : (i += 1) {
            if (tjd < tbl.dtcf16[i][0]) break :blk;
            if (tjd < tbl.dtcf16[i][1]) {
                irec = @intCast(i);
                break :blk;
            }
        }
    }
    if (irec >= 0) {
        t = (tjd - tbl.dtcf16[@intCast(irec)][0]) / (tbl.dtcf16[@intCast(irec)][1] - tbl.dtcf16[@intCast(irec)][0]);
        dt = tbl.dtcf16[@intCast(irec)][2] + tbl.dtcf16[@intCast(irec)][3] * t +
            tbl.dtcf16[@intCast(irec)][4] * t * t + tbl.dtcf16[@intCast(irec)][5] * t * t * t;
    } else if (Ygreg < -720.0) {
        t = (Ygreg - 1825.0) / 100.0;
        dt = -320 + 32.5 * t * t;
        dt -= 179.7337208;
    } else {
        t = (Ygreg - 1825.0) / 100.0;
        dt = -320 + 32.5 * t * t;
        dt += 269.4790417;
    }
    dt = adjust_for_tidacc(dt, Ygreg, tid_acc, SE_TIDAL_STEPHENSON_2016, true);
    dt /= 86400.0;
    return dt;
}

fn deltat_stephenson_morrison_1997_1600(tjd: f64, tid_acc: f64) f64 {
    var ans: f64 = 0;
    var ans2: f64 = 0;
    var ans3: f64 = 0;
    var p: f64 = 0;
    var B: f64 = 0;
    var Y: f64 = 0;
    var dd: f64 = 0;
    var iy: i32 = 0;
    Y = 2000.0 + (tjd - J2000) / 365.25;
    if (Y < @as(f64, @floatFromInt(TAB97_START))) {
        B = (Y - 1735.0) * 0.01;
        ans = -20 + 35 * B * B;
        ans = adjust_for_tidacc(ans, Y, tid_acc, SE_TIDAL_26, false);
        if (Y >= @as(f64, @floatFromInt(TAB97_START)) - 100.0) {
            ans2 = adjust_for_tidacc(@as(f64, @floatFromInt(tbl.dt97[0])), @as(f64, @floatFromInt(TAB97_START)), tid_acc, SE_TIDAL_26, false);
            B = @as(f64, @floatFromInt(TAB97_START - 1735)) * 0.01;
            ans3 = -20 + 35 * B * B;
            ans3 = adjust_for_tidacc(ans3, Y, tid_acc, SE_TIDAL_26, false);
            dd = ans3 - ans2;
            B = (Y - (@as(f64, @floatFromInt(TAB97_START)) - 100.0)) * 0.01;
            ans = ans - dd * B;
        }
    }
    if (Y >= @as(f64, @floatFromInt(TAB97_START)) and Y < @as(f64, @floatFromInt(TAB2_END))) {
        p = @floor(Y);
        iy = @intFromFloat((p - @as(f64, @floatFromInt(TAB97_START))) / 50.0);
        dd = (Y - @as(f64, @floatFromInt(TAB97_START + 50 * iy))) / 50.0;
        ans = @as(f64, @floatFromInt(tbl.dt97[@intCast(iy)])) +
            (@as(f64, @floatFromInt(tbl.dt97[@intCast(iy + 1)])) - @as(f64, @floatFromInt(tbl.dt97[@intCast(iy)]))) * dd;
        ans = adjust_for_tidacc(ans, Y, tid_acc, SE_TIDAL_26, false);
    }
    ans /= 86400.0;
    return ans;
}

fn deltat_stephenson_morrison_2004_1600(tjd: f64, tid_acc: f64) f64 {
    var ans: f64 = 0;
    var ans2: f64 = 0;
    var ans3: f64 = 0;
    var p: f64 = 0;
    var B: f64 = 0;
    var dd: f64 = 0;
    var tjd0: f64 = 0;
    var iy: i32 = 0;
    const Y = 2000.0 + (tjd - J2000) / 365.2425;
    if (Y < @as(f64, @floatFromInt(TAB2_START))) {
        ans = deltat_longterm_morrison_stephenson(tjd);
        ans = adjust_for_tidacc(ans, Y, tid_acc, SE_TIDAL_26, false);
        if (Y >= @as(f64, @floatFromInt(TAB2_START)) - 100.0) {
            ans2 = adjust_for_tidacc(@as(f64, @floatFromInt(tbl.dt2[0])), @as(f64, @floatFromInt(TAB2_START)), tid_acc, SE_TIDAL_26, false);
            tjd0 = (@as(f64, @floatFromInt(TAB2_START)) - 2000.0) * 365.2425 + J2000;
            ans3 = deltat_longterm_morrison_stephenson(tjd0);
            ans3 = adjust_for_tidacc(ans3, Y, tid_acc, SE_TIDAL_26, false);
            dd = ans3 - ans2;
            B = (Y - (@as(f64, @floatFromInt(TAB2_START)) - 100.0)) * 0.01;
            ans = ans - dd * B;
        }
    }
    if (Y >= @as(f64, @floatFromInt(TAB2_START)) and Y < @as(f64, @floatFromInt(TAB2_END))) {
        const Yjul = 2000 + (tjd - 2451557.5) / 365.25;
        p = @floor(Yjul);
        iy = @intFromFloat((p - @as(f64, @floatFromInt(TAB2_START))) / @as(f64, @floatFromInt(TAB2_STEP)));
        dd = (Yjul - @as(f64, @floatFromInt(TAB2_START + TAB2_STEP * iy))) / @as(f64, @floatFromInt(TAB2_STEP));
        ans = @as(f64, @floatFromInt(tbl.dt2[@intCast(iy)])) +
            (@as(f64, @floatFromInt(tbl.dt2[@intCast(iy + 1)])) - @as(f64, @floatFromInt(tbl.dt2[@intCast(iy)]))) * dd;
        ans = adjust_for_tidacc(ans, Y, tid_acc, SE_TIDAL_26, false);
    }
    ans /= 86400.0;
    return ans;
}

fn deltat_espenak_meeus_1620(tjd: f64, tid_acc: f64) f64 {
    var ans: f64 = 0;
    var u: f64 = 0;
    const Ygreg = 2000.0 + (tjd - J2000) / 365.2425;
    if (Ygreg < -500) {
        ans = deltat_longterm_morrison_stephenson(tjd);
    } else if (Ygreg < 500) {
        u = Ygreg / 100.0;
        ans = (((((0.0090316521 * u + 0.022174192) * u - 0.1798452) * u - 5.952053) * u + 33.78311) * u - 1014.41) * u + 10583.6;
    } else if (Ygreg < 1600) {
        u = (Ygreg - 1000) / 100.0;
        ans = (((((0.0083572073 * u - 0.005050998) * u - 0.8503463) * u + 0.319781) * u + 71.23472) * u - 556.01) * u + 1574.2;
    } else if (Ygreg < 1700) {
        u = Ygreg - 1600;
        ans = 120 - 0.9808 * u - 0.01532 * u * u + u * u * u / 7129.0;
    } else if (Ygreg < 1800) {
        u = Ygreg - 1700;
        ans = (((-u / 1174000.0 + 0.00013336) * u - 0.0059285) * u + 0.1603) * u + 8.83;
    } else if (Ygreg < 1860) {
        u = Ygreg - 1800;
        ans = ((((((0.000000000875 * u - 0.0000001699) * u + 0.0000121272) * u - 0.00037436) * u + 0.0041116) * u + 0.0068612) * u - 0.332447) * u + 13.72;
    } else if (Ygreg < 1900) {
        u = Ygreg - 1860;
        ans = ((((u / 233174.0 - 0.0004473624) * u + 0.01680668) * u - 0.251754) * u + 0.5737) * u + 7.62;
    } else if (Ygreg < 1920) {
        u = Ygreg - 1900;
        ans = (((-0.000197 * u + 0.0061966) * u - 0.0598939) * u + 1.494119) * u - 2.79;
    } else if (Ygreg < 1941) {
        u = Ygreg - 1920;
        ans = 21.20 + 0.84493 * u - 0.076100 * u * u + 0.0020936 * u * u * u;
    } else if (Ygreg < 1961) {
        u = Ygreg - 1950;
        ans = 29.07 + 0.407 * u - u * u / 233.0 + u * u * u / 2547.0;
    } else if (Ygreg < 1986) {
        u = Ygreg - 1975;
        ans = 45.45 + 1.067 * u - u * u / 260.0 - u * u * u / 718.0;
    } else if (Ygreg < 2005) {
        u = Ygreg - 2000;
        ans = ((((0.00002373599 * u + 0.000651814) * u + 0.0017275) * u - 0.060374) * u + 0.3345) * u + 63.86;
    }
    ans = adjust_for_tidacc(ans, Ygreg, tid_acc, SE_TIDAL_26, false);
    ans /= 86400.0;
    return ans;
}

fn deltat_longterm_morrison_stephenson(tjd: f64) f64 {
    const Ygreg = 2000.0 + (tjd - J2000) / 365.2425;
    const u = (Ygreg - 1820.0) / 100.0;
    return -20 + 32 * u * u;
}
