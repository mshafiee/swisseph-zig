// WASI-flavor semantics: on wasm (freestanding AND wasi) all file I/O goes
// through the VFS — a real file on a preopened FS is deliberately invisible.
// This locks the VFS-first contract: browser and server runtimes behave
// identically, with byte-identical results.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { loadWasi } from './helpers/loader.mjs';
import {
  buildSepl18,
  TMP_DIR,
  captureGolden,
  normSerr,
  bitsOf,
  registerFile,
  setEphePath,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const SWIEPH_SPEED = 2 | 256;
const PREOPEN_DIR = path.join(TMP_DIR, 'wasi-fs');

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

describe('wasi VFS-first semantics', () => {
  let sepl;
  before(async () => {
    sepl = buildSepl18();
    await mkdir(PREOPEN_DIR, { recursive: true });
    await writeFile(path.join(PREOPEN_DIR, sepl.name), sepl.bytes);
  });

  it('real preopened file is invisible without VFS registration', async () => {
    const swe = await loadWasi({ '/ephe': PREOPEN_DIR });
    setEphePath(swe, '/ephe');
    const r = calcUt(swe, JD_J2000, 2, SWIEPH_SPEED);
    // Graceful miss (Moshier fallback or error) — never the disk bytes.
    assert.ok(r.rc < 0 || /not found/i.test(r.serr), `rc=${r.rc} serr=[${r.serr}]`);
  });

  it('VFS registration unlocks bit-exact results on wasi too', async () => {
    const swe = await loadWasi({ '/ephe': PREOPEN_DIR });
    registerFile(swe, sepl.name, sepl.bytes);
    setEphePath(swe, '/ephe');
    const r = calcUt(swe, JD_J2000, 2, SWIEPH_SPEED);
    assert.equal(r.rc, 258, `rc=${r.rc} serr=[${r.serr}]`);
    const g = await captureGolden(PREOPEN_DIR, JD_J2000, 2, SWIEPH_SPEED);
    assert.deepEqual(r.bits, g.bits, 'wasi+VFS ≡ native disk bits');
    assert.equal(normSerr(r.serr), normSerr(g.serr), 'serr');
  });
});
