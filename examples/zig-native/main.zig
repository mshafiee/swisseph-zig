const std = @import("std");
const swe = @import("swisseph");

pub fn main(init: std.process.Init) !void {
    _ = init;
    var swed = swe.sweph.Swed{};
    var dctx = swe.deltat.DeltatCtx{};
    const models = swe.swephlib.AstroModels{};
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;
    const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL);
    _ = swe.calc_ut(jd, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
    std.debug.print("Sun 1.1.2000: {d:.6} deg\n", .{xx[0]});
}
