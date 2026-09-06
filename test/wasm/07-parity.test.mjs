// Parity matrix: swe_calc_ut vectors across bodies x flags x dates, wasm
// bit-compared against the native pure golden; file-independent APIs
// (houses, ayanamsa, sidtime) asserted freestanding ≡ wasi bit-exactly.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';
import {
  buildSepl18,
  writeEpheDir,
  captureGolden,
  normSerr,
  bitsOf,
  freshWithFiles,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const SWIEPH = 2, MOSEPH = 4, SPEED = 256;

function calcUt(swe, tjd, ipl, iflag) {
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_calc_ut(tjd, ipl, iflag, xx, se.ptr);
    return { rc, bits: bitsOf(swe, xx), serr: se.read() };
  } finally {
    se.free();
    swe.free(xx, 48);
  }
}

// [tjd, ipl, iflag]: fixture-backed SWIEPH (sun/mercury), Moshier elsewhere,
// minimal-transform path, and the out-of-range fallback.
const VECTORS = [
  [JD_J2000, 0, SWIEPH | SPEED],
  [JD_J2000, 2, SWIEPH | SPEED],
  [JD_J2000 - 10, 2, SWIEPH | SPEED],
  [JD_J2000 + 10, 0, SWIEPH | SPEED | 16 | 32 | 64 | 131072], // TRUEPOS|J2000|NONUT|ICRS
  [JD_J2000, 3, MOSEPH | SPEED],
  [JD_J2000, 4, MOSEPH | SPEED],
  [JD_J2000, 1, MOSEPH | SPEED],
  [JD_J2000 + 100, 2, SWIEPH | SPEED], // past tfend -> Moshier fallback
];

describe('parity matrix (both wasm flavors vs native pure golden)', () => {
  let epheDir;
  let sepl;
  before(async () => {
    sepl = buildSepl18();
    epheDir = await writeEpheDir([], 'parity');
  });

  // Fresh golden lifecycle per vector (see freshWithFiles): the golden
  // process ran setEphePath's moon probe, so each wasm instance must too.
  // Sharing instances across vectors (or post-close recomputes) is a
  // different lifecycle whose notes/paths may legitimately differ.
  for (const [tjd, ipl, iflag] of VECTORS) {
    it(`tjd=${tjd} ipl=${ipl} iflag=${iflag}`, async () => {
      const g = await captureGolden(epheDir, tjd, ipl, iflag);
      const fresh = await freshWithFiles([sepl]);
      for (const name of ['freestanding', 'wasi']) {
        const r = calcUt(fresh[name], tjd, ipl, iflag);
        assert.equal(r.rc, g.rc, `${name} rc (serr=[${r.serr}])`);
        assert.deepEqual(r.bits, g.bits, `${name} bits`);
        assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
      }
    });
  }
});

describe('file-independent APIs (freestanding ≡ wasi)', () => {
  let flavors;
  before(async () => {
    flavors = await loadBoth();
  });

  it('houses placidus agree bit-exactly', () => {
    for (const s of [flavors.freestanding, flavors.wasi]) {
      s._cusps = s.allocF64(13);
      s._ascmc = s.allocF64(10);
    }
    try {
      const outs = [];
      for (const s of [flavors.freestanding, flavors.wasi]) {
        const rc = s.exports.swe_houses(JD_J2000, 48.85, 2.35, 80 /* P */, s._cusps, s._ascmc);
        outs.push({ rc, cusps: s.readF64(s._cusps, 13), ascmc: s.readF64(s._ascmc, 10) });
      }
      assert.deepEqual(outs[0], outs[1]);
      assert.ok(outs[0].cusps.slice(1, 13).every((c) => c >= 0 && c < 360));
    } finally {
      for (const s of [flavors.freestanding, flavors.wasi]) {
        s.free(s._cusps, 104);
        s.free(s._ascmc, 80);
      }
    }
  });

  it('ayanamsa + sidtime agree bit-exactly', () => {
    const a = flavors.freestanding.exports;
    const b = flavors.wasi.exports;
    assert.equal(a.swe_get_ayanamsa(JD_J2000), b.swe_get_ayanamsa(JD_J2000));
    assert.equal(a.swe_sidtime(JD_J2000), b.swe_sidtime(JD_J2000));
    assert.equal(a.swe_deltat_ex(JD_J2000, 2, 0), b.swe_deltat_ex(JD_J2000, 2, 0));
  });
});
