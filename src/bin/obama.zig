// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
const swe = @import("swe_abi");

extern "c" fn printf(format: [*:0]const u8, ...) c_int;

const SE_GREG_CAL: i32 = 1;
const SEFLG_SWIEPH: i32 = 2;
const SEFLG_SPEED: i32 = 256;
const SE_SUN: i32 = 0;
const SE_TRUE_NODE: i32 = 11;

pub fn main() !void {
    const iday: i32 = 5;
    const imon: i32 = 8;
    const iyar: i32 = 1961;
    const dhour: f64 = 5.4;
    const dlon: f64 = -157.86666667;
    const dlat: f64 = 21.3;
    const ihsy: i32 = 'P';

    var xx: [6]f64 = undefined;
    var cusps: [13]f64 = undefined;
    var ascmc: [10]f64 = undefined;
    var serr: [256]u8 = undefined;
    var spname: [256]u8 = undefined;

    _ = printf("Date and time in UT: day=%d mon=%d year=%d decimal hour=%f\n", iday, imon, iyar, dhour);
    _ = printf("\tdecimal geographical coordinates lat=%f, long=%f\n", dlat, dlon);

    const jd_ut = swe.swe_julday(iyar, imon, iday, dhour, SE_GREG_CAL);
    _ = printf("\nJulday of birth = %f\n", jd_ut);

    var iflag: i32 = (SEFLG_SWIEPH | SEFLG_SPEED);
    _ = printf("Planet\tecl.long.\tecl.lat.\tdist. AU\tspeed deg/day\n");

    var ipl: i32 = SE_SUN;
    while (ipl <= SE_TRUE_NODE) : (ipl += 1) {
        _ = swe.swe_get_planet_name(ipl, @ptrCast(&spname));
        spname[7] = 0;
        _ = printf("%s\t", @as([*:0]u8, @ptrCast(&spname)));
        serr[0] = 0;
        const iret = swe.swe_calc_ut(jd_ut, ipl, iflag, &xx, @ptrCast(&serr));
        if (iret < 0) {
            _ = printf("iret=%d, %s\n", iret, &serr);
        }
        _ = printf("%10.6f\t%9.6f\t%9.6f\t%9.6f\n", xx[0], xx[1], xx[2], xx[3]);
    }

    iflag = 0;
    const iret = swe.swe_houses_ex(jd_ut, iflag, dlat, dlon, ihsy, &cusps, &ascmc);
    if (iret < 0) {
        _ = printf("Unknown problem with house calculation, iret=%d\n", iret);
        return;
    }
    _ = printf("\nAscendant %10.6f\tMC %10.6f\n", ascmc[0], ascmc[1]);
    const hname = swe.swe_house_name(ihsy);
    _ = printf("House system %s\n", hname);
    var i: usize = 1;
    while (i <= 12) : (i += 1) {
        _ = printf("cusp %2d\t%10.6f\n", @as(i32, @intCast(i)), cusps[i]);
    }
    _ = printf("\n");
}
