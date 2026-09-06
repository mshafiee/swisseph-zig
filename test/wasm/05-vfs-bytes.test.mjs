// Byte-exactness: the VFS must store fetched bytes verbatim (ArrayBuffer,
// never text-decode/re-encode) because text parsers demand CRLF and binary
// readers demand exact offsets. Every mutation below flips real file bytes
// and asserts the C-identical diagnostic or result change.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';
import {
  buildSepl18,
  fixCrc,
  bitsOf,
  registerFile,
  setEphePath,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const MERCURY = 2;
const SWIEPH_SPEED = 2 | 256;

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

async function withSepl(seplBytes, tjd = JD_J2000) {
  const flavors = await loadBoth(); // fresh state per mutation
  const out = {};
  for (const name of ['freestanding', 'wasi']) {
    const swe = flavors[name];
    registerFile(swe, 'sepl_18.se1', seplBytes);
    setEphePath(swe, '/ephe');
    out[name] = calcUt(swe, tjd, MERCURY, SWIEPH_SPEED);
  }
  return out;
}

describe('vfs byte-exactness (both wasm flavors)', () => {
  it('CRLF headers accepted (baseline sanity)', async () => {
    const r = await withSepl(buildSepl18().bytes);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(r[name].rc, 258, `${name} rc=${r[name].rc} serr=[${r[name].serr}]`);
    }
  });

  it('bare-LF version line rejected exactly like C (damaged 0)', async () => {
    const bad = buildSepl18({ eol: '\n' });
    const r = await withSepl(bad.bytes);
    for (const name of ['freestanding', 'wasi']) {
      assert.ok(r[name].rc < 0, `${name} rc=${r[name].rc}`);
      assert.ok(/damaged \(0\)/.test(r[name].serr), `${name} serr=[${r[name].serr}]`);
    }
  });

  it('overlong version line rejected (fgets window has no CRLF)', async () => {
    const bad = buildSepl18({ longVersion: true });
    const lon = await withSepl(bad.bytes);
    for (const name of ['freestanding', 'wasi']) {
      assert.ok(lon[name].rc < 0, `${name} rc=${lon[name].rc}`);
      assert.ok(/damaged \(0/.test(lon[name].serr), `${name} serr=[${lon[name].serr}]`);
    }
  });

  it('truncated file rejected by the flen check (damaged 0h)', async () => {
    const full = buildSepl18().bytes;
    const cut = full.subarray(0, full.length - 1);
    const r = await withSepl(cut);
    for (const name of ['freestanding', 'wasi']) {
      assert.ok(r[name].rc < 0, `${name} rc=${r[name].rc}`);
      assert.ok(/damaged \(0h\)/.test(r[name].serr), `${name} serr=[${r[name].serr}]`);
    }
  });

  it('bit flip in segment data changes results (bytes flow verbatim)', async () => {
    const a = buildSepl18().bytes;
    const fb = buildSepl18();
    const b = Buffer.from(fb.bytes);
    b[700] ^= 0x01; // inside body-0 segment coefficients
    fixCrc({ ...fb, bytes: b }); // re-stamp: isolate the data flip from CRC
    const ra = await withSepl(a);
    const rb = await withSepl(b);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(rb[name].rc, 258, `${name} rc=${rb[name].rc} serr=[${rb[name].serr}]`);
      assert.notDeepEqual(rb[name].bits, ra[name].bits, `${name} flip must move results`);
      // ...but both engines still agree with each other on mutated bytes
      const other = name === 'freestanding' ? 'wasi' : 'freestanding';
      assert.deepEqual(rb[name].bits, rb[other].bits, `${name} flavor agreement`);
    }
  });

  it('bad CRC rejected exactly like C (damaged 0n)', async () => {
    const f = buildSepl18();
    const b = Buffer.from(f.bytes);
    b[f.crcPos] ^= 0x01; // corrupt the ulng CRC word
    const r = await withSepl(b);
    for (const name of ['freestanding', 'wasi']) {
      assert.ok(r[name].rc < 0, `${name} rc=${r[name].rc}`);
      assert.ok(/damaged \(0n\)/.test(r[name].serr), `${name} serr=[${r[name].serr}]`);
    }
  });

  it('body absent from open file fails gracefully (no trap)', async () => {
    // sepl_18.se1 holds EMB/Mercury/Sunbary only. Venus triggers
    // get_new_segment on a zero pdp (C UB: (int)inf) — the port returns ERR
    // like C's observable damage error. serr TEXT differs from C's
    // garbage-dependent message by design; only the ERR status is asserted.
    const flavors = await loadBoth();
    for (const name of ['freestanding', 'wasi']) {
      const swe = flavors[name];
      registerFile(swe, 'sepl_18.se1', buildSepl18().bytes);
      setEphePath(swe, '/ephe');
      const r = calcUt(swe, JD_J2000, 3 /* Venus, absent */, SWIEPH_SPEED);
      assert.ok(r.rc < 0, `${name} expected ERR rc=${r.rc}`);
    }
  });

  it('wrong filename line rejected (name check, not crash)', async () => {
    const a = buildSepl18().bytes;
    const b = Buffer.from(a);
    // second header line must equal the requested basename
    const line2 = b.indexOf('sepl_18.se1');
    b.write('sepl_99.se1', line2, 'latin1');
    const r = await withSepl(b);
    for (const name of ['freestanding', 'wasi']) {
      assert.ok(r[name].rc < 0, `${name} rc=${r[name].rc}`);
      assert.ok(/wrong/.test(r[name].serr), `${name} serr=[${r[name].serr}]`);
    }
  });
});
