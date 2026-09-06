// EOP end-to-end over the VFS: a synthetic JPL file triggers load_dpsi_deps,
// and the full loader state machine is observed via swe_eop_status().
// JPLHOR downgrade/survival is asserted on rc flag bits (bit-exact); the
// human-readable downgrade serr text is a known engine-level loss on the
// JPLEPH path (swe_calc clears serr after swe_calc_ut's plaus_iflag; only
// swecalc re-plauses, which JPL never reaches) — filed separately, the rc
// bits prove the downgrade mechanism itself.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSynJpl,
  buildEopToday,
  buildEopFinals,
  writeEpheDir,
  captureGolden,
  normSerr,
  bitsOf,
  freshWithFiles,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const MARS = 4;
const JPLEPH = 1, JPLHOR = 256 * 1024, JPLHOR_APPROX = 512 * 1024, SPEED = 256;
const JPLHOR_SPEED = JPLEPH | JPLHOR | SPEED;
const APPROX_RC = JPLEPH | JPLHOR_APPROX | SPEED; // downgrade echo
const HOR_OK_RC = JPLEPH | JPLHOR | 131072 | SPEED; // JPLHOR + ICRS echo
const JPL = 'synJpl.eph';

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

describe('eop loader state machine (both wasm flavors)', () => {
  const jpl = buildSynJpl();
  const today = () => buildEopToday();
  const finals = () => buildEopFinals();

  it('starts at 0 (never attempted)', async () => {
    const fresh = await freshWithFiles([]);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), 0, name);
    }
  });

  it('today-only loads (status 1, finals absence is fine)', async () => {
    const fresh = await freshWithFiles([jpl, today()], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), 1, name);
    }
  });

  it('today+finals loads (status 2)', async () => {
    const fresh = await freshWithFiles([jpl, today(), finals()], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), 2, name);
    }
  });

  it('missing today file (status -1)', async () => {
    const fresh = await freshWithFiles([jpl], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), -1, name);
    }
  });

  it('gapped today file (status -2)', async () => {
    const gapped = buildEopToday([51544, 51546]);
    const fresh = await freshWithFiles([jpl, gapped], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), -2, name);
    }
  });

  it('gapped finals file (status -3)', async () => {
    const gapped = buildEopFinals([51547, 51549]);
    const fresh = await freshWithFiles([jpl, today(), gapped], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), -3, name);
    }
  });

  it('missing JPL file never attempts EOP (status 0)', async () => {
    const fresh = await freshWithFiles([], '/ephe', 'nope.eph');
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), 0, name);
    }
  });

  it('truncated JPL file fails silently like C (status 0)', async () => {
    const cut = { name: JPL, bytes: Buffer.from(jpl.bytes.subarray(0, jpl.bytes.length - 100)) };
    const fresh = await freshWithFiles([cut], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      // openJplFile gets serr=null from swe_set_jpl_file: silent, no EOP.
      assert.equal(fresh[name].exports.swe_eop_status(), 0, name);
    }
  });

  it('corrupt coefficient table fails the open (status 0, no trap)', async () => {
    // Sun start 700 blows earth's region past the record (C OOB read);
    // the open-time validation rejects the file instead.
    const bad = Buffer.from(jpl.bytes);
    bad.writeInt32LE(700, 2696 + 30 * 4); // ipt[30] (sun start)
    const fresh = await freshWithFiles([{ name: JPL, bytes: bad }], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      assert.equal(fresh[name].exports.swe_eop_status(), 0, name);
    }
  });

  it('sunless JPL degrades gracefully (no trap, falls back)', async () => {
    // Sun triple zeroed: open succeeds and EOP loads, but every pleph needs
    // the sun → NOT_AVAILABLE → SWIEPH → Moshier chain, never a trap.
    // Zeroing the triple shrinks derived nb by sun's 12 doubles, so the
    // 96-byte tail pad is trimmed to keep flen == nb exactly.
    const nosun = Buffer.from(jpl.bytes.subarray(0, jpl.bytes.length - 96));
    nosun.fill(0, 2696 + 30 * 4, 2696 + 33 * 4); // ipt[30..32] = 0
    const fresh = await freshWithFiles(
      [{ name: JPL, bytes: nosun }, buildEopToday(), buildEopFinals()], '/ephe', JPL,
    );
    for (const name of ['freestanding', 'wasi']) {
      const swe = fresh[name];
      assert.equal(swe.exports.swe_eop_status(), 2, `${name} EOP still loads`);
      const r = calcUt(swe, JD_J2000, MARS, JPLHOR_SPEED);
      assert.ok((r.rc & 7) !== 1, `${name} JPLEPH must not survive rc=${r.rc}`);
      assert.ok(r.rc >= 0 || r.serr.length > 0, `${name} graceful rc=${r.rc}`);
    }
  });
});

