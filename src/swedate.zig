// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port — Phase 0: swedate functions.
// Translated 1:1 from swedate.c to preserve exact floating-point
// operation order (differential-tested against the C oracle).

pub const SE_JUL_CAL: i32 = 0;
pub const SE_GREG_CAL: i32 = 1;
pub const OK: i32 = 0;
pub const ERR: i32 = -1;

/// Floor for f64, matching C's floor() exactly.
const floor = std.math.floor;

/// Equivalent of C swe_julday().
pub fn swe_julday(year: i32, month: i32, day: i32, hour: f64, gregflag: i32) f64 {
    var u: f64 = @floatFromInt(year);
    if (month < 3) u -= 1;
    const u_0: f64 = u + 4712.0;
    var uu1: f64 = @as(f64, @floatFromInt(month)) + 1.0;
    if (uu1 < 4) uu1 += 12.0;
    var jd: f64 = floor(u_0 * 365.25) + floor(30.6 * uu1 + 0.000001) +
        @as(f64, @floatFromInt(day)) + hour / 24.0 - 63.5;
    if (gregflag == SE_GREG_CAL) {
        var uu2: f64 = floor(@abs(u) / 100) - floor(@abs(u) / 400);
        if (u < 0.0) uu2 = -uu2;
        jd = jd - uu2 + 2;
        if ((u < 0.0) and (@divTrunc(u, 100) == floor(u / 100)) and (u / 400 != floor(u / 400)))
            jd -= 1;
    }
    return jd;
}

pub const RevJul = struct { year: i32, mon: i32, day: i32, ut: f64 };

/// Equivalent of C swe_revjul().
pub fn swe_revjul(jd: f64, gregflag: i32) RevJul {
    var u_0: f64 = jd + 32082.5;
    if (gregflag == SE_GREG_CAL) {
        var uu1: f64 = u_0 + floor(u_0 / 36525.0) - floor(u_0 / 146100.0) - 38.0;
        if (jd >= 1830691.5) uu1 += 1;
        u_0 = u_0 + floor(uu1 / 36525.0) - floor(uu1 / 146100.0) - 38.0;
    }
    const uu2: f64 = floor(u_0 + 123.0);
    const uu3: f64 = floor((uu2 - 122.2) / 365.25);
    const uu4: f64 = floor((uu2 - floor(365.25 * uu3)) / 30.6001);
    var jmon: i32 = @intFromFloat(uu4 - 1.0);
    if (jmon > 12) jmon -= 12;
    const jday: i32 = @intFromFloat(uu2 - floor(365.25 * uu3) - floor(30.6001 * uu4));
    const jyear: i32 = @intFromFloat(uu3 + floor((uu4 - 2.0) / 12.0) - 4800);
    const jut: f64 = (jd - floor(jd + 0.5) + 0.5) * 24.0;
    return .{ .year = jyear, .mon = jmon, .day = jday, .ut = jut };
}

/// Equivalent of C swe_date_conversion(). Returns OK/ERR and tjd.
pub fn swe_date_conversion(y: i32, m: i32, d: i32, uttime: f64, c: u8) struct { rc: i32, tjd: f64 } {
    var gregflag: i32 = SE_JUL_CAL;
    if (c == 'g') gregflag = SE_GREG_CAL;
    const rut: f64 = uttime;
    const jd: f64 = swe_julday(y, m, d, rut, gregflag);
    const r = swe_revjul(jd, gregflag);
    if (r.mon == m and r.day == d and r.year == y) {
        return .{ .rc = OK, .tjd = jd };
    } else {
        return .{ .rc = ERR, .tjd = jd };
    }
}

pub const UtcTimeZone = struct {
    year: i32,
    mon: i32,
    day: i32,
    hour: i32,
    min: i32,
    sec: f64,
};

/// Equivalent of C swe_utc_time_zone().
pub fn swe_utc_time_zone(
    iyear: i32,
    imonth: i32,
    iday: i32,
    ihour: i32,
    imin: i32,
    dsec_in: f64,
    d_timezone: f64,
) UtcTimeZone {
    var dsec = dsec_in;
    var have_leapsec = false;
    if (dsec >= 60.0) {
        have_leapsec = true;
        dsec -= 1.0;
    }
    var dhour: f64 = @as(f64, @floatFromInt(ihour)) +
        @as(f64, @floatFromInt(imin)) / 60.0 + dsec / 3600.0;
    var tjd: f64 = swe_julday(iyear, imonth, iday, 0, SE_GREG_CAL);
    dhour -= d_timezone;
    if (dhour < 0.0) {
        tjd -= 1.0;
        dhour += 24.0;
    }
    if (dhour >= 24.0) {
        tjd += 1.0;
        dhour -= 24.0;
    }
    const r = swe_revjul(tjd + 0.001, SE_GREG_CAL);
    var hour_out: i32 = @intFromFloat(dhour);
    var d: f64 = (dhour - @as(f64, @floatFromInt(hour_out))) * 60;
    var min_out: i32 = @intFromFloat(d);
    var sec_out: f64 = (d - @as(f64, @floatFromInt(min_out))) * 60;
    if (have_leapsec) sec_out += 1.0;
    _ = &hour_out;
    _ = &min_out;
    _ = &sec_out;
    _ = &d;
    return .{
        .year = r.year,
        .mon = r.mon,
        .day = r.day,
        .hour = hour_out,
        .min = min_out,
        .sec = sec_out,
    };
}

const std = @import("std");

test "julday/revjul roundtrip known values" {
    // 1 Jan 2000, 12:00 UT (Gregorian) = JD 2451545.0
    const jd = swe_julday(2000, 1, 1, 12.0, SE_GREG_CAL);
    try std.testing.expectEqual(@as(f64, 2451545.0), jd);
    const r = swe_revjul(2451545.0, SE_GREG_CAL);
    try std.testing.expectEqual(@as(i32, 2000), r.year);
    try std.testing.expectEqual(@as(i32, 1), r.mon);
    try std.testing.expectEqual(@as(i32, 1), r.day);
    try std.testing.expectEqual(@as(f64, 12.0), r.ut);
    // Julian calendar: 1 Jan 2000 JC = JD 2451557.5 at 0h (verified vs. C oracle)
    const jdj = swe_julday(2000, 1, 1, 0.0, SE_JUL_CAL);
    try std.testing.expectEqual(@as(f64, 2451557.5), jdj);
    // 24 Nov -4712 (astron.) 12h JC = JD 0
    try std.testing.expectEqual(@as(f64, 0.0), swe_julday(-4712, 1, 1, 12.0, SE_JUL_CAL));
}

test "date_conversion rejects 32 January" {
    try std.testing.expectEqual(ERR, swe_date_conversion(1993, 1, 32, 0.0, 'g').rc);
    try std.testing.expectEqual(OK, swe_date_conversion(1993, 1, 31, 0.0, 'g').rc);
}
