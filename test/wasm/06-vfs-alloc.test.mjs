// Allocator under wasm: the page_allocator probe (heap_choice), heap growth
// through fixstar realloc + segment alloc, allocator-consistent cleanup,
// big-file staging through memory.grow, and table limits.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { loadBoth } from './helpers/loader.mjs';
import {
  buildSepl18,
  buildSefstars,
  writeEpheDir,
  captureGoldenStar,
  normSerr,
  bitsOf,
  registerFile,
  setEphePath,
  freshWithFiles,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;

function fixstar2Ut(swe, name, tjd, iflag) {
  const { ptr: sp, len: sl } = swe.writeCString(name);
  const xx = swe.allocF64(6);
  const se = swe.serrBuf();
  try {
    const rc = swe.exports.swe_fixstar2_ut(sp, tjd, iflag, xx, se.ptr);
    return { rc, bits: bitsOf(swe, xx), serr: se.read() };
  } finally {
    se.free();
    swe.free(xx, 48);
    swe.free(sp, sl);
  }
}

// 200 valid star lines (forces the 128 -> 256 fixstar_buf realloc chain).
function bigStars(n = 200) {
  const lines = [];
  for (let i = 0; i < n; i++) {
    const rh = i % 24, rm = (i * 7) % 60, dd = ((i * 13) % 80) - 40;
    lines.push(`Star${i},B${i} X,2000,${rh},${rm},${(i % 50) + 0.1},${dd},${(i * 3) % 60},${(i * 11) % 60},0,0,0,0,-1.0`);
  }
  return buildSefstars(lines);
}

describe('vfs allocator (both wasm flavors)', () => {
  let flavors;
  before(async () => {
    flavors = await loadBoth();
    // Working set for the non-golden tests below (cleanup, big-file,
    // table-full). The golden test uses its own fresh instances.
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      registerFile(swe, 'sepl_18.se1', buildSepl18().bytes);
      registerFile(swe, 'sefstars.txt', bigStars().bytes);
      setEphePath(swe, '/ephe');
    }
  });

  it('heap probe completes without trapping (choice 1=page, 2=fallback)', () => {
    for (const name of ['freestanding', 'wasi']) {
      const c = flavors[name].exports.swe_vfs_heap_choice();
      assert.ok(c === 1 || c === 2, `${name} heap_choice=${c}`);
      console.log(`    ${name}: heap_choice=${c}`);
    }
  });

  it('200-star file loads, late star resolves, golden agrees', async () => {
    const stars = bigStars();
    const epheDir = await writeEpheDir([stars], 'alloc');
    const g = await captureGoldenStar(epheDir, 'Star150', JD_J2000, 0);
    assert.ok(g.rc >= 0, `golden rc=${g.rc} serr=[${g.serr}]`);
    const fresh = await freshWithFiles([buildSepl18(), stars]);
    for (const name of ['freestanding', 'wasi']) {
      const swe = fresh[name];
      const r = fixstar2Ut(swe, 'Star150', JD_J2000, 0);
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
      assert.deepEqual(r.bits, g.bits, `${name} star bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
    }
  });

  it('swe_cleanup frees consistently; reload works after', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      swe.exports.swe_cleanup(); // frees fixstar_buf via the same allocator
      const r = fixstar2Ut(swe, 'Star150', JD_J2000, 0); // reloads from VFS
      assert.ok(r.rc >= 0, `${name} rc=${r.rc} serr=[${r.serr}]`);
    }
  });

  it('5MB registration exercises memory.grow, clear releases', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      const before = swe.exports.swe_vfs_count();
      const big = randomBytes(5 * 1024 * 1024);
      registerFile(swe, 'big.bin', big);
      assert.equal(swe.exports.swe_vfs_count(), before + 1);
      swe.exports.swe_vfs_clear();
      assert.equal(swe.exports.swe_vfs_count(), 0);
    }
  });

  it('table-full returns -2, empty name -3, empty file registers', () => {
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      swe.exports.swe_vfs_clear();
      for (let i = 0; i < 64; i++) registerFile(swe, `f${i}.bin`, Buffer.from([i]));
      const nb = Buffer.from('overflow.bin', 'latin1');
      const np = swe.alloc(nb.length);
      const dp = swe.alloc(1);
      try {
        swe.writeBytes(np, nb);
        const rc = swe.exports.swe_vfs_register(np, nb.length, dp, 1);
        assert.equal(rc, -2, `${name} table-full rc=${rc}`);
        const rcEmpty = swe.exports.swe_vfs_register(0, 0, 0, 0);
        assert.equal(rcEmpty, -3, `${name} empty-name rc=${rcEmpty}`);
      } finally {
        swe.free(np, nb.length);
        swe.free(dp, 1);
      }
      swe.exports.swe_vfs_clear();
      registerFile(swe, 'empty.bin', Buffer.alloc(0));
      assert.equal(swe.exports.swe_vfs_count(), 1);
      swe.exports.swe_vfs_clear();
    }
  });
});
