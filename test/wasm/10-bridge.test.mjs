// Production root (zig-out/wasm/swe.wasm): session lifecycle, hermetic
// single calls, vector sweep, and VFS-backed precision through the bridge.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadProduction } from './helpers/loader.mjs';
import {
  buildSepl18,
  buildSefstars,
  writeEpheDir,
  captureGolden,
  registerFile,
  bitsOf,
} from './helpers/fixtures.mjs';

const JD_J2000 = 2451545.0;
const SEFLG_MOSEPH = 4;
const SEFLG_SWIEPH = 2;
const SEFLG_SPEED = 256;
const SEFLG_SIDEREAL = 64 * 1024;
const SE_SIDM_LAHIRI = 1;

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

describe('production bridge (swe.wasm session API)', () => {
  let swe;
  before(async () => {
    swe = await loadProduction();
  });

  it('bridge version is 1', () => {
    assert.equal(swe.exports.swe_bridge_version(), 1);
  });

  it('session lifecycle: 4 slots, exhaustion, reuse', () => {
    const hs = [0, 1, 2, 3].map(() => swe.exports.swe_session_init());
    assert.deepEqual(hs, [0, 1, 2, 3]);
    assert.equal(swe.exports.swe_session_init(), -1);
    swe.exports.swe_session_free(1);
    assert.equal(swe.exports.swe_session_init(), 1);
    for (const h of [0, 1, 2, 3]) swe.exports.swe_session_free(h);
  });

  it('Moshier Sun matches the native golden bit-for-bit', async () => {
    const dir = await writeEpheDir([], 'bridge');
    const g = await captureGolden(dir, JD_J2000, 0, SEFLG_MOSEPH | SEFLG_SPEED);
    const h = swe.exports.swe_session_init();
    try {
      const xx = swe.allocF64(6);
      const se = swe.serrBuf();
      try {
        const rc = swe.exports.swe_calc_ut(h, JD_J2000, 0, SEFLG_MOSEPH | SEFLG_SPEED, xx, se.ptr);
        assert.equal(rc, g.rc);
        assert.deepEqual(bitsOf(swe, xx), g.bits);
      } finally {
        swe.free(xx, 48);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('sweep equals repeated single calls bit-for-bit', () => {
    const h = swe.exports.swe_session_init();
    try {
      const steps = 3;
      const mask = 0b11; // Sun + Moon
      const req = swe.alloc(88);
      const out = swe.allocF64(steps * 2 * 6);
      const se = swe.serrBuf();
      try {
        const dv = new DataView(swe.exports.memory.buffer);
        dv.setFloat64(req, JD_J2000, true);
        dv.setFloat64(req + 8, 1.0, true);
        dv.setUint32(req + 16, steps, true);
        dv.setUint32(req + 20, mask, true);
        dv.setInt32(req + 24, SEFLG_MOSEPH | SEFLG_SPEED, true);
        dv.setUint8(req + 28, 0);
        dv.setUint8(req + 56, 0);
        const rc = swe.exports.swe_calc_sweep(h, req, out, steps * 2 * 6, se.ptr);
        assert.equal(rc, steps * 2 * 6);
        const got = swe.readF64(out, steps * 2 * 6);
        const want = [];
        for (let s = 0; s < steps; s++)
          for (const ipl of [0, 1]) want.push(...calcUt(swe, h, JD_J2000 + s, ipl, SEFLG_MOSEPH | SEFLG_SPEED).xx);
        assert.deepEqual(got, want);
      } finally {
        swe.free(req, 88);
        swe.free(out, steps * 2 * 6 * 8);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('guards: bad handle, empty sweep, short buffer', () => {
    const xx = swe.allocF64(6);
    const se = swe.serrBuf();
    const req = swe.alloc(88);
    try {
      assert.equal(swe.exports.swe_calc_ut(99, JD_J2000, 0, SEFLG_MOSEPH, xx, se.ptr), -1);
      const dv = new DataView(swe.exports.memory.buffer);
      const h = swe.exports.swe_session_init();
      try {
        dv.setFloat64(req, JD_J2000, true);
        dv.setFloat64(req + 8, 1.0, true);
        dv.setUint32(req + 16, 0, true); // zero steps
        dv.setUint32(req + 20, 0b11, true);
        assert.equal(swe.exports.swe_calc_sweep(h, req, xx, 12, se.ptr), -1);
        dv.setUint32(req + 16, 2, true);
        dv.setUint32(req + 20, 0, true); // empty mask
        assert.equal(swe.exports.swe_calc_sweep(h, req, xx, 12, se.ptr), -1);
        dv.setUint32(req + 20, 0b11, true);
        assert.equal(swe.exports.swe_calc_sweep(h, req, xx, 1, se.ptr), -1); // short buffer
      } finally {
        swe.exports.swe_session_free(h);
      }
    } finally {
      swe.free(xx, 48);
      se.free();
      swe.free(req, 88);
    }
  });

  it('sweep sidereal/topo matches session-set single calls', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      assert.equal(e.swe_set_sid_mode(h, SE_SIDM_LAHIRI, 0, 0), 0);
      const a = calcUt(swe, h, JD_J2000, 0, SEFLG_MOSEPH | SEFLG_SPEED | SEFLG_SIDEREAL).xx;
      const req = swe.alloc(88);
      const out = swe.allocF64(6);
      const se = swe.serrBuf();
      try {
        const dv = new DataView(swe.exports.memory.buffer);
        dv.setFloat64(req, JD_J2000, true);
        dv.setFloat64(req + 8, 1.0, true);
        dv.setUint32(req + 16, 1, true);
        dv.setUint32(req + 20, 0b1, true);
        dv.setInt32(req + 24, SEFLG_MOSEPH | SEFLG_SPEED | SEFLG_SIDEREAL, true);
        dv.setUint8(req + 28, 0);
        dv.setUint8(req + 56, 1);
        dv.setInt32(req + 64, SE_SIDM_LAHIRI, true);
        dv.setFloat64(req + 72, 0, true);
        dv.setFloat64(req + 80, 0, true);
        assert.equal(e.swe_calc_sweep(h, req, out, 6, se.ptr), 6);
        assert.deepEqual(swe.readF64(out, 6), a);
      } finally {
        swe.free(req, 88);
        swe.free(out, 48);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('sessions are isolated from each other', () => {
    const SEFLG_TOPOCTR = 32 * 1024;
    const a = swe.exports.swe_session_init();
    const b = swe.exports.swe_session_init();
    try {
      assert.equal(swe.exports.swe_set_topo(a, 8.5, 47.4, 400), 0);
      const flg = SEFLG_MOSEPH | SEFLG_SPEED | SEFLG_TOPOCTR;
      const ma = calcUt(swe, a, JD_J2000, 1, flg).xx;
      const mb = calcUt(swe, b, JD_J2000, 1, flg).xx;
      assert.notDeepEqual(ma, mb); // topo shifts the Moon on A only
    } finally {
      swe.exports.swe_session_free(a);
      swe.exports.swe_session_free(b);
    }
  });

  it('VFS file-backed Mercury matches the native golden bit-for-bit', async () => {
    const sepl = buildSepl18();
    const h = swe.exports.swe_session_init();
    try {
      registerFile(swe, 'sepl_18.se1', sepl.bytes);
      assert.equal(swe.exports.swe_vfs_count(), 1);
      const dir = await writeEpheDir([], 'bridge-se');
      const g = await captureGolden(dir, JD_J2000, 2, SEFLG_SWIEPH | SEFLG_SPEED);
      const xx = swe.allocF64(6);
      const se = swe.serrBuf();
      try {
        const rc = swe.exports.swe_calc_ut(h, JD_J2000, 2, SEFLG_SWIEPH | SEFLG_SPEED, xx, se.ptr);
        assert.equal(rc, g.rc);
        assert.deepEqual(bitsOf(swe, xx), g.bits);
      } finally {
        swe.free(xx, 48);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('freed sessions reject calls; eop status starts at 0', () => {
    const h = swe.exports.swe_session_init();
    assert.equal(swe.exports.swe_eop_status(h), 0);
    const xx = swe.allocF64(6);
    const se = swe.serrBuf();
    try {
      swe.exports.swe_session_free(h);
      assert.equal(swe.exports.swe_calc_ut(h, JD_J2000, 0, SEFLG_MOSEPH, xx, se.ptr), -1);
      assert.equal(swe.exports.swe_eop_status(h), -1);
    } finally {
      swe.free(xx, 48);
      se.free();
    }
  });

  it('swe_close on a live session is harmless', () => {
    const h = swe.exports.swe_session_init();
    try {
      assert.equal(swe.exports.swe_close(h), 0);
      const r = calcUt(swe, h, JD_J2000, 0, SEFLG_MOSEPH | SEFLG_SPEED);
      assert.ok(r.rc >= 0);
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('houses Placidus: cusp 1 equals ASC, all in range', () => {
    const h = swe.exports.swe_session_init();
    try {
      const cusps = swe.allocF64(37);
      const ascmc = swe.allocF64(10);
      const se = swe.serrBuf();
      try {
        const rc = swe.exports.swe_houses_armc_ex2(h, 280.4606, 51.5, 23.4393, 80, cusps, ascmc, se.ptr);
        assert.equal(rc, 0);
        const c = swe.readF64(cusps, 37);
        const a = swe.readF64(ascmc, 10);
        for (let i = 1; i <= 12; i++) assert.ok(c[i] >= 0 && c[i] < 360);
        assert.ok(Math.abs(c[1] - a[0]) < 1e-9); // Placidus: house 1 cusp is ASC
      } finally {
        swe.free(cusps, 37 * 8);
        swe.free(ascmc, 10 * 8);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('house_pos puts the Sun in houses 1..12; house_name resolves', () => {
    const h = swe.exports.swe_session_init();
    try {
      const se = swe.serrBuf();
      try {
        const r = calcUt(swe, h, JD_J2000, 0, SEFLG_MOSEPH | SEFLG_SPEED);
        const pos = swe.exports.swe_house_pos(h, 280.4606, 51.5, 23.4393, 80, r.xx[0], r.xx[1], se.ptr);
        assert.ok(pos >= 1 && pos <= 12);
        const namePtr = swe.exports.swe_house_name(80);
        assert.equal(swe.readCString(namePtr), 'Placidus');
      } finally {
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('fixstar Sirius resolves with magnitude', async () => {
    const h = swe.exports.swe_session_init();
    try {
      registerFile(swe, 'sefstars.txt', buildSefstars().bytes);
      const e = swe.exports;
      const { ptr: ep, len: el } = swe.writeCString('/ephe');
      e.swe_set_ephe_path(h, ep);
      swe.free(ep, el);
      const np = swe.alloc(512);
      const se = swe.serrBuf();
      const xx = swe.allocF64(6);
      const magp = swe.allocF64(1);
      try {
        const enc = new TextEncoder().encode('Sirius');
        new Uint8Array(e.memory.buffer).set(enc, np);
        new Uint8Array(e.memory.buffer)[np + enc.length] = 0;
        const rc = e.swe_fixstar2_ut(h, np, enc.length, JD_J2000, SEFLG_MOSEPH | SEFLG_SPEED, xx, se.ptr);
        assert.ok(rc >= 0); // engine echoes iflag on success
        assert.equal(e.swe_fixstar_mag(h, np, enc.length, magp, se.ptr), 0);
        const mag = new DataView(e.memory.buffer).getFloat64(magp, true);
        assert.ok(mag > -2 && mag < -1);
      } finally {
        swe.free(np, 512);
        swe.free(xx, 48);
        swe.free(magp, 8);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
      swe.exports.swe_vfs_clear();
    }
  });

  it('pheno, nod_aps, deltat, ayanamsa behave', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      const se = swe.serrBuf();
      const attr = swe.allocF64(20);
      try {
        assert.ok(e.swe_pheno_ut(h, JD_J2000, 0, SEFLG_MOSEPH, attr, se.ptr) >= 0);
        const elong = new DataView(e.memory.buffer).getFloat64(attr, true);
        assert.ok(elong >= 0 && elong <= 180);
      } finally {
        swe.free(attr, 160);
      }
      const nb = [swe.allocF64(6), swe.allocF64(6), swe.allocF64(6), swe.allocF64(6)];
      try {
        assert.ok(e.swe_nod_aps_ut(h, JD_J2000, 1, SEFLG_MOSEPH, 1, nb[0], nb[1], nb[2], nb[3], se.ptr) >= 0);
        const node = swe.readF64(nb[0], 6);
        assert.ok(node[0] >= 0 && node[0] < 360);
      } finally {
        for (const p of nb) swe.free(p, 48);
      }
      const dt = e.swe_deltat(h, JD_J2000);
      assert.ok(dt > 0.0005 && dt < 0.001); // ~64s in days
      const ayap = swe.allocF64(1);
      try {
        e.swe_set_sid_mode(h, SE_SIDM_LAHIRI, 0, 0);
        assert.ok(e.swe_get_ayanamsa_ex(h, JD_J2000, 0, ayap, se.ptr) >= 0);
        const aya = new DataView(e.memory.buffer).getFloat64(ayap, true);
        assert.ok(aya > 23 && aya < 24);
      } finally {
        swe.free(ayap, 8);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('sunrise and eclipses resolve near J2000', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      const se = swe.serrBuf();
      const tret = swe.allocF64(2);
      try {
        // SE_CALC_RISE=1, MOSEPH, Greenwich, standard pressure/temp
        const rc = e.swe_rise_trans(h, JD_J2000, 0, 0, 0, SEFLG_MOSEPH, 1, 0.0, 51.5, 0.0, 1013.25, 15.0, tret, se.ptr);
        assert.equal(rc, 0);
        const t = new DataView(e.memory.buffer).getFloat64(tret, true);
        assert.ok(Math.abs(t - JD_J2000) < 2);
      } finally {
        swe.free(tret, 16);
      }
      const te = swe.allocF64(10);
      const at = swe.allocF64(20);
      try {
        const rc = e.swe_sol_eclipse_when_glob(h, JD_J2000, 0, 63, te, 0, se.ptr);
        assert.ok(rc > 0);
        const t = new DataView(e.memory.buffer).getFloat64(te, true);
        assert.ok(t > JD_J2000 && t < JD_J2000 + 400);
        const rl = e.swe_lun_eclipse_when(h, JD_J2000, 0, 84, te, 0, se.ptr);
        assert.ok(rl > 0);
      } finally {
        swe.free(te, 80);
        swe.free(at, 160);
        se.free();
      }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('calendar conversions + pure helpers round-trip', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      // revjul round-trip
      const yi = swe.allocI32(3);
      try {
        e.swe_revjul(2451545.0, 1, yi, yi + 4, yi + 8, yi + 12);
        const [y, mo, d] = swe.readI32(yi, 3);
        const ut = new DataView(e.memory.buffer).getFloat64(yi + 12, true);
        assert.deepEqual([y, mo, d], [2000, 1, 1]);
        assert.ok(Math.abs(ut - 12) < 1e-9);
      } finally {
        swe.free(yi, 16);
      }
      // utc_to_jd / jd*_to_utc round-trip around J2000
      const d0 = swe.allocF64(1), d1 = swe.allocF64(1);
      const se = swe.serrBuf();
      try {
        assert.equal(e.swe_utc_to_jd(h, 2000, 1, 1, 12, 0, 0, 1, d0, d1, se.ptr), 0);
        const et = new DataView(e.memory.buffer).getFloat64(d0, true);
        const ut = new DataView(e.memory.buffer).getFloat64(d1, true);
        assert.ok(Math.abs(ut - 2451545.0) < 1e-4); // UT1-UTC ~ 0.35s
        assert.ok(et > ut);
        const yi = swe.allocI32(3), tp = swe.allocF64(1);
        try {
          e.swe_jdet_to_utc(h, et, 1, yi, yi + 4, yi + 8, yi + 12, yi + 16, tp);
          const [y, mo, d] = swe.readI32(yi, 3);
          assert.deepEqual([y, mo, d], [2000, 1, 1]);
        } finally { swe.free(yi, 20); swe.free(tp, 8); }
      } finally {
        swe.free(d0, 8); swe.free(d1, 8); se.free();
      }
      // pure helpers
      assert.equal(e.swe_degnorm(370), 10);
      assert.equal(e.swe_difdeg2n(10, 350), 20);
      assert.equal(e.swe_day_of_week(2451545.0), 5); // Saturday
      const sp = swe.alloc(32);
      try {
        e.swe_cs2degstr(12345678, sp, 32);
        assert.match(swe.readCString(sp), /°/);
        e.swe_version(sp, 32);
        assert.equal(swe.readCString(sp), '2.10.03');
      } finally { swe.free(sp, 32); }
      // split_deg zodiacal: ideg@0 imin@4 isec@8 isgn@12
      const ii = swe.allocI32(4), ff = swe.allocF64(1);
      try {
        e.swe_split_deg(h, 123.456789, 8, ii, ii + 4, ii + 8, ff, ii + 12);
        const [deg, min] = swe.readI32(ii, 2);
        const sgn = swe.readI32(ii + 12, 1)[0];
        assert.equal(sgn, 4); // Leo
        assert.equal(deg, 3);
        assert.equal(min, 27);
      } finally { swe.free(ii, 16); swe.free(ff, 8); }
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('time_equ + cross + pctr behave', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      const se = swe.serrBuf();
      const ep = swe.allocF64(1);
      try {
        assert.equal(e.swe_time_equ(h, JD_J2000, ep, se.ptr), 0);
        const eot = new DataView(e.memory.buffer).getFloat64(ep, true) * 1440; // minutes
        assert.ok(Math.abs(eot) < 20);
      } finally { swe.free(ep, 8); se.free(); }
      // Sun crossing 0° Aries after J2000 (~March 21, 2000)
      const jd = swe.exports.swe_solcross_ut(h, 0, JD_J2000, SEFLG_MOSEPH | SEFLG_SPEED, se.ptr);
      assert.ok(jd > JD_J2000 + 60 && jd < JD_J2000 + 110);
      // planetocentric: Sun as seen from Mercury (SWIEPH fixture; Moshier has no BARYCTR)
      const { writeEpheDir: _, ...rest } = {};
      void rest;
      const sepl = buildSepl18();
      registerFile(swe, 'sepl_18.se1', sepl.bytes);
      const { ptr: ep2, len: el2 } = swe.writeCString('/ephe');
      e.swe_set_ephe_path(h, ep2);
      swe.free(ep2, el2);
      const xx = swe.allocF64(6);
      try {
        const rc = e.swe_calc_pctr(h, JD_J2000, 0, 2, SEFLG_SWIEPH | SEFLG_SPEED, xx, se.ptr);
        assert.ok(rc >= 0);
        const lon = new DataView(e.memory.buffer).getFloat64(xx, true);
        assert.ok(lon >= 0 && lon < 360);
      } finally { swe.free(xx, 48); }
      // helio_cross rejects Sun
      const jdc = swe.allocF64(1);
      try {
        assert.equal(e.swe_helio_cross_ut(h, 0, 0, JD_J2000, SEFLG_MOSEPH, 1, jdc, se.ptr), -1);
      } finally { swe.free(jdc, 8); }
      swe.exports.swe_vfs_clear();
    } finally {
      swe.exports.swe_session_free(h);
    }
  });

  it('azalt/azalt_rev + sidtime + tidal round-trip', () => {
    const h = swe.exports.swe_session_init();
    try {
      const e = swe.exports;
      const xin = swe.allocF64(3), xaz = swe.allocF64(3);
      const se = swe.serrBuf();
      try {
        // ECL2HOR: Sun ecliptic lon/lat/dist at J2000, Greenwich
        swe.writeF64(xin, [280.36892, 0.00023, 0.98333]);
        assert.equal(e.swe_azalt(h, JD_J2000, 0, 0.0, 51.5, 0.0, 1013.25, 15.0, xin, xaz), 0);
        const az = swe.readF64(xaz, 3);
        assert.ok(az[1] > -90 && az[1] < 90); // altitude sane
        assert.equal(e.swe_azalt_rev(h, JD_J2000, 1, 0.0, 51.5, 0.0, xaz, xin), 0); // HOR2EQU
      } finally {
        swe.free(xin, 24); swe.free(xaz, 24); se.free();
      }
      const st = e.swe_sidtime(h, JD_J2000);
      assert.ok(st >= 0 && st < 24);
      const st0 = e.swe_sidtime0(h, JD_J2000, 23.4393, 0);
      assert.ok(st0 >= 0 && st0 < 24);
      // tidal set/get
      assert.equal(e.swe_set_tid_acc(h, -25.936), 0);
      const ta = new DataView(e.memory.buffer).getFloat64((e.swe_get_tid_acc(h), (() => { const p = e.swe_wasm_alloc(8); return p; })()), true);
      swe.exports.swe_wasm_free(ta, 8);
      assert.equal(e.swe_set_tid_acc(h, 999999), 0); // reset to auto
    } finally {
      swe.exports.swe_session_free(h);
    }
  });
});
