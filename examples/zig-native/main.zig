const std = @import("std");
const swe = @import("swisseph");

pub fn main() !void {
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;
    const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL);
    _ = swe.calc_ut(jd, 0, swe.sweph.SEFLG_SPEED, &xx, &serr);
    std.debug.print("Sun (J2000 +5d): {d:.6} deg\n", .{xx[0]});
}
