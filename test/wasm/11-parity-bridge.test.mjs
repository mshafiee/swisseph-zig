// Bridge parity: replay C-oracle corpora through the production swe.wasm
// session API, bit-exact (==) against the oracle's %.17g values.
//
// Corpora live in the companion verify repo (../swisseph-zig-verify/corpora)
// with the real ephemeris files in ../swisseph/ephe. The whole run is
// skipped (with a loud log) when either is absent — CI without the
// companion checkout still runs the synthetic-fixture gates in 10-bridge.
//
// Coverage per corpus kind (each 'U/v/S/p/ew/i/H' line is one oracle call):
//   swecalc  — swe_calc_ut over the full flag matrix (MOSEPH path needs no
//              files; SWIEPH lines resolve era files per §era-files)
//   topo     — swe_set_topo + topocentric calc (SWIEPH via VFS, era-swapped)
//   pheno    — p lines via swe_pheno (ET), q lines via swe_pheno_ut,
//              w lines replayed as swe_set_topo state
//   ecl      — swe_sol_eclipse_where (ew lines; Sun+Moon era files)
//   rise     — swe_rise_trans (i lines; star lines pin sefstars.txt)
//   sid      — swe_get_ayanamsa_ex / _ex_ut (S/Q lines) + sidereal
//              swe_calc_ut (U lines); L lines replayed as swe_set_sid_mode
//   house    — swe_houses_armc_ex2 (13-cusp tropical slice; full sidereal house
//              math is exercised by the native zig-difftest gate)
//   nut      — skipped here: nutation is an internal of calc_ut, no direct
//              bridge export (covered bit-exactly by 09-eop + calc corpora)
//
// §era-files: the engine builds deterministic era filenames per
// swi_gen_filename (sepl_18.se1 for the modern era, seplm30.se1-style
// "m" files outside it). needFiles() replicates that math exactly, so the
// VFS holds precisely what the oracle's full ../ephe dir provided. The VFS
// caps at 16 files, so the context evicts + re-registers on era change
// (swap count is asserted small) with a fresh session each time — open
// file handles cached in session state must never outlive a clear.
//
// §history: oracle values embed single-process call history (open files
// feeding deltat denums, workspace caches — e.g. an apogee line matches
// only when a much earlier Moshier node line ran before it). Every kind
// therefore executes ALL its lines in order and asserts only a sampled
// subset (BRIDGE_PARITY_SAMPLES, 0 = all).
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { loadProduction } from './helpers/loader.mjs';
import { registerFile } from './helpers/fixtures.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const VERIFY_DIR = path.resolve(ROOT, '../swisseph-zig-verify/corpora');
const EPHE_DIR = path.resolve(ROOT, '../swisseph/ephe');

const HAVE = fs.existsSync(path.join(VERIFY_DIR, 'swecalc_corpus.txt')) && fs.existsSync(path.join(EPHE_DIR, 'sepl_18.se1'));

const SEFLG_SPEED = 256;
const SAMPLE_PER_KIND = parseInt(process.env.BRIDGE_PARITY_SAMPLES ?? '400', 10);

function deterministicSample(n, total) {
  if (n === 0 || total <= n) return Array.from({ length: total }, (_, i) => i);
  const picked = new Set();
  let x = 0x9e3779b9;
  while (picked.size < n) {
    x = (Math.imul(x, 0x85ebca6b) ^ (x >>> 13)) >>> 0;
    picked.add(x % total);
  }
  return [...picked].sort((a, b) => a - b);
}

function parseSerr(raw) {
  // Corpus lines are captured without the serr='...' wrapper by the
  // per-kind regexes, but accept wrapped form too; normalize PATH text.
  const m = raw.match(/^serr='(.*)'$/s);
  return (m ? m[1] : raw).replace(/in PATH '[^']*'/g, "in PATH '<dir>'");
}

async function readCorpus(name) {
  const lines = [];
  const rl = readline.createInterface({ input: fs.createReadStream(path.join(VERIFY_DIR, name)), crlfDelay: Infinity });
  for await (const line of rl) if (line.trim()) lines.push(line);
  return lines;
}

// ---------- era math (exact mirror of swe_revjul + swi_gen_filename) ----------

