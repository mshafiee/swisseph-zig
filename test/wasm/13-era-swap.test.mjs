// P1 data-layer gates (plan §10 P1 / §6 / §12): era-swap VFS primitive,
// pack-readiness probe (swe_get_current_file_data), and the era-swap memory
// ceiling via swe_vfs_count back to baseline.
//
// Hermetic: Moshier + synthetic se1 (no companion checkout needed), so this
// file is count-pinned in run-all.mjs.
//
// Era model in these tests: one era = {sepl_18.se1} registered for a JD
// window; swapping eras = evict('sepl_18.se1') + register the other era's
// bytes under the same name. No session restart required — that is the
// point: the pack pipeline (web repo) will do exactly this in Cache API.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadProduction } from './helpers/loader.mjs';
import { registerFile, buildSepl18 } from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0; // inside the base fixture era
const MOSEPH = 4;
const SWIEPH = 2;
const SPEED = 256;

// swe_get_current_file_data returns: 0 = era not loaded, 1 = loaded,
// -1 = bad handle, -2 = bad ifno.
function fileData(swe, h, ifno) {
  const tsp = swe.allocF64(2); // tfstart, tfend
  const dnp = swe.allocI32(1);
  const fnp = swe.alloc(256);
  try {
    const rc = swe.exports.swe_get_current_file_data(h, ifno, tsp, tsp + 8, dnp, fnp, 256);
    return {
      rc,
      tfstart: swe.readF64(tsp, 2)[0],
      tfend: swe.readF64(tsp, 2)[1],
      denum: swe.readI32(dnp, 1)[0],
      fname: swe.readCString(fnp, 256),
    };
  } finally {
    swe.free(tsp, 16);
    swe.free(dnp, 4);
    swe.free(fnp, 256);
  }
}

function calcUt(swe, h, jd, ipl, iflag) {
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_calc_ut(h, jd, ipl, iflag, xx, se.ptr);
    return { rc, xx: swe.readF64(xx, 6), serr: se.read() };
  } finally {
    swe.free(xx, 48);
    se.free();
  }
}

