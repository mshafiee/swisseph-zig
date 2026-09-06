// Differential test: reads the C oracle's output file and recomputes each
// case with the Zig port, comparing bit-for-bit.
// Usage: zig-difftest <oracle_output_file>
// Note: uses raw C read(); Zig 0.16 std Io truncates large reads in this env.
const std = @import("std");
const swe = @import("swedate");
const deltat = @import("deltat");
const housediff = @import("housedifftest.zig");
const moondiff = @import("moondifftest.zig");
const plandiff = @import("plandifftest.zig");
const nutdiff = @import("nutdifftest.zig");
const swecalc_diff = @import("swecalc_difftest.zig");
const swecl_diff = @import("swecldifftest.zig");
const fict_diff = @import("fictdifftest.zig");

extern "c" fn open(path: [*:0]const u8, flags: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn close(fd: c_int) c_int;

pub fn main(init: std.process.Init) !void {
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, std.heap.page_allocator);
    defer it.deinit();
    _ = it.next(); // skip argv[0]
    const arg1 = it.next();
    var fd: c_int = 0; // stdin by default
    if (arg1) |path| {
        const pathz = try std.heap.page_allocator.dupeZ(u8, path);
        fd = open(pathz.ptr, 0);
        if (fd < 0) return error.FileNotFound;
    }

    var n: usize = 0;
    var total_bytes: usize = 0;
    var fails: usize = 0;
    var line_buf: [4096]u8 = undefined;
    var line_len: usize = 0;
    var chunk: [1 << 16]u8 = undefined;
    while (true) {
        const r = read(fd, &chunk, chunk.len);
        if (r <= 0) break;
        total_bytes += @intCast(r);
        var i: usize = 0;
        while (i < @as(usize, @intCast(r))) : (i += 1) {
            const ch = chunk[i];
            if (ch == '\n') {
                if (line_len > 0) {
                    n += 1;
                    if (!checkLine(line_buf[0..line_len])) fails += 1;
                    line_len = 0;
                }
            } else if (line_len < line_buf.len) {
                line_buf[line_len] = ch;
                line_len += 1;
            }
        }
    }
    // trailing line without newline
    if (line_len > 0) {
        n += 1;
        if (!checkLine(line_buf[0..line_len])) fails += 1;
    }
    std.debug.print("STREAMING_OK bytes={d} {d} cases checked, {d} failures\n", .{ total_bytes, n, fails });
    if (fails > 0) std.process.exit(1);
}

