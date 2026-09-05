//! Thread-safety test for the swisseph-zig core API.
//!
//! CURRENT STATUS: Phase A complete (threadlocal vars), Phase B pending.
//!
//! threadlocal vars give per-thread isolation for the Moshier polynomial
//! tables (ss, cc, moonpol, etc.), matching C's __thread on Linux. However,
//! the Moshier moon/planet algorithms use CALL-ORDER-DEPENDENT accumulated
//! state: the ss/cc tables are lazily built and indexed by date range. A
//! fresh thread computes different intermediate values than a thread that
//! has processed prior dates, even with threadlocal storage.
//!
//! FULL FIX (Phase B): move the accumulated state into a MoonCtx/JplCtx
//! struct passed per-caller, so each thread can maintain its own complete
//! computation context. Then this test passes with 0 races.
//!
//! Run: zig build test
const std = @import("std");
const sweph = @import("sweph");
const swephlib = @import("swephlib");
const deltat = @import("deltat");
const swedate = @import("swedate");

const N_THREADS = 4;
const N_CALLS = 50;

test "concurrent swedate is always safe (no shared state)" {
    // swedate has no mutable state — always safe, any thread count
    const T = 8;
    var results: [T]f64 = [_]f64{0} ** T;
    var threads: [T]std.Thread = undefined;
    for (0..T) |tidx| {
        threads[tidx] = std.Thread.spawn(.{}, struct {
            fn run(r: *f64, day: usize) void {
                r.* = swedate.swe_julday(2000, 1, @intCast(day + 1), 12.0, 1);
            }
        }.run, .{ &results[tidx], tidx }) catch unreachable;
    }
    for (0..T) |tidx| threads[tidx].join();
    for (0..T) |tidx| {
        try std.testing.expect(results[tidx] > 2451544.0 + @as(f64, @floatFromInt(tidx)));
    }
}

test "concurrent degnorm is always safe (pure function)" {
    const T = 4;
    var results: [T]f64 = [_]f64{0} ** T;
    var threads: [T]std.Thread = undefined;
    for (0..T) |tidx| {
        threads[tidx] = std.Thread.spawn(.{}, struct {
            fn run(r: *f64, x: f64) void {
                r.* = swephlib.swe_degnorm(x * 100000.0);
            }
        }.run, .{ &results[tidx], @as(f64, @floatFromInt(tidx)) }) catch unreachable;
    }
    for (0..T) |tidx| threads[tidx].join();
    for (0..T) |tidx| {
        try std.testing.expect(results[tidx] >= 0.0 and results[tidx] < 360.0);
    }
}

test "swe_calc Moshier: document thread-safety limitation" {
    // This test documents the known limitation. It runs serial swe_calc
    // and verifies correctness — the concurrent race is documented, not
    // yet fixed (Phase B: MoonCtx/JplCtx context structs needed).
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = [_]u8{0} ** 256;
    var swed = sweph.Swed{};
    var dctx = deltat.DeltatCtx{};
    const ret = sweph.swe_calc(2451545.0, 0, 0, &xx, &swed, .{}, &dctx, &serr);
    try std.testing.expect(ret >= 0);
    try std.testing.expect(xx[0] > 279.0 and xx[0] < 281.0);
}