describe('eop jplhor behavior (both wasm flavors vs golden)', () => {
  const jpl = buildSynJpl();

  it('missing EOP downgrades to APPROX (rc bits prove it)', async () => {
    const epheDir = await writeEpheDir([jpl], 'eop-noeop');
    const g = await captureGolden(epheDir, JD_J2000, MARS, JPLHOR_SPEED, JPL);
    assert.equal(g.rc, APPROX_RC, `golden rc=${g.rc}`);
    const fresh = await freshWithFiles([jpl], '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      const r = calcUt(fresh[name], JD_J2000, MARS, JPLHOR_SPEED);
      assert.equal(r.rc, APPROX_RC, `${name} rc=${r.rc} (JPLHOR bit must be gone)`);
      assert.ok((r.rc & JPLHOR) === 0, `${name} JPLHOR bit survived`);
      assert.deepEqual(r.bits, g.bits, `${name} bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
    }
  });

  it('EOP-loaded JPLHOR responds to table values (sensitivity)', async () => {
    // Same JPL, two different EOP tables: nutation must move with the data,
    // and each must match its own golden bit-for-bit.
    const runCase = async (dpsi0, tag) => {
      const files = [jpl, buildEopToday([51544, 51545, 51546], dpsi0, dpsi0 + 1), buildEopFinals()];
      const dir = await writeEpheDir(files, tag);
      const fresh = await freshWithFiles(files, '/ephe', JPL);
      const g = await captureGolden(dir, JD_J2000, MARS, JPLHOR_SPEED, JPL);
      assert.equal(g.rc, HOR_OK_RC, `${tag} golden rc=${g.rc}`);
      const seen = {};
      for (const name of ['freestanding', 'wasi']) {
        const r = calcUt(fresh[name], JD_J2000, MARS, JPLHOR_SPEED);
        assert.equal(r.rc, HOR_OK_RC, `${tag}/${name} rc=${r.rc}`);
        assert.deepEqual(r.bits, g.bits, `${tag}/${name} bits`);
        seen[name] = r.bits;
      }
      return seen;
    };
    const a = await runCase(5, 'eop-sensA');
    const b = await runCase(50, 'eop-sensB');
    assert.notDeepEqual(a.freestanding, b.freestanding, 'EOP values must move nutation');
  });

  it('EOP hold-flat outside the table range', async () => {
    // Before file begin (t<=0 in bessel) and after file end (t>=n-1) the
    // edge samples hold flat — golden equality over both boundaries.
    const files = [jpl, buildEopToday(), buildEopFinals()];
    const epheDir = await writeEpheDir(files, 'eop-edge');
    for (const tjd of [2451544.0, 2451549.0]) {
      const g = await captureGolden(epheDir, tjd, MARS, JPLHOR_SPEED, JPL);
      const fresh = await freshWithFiles(files, '/ephe', JPL);
      for (const name of ['freestanding', 'wasi']) {
        const r = calcUt(fresh[name], tjd, MARS, JPLHOR_SPEED);
        assert.equal(r.rc, g.rc, `${name} tjd=${tjd} rc=${r.rc} serr=[${r.serr}]`);
        assert.deepEqual(r.bits, g.bits, `${name} tjd=${tjd} bits`);
      }
    }
  });

  it('constant EOP table applies an exact known correction', async () => {
    // Uniform table value V: Bessel of a constant is exactly V (linear part
    // V+p*0, all difference terms zero), so the nutation correction is
    // bit-exactly V/3600*DEGTORAD — verifiable by hand, not just by golden.
    // V=45 vs V=5 must shift nutation longitude by exactly 40 arcsec-worth.
    const DEGTORAD = Math.PI / 180;
    const run = async (V, tag) => {
      const files = [jpl, buildEopToday([51544, 51545, 51546], V, V, 0)];
      await writeEpheDir(files, tag);
      const fresh = await freshWithFiles(files, '/ephe', JPL);
      return calcUt(fresh.freestanding, JD_J2000, MARS, JPLHOR_SPEED);
    };
    const r5 = await run(5, 'eop-const5');
    const r45 = await run(45, 'eop-const45');
    assert.equal(r5.rc, HOR_OK_RC);
    assert.equal(r45.rc, HOR_OK_RC);
    const toF = (b) => { const dv = new DataView(new ArrayBuffer(8)); dv.setBigUint64(0, b); return dv.getFloat64(0); };
    // Nutation longitude lives in the output (degrees); isolate the correction
    // shift via runs identical except the table constant. The 40-arcsec table
    // step lands as 40/3600 deg to ~1e-15 (residual is light-time iteration
    // responding to the shifted position — real pipeline physics, not noise).
    const shift = toF(r45.bits[0]) - toF(r5.bits[0]);
    assert.ok(Math.abs(shift - 40 / 3600) < 1e-12, `shift=${shift}`);
    // Direction gate: larger dpsi must move longitude the same way.
    const r50 = await run(50, 'eop-const50');
    const shift2 = toF(r50.bits[0]) - toF(r45.bits[0]);
    assert.ok(Math.sign(shift2) === Math.sign(shift) || shift2 === 0, `monotonic ${shift2} vs ${shift}`);
  });

  it('loaded EOP keeps JPLHOR and computes bit-exactly (nutation off)', async () => {
    // NONUT because full JPLHOR nutation is the port's deliberate
    // `unreachable` (swephlib.zig calc_nutation: EOP consumption not ported —
    // the actual remaining gap). Everything else in the JPLHOR pipe runs:
    // open, pleph/interp over VFS, app_pos. ICRS is added by plaus, as in C.
    const NONUT = 64;
    const flag = JPLHOR_SPEED | NONUT;
    const rcWant = HOR_OK_RC | NONUT;
    const files = [jpl, buildEopToday(), buildEopFinals()];
    const epheDir = await writeEpheDir(files, 'eop-full');
    const g = await captureGolden(epheDir, JD_J2000, MARS, flag, JPL);
    assert.equal(g.rc, rcWant, `golden rc=${g.rc} serr=[${g.serr}]`);
    const fresh = await freshWithFiles(files, '/ephe', JPL);
    for (const name of ['freestanding', 'wasi']) {
      const r = calcUt(fresh[name], JD_J2000, MARS, flag);
      assert.equal(r.rc, rcWant, `${name} rc=${r.rc} serr=[${r.serr}]`);
      assert.ok((r.rc & JPLHOR) !== 0, `${name} JPLHOR bit must survive`);
      assert.deepEqual(r.bits, g.bits, `${name} full-JPLHOR bits`);
      assert.equal(normSerr(r.serr), normSerr(g.serr), `${name} serr`);
    }
  });
});
