//! Heavy multithreaded race test for the swisseph-zig library.
//!
//! Strategy: N workers with fully independent context bundles execute the
//! SAME deterministic mixed sequence (Moshier, SWIEPH files, JPL file,
//! fixstar with memo invalidation, houses, sidereal mode toggling, delta-T).
//! Every worker's results must be BIT-IDENTICAL to a single-threaded
//! reference run. Any cross-thread contamination (a stray module-level
//! write, a shared cache) flips at least one bit somewhere across the
//! thousands of coordinates compared.
//!
//! Also exercises the C-ABI threadlocal SweState under concurrency.
//!
//! Run: zig build test  (included in the test step)

const std = @import("std");
const sweph = @import("sweph");
const deltat = @import("deltat");
const lib = @import("swephlib");
const swehouse = @import("swehouse");
const swemmoon = @import("swemmoon");

const N_WORKERS = 32; // heavy oversubscription vs typical 8-10 cores
const N_SEQ = 40; // mixed ops per worker per round
const ROUNDS = 4;

const SE_SUN: i32 = 0;
const SE_MOON: i32 = 1;
const SE_MARS: i32 = 4;
const SE_JUPITER: i32 = 5;
const SE_TRUE_NODE: i32 = 11;

const Bundle = struct {
    swed: sweph.Swed = .{},
    dctx: deltat.DeltatCtx = .{},
    models: lib.AstroModels = .{},
    hctx: swehouse.HouseCtx = .{},
    moon_ws: swemmoon.MoonWs = .{},
    // results: [round][seq][coord]
    results: [ROUNDS][N_SEQ][6]f64 = undefined,
    failed_ops: usize = 0,
};

fn seqDate(i: usize) f64 {
    // deliberately non-monotonic, spread over ~120 years to force JPL
    // segment jumps, fixstar reloads and moon pdp cache misses
    const span: f64 = 43830.0; // ~120 years
    return 2400000.5 + span * @as(f64, @floatFromInt((i * 7919 + 13) % N_SEQ)) / @as(f64, @floatFromInt(N_SEQ));
}

/// One deterministic mixed workload. `b` holds all state; nothing global
/// is read or written.
fn runSequence(b: *Bundle) void {
    var serr: [256]u8 = undefined;

    // per-bundle setup (mirrors what a real user thread does)
    var ephepath_buf: [256]u8 = undefined;
    const ephepath = std.fmt.bufPrintZ(&ephepath_buf, "../ephe", .{}) catch unreachable;
    sweph.swe_set_ephe_path(ephepath, &b.swed, &b.models, &b.dctx, null);

    var jplname_buf: [64]u8 = undefined;
    const jplname = std.fmt.bufPrintZ(&jplname_buf, "../ephe/de406.eph", .{}) catch unreachable;
    sweph.swe_set_jpl_file(jplname, &b.swed, &b.models, &b.dctx);

    for (0..N_SEQ) |i| {
        const jd_et = seqDate(i);
        _ = deltat.swe_deltat_ex(&b.dctx, jd_et, -1); // exercise deltat state
        var xx: [6]f64 = undefined;
        var op_ok = true;

        // alternate ephemeris flags: JPL file / SWIEPH / Moshier
        const flag: i32 = switch (i % 3) {
            0 => lib.SEFLG_JPLEPH | lib.SEFLG_SPEED,
            1 => lib.SEFLG_SWIEPH | lib.SEFLG_SPEED,
            else => lib.SEFLG_MOSEPH | lib.SEFLG_SPEED,
        };
        const planet: i32 = switch (i % 4) {
            0 => SE_MOON,
            1 => SE_JUPITER,
            2 => SE_MARS,
            else => SE_TRUE_NODE,
        };
        if (sweph.swe_calc(jd_et, planet, flag, &xx, &b.swed, b.models, &b.dctx, &serr) < 0)
            op_ok = false;

        // houses (writes hctx memo — Sunshine path exercised only via 'I',
        // but the param is threaded everywhere)
        var cusp: [37]f64 = undefined;
        var ascmc: [10]f64 = undefined;
        _ = swehouse.swe_houses_armc_ex2(
            @mod(xx[0] + (jd_et - 2451545.0) * 360.98564736629470, 360.0),
            -33.0 + @as(f64, @floatFromInt(i % 7)),
            23.43673046,
            'P',
            &cusp,
            &ascmc,
            null,
            null,
            null,
            &b.hctx,
        );

        // sidereal mode toggle + ayanamsa (writes swed.sid-mode state)
        if (i % 5 == 0) {
            sweph.swe_set_sid_mode(@intCast(i % 3), 0, 0, &b.swed, null);
            var daya: f64 = undefined;
            _ = sweph.swe_get_ayanamsa_ex(jd_et, 0, &daya, &b.swed, b.models, &b.dctx, &serr);
        }

        // fixstar (loads sefstars.txt into swed.fixed_stars; the slast_*
        // memos are per-Swed now)
        var star_buf: [64]u8 = undefined;
        const star = std.fmt.bufPrint(&star_buf, "Sirius", .{}) catch unreachable;
        var fserr: [256]u8 = undefined;
        if (sweph.swe_fixstar2(star, jd_et, flag & @as(i32, 255), &xx, &b.swed, b.models, &b.dctx, &fserr) < 0)
            op_ok = false;

        // direct moon internals with the per-bundle workspace
        var pol: [3]f64 = undefined;
        var node: f64 = undefined;
        var dnode: f64 = undefined;
        var peri: f64 = undefined;
        var dperi: f64 = undefined;
        swemmoon.swi_mean_lunar_elements(jd_et, &node, &dnode, &peri, &dperi, &b.moon_ws);
        _ = swemmoon.swi_intp_apsides(jd_et, &pol, 4, &b.moon_ws);

        if (!op_ok) b.failed_ops += 1;
        b.results[0][i] = xx; // fixstar result as the compared artifact
    }
}

