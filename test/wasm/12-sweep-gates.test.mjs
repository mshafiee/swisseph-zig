// Sweep gates: interleaved-task integrity, hot-path scale identity, timing
// parity, zero-copy/transferable results, and allocation stability.
//
// All hermetic (Moshier + synthetic se1: no companion checkout needed), so
// this file is count-pinned in run-all.mjs.
//
// Background on the benchmark (no >=10x claim): measured sweep-vs-singles
// on the 365x10 Moshier hot path is ~1.0x (best case 1.09x, Sun-only).
// swe_calc_sweep performs the same engine work as the singles loop; it
// only saves JS<->wasm boundary crossings, which are negligible next to
// ~20us of ephemeris compute per position. The gate therefore asserts
// bit-identity at scale plus a no-pathology ceiling (sweep never slower
// than 2x the same-work singles loop, generous absolute budgets), and
// prints the measured ratio informationally.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { Worker } from 'node:worker_threads';
import { loadProduction } from './helpers/loader.mjs';
import { registerFile, buildSepl18 } from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const MOSEPH = 4;
const SPEED = 256;
const TOPOCTR = 32 * 1024;
const SIDEREAL = 64 * 1024;
const HELCTR = 8;
const SWIEPH = 2;
const LAHIRI = 1;
const KRISHNAMURTI = 5;

// SweepRequest layout (frozen in wasm.zig SweepRequest): f64 start_jd @0,
// f64 step_days @8, u32 steps @16, u32 body_mask @20, i32 flags @24,
// u8 use_topo @28, f64 topo[3] @32, u8 use_sidereal @56,
// sidmode{i32 mode @64, f64 t0 @72, f64 ayan @80}, size 88.
function writeReq(swe, req, { start, step, steps, mask, flags, topo = null, sid = null }) {
  const dv = new DataView(swe.exports.memory.buffer);
  dv.setFloat64(req, start, true);
  dv.setFloat64(req + 8, step, true);
  dv.setUint32(req + 16, steps, true);
  dv.setUint32(req + 20, mask, true);
  dv.setInt32(req + 24, flags, true);
  dv.setUint8(req + 28, topo ? 1 : 0);
  if (topo) for (let i = 0; i < 3; i++) dv.setFloat64(req + 32 + i * 8, topo[i], true);
  dv.setUint8(req + 56, sid ? 1 : 0);
  if (sid) {
    dv.setInt32(req + 64, sid[0], true);
    dv.setFloat64(req + 72, sid[1], true);
    dv.setFloat64(req + 80, sid[2], true);
  }
}

function calcUt(swe, h, jd, ipl, iflag) {
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_calc_ut(h, jd, ipl, iflag, xx, se.ptr);
    return { rc, xx: swe.readF64(xx, 6) };
  } finally {
    swe.free(xx, 48);
    se.free();
  }
}

function sweep(swe, h, opts, nF64) {
  const req = swe.alloc(88);
  const out = swe.allocF64(nF64);
  const se = swe.serrBuf();
  try {
    writeReq(swe, req, opts);
    const rc = swe.exports.swe_calc_sweep(h, req, out, nF64, se.ptr);
    assert.equal(rc, nF64, `sweep rc=${rc} serr=${se.read()}`);
    return swe.readF64(out, nF64);
  } finally {
    swe.free(req, 88);
    swe.free(out, nF64 * 8);
    se.free();
  }
}

function med(ns) {
  const s = [...ns].sort((a, b) => a - b);
  return s[s.length >> 1];
}

