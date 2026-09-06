// Native golden-vector dumper for the test/wasm/ Node harness.
// Usage: swe-golden <ephe_dir> <tjd_ut> <ipl> <iflag> [jplfile]
//        swe-golden <ephe_dir> star <name> <tjd_ut> <iflag> [jplfile]
// Prints one machine-parseable line:
//   rc=<i> x=<u64hex> x6 serr=<s>
// Build pure (same math as wasm): zig build swe-golden -Dpure=true
// The optional jplfile runs swe_set_jpl_file first (JPL+EOP vectors),
// mirroring the JS lifecycle exactly (ephe path, then JPL, then calc).
const std = @import("std");
const abi = @import("swe_abi");

fn usage() error{Usage} {
    std.debug.print("usage: swe-golden <ephe_dir> <tjd_ut> <ipl> <iflag> [jplfile]\n", .{});
    std.debug.print("   or: swe-golden <ephe_dir> star <name> <tjd_ut> <iflag> [jplfile]\n", .{});
    return error.Usage;
}

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer it.deinit();
    _ = it.next(); // argv[0]
    const ephe_arg = it.next() orelse return usage();
    const mode_arg = it.next() orelse return usage();
    const ephe = try alloc.dupeZ(u8, ephe_arg);
    abi.swe_set_ephe_path(ephe.ptr);
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;
    serr[0] = 0;
    var rc: i32 = undefined;
    if (std.mem.eql(u8, mode_arg, "star")) {
        const name_arg = it.next() orelse return usage();
        const tjd_arg = it.next() orelse return usage();
        const iflag_arg = it.next() orelse return usage();
        const name = try alloc.dupeZ(u8, name_arg);
        const tjd = try std.fmt.parseFloat(f64, tjd_arg);
        const iflag = try std.fmt.parseInt(i32, iflag_arg, 10);
        rc = abi.swe_fixstar2_ut(name.ptr, tjd, iflag, xx[0..].ptr, @ptrCast(&serr));
    } else {
        const tjd = try std.fmt.parseFloat(f64, mode_arg);
        const ipl_arg = it.next() orelse return usage();
        const iflag_arg = it.next() orelse return usage();
        const ipl = try std.fmt.parseInt(i32, ipl_arg, 10);
        const iflag = try std.fmt.parseInt(i32, iflag_arg, 10);
        if (it.next()) |jpl_arg| {
            const jpl = try alloc.dupeZ(u8, jpl_arg);
            abi.swe_set_jpl_file(jpl.ptr);
        }
        rc = abi.swe_calc_ut(tjd, ipl, iflag, xx[0..].ptr, @ptrCast(&serr));
    }
    var line: [2048]u8 = undefined;
    var pos: usize = 0;
    {
        const w = std.fmt.bufPrint(line[pos..], "rc={d}", .{rc}) catch "";
        pos += w.len;
    }
    for (xx) |v| {
        const w = std.fmt.bufPrint(line[pos..], " {x}", .{@as(u64, @bitCast(v))}) catch "";
        pos += w.len;
    }
    {
        const s = std.mem.sliceTo(&serr, 0);
        const w = std.fmt.bufPrint(line[pos..], " serr={s}", .{s}) catch "";
        pos += w.len;
    }
    // Repo convention (difftest, swephgen4): tool output via debug print.
    // The harness captures stderr.
    std.debug.print("{s}\n", .{line[0..pos]});
}