describe('era-swap data-layer gates (session API)', () => {
  let swe;

  before(async () => {
    swe = await loadProduction();
  });

  it('bridge version is 2 (this suite pins the era-swap ABI)', () => {
    assert.equal(swe.exports.swe_bridge_version(), 2);
  });

  it('swe_vfs_evict frees exactly one file; others survive', () => {
    const eraA = buildSepl18();
    swe.exports.swe_vfs_clear();
    registerFile(swe, 'sepl_18.se1', eraA.bytes);
    registerFile(swe, 'sefstars.txt', Buffer.from('Sirius,alf CMa,2000,6,45,8.9,-16,42,58,-553.0,-1205.0,-7.6,379.2,-1.46\r\n', 'latin1'));
    registerFile(swe, 'seorbel.txt', Buffer.from('J2000,J2000,120.5,1.5,0.2,30.0,45.0,10.0,CupidoX\r\n', 'latin1'));
    assert.equal(swe.exports.swe_vfs_count(), 3);
    const { ptr, len } = swe.writeCString('sepl_18.se1');
    try {
      assert.equal(swe.exports.swe_vfs_evict(ptr, len - 1), 0);
    } finally {
      swe.free(ptr, len);
    }
    assert.equal(swe.exports.swe_vfs_count(), 2, 'only the evicted file goes');
    // evicting again → not found; bad name → -3; clearing still works
    const { ptr: p2, len: l2 } = swe.writeCString('sepl_18.se1');
    const { ptr: p3, len: l3 } = swe.writeCString('');
    try {
      assert.equal(swe.exports.swe_vfs_evict(p2, l2 - 1), -1);
      assert.equal(swe.exports.swe_vfs_evict(p3, l3 - 1), -3);
    } finally {
      swe.free(p2, l2);
      swe.free(p3, l3);
    }
    swe.exports.swe_vfs_clear();
    assert.equal(swe.exports.swe_vfs_count(), 0);
  });

  it('evicted-while-open: cached segments stay valid, new-segment reads fail loudly, reload recovers', () => {
    const eraA = buildSepl18();
    swe.exports.swe_vfs_clear();
    registerFile(swe, 'sepl_18.se1', eraA.bytes);
    const h = swe.exports.swe_session_init();
    try {
      const { ptr, len } = swe.writeCString('/ephe');
      swe.exports.swe_set_ephe_path(h, ptr);
      swe.free(ptr, len);
      // SWIEPH calc opens the file and caches a 2-day Chebyshev segment
      const first = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(first.rc >= 0, `pre-evict calc rc=${first.rc} serr=${first.serr}`);

      // era-swap underneath the live session: evict the file it holds open
      const e = swe.writeCString('sepl_18.se1');
      assert.equal(swe.exports.swe_vfs_evict(e.ptr, e.len - 1), 0);
      swe.free(e.ptr, e.len);

      // Same JD: the parsed segment is in session memory — a cache hit is
      // CORRECT (bit-identical, no file involved, no wrong-data hazard).
      const cached = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(cached.rc >= 0, `cached calc rc=${cached.rc} serr=${cached.serr}`);
      assert.deepEqual(cached.xx, first.xx, 'cached segment unaffected by eviction');

      // A DIFFERENT segment forces a file read through the dead handle:
      // must fail loudly (damage / not-found diagnostic), never silently
      // serve wrong or absent bytes. JD 2451520 sits in another 2-day
      // segment inside the same era window.
      const miss = calcUt(swe, h, 2451520.0, 2, SWIEPH | SPEED);
      assert.ok(
        miss.rc < 0 || /damaged|not found|error/i.test(miss.serr),
        `expected loud failure on dead-handle read, rc=${miss.rc} serr=${miss.serr}`,
      );

      // recovery path from plan §6: fetch the pack → re-register → close
      // (drops parsed caches + dead handle) → recalc gets the era back.
      registerFile(swe, 'sepl_18.se1', eraA.bytes);
      assert.equal(swe.exports.swe_close(h), 0);
      const recovered = calcUt(swe, h, 2451520.0, 2, SWIEPH | SPEED);
      assert.ok(recovered.rc >= 0, `recovered rc=${recovered.rc} serr=${recovered.serr}`);
      assert.equal(swe.exports.swe_close(h), 0);
      const again = calcUt(swe, h, 2451520.0, 2, SWIEPH | SPEED);
      assert.ok(again.rc >= 0);
      assert.deepEqual(again.xx, recovered.xx, 'reload is deterministic after eviction churn');
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('re-registered bytes under the same name: dead handle fails loudly, close+recalc reads the new era', () => {
    const eraA = buildSepl18({ coordShift: 0 });
    const eraB = buildSepl18({ coordShift: 0.05 });
    swe.exports.swe_vfs_clear();
    registerFile(swe, 'sepl_18.se1', eraA.bytes);
    const h = swe.exports.swe_session_init();
    try {
      const { ptr, len } = swe.writeCString('/ephe');
      swe.exports.swe_set_ephe_path(h, ptr);
      swe.free(ptr, len);
      const a = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(a.rc >= 0);

      // Replace bytes WITHOUT evict (same name, pack pipeline's
      // "refresh" shape): the stale handle dies; the era probe must flip
      // to "absent" for a NEW segment read... but first, same-JD cache
      // hit still returns era A legitimately.
      registerFile(swe, 'sepl_18.se1', eraB.bytes);
      const cached = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.deepEqual(cached.xx, a.xx, 'same-JD cache hit serves the parsed era-A segment');

      // New segment through the dead handle: loud failure, not era-B
      // bytes smuggled through a stale cursor.
      const miss = calcUt(swe, h, 2451520.0, 2, SWIEPH | SPEED);
      assert.ok(
        miss.rc < 0 || /damaged|not found|error/i.test(miss.serr),
        `expected loud failure on dead-handle read, rc=${miss.rc} serr=${miss.serr}`,
      );

      // close + recalc: the new bytes (era B) are actually used.
      assert.equal(swe.exports.swe_close(h), 0);
      const b = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(b.rc >= 0, `b rc=${b.rc} serr=${b.serr}`);
      assert.notDeepEqual(b.xx, a.xx, 'replaced bytes are actually used after reopen');
      const b2 = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(b2.rc >= 0);
      assert.deepEqual(b2.xx, b.xx, 'reopen reads the replacement consistently');
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('swe_get_current_file_data reports the live era (pack-readiness probe, §6)', () => {
    const eraA = buildSepl18();
    swe.exports.swe_vfs_clear();
    const h = swe.exports.swe_session_init();
    try {
      // not loaded yet: rc 0 + zeros — the readiness state machine's
      // "absent, fetch it" signal
      let fd = fileData(swe, h, 0);
      assert.equal(fd.rc, 0);
      assert.equal(fd.tfstart, 0);
      assert.equal(fd.denum, 0);
      // bad handle / bad ifno (null out-pointers are legal: rc-only probe)
      assert.equal(fileData(swe, h, 7).rc, -2);
      assert.equal(swe.exports.swe_get_current_file_data(99, 0, 0, 0, 0, 0, 0), -1);

      registerFile(swe, 'sepl_18.se1', eraA.bytes);
      const { ptr, len } = swe.writeCString('/ephe');
      swe.exports.swe_set_ephe_path(h, ptr);
      swe.free(ptr, len);
      const c = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(c.rc >= 0, `calc rc=${c.rc} serr=${c.serr}`);

      fd = fileData(swe, h, 0);
      assert.equal(fd.rc, 1, 'planets file slot reads as loaded');
      assert.equal(fd.denum, 431, 'header DE number');
      assert.equal(fd.tfstart, eraA.tfstart, 'era start matches the pack header');
      assert.equal(fd.tfend, eraA.tfend, 'era end matches the pack header');
      assert.ok(fd.fname.endsWith('sepl_18.se1'), `fname=${fd.fname}`);

      // moon slot absent (no semo_18 registered): rc 0 — exactly the
      // "missing-era prompt" signal from plan §6
      assert.equal(fileData(swe, h, 1).rc, 0);

      // era-swap: evict → probe drops to rc 0 (dead fidat handle reports
      // absent — the state machine's "fetch it" signal); re-register new
      // era with a different window → probe reports the NEW era after
      // close + recalc.
      const e = swe.writeCString('sepl_18.se1');
      assert.equal(swe.exports.swe_vfs_evict(e.ptr, e.len - 1), 0);
      swe.free(e.ptr, e.len);
      assert.equal(fileData(swe, h, 0).rc, 0, 'evicted era reads as absent');

      const eraB = buildSepl18({ tfstart: 2451545.0, name: 'sepl_18.se1' }); // shifted window
      registerFile(swe, 'sepl_18.se1', eraB.bytes);
      swe.exports.swe_close(h);
      const c2 = calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      assert.ok(c2.rc >= 0, `calc2 rc=${c2.rc} serr=${c2.serr}`);
      fd = fileData(swe, h, 0);
      assert.equal(fd.rc, 1);
      assert.equal(fd.tfstart, eraB.tfstart, 'probe reports the NEW era start');
      assert.equal(fd.tfend, eraB.tfend, 'probe reports the NEW era end');
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('era-swap 500 cycles: swe_vfs_count returns to baseline, pages stable, bit-identical', () => {
    // Plan P1 gate: "500-cycle era-swap memory ceiling (swe_vfs_count back
    // to baseline, WASM pages stable ≤16 MB)". Each cycle = evict +
    // register + session init + calc + session free — the exact shape the
    // production pack pipeline uses for era transitions, without ever
    // calling swe_vfs_clear().
    const eraA = buildSepl18();
    const pages = () => swe.exports.memory.buffer.byteLength;
    const countBaseline = swe.exports.swe_vfs_count(); // 0 here

    function oneCycle() {
      // evict whatever era is registered, register the next era's bytes
      const name = swe.writeCString('sepl_18.se1');
      swe.exports.swe_vfs_evict(name.ptr, name.len - 1);
      swe.free(name.ptr, name.len);
      registerFile(swe, 'sepl_18.se1', eraA.bytes);
      const h = swe.exports.swe_session_init();
      try {
        const { ptr, len } = swe.writeCString('/ephe');
        swe.exports.swe_set_ephe_path(h, ptr);
        swe.free(ptr, len);
        return calcUt(swe, h, JD_J2000, 2, SWIEPH | SPEED);
      } finally {
        swe.exports.swe_session_free(h);
      }
    }

    // Warm until the allocator freelist settles (same discipline as the
    // 12-sweep-gates cycle test).
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
      assert.ok(r.rc >= 0, `cycle ${c} rc=${r.rc} serr=${r.serr}`);
      if (c === 0) first = r.xx;
      else assert.deepEqual(r.xx, first, `cycle ${c} diverged`);
    }
    const ms = performance.now() - t;
    console.log(`500 era-swap cycles: ${ms.toFixed(0)}ms, pages=${pages()} (${(pages() / 65536).toFixed(1)} MB)`);
    assert.ok(ms < 60_000, `era-swap budget blown: ${ms}ms`);
    assert.equal(swe.exports.swe_vfs_count(), countBaseline + 1, 'exactly one era file remains after 500 swaps');
    assert.equal(pages(), pages0, `wasm memory grew: ${pages0} -> ${pages()}`);
    assert.ok(pages() <= 16 * 1024 * 1024, `page ceiling exceeded: ${pages()} bytes`);
    // cleanup: evict the last era so the VFS returns fully to baseline
    const name = swe.writeCString('sepl_18.se1');
    swe.exports.swe_vfs_evict(name.ptr, name.len - 1);
    swe.free(name.ptr, name.len);
    assert.equal(swe.exports.swe_vfs_count(), countBaseline, 'swe_vfs_count back to baseline');
  });

  it('missing-era query surfaces the standard engine diagnostic and prompts before fallback', () => {
    // Plan P1 gate: "missing-era queries surface the standard engine
    // diagnostic and prompt before any fallback". Register ONLY sepl (no
    // moon file): a Moon calc must fail with the standard
    // "not found in PATH" diagnostic naming the missing shard — the
    // surface the worker readiness state machine matches on to trigger the
    // §6 prompt — and must NOT silently deliver Moshier output.
    const eraA = buildSepl18();
    swe.exports.swe_vfs_clear();
    registerFile(swe, 'sepl_18.se1', eraA.bytes);
    const h = swe.exports.swe_session_init();
    try {
      const { ptr, len } = swe.writeCString('/ephe');
      swe.exports.swe_set_ephe_path(h, ptr);
      swe.free(ptr, len);
      const m = calcUt(swe, h, JD_J2000, 1, SWIEPH | SPEED);
      assert.ok(m.rc < 0 || /semo_18\.se1' not found/.test(m.serr), `expected missing-moon diagnostic, rc=${m.rc} serr=${m.serr}`);
      assert.ok(!/Moshier/.test(m.serr), 'no silent Moshier fallback when a shard is missing');
      // and the probe confirms the moon era is absent
      assert.equal(fileData(swe, h, 1).rc, 0);
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('Moshier readiness path unaffected by VFS churn (full-pack-absent flow)', () => {
    // Degraded-mode hierarchy (plan §2): with NO pack registered at all,
    // Moshier renders today — the offline-before-fetch banner path.
    swe.exports.swe_vfs_clear();
    const h = swe.exports.swe_session_init();
    try {
      const r = calcUt(swe, h, JD_J2000, 0, MOSEPH | SPEED);
      assert.ok(r.rc >= 0, `moshier rc=${r.rc} serr=${r.serr}`);
      assert.equal(swe.exports.swe_vfs_count(), 0);
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });
});