describe('sweep gates (session API)', () => {
  let swe;
  let pagesWarmed;
  before(async () => {
    swe = await loadProduction();
    // Warm the wasm staging allocator through every size class this file
    // uses, so the pages-stability gate measures steady state, not warmup.
    for (let i = 0; i < 200; i++) {
      const a = swe.alloc(48);
      const b = swe.alloc(256);
      const c = swe.alloc(88);
      swe.free(a, 48);
      swe.free(b, 256);
      swe.free(c, 88);
    }
    pagesWarmed = swe.exports.memory.buffer.byteLength;
  });

  it('chunked sweep survives interleaved conflicting natal', () => {
    // Worker-task simulation: sweep chunks on session S with topo+Lahiri,
    // natal singles on session N with CONFLICTING topo (other hemisphere)
    // and sidereal mode between chunks. wasm.zig's contract: tasks own
    // different sessions, so neither side may observe the other's state.
    const S = swe.exports.swe_session_init();
    const N = swe.exports.swe_session_init();
    const S2 = swe.exports.swe_session_init();
    const N2 = swe.exports.swe_session_init();
    try {
      const steps = 12;
      const mask = 0b11111; // ipl 0..4
      const nbodies = 5;
      // NOTE: session topo/sidereal alone do nothing — the TOPOCTR and
      // SIDEREAL flag bits must be in iflag (same as C). The sweep request
      // carries them here so the session state is actually exercised.
      const flags = MOSEPH | SPEED | TOPOCTR | SIDEREAL;
      const topoS = [8.5, 47.4, 400];
      const topoN = [-70.7, -33.5, 500];
      const req = { start: JD_J2000, step: 1.0, steps, mask, flags, topo: topoS, sid: [LAHIRI, 0, 0] };
      // Chunk A on S.
      const outA = sweep(swe, S, { ...req, steps: 5 }, 5 * nbodies * 6);
      // Conflicting natal on N between chunks.
      assert.equal(swe.exports.swe_set_topo(N, ...topoN), 0);
      assert.equal(swe.exports.swe_set_sid_mode(N, KRISHNAMURTI, 0, 0), 0);
      const natals = [JD_J2000 + 2, JD_J2000 + 7, JD_J2000 + 30].map((jd) =>
        calcUt(swe, N, jd, 1, flags | TOPOCTR | SIDEREAL).xx,
      );
      // Chunk B on S (topo/sidereal must be intact after N ran).
      const outB = sweep(swe, S, { ...req, start: JD_J2000 + 5, steps: steps - 5 }, (steps - 5) * nbodies * 6);
      // References: uninterrupted one-shot sweep + isolated natals.
      const ref = sweep(swe, S2, req, steps * nbodies * 6);
      assert.equal(swe.exports.swe_set_topo(N2, ...topoN), 0);
      assert.equal(swe.exports.swe_set_sid_mode(N2, KRISHNAMURTI, 0, 0), 0);
      const refNatals = [JD_J2000 + 2, JD_J2000 + 7, JD_J2000 + 30].map((jd) =>
        calcUt(swe, N2, jd, 1, flags | TOPOCTR | SIDEREAL).xx,
      );
      assert.deepEqual([...outA, ...outB], ref, 'chunked sweep == one-shot sweep bit-for-bit');
      assert.deepEqual(natals, refNatals, 'interleaved natal == isolated natal bit-for-bit');
      // Cross-talk checks: S really ran topo+Lahiri (differs from plain
      // geocentric tropical single), and N's conflicting topo/mode differs
      // from S's result at the same JD.
      const geo = calcUt(swe, N2, JD_J2000, MOSEPH | SPEED).xx;
      assert.notDeepEqual(ref.slice(6, 12), geo, 'sweep Moon is topocentric, not geocentric');
      assert.notDeepEqual(natals[0], ref.slice(nbodies * 6 * 2 + 6, nbodies * 6 * 2 + 12), 'natal topo != sweep topo at same JD');
    } finally {
      for (const h of [S, N, S2, N2]) swe.exports.swe_session_free(h);
    }
  });

  it('365x10 hot path: bit-identity plus no-pathology ceiling', () => {
    const h = swe.exports.swe_session_init();
    try {
      const steps = 365;
      const bodies = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      const mask = bodies.reduce((m, b) => m | (1 << b), 0);
      const n = steps * bodies.length * 6;
      const req = { start: JD_J2000, step: 1.0, steps, mask, flags: MOSEPH | SPEED };
      const swTimes = [];
      let got;
      for (let r = 0; r < 7; r++) {
        const t = performance.now();
        got = sweep(swe, h, req, n);
        swTimes.push(performance.now() - t);
      }
      const sweepMs = med(swTimes);
      assert.ok(sweepMs < 30_000, `sweep budget blown: ${sweepMs}ms`);
      // Same-work singles reference (app-style: alloc/call/read/free each).
      const sgTimes = [];
      let want;
      for (let r = 0; r < 3; r++) {
        const t = performance.now();
        want = [];
        for (let s = 0; s < steps; s++)
          for (const ipl of bodies) want.push(...calcUt(swe, h, JD_J2000 + s, ipl, MOSEPH | SPEED).xx);
        sgTimes.push(performance.now() - t);
      }
      const singlesMs = med(sgTimes);
      assert.deepEqual(got, want, '365x10 sweep == singles bit-for-bit');
      console.log(`sweep-vs-singles: sweep=${sweepMs.toFixed(1)}ms singles=${singlesMs.toFixed(1)}ms ratio=${(singlesMs / sweepMs).toFixed(2)}x`);
      assert.ok(sweepMs <= 2 * singlesMs, `sweep pathologically slower: ${sweepMs}ms vs ${singlesMs}ms`);
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('zero-copy view plus transferable handoff', async () => {
    const h = swe.exports.swe_session_init();
    try {
      const steps = 3;
      const mask = 0b11;
      const n = steps * 2 * 6;
      const req = swe.alloc(88);
      const out = swe.allocF64(n);
      const se = swe.serrBuf();
      try {
        writeReq(swe, req, { start: JD_J2000, step: 1.0, steps, mask, flags: MOSEPH | SPEED });
        assert.equal(swe.exports.swe_calc_sweep(h, req, out, n, se.ptr), n);
        // Zero-copy: view straight over wasm memory, no readF64 copy.
        const mem = swe.exports.memory.buffer;
        const view = new Float64Array(mem, out, n);
        assert.equal(view.buffer, mem, 'view shares wasm memory (zero-copy)');
        const want = [];
        for (let s = 0; s < steps; s++)
          for (const ipl of [0, 1]) want.push(...calcUt(swe, h, JD_J2000 + s, ipl, MOSEPH | SPEED).xx);
        assert.deepEqual([...view], want, 'zero-copy view matches singles');
        // Transferable handoff: copy out to a standalone buffer and move it
        // to a worker (wasm memory itself must never be transferred).
        const owned = view.slice().buffer;
        let sum = 0;
        for (const v of want) sum += v;
        const reply = await new Promise((resolve, reject) => {
          const w = new Worker(
            `const { parentPort } = require('node:worker_threads');
             parentPort.once('message', (buf) => {
               const v = new Float64Array(buf);
               let s = 0; for (let i = 0; i < v.length; i++) s += v[i];
               parentPort.postMessage({ n: v.length, sum: s });
             });`,
            { eval: true },
          );
          w.once('message', (m) => { w.terminate(); resolve(m); });
          w.once('error', (e) => { w.terminate(); reject(e); });
          w.postMessage(owned, [owned]);
        });
        assert.equal(reply.n, n);
        assert.equal(reply.sum, sum);
        assert.equal(owned.byteLength, 0, 'transferred buffer neutered (moved, not copied)');
      } finally {
        swe.free(req, 88);
        swe.free(out, n * 8);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('pages stable plus 500 session/VFS cycles bit-identical', () => {
    // Legal high-churn pattern (handles must never outlive a clear:
    // free session, clear VFS, re-register, fresh session, set path).
    // Guards allocator/VFS leaks (pages-stable) and handle staleness
    // (bit-identity) across 500 cycles of heliocentric Mercury on the
    // synthetic sepl_18 (HELCTR needs no Moon file).
    const sepl = buildSepl18();
    const pages = () => swe.exports.memory.buffer.byteLength;
    function oneCycle() {
      swe.exports.swe_vfs_clear();
      registerFile(swe, 'sepl_18.se1', sepl.bytes);
      const h = swe.exports.swe_session_init();
      try {
        const { ptr, len } = swe.writeCString('/ephe');
        swe.exports.swe_set_ephe_path(h, ptr);
        swe.free(ptr, len);
        return calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED | HELCTR);
      } finally {
        swe.exports.swe_session_free(h);
      }
    }
    // Warm the exact cycle shape until the allocator freelist settles
    // (stable page count for 100 consecutive cycles); a true leak grows
    // without bound and never settles.
    let calm = 0;
    for (let c = 0; c < 3000 && calm < 100; c++) {
      const before = pages();
      oneCycle();
      calm = pages() === before ? calm + 1 : 0;
    }
    assert.ok(calm === 100, 'allocator never settled (leak?)');
    const pages0 = pages();
    const t = performance.now();
    let first = null;
    for (let c = 0; c < 500; c++) {
      const r = oneCycle();
      assert.ok(r.rc >= 0, `cycle ${c} rc=${r.rc}`);
      if (c === 0) first = r.xx;
      else assert.deepEqual(r.xx, first, `cycle ${c} diverged`);
    }
    swe.exports.swe_vfs_clear();
    const ms = performance.now() - t;
    console.log(`500 session/VFS cycles: ${ms.toFixed(0)}ms`);
    assert.ok(ms < 30_000, `cycle budget blown: ${ms}ms`);
    assert.equal(
      swe.exports.memory.buffer.byteLength,
      pages0,
      `wasm memory grew: ${pages0} -> ${swe.exports.memory.buffer.byteLength}`,
    );
  });
});