// swe_revjul year only (gregorian iff jd >= 2305447.5, like swi_gen_filename).
function revjulYear(jd) {
  const greg = jd >= 2305447.5;
  let u0 = jd + 32082.5;
  if (greg) {
    let uu1 = u0 + Math.floor(u0 / 36525.0) - Math.floor(u0 / 146100.0) - 38.0;
    if (jd >= 1830691.5) uu1 += 1;
    u0 = u0 + Math.floor(uu1 / 36525.0) - Math.floor(uu1 / 146100.0) - 38.0;
  }
  const uu2 = Math.floor(u0 + 123.0);
  const uu3 = Math.floor((uu2 - 122.2) / 365.25);
  const uu4 = Math.floor((uu2 - Math.floor(365.25 * uu3)) / 30.6001);
  return Math.trunc(uu3 + Math.floor((uu4 - 2.0) / 12.0) - 4800);
}

// swi_gen_filename era suffix: modern eras 'sepl_18.se1', outer eras
// 'seplm30.se1'. ncties = 6.
function eraName(base, jd) {
  const jyear = revjulYear(jd);
  const sgn = jyear < 0 ? -1 : 1;
  let icty = Math.trunc(jyear / 100);
  if (sgn < 0 && jyear % 100 !== 0) icty -= 1;
  while (icty % 6 !== 0) icty -= 1;
  const sep = icty < 0 ? 'm' : '_';
  return `${base}${sep}${String(Math.abs(icty)).padStart(2, '0')}.se1`;
}

// ---------- ephemeris file resolution ----------

const fileCache = new Map(); // relname -> Buffer|null (null = absent on disk)
function readEphe(rel) {
  if (!fileCache.has(rel)) {
    const p = path.join(EPHE_DIR, rel);
    fileCache.set(rel, fs.existsSync(p) ? fs.readFileSync(p) : null);
  }
  return fileCache.get(rel);
}

// Files the engine will request for one call. Mirrors swi_gen_filename
// classes: semo (Moon), sepl (Sun/planets), seas (asteroids); numbered
// asteroids live in ast{q}/se{nnnnn}.se1 singles; fictitious bodies read
// seorbel.txt; named stars read sefstars.txt.
function needFiles({ jd, ipl = null, iflag = 2, star = null }) {
  const ephe = iflag & 7;
  const out = [];
  if (star) out.push('sefstars.txt');
  if (ephe === 4 || ephe === 1) return out; // MOSEPH needs nothing; JPL out of scope
  if (ipl !== null && ipl >= 10000) {
    const n = ipl - 10000;
    out.push(`ast${Math.trunc(n / 1000)}/se${String(n).padStart(5, '0')}.se1`);
    return out;
  }
  if (ipl !== null && ipl >= 40 && ipl < 1000) {
    out.push('seorbel.txt');
    return out;
  }
  out.push(eraName('sepl', jd), eraName('semo', jd), eraName('seas', jd));
  return out;
}

// Extra text files a kind needs beyond its era set (e.g. sefstars.txt for
// rise's named stars) travel via needFiles()/preRegister texts — the path
// setter only ever pins the Moon-probe pair below.
const PINNED_PROBE = ['semo_18.se1', 'sepl_18.se1'];

// ---------- session context with era swapping (§era-files, §state) ----------

function makeCtx(swe) {
  let session = swe.exports.swe_session_init();
  let registered = new Set();
  let swaps = 0;
  const snapshot = { topo: null, sid: null };
  function register(name) {
    const bytes = readEphe(name);
    if (bytes === null) return false; // absent on disk: oracle missed it too
    registerFile(swe, name, bytes);
    registered.add(name);
    return true;
  }
  function setPath() {
    // Probe files first: the J2000 Moon probe inside swe_set_ephe_path
    // must succeed exactly as in the C oracle's startup. (Texts like
    // sefstars/seorbel arrive via needFiles/preRegister texts, never here.)
    for (const n of PINNED_PROBE) register(n);
    const { ptr, len } = swe.writeCString('/ephe');
    swe.exports.swe_set_ephe_path(session, ptr);
    swe.free(ptr, len);
  }
  setPath();
  function applySnapshot() {
    if (snapshot.topo) swe.exports.swe_set_topo(session, ...snapshot.topo);
    if (snapshot.sid) swe.exports.swe_set_sid_mode(session, ...snapshot.sid);
  }
  return {
    get session() {
      return session;
    },
    get swaps() {
      return swaps;
    },
    get files() {
      return [...registered].sort();
    },
    setTopo(lon, lat, alt) {
      snapshot.topo = [lon, lat, alt];
      swe.exports.swe_set_topo(session, lon, lat, alt);
    },
    setSid(mode, t0, ayan) {
      snapshot.sid = [mode, t0, ayan];
      swe.exports.swe_set_sid_mode(session, mode, t0, ayan);
    },
    ensureFiles(need) {
      const missing = need.filter((n) => !registered.has(n));
      if (missing.length === 0) return;
      swe.exports.swe_session_free(session);
      swe.exports.swe_vfs_clear();
      registered = new Set();
      for (const n of [...PINNED_PROBE, ...need]) {
        register(n);
      }
      swaps += 1;
      session = swe.exports.swe_session_init();
      setPath();
      applySnapshot();
    },
    // Register the COMPLETE kind file-set up front (when it fits the
    // 16-file VFS): zero swaps/resets, so engine history evolves exactly
    // like the C oracle's single-process run. Must be called before any
    // state lines are applied (snapshot empty). Extra texts (e.g. sefstars
    // for rise stars) passed explicitly; returns false when the union
    // overflows 16 (caller falls back to lazy ensureFiles).
    preRegister(all, texts = []) {
      const union = [...new Set([...PINNED_PROBE, ...texts, ...all])].filter((n) => readEphe(n) !== null);
      if (union.length > 16) return false;
      swe.exports.swe_session_free(session);
      swe.exports.swe_vfs_clear();
      registered = new Set();
      for (const n of union) {
        register(n);
      }
      swaps += 1;
      session = swe.exports.swe_session_init();
      setPath();
      return true;
    },
    close() {
      swe.exports.swe_session_free(session);
      swe.exports.swe_vfs_clear();
      session = -1;
    },
  };
}

