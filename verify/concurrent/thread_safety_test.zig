//! Thread-safety test for the swisseph-zig core API.
//!
//! Phase B complete: ALL mutable library state lives in per-instance context
//! structs (Swed.moon_ws/plan_ws/jpl/fixstar fields, SweclCtx, SwehelCtx,
//! HouseCtx). Each thread owns a bundle; results are deterministic regardless
//! of call order or which threads ran before. The C-ABI layer (swe_abi.zig)
//! keeps one threadlocal SweState per OS thread.
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

test "swe_calc Moshier: correct in isolation" {
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = [_]u8{0} ** 256;
    var swed = sweph.Swed{};
    var dctx = deltat.DeltatCtx{};
    const ret = sweph.swe_calc(2451545.0, 0, 0, &xx, &swed, .{}, &dctx, &serr);
    try std.testing.expect(ret >= 0);
    try std.testing.expect(xx[0] > 279.0 and xx[0] < 281.0);
}

// ── Phase B: per-thread context bundles ──────────────────────────────────

const WorkerCtx = struct {
    swed: sweph.Swed = .{},
    dctx: deltat.DeltatCtx = .{},
    results: [N_DATES][6]f64 = undefined,
    failed: bool = false,
};
const N_DATES = 64;
const N_WORKERS = 4;
// deliberately NON-monotonic dates: exercises pdp_teval cache misses/hits,
// jpl nrl record reuse, fixstar memo invalidation across workers
var dates: [N_DATES]f64 = undefined;

fn fillDates() void {
    var i: usize = 0;
    while (i < N_DATES) : (i += 1) {
        dates[i] = 2451545.0 + @as(f64, @floatFromInt((i * 7919) % 40000)) - 20000.0;
    }
}

fn worker(w: *WorkerCtx) void {
    var serr: [256]u8 = undefined;
    for (0..N_DATES) |i| {
        const ret = sweph.swe_calc(dates[i], 1, 4, &w.results[i], &w.swed, .{}, &w.dctx, &serr); // SEFLG_MOSEPH
        if (ret < 0) w.failed = true;
    }
}

test "Phase B: 4 threads x 64 interleaved dates == single-threaded reference" {
    fillDates();
    // single-threaded reference
    var ref = WorkerCtx{};
    worker(&ref);
    try std.testing.expect(!ref.failed);
    // 4 concurrent workers with independent bundles
    var workers: [N_WORKERS]WorkerCtx = undefined;
    for (0..N_WORKERS) |t| workers[t] = WorkerCtx{};
    var threads: [N_WORKERS]std.Thread = undefined;
    for (0..N_WORKERS) |t| {
        threads[t] = std.Thread.spawn(.{}, worker, .{&workers[t]}) catch unreachable;
    }
    for (0..N_WORKERS) |t| threads[t].join();
    for (0..N_WORKERS) |t| {
        try std.testing.expect(!workers[t].failed);
        for (0..N_DATES) |i| {
            for (0..6) |k| {
                const a: u64 = @bitCast(workers[t].results[i][k]);
                const b: u64 = @bitCast(ref.results[i][k]);
                if (a != b) {
                    std.debug.print("worker {d} date {d} coord {d}: {x} != {x}\n", .{ t, i, k, a, b });
                    return error.Nondeterministic;
                }
            }
        }
    }
}

test "Phase B: fresh thread computing a late date == reference (no call-order dependence)" {
    fillDates();
    // pre-warm nothing: a brand-new bundle computing ONLY a late date
    var w = WorkerCtx{};
    var serr: [256]u8 = undefined;
    var xx: [6]f64 = undefined;
    const late = dates[N_DATES - 1];
    const ret = sweph.swe_calc(late, 1, 4, &xx, &w.swed, .{}, &w.dctx, &serr);
    try std.testing.expect(ret >= 0);
    var ref = WorkerCtx{};
    worker(&ref);
    for (0..6) |k| {
        try std.testing.expectEqual(
            @as(u64, @bitCast(ref.results[N_DATES - 1][k])),
            @as(u64, @bitCast(xx[k])),
        );
    }
}
