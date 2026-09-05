const std = @import("std");
const abi = @import("swe_abi");
const lib = @import("swephlib");
pub fn main(init: std.process.Init) !void {
    _ = init;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, "../ephe/sefstars.txt", .{}) catch |e| {
        std.debug.print("ephe missing: {}\n", .{e});
        return;
    };
    var star_buf: [64]u8 = undefined;
    const star = std.fmt.bufPrintZ(&star_buf, "Sirius", .{}) catch unreachable;
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;
    _ = abi.swe_fixstar2(star.ptr, 2451545.0, 0, &xx, null);
    std.debug.print("first: {x} {d:.6}\n", .{ @as(u64, @bitCast(xx[0])), xx[0] });
    abi.swe_cleanup();
    abi.swe_cleanup();
    var first: [6]f64 = undefined;
    const ret = abi.swe_fixstar2(star.ptr, 2451545.0, 0, &first, &serr);
    std.debug.print("ret={} serr={s}\n", .{ ret, std.mem.sliceTo(&serr, 0) });
    std.debug.print("after : {x} {d:.6}\n", .{ @as(u64, @bitCast(first[0])), first[0] });
    abi.swe_cleanup();
    const ret2 = abi.swe_fixstar2(star.ptr, 2451545.0, 0, &xx, &serr);
    std.debug.print("ret2={} serr={s}\n", .{ ret2, std.mem.sliceTo(&serr, 0) });
    std.debug.print("after2: {x}\n", .{@as(u64, @bitCast(xx[0]))});
}