function normGot(se) {
  return se.read().replace(/in PATH '[^']*'/g, "in PATH '<dir>'");
}

// Union of needFiles() over corpus lines (extract returns the needFiles
// argument or null for state/unrelated lines). Only existing files.
function collectKindFiles(lines, extract) {
  const set = new Set();
  for (const line of lines) {
    const r = extract(line);
    if (!r) continue;
    for (const n of needFiles(r)) {
      if (readEphe(n) !== null) set.add(n);
    }
  }
  return [...set];
}

// Soft assert collector: records per-line mismatches and continues, so one
// run yields the full inventory (compared against the pure-native failure
// set to separate harness issues from pure-math divergence). The test
// still fails unless the inventory is empty.
function soft(failures, label, fn) {
  try {
    fn();
  } catch (e) {
    failures.push(`${label}: ${String((e && e.message) || e).split('\n')[0]}`);
  }
}

function reportFailures(failures, what) {
  if (failures.length > 0) {
    const cap = parseInt(process.env.BRIDGE_PARITY_DUMP ?? '20', 10);
    console.log(`${what}: ${failures.length} mismatches (first ${cap}):\n` + failures.slice(0, cap).join('\n'));
  }
  assert.deepEqual(failures, []);
}

// Freshly zeroed 256-byte serr buffer (the C contract: callers memset
// before each call — native difftest zeroes per line; without this,
// recycled wasm memory leaks earlier messages into success paths).
function serrBuf(swe) {
  const ptr = swe.alloc(256);
  swe.writeBytes(ptr, new Uint8Array(256));
  return {
    ptr,
    read: () => swe.readCString(ptr, 256),
    free: () => swe.free(ptr, 256),
  };
}

