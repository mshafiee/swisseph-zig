// .se1 binary path over the VFS: open + CRLF header parse + endian check +
// indexed segment seek + packed-chebyshev unpack, end to end through swe_calc.
// Same bytes on disk (native pure golden) and in the VFS must agree bit-for-bit.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';
import {
  buildSepl18,
  writeEpheDir,
  captureGolden,
  normSerr,
  bitsOf,
  registerFile,
  setEphePath,
  freshWithFiles,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const MERCURY = 2;
const SWIEPH_SPEED = 2 | 256;

function calcUt(swe, tjd, ipl, iflag) {
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_calc_ut(tjd, ipl, iflag, xx, se.ptr);
    return { rc, bits: bitsOf(swe, xx), floats: swe.readF64(xx, 6), serr: se.read() };
  } finally {
    se.free();
    swe.free(xx, 48);
  }
}

describe('vfs .se1 (both wasm flavors)', () => {
  let flavors;
  let epheDir;
  let sepl;
  before(async () => {
    flavors = await loadBoth();
    sepl = buildSepl18();
    epheDir = await writeEpheDir([], 'se1');
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      registerFile(swe, sepl.name, sepl.bytes);
      assert.equal(swe.exports.swe_vfs_count(), 1);
      setEphePath(swe, '/ephe'); // nonexistent dir: lookup must key on basename
    }
  });

  it('mercury SWIEPH computes, moon falls back to Moshier with a note', () => {
    for (const name of ['freestanding', 'wasi']) {
      const r = calcUt(flavors[name], JD_J2000, MERCURY, SWIEPH_SPEED);
      assert.equal(r.rc, 258, `${name} rc=${r.rc} serr=[${r.serr}]`);
      // sepl itself must open cleanly; only the (unregistered) moon may miss
      assert.ok(!/sepl_18\.se1.*not found|damaged/i.test(r.serr), `${name} serr=[${r.serr}]`);
      assert.ok(/semo_18\.se1' not found/.test(r.serr), `${name} moon-miss note, serr=[${r.serr}]`);
      assert.ok(/Moshier/.test(r.serr), `${name} moon-Moshier note, serr=[${r.serr}]`);
      assert.ok(r.floats.every(Number.isFinite), `${name} non-finite`);
      assert.ok(r.floats[0] >= 0 && r.floats[0] < 360, `${name} lon=${r.floats[0]}`);
      assert.ok(Math.abs(r.floats[1]) <= 90, `${name} lat=${r.floats[1]}`);
    }
  });

  it('matches the native pure-disk golden bit-for-bit', async () => {
    const g = await captureGolden(epheDir, JD_J2000, MERCURY, SWIEPH_SPEED);
    assert.equal(g.rc, 258, `golden rc=${g.rc} serr=[${g.serr}]`);
    // Fresh lifecycle per golden comparison (see freshWithFiles): the golden
    // process ran setEphePath's moon probe, so wasm must too.
    const fresh = await freshWithFiles([sepl]);
    for (const name of ['freestanding', 'wasi']) {
      const r = calcUt(fresh[name], JD_J2000, MERCURY, SWIEPH_SPEED);
      assert.equal(r.rc, g.rc, `${name} rc`);
      assert.deepEqual(r.bits, g.bits, `${name} position bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
    }
  });

  it('out-of-range date reports file limits, then Moshier fallback', () => {
    for (const name of ['freestanding', 'wasi']) {
      const r = calcUt(flavors[name], JD_J2000 + 1000, MERCURY, SWIEPH_SPEED);
      // header tfstart/tfend parsed from the VFS file proves the range check
      assert.ok(/upper limit 2451575/.test(r.serr), `${name} serr=[${r.serr}]`);
      // C downgrades to Moshier past the range (rc echoes MOSEPH=4|SPEED)
      assert.equal(r.rc, 260, `${name} rc=${r.rc}`);
    }
  });

  it('clear + close + re-register round-trips', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      swe.exports.swe_close();
      swe.exports.swe_vfs_clear();
      assert.equal(swe.exports.swe_vfs_count(), 0);
      registerFile(swe, sepl.name, sepl.bytes);
      setEphePath(swe, '/ephe');
      const r = calcUt(swe, JD_J2000, MERCURY, SWIEPH_SPEED);
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
    }
  });
});

describe('vfs .se1 missing file', () => {
  let flavors;
  before(async () => {
    flavors = await loadBoth(); // fresh instances, empty VFS
  });

  it('fails gracefully (no trap) without sepl registered', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      assert.equal(swe.exports.swe_vfs_count(), 0);
      setEphePath(swe, '/ephe');
      const r = calcUt(swe, JD_J2000, MERCURY, SWIEPH_SPEED);
      // Graceful = returns (Moshier fallback or error) with an explanation.
      assert.ok(r.rc < 0 || r.serr.length > 0, `${name} silent rc=${r.rc}`);
      if (r.rc < 0) assert.ok(/not found/i.test(r.serr), `${name} serr=[${r.serr}]`);
    }
  });
});