pub fn heavyRaceCheck() !void {
    // heap-allocate bundles: 32 x Swed exceeds comfortable main-stack use
    const ref = try std.heap.page_allocator.create(Bundle);
    ref.* = Bundle{};
    for (0..ROUNDS) |_| runSequence(ref);
    try std.testing.expectEqual(@as(usize, 0), ref.failed_ops);

    const bundles = try std.heap.page_allocator.alloc(Bundle, N_WORKERS);
    for (0..N_WORKERS) |t| bundles[t] = Bundle{};

    var threads: [N_WORKERS]std.Thread = undefined;
    for (0..N_WORKERS) |t| {
        threads[t] = std.Thread.spawn(.{}, struct {
            fn run(b: *Bundle) void {
                for (0..ROUNDS) |_| runSequence(b);
            }
        }.run, .{&bundles[t]}) catch unreachable;
    }
    for (0..N_WORKERS) |t| threads[t].join();

    var mismatches: usize = 0;
    for (0..N_WORKERS) |t| {
        try std.testing.expectEqual(@as(usize, 0), bundles[t].failed_ops);
        for (0..N_SEQ) |i| {
            for (0..6) |k| {
                const a: u64 = @bitCast(bundles[t].results[0][i][k]);
                const b: u64 = @bitCast(ref.results[0][i][k]);
                if (a != b) {
                    if (mismatches < 8)
                        std.debug.print("RACE: worker {d} seq {d} coord {d}: {x} != ref {x}\n", .{ t, i, k, a, b });
                    mismatches += 1;
                }
            }
        }
    }
    if (mismatches != 0) return error.RaceDetected;
}

// ── C-ABI threadlocal stress ─────────────────────────────────────────────

const N_ABI_WORKERS = 8;
const N_ABI_CALLS = 200;

pub fn abiRaceCheck() !void {
    const abi = @import("swe_abi");
    // serial reference on this thread
    var ref: [N_ABI_CALLS][6]f64 = undefined;
    var xx: [6]f64 = undefined;
    for (0..N_ABI_CALLS) |i| {
        const jd = 2451545.0 + @as(f64, @floatFromInt((i * 104729) % 9000));
        _ = abi.swe_calc(jd, SE_MOON, lib.SEFLG_MOSEPH, &xx, null);
        ref[i] = xx;
    }
    const results = try std.heap.page_allocator.alloc([N_ABI_CALLS][6]f64, N_ABI_WORKERS);
    for (0..N_ABI_WORKERS) |t| results[t] = .{undefined} ** N_ABI_CALLS;
    var threads: [N_ABI_WORKERS]std.Thread = undefined;
    for (0..N_ABI_WORKERS) |t| {
        threads[t] = std.Thread.spawn(.{}, struct {
            fn run(out: *[N_ABI_CALLS][6]f64) void {
                for (0..N_ABI_CALLS) |i| {
                    const jd = 2451545.0 + @as(f64, @floatFromInt((i * 104729) % 9000));
                    _ = abi.swe_calc(jd, SE_MOON, lib.SEFLG_MOSEPH, &out[i], null);
                }
            }
        }.run, .{&results[t]}) catch unreachable;
    }
    for (0..N_ABI_WORKERS) |t| threads[t].join();
    for (0..N_ABI_WORKERS) |t| {
        for (0..N_ABI_CALLS) |i| {
            for (0..6) |k| {
                const a: u64 = @bitCast(results[t][i][k]);
                const b: u64 = @bitCast(ref[i][k]);
                if (a != b) {
                    std.debug.print("ABI RACE: worker {d} call {d} coord {d}: {x} != {x}\n", .{ t, i, k, a, b });
                    return error.AbiRaceDetected;
                }
            }
        }
    }
}

test "heavy race (wrapper)" {
    try heavyRaceCheck();
}
test "ABI race (wrapper)" {
    try abiRaceCheck();
}

/// Executable entry for `zig build run-stress`.
pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("== heavy race check: {d} threads x {d} rounds x {d} mixed ops ==\n", .{ N_WORKERS, ROUNDS, N_SEQ });
    try heavyRaceCheck();
    std.debug.print("== ABI race check: {d} threads x {d} calls ==\n", .{ N_ABI_WORKERS, N_ABI_CALLS });
    try abiRaceCheck();
    std.debug.print("ALL RACE CHECKS PASSED\n", .{});
}
