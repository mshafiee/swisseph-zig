// Mirrors test/smoke.zig in the browser-realistic wasm runtimes:
// julday, revjul, csnorm, deltat range, version string — both flavors.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { loadBoth } from './helpers/loader.mjs';

describe('smoke (both wasm flavors)', () => {
  let flavors;
  before(async () => {
    flavors = await loadBoth();
  });

  for (const name of ['freestanding', 'wasi']) {
    describe(name, () => {
      const swe = () => flavors[name];

      it('julday J2000', () => {
        assert.equal(swe().exports.swe_julday(2000, 1, 1, 12.0, 1), 2451545.0);
      });

      it('revjul roundtrip', () => {
        const s = swe();
        const py = s.allocI32(1), pm = s.allocI32(1), pd = s.allocI32(1), put = s.allocF64(1);
        try {
          s.exports.swe_revjul(2451545.0, 1, py, pm, pd, put);
          assert.deepEqual(s.readI32(py, 1).concat(s.readI32(pm, 1), s.readI32(pd, 1)), [2000, 1, 1]);
        } finally {
          s.free(py, 4); s.free(pm, 4); s.free(pd, 4); s.free(put, 8);
        }
      });

      it('csnorm', () => {
        assert.equal(swe().exports.swe_csnorm(0), 0);
        assert.equal(swe().exports.swe_csnorm(-360000), 359 * 360000);
      });

      it('deltat J2000 reasonable', () => {
        const dt = swe().exports.swe_deltat(2451545.0);
        assert.ok(dt > 60.0 / 86400.0 && dt < 70.0 / 86400.0, `dt=${dt}`);
      });

      it('version string', () => {
        const s = swe();
        const p = s.alloc(256);
        try {
          s.exports.swe_version(p);
          assert.ok(s.readCString(p).startsWith('2.10'), s.readCString(p));
        } finally {
          s.free(p, 256);
        }
      });
    });
  }

  it('flavors agree bit-exactly on smoke scalars', () => {
    const a = flavors.freestanding.exports;
    const b = flavors.wasi.exports;
    assert.equal(a.swe_julday(2000, 1, 1, 12.0, 1), b.swe_julday(2000, 1, 1, 12.0, 1));
    assert.equal(a.swe_deltat(2451545.0), b.swe_deltat(2451545.0));
  });
});
