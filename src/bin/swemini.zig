// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
const swe = @import("swe_abi");

extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn fgets(buf: [*]u8, n: c_int, stream: ?*anyopaque) ?[*]u8;
extern "c" fn sscanf(buf: [*:0]const u8, format: [*:0]const u8, ...) c_int;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*anyopaque;
var stdin_file: ?*anyopaque = null;

const SE_GREG_CAL: i32 = 1;
const SEFLG_SPEED: i32 = 256;
const SE_SUN: i32 = 0;
const SE_CHIRON: i32 = 15;
const SE_EARTH: i32 = 14;

const smon = [_][:0]const u8{ "", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

pub fn main() !void {
    var jday: i32 = 1;
    var jmon: i32 = 1;
    var jyear: i32 = 2022;
    var jut: f64 = 0.0;

    swe.swe_set_ephe_path(null);
    const iflag: i32 = SEFLG_SPEED;

    var sdate: [256]u8 = undefined;
    var snam: [40]u8 = undefined;
    var serr: [256]u8 = undefined;

    stdin_file = fdopen(0, "r");
    while (true) {
        _ = printf("\nDate (d.m.y) ?");
        if (fgets(&sdate, 256, stdin_file) == null) return;
        if (sdate[0] == '.') return;
        var jd: i32 = jday;
        var jm: i32 = jmon;
        var jy: i32 = jyear;
        sdate[255] = 0;
        const n = sscanf(@ptrCast(&sdate), "%d%*c%d%*c%d", &jd, &jm, &jy);
        if (n >= 1) jday = jd;
        if (n >= 2) jmon = jm;
        if (n >= 3) jyear = jy;

        if (jmon < 1 or jmon > 12) {
            _ = printf("illegal month %d\n", jmon);
            continue;
        }

        const tjd = swe.swe_julday(jyear, jmon, jday, jut, SE_GREG_CAL);
        const te = tjd + swe.swe_deltat(tjd);
        _ = printf("date: %02d %s %04d at 0:00 Universal time, jd=%.1f\n", jday, smon[@intCast(jmon)].ptr, jyear, tjd);
        _ = printf("planet     \tlongitude\tlatitude\tdistance\tspeed long.\n");

        var p: i32 = SE_SUN;
        while (p <= SE_CHIRON) : (p += 1) {
            if (p == SE_EARTH) continue;
            _ = swe.swe_get_planet_name(p, @ptrCast(&snam));
            var x2: [6]f64 = undefined;
            serr[0] = 0;
            const iflgret = swe.swe_calc(te, p, iflag, &x2, @ptrCast(&serr));
            if (iflgret < 0) {
                _ = printf("%10s\terror: %s\n", &snam, &serr);
                continue;
            }
            if (iflgret != iflag) {
                _ = printf("warning: iflgret != iflag. %s\n", &serr);
            }
            _ = printf("%10s\t%11.7f\t%10.7f\t%10.7f\t%10.7f\n", &snam, x2[0], x2[1], x2[2], x2[3]);
        }

        const tjd_next = tjd + 1;
        var out_year: i32 = undefined;
        var out_mon: i32 = undefined;
        var out_day: i32 = undefined;
        var out_jut: f64 = undefined;
        swe.swe_revjul(tjd_next, SE_GREG_CAL, &out_year, &out_mon, &out_day, &out_jut);
        jyear = out_year;
        jmon = out_mon;
        jday = out_day;
        jut = out_jut;
    }
}
