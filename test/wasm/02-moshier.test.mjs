// Moshier analytical ephemeris (SEFLG_MOSEPH): the file-independent path that
// works in-browser today. Proves wasm codegen/ABI health and gives the control
// signal every VFS test compares against (file-backed results must differ from
// Moshier only where physics says so, never by wasm breakage).
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';

const SEFLG_MOSEPH = 4;
const JD_J2000 = 2451545.0; // 2000-01-01 12:00 UT
const PLANETS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]; // Sun..Pluto

function calc(swe, tjd, ipl, iflag) {
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_calc(tjd, ipl, iflag, xx, se.ptr);
    return { rc, xx: swe.readF64(xx, 6), serr: se.read() };
  } finally {
    se.free();
    swe.free(xx, 48);
  }
}

describe('moshier (both wasm flavors)', () => {
  let flavors;
  before(async () => {
    flavors = await loadBoth();
  });

  it('all planets compute without error at J2000', () => {
    for (const name of ['freestanding', 'wasi']) {
      for (const ipl of PLANETS) {
        const { rc, serr } = calc(flavors[name], JD_J2000, ipl, SEFLG_MOSEPH);
        assert.ok(rc >= 0, `${name} ipl=${ipl} rc=${rc} serr=[${serr}]`);
      }
    }
  });

  it('freestanding ≡ wasi bit-exactly (same pure math, deterministic wasm)', () => {
    for (const ipl of PLANETS) {
      const a = calc(flavors.freestanding, JD_J2000, ipl, SEFLG_MOSEPH);
      const b = calc(flavors.wasi, JD_J2000, ipl, SEFLG_MOSEPH);
      assert.deepEqual(a.xx, b.xx, `ipl=${ipl}`);
      assert.equal(a.rc, b.rc, `ipl=${ipl} rc`);
    }
  });

  it('deterministic across repeated calls', () => {
    const first = calc(flavors.freestanding, JD_J2000, 1, SEFLG_MOSEPH);
    const second = calc(flavors.freestanding, JD_J2000, 1, SEFLG_MOSEPH);
    assert.deepEqual(first.xx, second.xx);
  });

  it('sun sanity at J2000 (perihelion season)', () => {
    const { xx } = calc(flavors.freestanding, JD_J2000, 0, SEFLG_MOSEPH);
    assert.ok(xx[0] > 279 && xx[0] < 282, `lon=${xx[0]}`); // ~280.4 apparent
    assert.ok(Math.abs(xx[1]) < 0.01, `lat=${xx[1]}`);
    assert.ok(xx[2] > 0.98 && xx[2] < 0.99, `dist=${xx[2]}`); // ~0.9833 AU
  });

  it('longitudes normalized, moon moves fast', () => {
    for (const ipl of PLANETS) {
      const { xx } = calc(flavors.freestanding, JD_J2000, ipl, SEFLG_MOSEPH);
      assert.ok(xx[0] >= 0 && xx[0] < 360, `ipl=${ipl} lon=${xx[0]}`);
    }
    const m1 = calc(flavors.freestanding, JD_J2000, 1, SEFLG_MOSEPH).xx;
    const m2 = calc(flavors.freestanding, JD_J2000 + 1, 1, SEFLG_MOSEPH).xx;
    const dl = Math.abs(m2[0] - m1[0]);
    assert.ok(dl > 10 && dl < 16, `moon daily motion=${dl}`); // ~13.2 deg/day
  });
});
