const std = @import("std");
const swe = @import("swe_abi");

test "julday J2000" {
    const jd = swe.swe_julday(2000, 1, 1, 12.0, 1);
    try std.testing.expectEqual(@as(f64, 2451545.0), jd);
}

test "revjul roundtrip" {
    var y: i32 = 0;
    var m: i32 = 0;
    var d: i32 = 0;
    var ut: f64 = 0;
    swe.swe_revjul(2451545.0, 1, &y, &m, &d, &ut);
    try std.testing.expectEqual(@as(i32, 2000), y);
    try std.testing.expectEqual(@as(i32, 1), m);
    try std.testing.expectEqual(@as(i32, 1), d);
}

test "csnorm" {
    try std.testing.expectEqual(@as(i32, 0), swe.swe_csnorm(0));
    try std.testing.expectEqual(@as(i32, 359 * 360000), swe.swe_csnorm(-360000));
}

test "deltat J2000 reasonable" {
    const dt = swe.swe_deltat(2451545.0);
    try std.testing.expect(dt > 60.0 / 86400.0 and dt < 70.0 / 86400.0);
}

test "version string" {
    var buf: [256]u8 = undefined;
    const v = swe.swe_version(@ptrCast(&buf));
    try std.testing.expect(std.mem.startsWith(u8, std.mem.span(v), "2.10"));
}
