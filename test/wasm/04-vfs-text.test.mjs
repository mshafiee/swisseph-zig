// Text files over the VFS: sefstars.txt (swe_fixstar2), seorbel.txt
// (fictitious planets), EOP registration. Fixed stars and fictitious bodies
// are compared against the native pure-disk golden bit-for-bit.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';
import {
  buildSepl18,
  buildSefstars,
  buildSeorbel,
  buildEopToday,
  writeEpheDir,
  captureGolden,
  captureGoldenStar,
  normSerr,
  bitsOf,
  registerFile,
  setEphePath,
  freshWithFiles,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const CUPIDO = 40; // SE_FICT_OFFSET: first fictitious body

function fixstar2(swe, name, tjd, iflag) {
  const { ptr: sp, len: sl } = swe.writeCString(name);
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_fixstar2_ut(sp, tjd, iflag, xx, se.ptr);
    return { rc, bits: bitsOf(swe, xx), floats: swe.readF64(xx, 6), serr: se.read() };
  } finally {
    se.free();
    swe.free(xx, 48);
    swe.free(sp, sl);
  }
}

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

function planetName(swe, ipl) {
  const p = swe.alloc(64);
  try {
    swe.exports.swe_get_planet_name(ipl, p);
    return swe.readCString(p, 64);
  } finally {
    swe.free(p, 64);
  }
}

describe('vfs text files (both wasm flavors)', () => {
  let flavors;
  let epheDir;
  const files = [buildSepl18(), buildSefstars(), buildSeorbel(), buildEopToday()];
  before(async () => {
    flavors = await loadBoth();
    epheDir = await writeEpheDir(files.slice(1), 'text'); // sepl + texts on disk for golden
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      for (const f of files) registerFile(swe, f.name, f.bytes);
      assert.equal(swe.exports.swe_vfs_count(), files.length);
      setEphePath(swe, '/ephe');
    }
  });

  it('fixstar Sirius resolves and matches the golden bit-for-bit', async () => {
    const g = await captureGoldenStar(epheDir, 'Sirius', JD_J2000, 0);
    const fresh = await freshWithFiles(files);
    for (const name of ['freestanding', 'wasi']) {
      const swe = fresh[name];
      const r = fixstar2(swe, 'Sirius', JD_J2000, 0);
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
      assert.deepEqual(r.bits, g.bits, `${name} star bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
      // default output is apparent ecliptic: Sirius ≈ lon 104°, lat -39.6°
      assert.ok(r.floats[0] > 100 && r.floats[0] < 108, `${name} lon=${r.floats[0]}`);
      assert.ok(r.floats[1] > -42 && r.floats[1] < -37, `${name} lat=${r.floats[1]}`);
    }
  });

  it('fictitious Cupido uses file elements, not built-ins', async () => {
    const g = await captureGolden(epheDir, JD_J2000, CUPIDO, 2 | 256);
    assert.ok(g.rc >= 0, `golden rc=${g.rc} serr=[${g.serr}]`);
    const fresh = await freshWithFiles(files);
    for (const name of ['freestanding', 'wasi']) {
      const swe = fresh[name];
      const r = calcUt(swe, JD_J2000, CUPIDO, 2 | 256);
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
      assert.deepEqual(r.bits, g.bits, `${name} fict bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
      // file elements (a=1.5, e=0.2, J2000) vs built-in Cupido (a=41, J1900):
      // positions must differ from the built-in computation below.
    }
  });

  it('file elements differ observably from built-ins', () => {
    for (const name of ['freestanding', 'wasi']) {
      const withFile = calcUt(flavors[name], JD_J2000, CUPIDO, 2 | 256);
      flavors[name].exports.swe_vfs_clear(); // drop seorbel -> built-in Neely
      flavors[name].exports.swe_close();
      const builtin = calcUt(flavors[name], JD_J2000, CUPIDO, 2 | 256);
      assert.ok(builtin.rc >= 0, `${name} builtin rc=${builtin.rc} serr=[${builtin.serr}]`);
      assert.notDeepEqual(withFile.bits, builtin.bits, `${name} file must change elements`);
      // planet name comes from the file too
      for (const f of files) registerFile(flavors[name], f.name, f.bytes);
      assert.equal(planetName(flavors[name], CUPIDO).split(',')[0].trim(), 'CupidoX');
    }
  });

  it('malformed seorbel line errors like C (nine elements required)', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      swe.exports.swe_vfs_clear();
      swe.exports.swe_close();
      registerFile(swe, 'sepl_18.se1', files[0].bytes);
      registerFile(swe, 'seorbel.txt', buildSeorbel(['J2000,J2000,0,1.0,0.1,0,0,0']).bytes);
      setEphePath(swe, '/ephe');
      const r = calcUt(swe, JD_J2000, CUPIDO, 2 | 256);
      assert.ok(r.rc < 0, `${name} expected ERR rc=${r.rc}`);
      assert.ok(/nine elements required/.test(r.serr), `${name} serr=[${r.serr}]`);
      // restore full fixture set for later tests in this file
      swe.exports.swe_vfs_clear();
      swe.exports.swe_close();
      for (const f of files) registerFile(swe, f.name, f.bytes);
      setEphePath(swe, '/ephe');
    }
  });

  it('EOP files register and do not disturb calculations', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      const r = calcUt(swe, JD_J2000, CUPIDO, 2 | 256);
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
      // Full EOP end-to-end (loader state machine via synthetic JPL) lives
      // in 09-eop.test.mjs; here we only prove registration is harmless.
    }
  });
});