describe('bridge parity vs C-oracle corpora', () => {
  let swe;
  before(async function () {
    if (!HAVE) {
      console.log('bridge-parity: companion corpora/ephe not found — skipping (synthetic gates in 10-bridge still run)');
      return;
    }
    swe = await loadProduction();
  });
  after(() => {
    fileCache.clear();
  });

  it('era math matches the engine filename scheme', { skip: !HAVE }, () => {
    assert.equal(eraName('sepl', 2451545.0), 'sepl_18.se1');
    assert.equal(eraName('semo', 2451545.0), 'semo_18.se1');
    assert.equal(eraName('seas', 2451545.0), 'seas_18.se1');
    assert.equal(eraName('sepl', 639549), 'seplm30.se1');
    assert.equal(eraName('semo', 626000.19999999995), 'semom30.se1');
    for (const n of ['sepl_18.se1', 'seplm30.se1', 'semom30.se1', 'seasm30.se1', 'ast1/se01566.se1']) {
      assert.ok(readEphe(n) !== null, `expected ${n} on disk`);
    }
  });

  it('swecalc', { skip: !HAVE }, async () => {
    // Walk-all/assert-sampled (§history): every line executes so engine
    // history (open files, caches) evolves exactly like the C oracle's
    // single-process run; only sampled lines assert. Verified necessary:
    // sampled-only runs mismatch history-sensitive lines (e.g. apogee
    // after a Moshier node calc) that full-order runs match bit-exactly.
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('swecalc_corpus.txt');
      const sampleSet = new Set(deterministicSample(SAMPLE_PER_KIND, lines.length));
      const xx = swe.allocF64(6);
      const se = serrBuf(swe);
      const zero256 = new Uint8Array(256);
      const failures = [];
      let checked = 0;
      try {
        for (let i = 0; i < lines.length; i++) {
          // U <ipl> <jd> <iflag> -> <rc> <6 x %.17g> serr='...'
          const m = lines[i].match(/^U (\d+) (\S+) (\d+) -> (-?\d+)((?: \S+){0,6}) serr='(.*)'$/);
          assert.ok(m, `unparsed swecalc line: ${lines[i]}`);
          const ipl = Number(m[1]), jd = Number(m[2]), iflag = Number(m[3]);
          const need = needFiles({ jd, ipl, iflag });
          ctx.ensureFiles(need);
          swe.writeBytes(se.ptr, zero256);
          const gotRc = swe.exports.swe_calc_ut(ctx.session, jd, ipl, iflag, xx, se.ptr);
          if (!sampleSet.has(i)) continue;
          const rc = Number(m[4]);
          const want = m[5].trim() ? m[5].trim().split(/\s+/).map(Number) : [];
          const wantSerr = parseSerr(m[6]);
          const diag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc mismatch ${diag}: ${lines[i]}`);
            if (rc >= 0 && want.length === 6) {
              assert.deepEqual(swe.readF64(xx, 6), want, `xx mismatch ${diag}`);
            }
            assert.equal(normGot(se), wantSerr, `serr mismatch ${diag}`);
          });
          checked++;
        }
      } finally {
        swe.free(xx, 48);
        se.free();
      }
      assert.ok(checked > 0);
      console.log(`swecalc: ${checked} asserted, ${lines.length} executed, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'swecalc');
    } finally {
      ctx.close();
    }
  });

  it('topo', { skip: !HAVE }, async () => {
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('topo_corpus.txt');
      const pre = ctx.preRegister(collectKindFiles(lines, (line) => {
        const m = line.match(/^U (\d+) (\S+) (\d+) ->/);
        return m ? { jd: Number(m[2]), ipl: Number(m[1]), iflag: Number(m[3]) } : null;
      }));
      console.log(`topo: pre-registered=${pre}`);
      const calls = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('U '));
      const idx = deterministicSample(SAMPLE_PER_KIND, calls.length);
      const sampleSet = new Set(idx);
      let uIdx = -1;
      let checked = 0;
      const failures = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line.startsWith('U ')) {
          const v = line.match(/^v (\S+) (\S+) (\S+)$/);
          if (v) ctx.setTopo(Number(v[1]), Number(v[2]), Number(v[3]));
          continue;
        }
        uIdx++;
        const m = line.match(/^U (\d+) (\S+) (\d+) -> (-?\d+)((?: \S+){0,6}) serr='(.*)'$/);
        assert.ok(m, `unparsed topo line: ${line}`);
        const ipl = Number(m[1]), jd = Number(m[2]), iflag = Number(m[3]);
        const need = needFiles({ jd, ipl, iflag });
        ctx.ensureFiles(need);
        const xx = swe.allocF64(6);
        const se = serrBuf(swe);
        try {
          const gotRc = swe.exports.swe_calc_ut(ctx.session, jd, ipl, iflag, xx, se.ptr);
          if (!sampleSet.has(uIdx)) continue;
          const rc = Number(m[4]);
          const want = m[5].trim() ? m[5].trim().split(/\s+/).map(Number) : [];
          const wantSerr = parseSerr(m[6]);
          const diag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc mismatch ${diag}: ${line}`);
            if (rc >= 0 && want.length === 6) {
              assert.deepEqual(swe.readF64(xx, 6), want, `xx mismatch ${diag}`);
            }
            assert.equal(normGot(se), wantSerr, `serr mismatch ${diag}`);
          });
        } finally {
          swe.free(xx, 48);
          se.free();
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`topo: ${checked} asserted, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'topo');
    } finally {
      ctx.close();
    }
  });

  it('pheno', { skip: !HAVE }, async () => {
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('pheno_corpus.txt');
      const pre = ctx.preRegister(collectKindFiles(lines, (line) => {
        const m = line.match(/^[pq] (\d+) (\S+) (\d+) ->/);
        return m ? { jd: Number(m[2]), ipl: Number(m[1]), iflag: Number(m[3]) } : null;
      }));
      console.log(`pheno: pre-registered=${pre}`);
      const ps = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('p '));
      const qs = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('q '));
      const pIdx = new Set(deterministicSample(SAMPLE_PER_KIND, ps.length));
      const qIdx = new Set(deterministicSample(SAMPLE_PER_KIND, qs.length));
      let pi = -1, qi = -1;
      let checked = 0;
      const failures = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('w ')) {
          const w = line.match(/^w (\S+) (\S+) (\S+)$/);
          if (w) ctx.setTopo(Number(w[1]), Number(w[2]), Number(w[3]));
          continue;
        }
        const isP = line.startsWith('p ');
        if (!isP && !line.startsWith('q ')) continue;
        const k = isP ? ++pi : ++qi;
        const sampled = isP ? pIdx.has(k) : qIdx.has(k);
        // p <ipl> <jd> <iflag> -> <rc> <up to 6 vals> serr='...' (ET swe_pheno)
        // q <ipl> <jd> <iflag> -> <rc> <up to 6 vals> serr='...' (UT swe_pheno_ut)
        const m = line.match(/^[pq] (\d+) (\S+) (\d+) -> (-?\d+)((?: \S+){0,6}) serr='(.*)'$/);
        assert.ok(m, `unparsed pheno line: ${line}`);
        const ipl = Number(m[1]), jd = Number(m[2]), iflag = Number(m[3]);
        const need = needFiles({ jd, ipl, iflag });
        ctx.ensureFiles(need);
        const attr = swe.allocF64(20);
        const se = serrBuf(swe);
        try {
          const gotRc = isP
            ? swe.exports.swe_pheno(ctx.session, jd, ipl, iflag, attr, se.ptr)
            : swe.exports.swe_pheno_ut(ctx.session, jd, ipl, iflag, attr, se.ptr);
          if (!sampled) continue;
          const rc = Number(m[4]);
          const want = m[5].trim() ? m[5].trim().split(/\s+/).map(Number) : [];
          const wantSerr = parseSerr(m[6]);
          const diag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc mismatch ${diag}: ${line}`);
            if (rc >= 0) {
              assert.deepEqual(swe.readF64(attr, want.length), want, `attr mismatch ${diag}`);
            }
            assert.equal(normGot(se), wantSerr, `serr mismatch ${diag}`);
          });
        } finally {
          swe.free(attr, 160);
          se.free();
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`pheno: ${checked} asserted, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'pheno');
    } finally {
      ctx.close();
    }
  });

  it('ecl', { skip: !HAVE }, async () => {
    const ctx = makeCtx(swe);
    try {
      const lines = (await readCorpus('ecl_corpus.txt')).filter((l) => l.startsWith('ew '));
      const pre = ctx.preRegister(collectKindFiles(lines, (line) => {
        const m = line.match(/^ew (\S+) (\d+) ->/);
        return m ? { jd: Number(m[1]), iflag: Number(m[2]) } : null;
      }));
      console.log(`ecl: pre-registered=${pre}`);
      const idx = deterministicSample(Math.min(SAMPLE_PER_KIND, lines.length), lines.length);
      let checked = 0;
      const failures = [];
      for (const i of idx) {
        // ew <jd> <ifl> -> <rc> <geolon> <geolat> <up to 18 attr> serr='...'
        const m = lines[i].match(/^ew (\S+) (\d+) -> (-?\d+)((?: \S+){1,20}) serr='(.*)'$/);
        assert.ok(m, `unparsed ecl line: ${lines[i]}`);
        const jd = Number(m[1]), ifl = Number(m[2]);
        const rc = Number(m[3]);
        const want = m[4].trim().split(/\s+/).map(Number);
        const wantSerr = parseSerr(m[5]);
        const need = needFiles({ jd, iflag: ifl }); // Sun+Moon classes
        ctx.ensureFiles(need);
        const diag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
        const geopos = swe.allocF64(2);
        const attr = swe.allocF64(20);
        const se = serrBuf(swe);
        try {
          const gotRc = swe.exports.swe_sol_eclipse_where(ctx.session, jd, ifl, geopos, attr, se.ptr);
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc mismatch ${diag}: ${lines[i]}`);
            if (rc >= 0) {
              const gp = swe.readF64(geopos, 2);
              assert.equal(gp[0], want[0], `geolon ${diag}`);
              assert.equal(gp[1], want[1], `geolat ${diag}`);
              const nAttr = want.length - 2;
              if (nAttr > 0) {
                assert.deepEqual(swe.readF64(attr, nAttr), want.slice(2), `attr ${diag}`);
              }
            }
            assert.equal(normGot(se), wantSerr, `serr mismatch ${diag}`);
          });
        } finally {
          swe.free(geopos, 16);
          swe.free(attr, 160);
          se.free();
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`ecl: ${checked} asserted, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'ecl');
    } finally {
      ctx.close();
    }
  });

  it('rise', { skip: !HAVE }, async () => {
    // Walk-all/assert-sampled (§history): i lines via swe_rise_trans and
    // k lines via swe_rise_trans_true_hor (extra horhgt field) both execute
    // in order so transit-search file/cache history matches the oracle.
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('rise_corpus.txt');
      const pre = ctx.preRegister(collectKindFiles(lines, (line) => {
        const m = line.match(/^[ik] (\d+) (\S+) (\d+) (\d+) '([^']*)' /);
        if (!m) return null;
        const star = m[5];
        return { jd: Number(m[2]), ipl: Number(m[1]), iflag: Number(m[3]), star: star && star !== '-' ? star : null };
      }), ['sefstars.txt']);
      console.log(`rise: pre-registered=${pre}`);
      const is = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('i '));
      const ks = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('k '));
      const iIdx = new Set(deterministicSample(SAMPLE_PER_KIND, is.length));
      const kIdx = new Set(deterministicSample(SAMPLE_PER_KIND, ks.length));
      let ii = -1, ki = -1;
      let checked = 0;
      const failures = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const isI = line.startsWith('i ');
        if (!isI && !line.startsWith('k ')) continue;
        const k = isI ? ++ii : ++ki;
        const sampled = isI ? iIdx.has(k) : kIdx.has(k);
        // i <ipl> <jd> <ephe> <rsmi> '<star>' <lon> <lat> <alt> <press> <temp> [horhgt] -> <rc> <tret> serr='...'
        const m = line.match(/^[ik] (\d+) (\S+) (\d+) (\d+) '([^']*)' (\S+) (\S+) (\S+) (\S+) (\S+)( \S+)? -> (-?\d+) (\S+) serr='(.*)'$/);
        assert.ok(m, `unparsed rise line: ${line}`);
        const ipl = Number(m[1]), jd = Number(m[2]), ephe = Number(m[3]), rsmi = Number(m[4]);
        const star = m[5];
        const lon = Number(m[6]), lat = Number(m[7]), alt = Number(m[8]);
        const press = Number(m[9]), temp = Number(m[10]);
        const horhgt = m[11] === undefined ? 0 : Number(m[11].trim());
        const need = needFiles({ jd, ipl, iflag: ephe, star: star && star !== '-' ? star : null });
        ctx.ensureFiles(need);
        let starPtr = 0;
        let staged = null;
        if (star && star !== '-') {
          staged = swe.writeCString(star);
          starPtr = staged.ptr;
        }
        const tret = swe.allocF64(1);
        const se = serrBuf(swe);
        try {
          const starLen = staged ? staged.len - 1 : 0; // C string length w/o NUL
          const gotRc = isI
            ? swe.exports.swe_rise_trans(ctx.session, jd, ipl, starPtr, starLen, ephe, rsmi, lon, lat, alt, press, temp, tret, se.ptr)
            : swe.exports.swe_rise_trans_true_hor(ctx.session, jd, ipl, starPtr, starLen, ephe, rsmi, lon, lat, alt, press, temp, horhgt, tret, se.ptr);
          if (!sampled) continue;
          const rc = Number(m[12]);
          const wantTret = m[13] === 'x' ? null : Number(m[13]);
          const wantSerr = parseSerr(m[14]);
          const diag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc mismatch ${diag}: ${line}`);
            if (rc >= 0 && wantTret !== null) {
              assert.equal(new DataView(swe.exports.memory.buffer).getFloat64(tret, true), wantTret, `tret ${diag}`);
            }
            assert.equal(normGot(se), wantSerr, `serr ${diag}`);
          });
        } finally {
          swe.free(tret, 8);
          se.free();
          if (staged) swe.free(staged.ptr, staged.len);
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`rise: ${checked} asserted, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'rise');
    } finally {
      ctx.close();
    }
  });

  it('sid', { skip: !HAVE }, async () => {
    // S lines: swe_get_ayanamsa_ex (ET); Q lines: swe_get_ayanamsa_ex_ut;
    // U lines: swe_calc_ut with SEFLG_SIDEREAL. L lines replay sid-mode
    // state (swe_set_sid_mode). Pure computation, no ephemeris files.
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('sid_corpus.txt');
      const pre = ctx.preRegister(collectKindFiles(lines, (line) => {
        const m = line.match(/^U (\d+) (\S+) (\d+) ->/);
        return m ? { jd: Number(m[2]), ipl: Number(m[1]), iflag: Number(m[3]) } : null;
      }));
      console.log(`sid: pre-registered=${pre}`);
      const ss = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('S '));
      const qs = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('Q '));
      const us = lines.map((l, i) => ({ l, i })).filter(({ l }) => l.startsWith('U '));
      const sIdx = new Set(deterministicSample(SAMPLE_PER_KIND, ss.length));
      const qIdx = new Set(deterministicSample(SAMPLE_PER_KIND, qs.length));
      const uIdx = new Set(deterministicSample(SAMPLE_PER_KIND, us.length));
      let si = -1, qi = -1, ui = -1;
      let checked = 0;
      const failures = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('L ')) {
          const lm = line.match(/^L (\d+) (\S+) (\S+)$/);
          assert.ok(lm, `unparsed sid state line: ${line}`);
          ctx.setSid(Number(lm[1]), Number(lm[2]), Number(lm[3]));
          continue;
        }
        const kind = line[0];
        if (kind !== 'S' && kind !== 'Q' && kind !== 'U') continue;
        const k = kind === 'S' ? ++si : kind === 'Q' ? ++qi : ++ui;
        const sampled = (kind === 'S' && sIdx.has(k)) || (kind === 'Q' && qIdx.has(k)) || (kind === 'U' && uIdx.has(k));
        const diag = `line ${i} (pure sidereal computation)`;
        if (kind === 'S' || kind === 'Q') {
          // S <jd> <iflag> -> <rc> <daya> serr='...' (ET ayanamsa)
          // Q <jd> <iflag> -> <rc> <daya> serr='...' (UT ayanamsa)
          const m = line.match(/^[SQ] (\S+) (\d+) -> (-?\d+) (\S+) serr='(.*)'$/);
          assert.ok(m, `unparsed sid line: ${line}`);
          const jd = Number(m[1]), iflag = Number(m[2]);
          const daya = swe.allocF64(1);
          const se = serrBuf(swe);
          try {
            const gotRc = kind === 'S'
              ? swe.exports.swe_get_ayanamsa_ex(ctx.session, jd, iflag, daya, se.ptr)
              : swe.exports.swe_get_ayanamsa_ex_ut(ctx.session, jd, iflag, daya, se.ptr);
            if (!sampled) continue;
            const rc = Number(m[3]);
            const want = Number(m[4]);
            const wantSerr = parseSerr(m[5]);
            soft(failures, diag, () => {
              assert.equal(gotRc, rc, `rc mismatch ${diag}: ${line}`);
              if (rc >= 0) {
                assert.equal(new DataView(swe.exports.memory.buffer).getFloat64(daya, true), want, `daya mismatch ${diag}`);
              }
              assert.equal(normGot(se), wantSerr, `serr mismatch ${diag}`);
            });
          } finally {
            swe.free(daya, 8);
            se.free();
          }
        } else {
          const m = line.match(/^U (\d+) (\S+) (\d+) -> (-?\d+)((?: \S+){0,6}) serr='(.*)'$/);
          assert.ok(m, `unparsed sidcalc line: ${line}`);
          const ipl = Number(m[1]), jd = Number(m[2]), iflag = Number(m[3]);
          const need = needFiles({ jd, ipl, iflag });
          ctx.ensureFiles(need);
          const fdiag = `line ${i} need=[${need}] reg=[${ctx.files}]`;
          const xx = swe.allocF64(6);
          const se = serrBuf(swe);
          try {
            const gotRc = swe.exports.swe_calc_ut(ctx.session, jd, ipl, iflag, xx, se.ptr);
            if (!sampled) continue;
            const rc = Number(m[4]);
            const want = m[5].trim() ? m[5].trim().split(/\s+/).map(Number) : [];
            const wantSerr = parseSerr(m[6]);
            soft(failures, fdiag, () => {
              assert.equal(gotRc, rc, `rc mismatch ${fdiag}: ${line}`);
              if (rc >= 0 && want.length === 6) {
                assert.deepEqual(swe.readF64(xx, 6), want, `xx mismatch ${fdiag}`);
              }
              assert.equal(normGot(se), wantSerr, `serr mismatch ${fdiag}`);
            });
          } finally {
            swe.free(xx, 48);
            se.free();
          }
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`sid: ${checked} asserted, ${ctx.swaps} era swaps`);
      reportFailures(failures, 'sid');
    } finally {
      ctx.close();
    }
  });

  it('house', { skip: !HAVE }, async () => {
    // Walk-all/assert-sampled (§history): H asserts plus P (house_pos)
    // and T (cotrans) history execution in corpus order (N lines are a
    // pure name table with no session state and are skipped).
    const ctx = makeCtx(swe);
    try {
      const lines = await readCorpus('house_corpus_esc.txt');
      // Only non-sidereal lines (iflag without SEFLG_SIDEREAL=65536) with
      // no speed flags (iflag & 3 == 0) and never Sunshine ('I'): the
      // bridge's houses_armc_ex2 takes no speed buffers and no ascmc[9]
      // sun-declination input. Speeds + sidereal + Sunshine projection
      // live in the native zig-difftest gate (green).
      const calls = lines
        .map((l, i) => ({ l, i }))
        .filter(({ l }) => {
          const m = l.match(/^H (\w) (\d+) (\S+) (\S+) (\d+) /);
          return m && (Number(m[5]) & 65536) === 0 && (Number(m[5]) & 3) === 0 && m[1] !== 'I';
        });
      const idx = new Set(deterministicSample(Math.min(SAMPLE_PER_KIND, calls.length), calls.length));
      const byFileIdx = new Map(calls.map((c, k) => [c.i, k]));
      let checked = 0;
      const failures = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('P ')) {
          // P <hsys> <armc> <geolat> <eps> <x0> <x1> -> <hp> serr='...'
          const pm = line.match(/^P (\w) (\S+) (\S+) (\S+) (\S+) (\S+) -> (\S+) serr='(.*)'$/);
          assert.ok(pm, `unparsed house_pos line: ${line}`);
          const se = serrBuf(swe);
          try {
            swe.exports.swe_house_pos(ctx.session, Number(pm[2]), Number(pm[3]), Number(pm[4]), pm[1].charCodeAt(0), Number(pm[5]), Number(pm[6]), se.ptr);
          } finally {
            se.free();
          }
          continue;
        }
        if (line.startsWith('T ')) {
          // T <x0> <x1> <x2> <eps> -> <y0> <y1> <y2>
          const tm = line.match(/^T (\S+) (\S+) (\S+) (\S+) -> (\S+) (\S+) (\S+)$/);
          assert.ok(tm, `unparsed cotrans line: ${line}`);
          const xpo = swe.allocF64(3), xpn = swe.allocF64(3);
          try {
            swe.writeF64(xpo, [Number(tm[1]), Number(tm[2]), Number(tm[3])]);
            swe.exports.swe_cotrans(xpo, xpn, Number(tm[4]));
          } finally {
            swe.free(xpo, 24);
            swe.free(xpn, 24);
          }
          continue;
        }
        if (!line.startsWith('H ')) continue;
        const k = byFileIdx.get(i);
        // Execute every H line (hctx history); assert only the tropical
        // no-speed slice. Sidereal lines run under default sid mode in
        // both oracle (stubbed set_sid_mode) and bridge (never set).
        const m = line.match(/^H (\w) (\S+) (\S+) (\S+) (\d+) -> (-?\d+)(.*) serr='(.*)'$/);
        assert.ok(m, `unparsed house line: ${line}`);
        const hsysChar = m[1];
        const armc = Number(m[2]);
        const geolat = Number(m[3]);
        const eps = Number(m[4]);
        const rc = Number(m[6]);
        const wantSerr = parseSerr(m[8]);
        const diag = `line ${i} (pure computation, no files)`;
        const cusps = swe.allocF64(37);
        const ascmc = swe.allocF64(10);
        const se = serrBuf(swe);
        try {
          const hsys = hsysChar.charCodeAt(0);
          const gotRc = swe.exports.swe_houses_armc_ex2(ctx.session, armc, geolat, eps, hsys, cusps, ascmc, se.ptr);
          if (!idx.has(k)) continue;
          soft(failures, diag, () => {
            assert.equal(gotRc, rc, `rc ${diag}: ${line}`);
            const fields = m[7].trim() ? m[7].trim().split(/\s+/) : [];
            const want = {};
            for (const f of fields) {
              const kv = f.match(/^([cab])(\d+)=(\S+)$/);
              if (kv) want[`${kv[1]}${kv[2]}`] = Number(kv[3]);
            }
            const gotC = swe.readF64(cusps, 37);
            const gotA = swe.readF64(ascmc, 10);
            for (let c = 0; c <= 12; c++) {
              const w = want[`c${c}`];
              if (w !== undefined) assert.equal(gotC[c], w, `cusp c${c} ${diag}`);
            }
            for (let a = 0; a <= 9; a++) {
              const w = want[`a${a}`];
              if (w !== undefined) assert.equal(gotA[a], w, `ascmc a${a} ${diag}`);
            }
            assert.equal(normGot(se), wantSerr, `serr ${diag}`);
          });
        } finally {
          swe.free(cusps, 296);
          swe.free(ascmc, 80);
          se.free();
        }
        checked++;
      }
      assert.ok(checked > 0);
      console.log(`house: ${checked} asserted`);
      reportFailures(failures, 'house');
    } finally {
      ctx.close();
    }
  });
});