fn checkLine(line: []const u8) bool {
    // Dispatch on the kind token (not line[0]): the swedate corpus's
    // utc_time_zone lines and the houses corpus's cotrans lines both start
    // with 'T'. Distinguish by arity: 4 values before '->' = cotrans,
    // 7 = utc_time_zone.
    var kind_tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind0 = kind_tok.next() orelse return true;
    if (std.mem.eql(u8, kind0, "H") or std.mem.eql(u8, kind0, "P") or std.mem.eql(u8, kind0, "N"))
        return housediff.checkHousesLine(line);
    if (std.mem.eql(u8, kind0, "M") or std.mem.eql(u8, kind0, "E") or
        std.mem.eql(u8, kind0, "V") or std.mem.eql(u8, kind0, "F") or
        std.mem.eql(u8, kind0, "I") or std.mem.eql(u8, kind0, "G") or
        std.mem.eql(u8, kind0, "K") or std.mem.eql(u8, kind0, "W"))
        return moondiff.checkMoonLine(line);
    if (std.mem.eql(u8, kind0, "A"))
        return plandiff.checkPlanLine(line);
    if (std.mem.eql(u8, kind0, "B") or std.mem.eql(u8, kind0, "O") or
        std.mem.eql(u8, kind0, "X") or std.mem.eql(u8, kind0, "Y") or
        std.mem.eql(u8, kind0, "Z") or std.mem.eql(u8, kind0, "EB"))
        return nutdiff.checkNutLine(line);
    if (std.mem.eql(u8, kind0, "U") or std.mem.eql(u8, kind0, "S") or
        std.mem.eql(u8, kind0, "Q") or std.mem.eql(u8, kind0, "L") or
        std.mem.eql(u8, kind0, "v") or std.mem.eql(u8, kind0, "n") or
        std.mem.eql(u8, kind0, "j") or std.mem.eql(u8, kind0, "x") or
        std.mem.eql(u8, kind0, "y") or std.mem.eql(u8, kind0, "z") or
        std.mem.eql(u8, kind0, "N"))
        return swecalc_diff.checkSwecalcLine(line);
    if (std.mem.eql(u8, kind0, "l") or std.mem.eql(u8, kind0, "r") or
        std.mem.eql(u8, kind0, "e") or std.mem.eql(u8, kind0, "o") or
        std.mem.eql(u8, kind0, "b") or std.mem.eql(u8, kind0, "p") or
        std.mem.eql(u8, kind0, "q") or std.mem.eql(u8, kind0, "w") or
        std.mem.eql(u8, kind0, "i") or std.mem.eql(u8, kind0, "k") or
        std.mem.eql(u8, kind0, "g") or std.mem.eql(u8, kind0, "a") or
        std.mem.eql(u8, kind0, "m") or std.mem.eql(u8, kind0, "f") or
        std.mem.eql(u8, kind0, "h"))
        return swecl_diff.checkSweclLine(line);
    if (std.mem.eql(u8, kind0, "u") or std.mem.eql(u8, kind0, "d") or
        std.mem.eql(u8, kind0, "s") or std.mem.eql(u8, kind0, "t"))
        return fict_diff.checkFictLine(line);
    // kind c (fictitious planet names) is a single-char token, but "c" is
    // also used by the swedate corpus's date_conversion; disambiguate by
    // arity: fictitious name lines are "c <ipl> -> '<name>'".
    if (std.mem.eql(u8, kind0, "c"))
        return fict_diff.checkFictLine(line);
    if (std.mem.eql(u8, kind0, "pn"))
        return swecalc_diff.checkSwecalcLine(line);
    if (std.mem.eql(u8, kind0, "n1") or std.mem.eql(u8, kind0, "n2") or
        std.mem.eql(u8, kind0, "o1") or std.mem.eql(u8, kind0, "o2") or
        std.mem.eql(u8, kind0, "g1") or std.mem.eql(u8, kind0, "tp"))
        return swecl_diff.checkOscLine(line);
    if (std.mem.eql(u8, kind0, "ew") or std.mem.eql(u8, kind0, "ow") or
        std.mem.eql(u8, kind0, "eh") or std.mem.eql(u8, kind0, "eg") or
        std.mem.eql(u8, kind0, "og") or std.mem.eql(u8, kind0, "el") or
        std.mem.eql(u8, kind0, "ol") or std.mem.eql(u8, kind0, "lh") or
        std.mem.eql(u8, kind0, "lg") or std.mem.eql(u8, kind0, "ll"))
        return swecl_diff.checkEclLine(line);
    if (std.mem.eql(u8, kind0, "T")) {
        var n: usize = 0;
        while (kind_tok.next()) |t| {
            if (std.mem.eql(u8, t, "->")) break;
            n += 1;
        }
        if (n == 4) return housediff.checkHousesLine(line);
        // else: utc_time_zone, handled by the "T" branch below
    }
    var tok = std.mem.tokenizeScalar(u8, line, ' ');
    const kind = tok.next() orelse return true;
    if (std.mem.eql(u8, kind, "J")) {
        const y = parseInt(tok.next());
        const mo = parseInt(tok.next());
        const d = parseInt(tok.next());
        const hour = parseFloat(tok.next());
        const g = parseInt(tok.next());
        _ = tok.next(); // "->"
        const want = parseFloat(tok.next());
        const got = swe.swe_julday(y, mo, d, hour, g);
        return report(want == got, line, want, got);
    } else if (std.mem.eql(u8, kind, "R")) {
        const jd = parseFloat(tok.next());
        const g = parseInt(tok.next());
        _ = tok.next(); // "->"
        const wy = parseInt(tok.next());
        const wmo = parseInt(tok.next());
        const wd = parseInt(tok.next());
        const wut = parseFloat(tok.next());
        const r = swe.swe_revjul(jd, g);
        const ok = r.year == wy and r.mon == wmo and r.day == wd and r.ut == wut;
        return report(ok, line, null, null);
    } else if (std.mem.eql(u8, kind, "C")) {
        const y = parseInt(tok.next());
        const mo = parseInt(tok.next());
        const d = parseInt(tok.next());
        const hour = parseFloat(tok.next());
        const cal = tok.next().?[0];
        _ = tok.next(); // "->"
        const wrc = parseInt(tok.next());
        const wtjd = parseFloat(tok.next());
        const c = swe.swe_date_conversion(y, mo, d, hour, cal);
        return report(c.rc == wrc and c.tjd == wtjd, line, wtjd, c.tjd);
    } else if (std.mem.eql(u8, kind, "D")) {
        const model = parseInt(tok.next());
        const tjd = parseFloat(tok.next());
        _ = tok.next(); // "->"
        const want = parseFloat(tok.next());
        var ctx = deltat.DeltatCtx{ .astro_model_deltat = model };
        const got = deltat.swe_deltat_ex(&ctx, tjd, -1);
        return report(want == got, line, want, got);
    } else if (std.mem.eql(u8, kind, "T")) {
        const y = parseInt(tok.next());
        const mo = parseInt(tok.next());
        const d = parseInt(tok.next());
        const h = parseInt(tok.next());
        const mi = parseInt(tok.next());
        const s = parseFloat(tok.next());
        const tz = parseFloat(tok.next());
        _ = tok.next(); // "->"
        const wy = parseInt(tok.next());
        const wmo = parseInt(tok.next());
        const wd = parseInt(tok.next());
        const wh = parseInt(tok.next());
        const wmi = parseInt(tok.next());
        const ws = parseFloat(tok.next());
        const r = swe.swe_utc_time_zone(y, mo, d, h, mi, s, tz);
        const ok = r.year == wy and r.mon == wmo and r.day == wd and
            r.hour == wh and r.min == wmi and r.sec == ws;
        return report(ok, line, null, null);
    }
    return true;
}

fn report(ok: bool, line: []const u8, want: ?f64, got: ?f64) bool {
    if (!ok) {
        std.debug.print("MISMATCH: {s}", .{line});
        if (want != null and got != null)
            std.debug.print("  want={d} got={d}\n", .{ want.?, got.? })
        else
            std.debug.print("\n", .{});
    }
    return ok;
}

fn parseInt(s: ?[]const u8) i32 {
    return std.fmt.parseInt(i32, s.?, 10) catch 0;
}

fn parseFloat(s: ?[]const u8) f64 {
    return std.fmt.parseFloat(f64, s.?) catch 0;
}
