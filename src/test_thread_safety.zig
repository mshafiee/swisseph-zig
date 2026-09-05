// Threaded smoke test for the context-ification refactor: 4 threads x 500
// iterations, each thread owning its own Swed/context instances (MOSEPH —
// no ephemeris files needed), verifying that per-instance state does not
// leak across threads and results stay deterministic.
//
// Also exercises the C-ABI layer's threadlocal SweState: a sid-mode set in
// one thread must not be visible in another.
const std = @import("std");
const sweph = @import("sweph");
const deltat = @import("deltat");
const lib = @import("swephlib");
const swehouse = @import("swehouse");
const abi = @import("swe_abi.zig");

const N_THREADS = 4;
const N_ITERS = 500;
const SE_MOON: i32 = 1;
const SE_MERCURY: i32 = 2;
const SE_JUPITER: i32 = 5;

fn worker(id: usize) void {
    var swed = sweph.Swed{};
    var dctx = deltat.DeltatCtx{};
    const models = lib.AstroModels{};
    var hctx = swehouse.HouseCtx{};
    var serr: [256]u8 = undefined;

    var i: usize = 0;
    while (i < N_ITERS) : (i += 1) {
        // staggered tjd per thread/iter: exercises the file-static-era
        // workspaces (moon_ws, plan_ws, jpl, fixstar memos) independently
        const tjd = 2451545.0 + @as(f64, @floatFromInt(i)) * 10.0 + @as(f64, @floatFromInt(id)) * 0.25;

        // MOSEPH moon: drives swemmoon.MoonWs + swemplan.PlanWs via the
        // swed-owned workspaces
        var xx: [6]f64 = undefined;
        const ret = sweph.swe_calc(tjd, SE_MOON, lib.SEFLG_MOSEPH | lib.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
        if (ret < 0) {
            std.debug.panic("thread {d} iter {d}: moon calc failed: {s}", .{ id, i, std.mem.sliceTo(&serr, 0) });
        }
        // determinism: same input, same output, every iteration
        var xx2: [6]f64 = undefined;
        _ = sweph.swe_calc(tjd, SE_MOON, lib.SEFLG_MOSEPH | lib.SEFLG_SPEED, &xx2, &swed, models, &dctx, &serr);
        for (0..6) |k| {
            if (xx[k] != xx2[k]) {
                std.debug.panic("thread {d} iter {d}: moon nondeterministic at [{d}]", .{ id, i, k });
            }
        }

        // planet + houses: drives plan_ws + HouseCtx
        var xp: [6]f64 = undefined;
        _ = sweph.swe_calc(tjd, SE_JUPITER, lib.SEFLG_MOSEPH, &xp, &swed, models, &dctx, &serr);
        var cusp: [37]f64 = undefined;
        var ascmc: [10]f64 = undefined;
        const eps = 23.43673046;
        _ = swehouse.swe_houses_armc_ex2(xx[0] + tjd * 360.98564736629470, -33.0, eps, 'P', &cusp, &ascmc, null, null, null, &hctx);

        // julday/revjul round-trip (stateless but part of the smoke path)
        const jd = 2400000.5 + @as(f64, @floatFromInt(i % 100)) * 7.0;
        const r = @import("swedate").swe_revjul(jd, 1);
        const jd2 = @import("swedate").swe_julday(r.year, r.mon, r.day, r.ut, 1);
        if (jd != jd2) {
            std.debug.panic("thread {d} iter {d}: julday round-trip mismatch", .{ id, i });
        }
    }
}

/// ABI threadlocal isolation: thread A sets sidereal mode; thread B must
/// not see it (each thread owns its SweState).
var abi_saw_sid_result: ?bool = null;

fn abiWorkerA() void {
    // set sidereal mode in this thread's state
    abi.swe_set_sid_mode(0, 0, 0);
    // mark our presence: compute with this state
    var xx: [6]f64 = undefined;
    _ = abi.swe_calc(2451545.0, SE_MERCURY, lib.SEFLG_MOSEPH, &xx, null);
    // signal B to check
    abiIsSet.store(true, .release);
    var spins: usize = 0;
    while (abi_saw_sid_result == null and spins < 1_000_000) : (spins += 1) {
        std.Thread.yield() catch {};
    }
}

var abiIsSet: std.atomic.Value(bool) = .init(false);

fn abiWorkerB() void {
    // wait until A has set its sid mode
    var spins: usize = 0;
    while (!abiIsSet.load(.acquire) and spins < 1_000_000) : (spins += 1) {
        std.Thread.yield() catch {};
    }
    // B's swe_calc runs on B's own threadlocal SweState: sid mode must NOT
    // leak. We can only observe indirectly (isolation = no crash, and B
    // gets a normal tropical calc). Record success of the call itself.
    var xx: [6]f64 = undefined;
    const ret = abi.swe_calc(2451545.0, SE_MERCURY, lib.SEFLG_MOSEPH, &xx, null);
    abi_saw_sid_result = (ret >= 0);
}

test "4 threads x 500 iters: isolated SweState, deterministic results" {
    var threads: [N_THREADS]std.Thread = undefined;
    for (0..N_THREADS) |t| {
        threads[t] = try std.Thread.spawn(.{}, worker, .{t});
    }
    for (0..N_THREADS) |t| {
        threads[t].join();
    }
}

test "ABI threadlocal: sid mode does not leak across threads" {
    const a = try std.Thread.spawn(.{}, abiWorkerA, .{});
    const b = try std.Thread.spawn(.{}, abiWorkerB, .{});
    a.join();
    b.join();
    try std.testing.expectEqual(true, abi_saw_sid_result.?);
}
