// Fixture builders for the wasm VFS tests.
// The .se1 layout below mirrors src/sweph.zig read_const / do_fread /
// get_new_segment byte-for-byte (little-endian host == wasm).
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const TMP_DIR = path.resolve(HERE, '../.tmp');
export const EPHE_DIR = path.join(TMP_DIR, 'ephe');
export const GOLDEN_BIN = path.resolve(HERE, '../../../zig-out/wasm-test/swe-golden');

// Test files run in parallel OS processes under `node --test`; each suite
// gets its own ephe dir so fixtures (e.g. sefstars content) never race.
export function epheDirFor(tag) {
  return path.join(TMP_DIR, `ephe-${tag}`);
}

const execFileAsync = promisify(execFile);

// Bodies in the synthetic sepl_18.se1: [file-ipl, [x, y, z]].
const BODIES = [
  [0, [0.9, 0.4, 0.0]], // EMB
  [2, [0.3, -0.2, 0.1]], // Mercury (barycentric frame, iflg=0: no sun add)
  [10, [-0.004, -0.002, 0.0]], // Sun barycenter
];
const TFSTART = 2451515.0; // J2000 - 30d
const TFEND = 2451575.0; // J2000 + 30d
const DSEG = 2.0;
const NNDX = 30; // trunc((60 + 0.1) / 2)
const RMAX = 1000; // lng2 = RMAX * 1000

// Pack one coefficient per get_new_segment group0/1 decoding:
// seg = K/1e9*RMAX/2, K = L/2 (L even, v>=0) or (L+1)/2 (L odd, v<0).
function encodeLong(v) {
  const K = Math.round(Math.abs(v) * 2e9 / RMAX);
  return v >= 0 ? 2 * K : 2 * K - 1;
}

// CRC-32/MSB-first (AUTODIN poly), bit-identical to swi_crc32 in C and Zig:
// crc = (crc << 8) ^ table[(crc >> 24) ^ byte], init 0xFFFFFFFF, final ~.
// Real .se1 files carry a correct CRC and both C and the port enforce it
// (damage "0n", verified 3/3 on dist files); fixtures stamp a valid CRC so
// the SAME bytes exercise the pass path, with fixCrc()/bad-CRC variants
// covering both outcomes.
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = (n << 24) >>> 0;
    for (let k = 0; k < 8; k++) c = (c & 0x80000000) ? (((c << 1) ^ 0x04c11db7) >>> 0) : ((c << 1) >>> 0);
    t[n] = c;
  }
  return t;
})();
function crc32MsbFirst(buf) {
  let crc = 0xffffffff;
  for (const b of buf) crc = ((crc << 8) ^ CRC_TABLE[((crc >>> 24) ^ b) & 0xff]) >>> 0;
  return (~crc) >>> 0;
}

export function buildSepl18({ eol = '\r\n', longVersion = false } = {}) {
  const vline = longVersion ? 'V' + 'A'.repeat(300) : 'SYNTHETIC SE1 V1';
  const text = Buffer.from(
    vline + eol + 'sepl_18.se1' + eol + '(c) synthetic fixture for wasm VFS tests' + eol,
    'latin1',
  );
  const perBodyConst = 4 + 1 + 1 + 4 + 80; // lndx0+iflg+ncoe+lng2+10xf64
  const nBodies = BODIES.length;
  const constEnd = text.length + 4 + 4 + 4 + 8 + 8 + 2 + 2 * nBodies + 4 + 40 + perBodyConst * nBodies;
  const idxSize = NNDX * 3;
  const segSize = 3 * (2 + 4 + 3); // 3 coords x (header + u32 + 3 bytes)
  const segBase = constEnd + idxSize * nBodies;
  const total = segBase + segSize * nBodies;

  const buf = Buffer.alloc(total);
  let o = 0;
  text.copy(buf, o); o += text.length;
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  dv.setUint32(o, 0x00616263, true); o += 4; // testendian ("abc", LE host)
  dv.setInt32(o, total, true); o += 4; // flen self-length
  dv.setInt32(o, 431, true); o += 4; // DE number
  dv.setFloat64(o, TFSTART, true); o += 8;
  dv.setFloat64(o, TFEND, true); o += 8;
  dv.setInt16(o, nBodies, true); o += 2; // nplan
  for (const [ipl] of BODIES) { dv.setInt16(o, ipl, true); o += 2; }
  const crcPos = o;
  dv.setUint32(o, 0, true); o += 4; // ulng placeholder; filled below
  for (const v of [2.99792458e8, 1.495978707e11, 1.32712440018e20, 81.30056, 6.957e8]) {
    dv.setFloat64(o, v, true); o += 8;
  }
  BODIES.forEach(([ipl, xyz], bi) => {
    void ipl; void xyz;
    dv.setInt32(o, constEnd + idxSize * bi, true); o += 4; // lndx0
    buf[o++] = 0; // iflg: no reorder/ellipse/rotate
    buf[o++] = 2; // ncoe
    dv.setInt32(o, RMAX * 1000, true); o += 4; // lng2 -> rmax
    for (const v of [TFSTART, TFEND, DSEG, 2451545.0, 0, 0, 0, 0, 0, 0]) {
      dv.setFloat64(o, v, true); o += 8;
    }
  });
  if (o !== constEnd) throw new Error(`const layout drift: ${o} != ${constEnd}`);
  BODIES.forEach(([, xyz], bi) => {
    void xyz;
    for (let s = 0; s < NNDX; s++) {
      const off = segBase + segSize * bi;
      buf[o++] = off & 0xff; buf[o++] = (off >> 8) & 0xff; buf[o++] = (off >> 16) & 0xff;
    }
  });
  BODIES.forEach(([, xyz]) => {
    for (const v of xyz) {
      buf[o++] = 0x11; buf[o++] = 0x00; // nsize=[1,1,0,0], nco=2=ncoe
      const L = encodeLong(v);
      dv.setUint32(o, L >>> 0, true); o += 4; // group0: full u32 (c0)
      buf[o++] = 0; buf[o++] = 0; buf[o++] = 0; // group1: 3 bytes (c1=0)
    }
  });
  if (o !== total) throw new Error(`segment layout drift: ${o} != ${total}`);
  // CRC covers [0..crcPos] (bytes before ulng), exactly like C's check area.
  dv.setUint32(crcPos, crc32MsbFirst(buf.subarray(0, crcPos)), true);
  return { name: 'sepl_18.se1', bytes: buf, crcPos };
}

// Re-stamp the CRC after mutating bytes (mirrors what swephgen would emit).
export function fixCrc(file) {
  const dv = new DataView(file.bytes.buffer, file.bytes.byteOffset, file.bytes.byteLength);
  dv.setUint32(file.crcPos, crc32MsbFirst(file.bytes.subarray(0, file.crcPos)), true);
  return file;
}

export async function writeEpheDir(extraFiles = [], tag = 'shared') {
  const dir = epheDirFor(tag);
  await mkdir(dir, { recursive: true });
  const sepl = buildSepl18();
  await writeFile(path.join(dir, sepl.name), sepl.bytes);
  for (const f of extraFiles) await writeFile(path.join(dir, f.name), f.bytes);
  return dir;
}

// Run the native pure-math golden dumper; parses `rc=.. <6 hex> serr=..`
// (serr may span lines; PATH trials differ per host, see normSerr).
export async function captureGolden(epheDir, tjd, ipl, iflag, jplfile = null) {
  const args = [epheDir, String(tjd), String(ipl), String(iflag)];
  if (jplfile) args.push(jplfile);
  const { stderr } = await execFileAsync(GOLDEN_BIN, args);
  return parseGolden(stderr);
}

export async function captureGoldenStar(epheDir, star, tjd, iflag) {
  const { stderr } = await execFileAsync(GOLDEN_BIN, [epheDir, 'star', star, String(tjd), String(iflag)]);
  return parseGolden(stderr);
}

function parseGolden(stderr) {
  // Strip exactly the one trailing newline debug.print adds; serr bytes
  // (including trailing spaces) are significant and must survive.
  const m = stderr.replace(/\r?\n$/, '').match(/^rc=(-?\d+) ((?:[0-9a-f]+ ?){6})serr=(.*)$/s);
  if (!m) throw new Error(`unparseable golden output: ${JSON.stringify(stderr)}`);
  return {
    rc: Number(m[1]),
    bits: m[2].trim().split(/\s+/).map((h) => BigInt('0x' + h)),
    serr: m[3],
  };
}

// Trial PATHs differ between golden (disk dir) and wasm (VFS dir hint);
// redact them so serr text is comparable.
export function normSerr(s) {
  return s.replace(/in PATH '[^']*'/g, "in PATH '<dir>'");
}

const CRLF = '\r\n';

// Minimal sefstars.txt: 14 comma fields per fixstarCutString
// (trad,bayer,epoch,ra_h,ra_m,ra_s,de_d,de_m,de_s,ra_pm,de_pm,radv,parall,mag).
export function buildSefstars(extraLines = []) {
  const lines = [
    '# synthetic fixture for wasm VFS tests',
    'Sirius,alf CMa,2000,6,45,8.9,-16,42,58,-553.0,-1205.0,-7.6,379.2,-1.46',
    'Canopus,alf Car,2000,6,23,57.1,-52,41,44,19.9,23.7,20.8,10.6,-0.74',
    'Arcturus,alf Boo,2000,14,15,39.7,19,10,57,-1093.0,-1999.0,-5.2,88.8,-0.05',
    ...extraLines,
  ];
  return { name: 'sefstars.txt', bytes: Buffer.from(lines.join(CRLF) + CRLF, 'latin1') };
}

// Minimal seorbel.txt: epoch,equinox,M0,sema,ecce,parg,node,incl,name[,geo].
// Body 0 (public ipl 40) deliberately differs from built-in Cupido elements.
export function buildSeorbel(lines = ['J2000,J2000,120.5,1.5,0.2,30.0,45.0,10.0,CupidoX']) {
  const body = ['# synthetic fixture for wasm VFS tests', ...lines];
  return { name: 'seorbel.txt', bytes: Buffer.from(body.join(CRLF) + CRLF, 'latin1') };
}

// Minimal eop_1962_today.txt: dense space-separated tokens (swi_cutstr skips
// delimiter runs), cpos[0]=year, cpos[3]=mjd, cpos[8]=dpsi, cpos[9]=deps,
// strictly one-day steps. NO leading spaces: those would make cpos[0] empty
// (iyear==0 → line skipped, exactly like C).
// Covered end-to-end in 09-eop.test.mjs (loader states + JPLHOR behavior).
export function buildEopToday(mjds = [51544, 51545, 51546], dpsi0 = 5, deps0 = 6, step = 1) {
  const lines = mjds.map((mjd, i) => {
    const d = mjd - 51543; // 51544 -> Jan 1
    return `2024 1 ${d} ${mjd} 0 0 0 0 ${(dpsi0 + i * step).toFixed(1)} ${(deps0 + i * step).toFixed(1)} 0`;
  });
  return { name: 'eop_1962_today.txt', bytes: Buffer.from(lines.join(CRLF) + CRLF, 'latin1') };
}

// Minimal eop_finals.txt: FIXED offsets (no tokenizing) — mjd at 7,
// Bulletin-A dpsi at 99, deps at 118, Bulletin-B at 168/178 (pinned to 0.0
// so the deterministic A branch is taken; fgets-buffer garbage past NUL
// must never decide this). MJDs must continue today's end +1/day.
export function buildEopFinals(mjds = [51547, 51548]) {
  const lines = mjds.map((mjd, i) => {
    const s = new Array(190).fill(' ');
    const put = (off, str) => { for (let k = 0; k < str.length; k++) s[off + k] = str[k]; };
    put(7, String(mjd));
    put(99, (7 + i).toFixed(1));
    put(118, (8 + i).toFixed(1));
    put(168, '0.0');
    put(178, '0.0');
    return s.join('');
  });
  return { name: 'eop_finals.txt', bytes: Buffer.from(lines.join(CRLF) + CRLF, 'latin1') };
}

// Minimal synthetic JPL ephemeris (synJpl.eph) per swejpl.fsizer /
// swi_open_jpl_file: 252B title + 2400B cnam + ss=[2451545,2451609,32] +
// ncon/au/emrat + 36xi32 ipt + numde=431 + lpt; record1 = 400xf64 cval;
// 2 segment records [segstart,segend] + earth coeff ramp.
// ipt: earth(3,12,20) anchors ksize=2*(3+3*12*20-1)=1444 (irecsz=5776);
// sun/mars/moon share small overlapping (3,2,1) regions so every interp
// stays in-bounds and finite (positions are deterministic garbage — only
// survival and determinism are asserted, never physics).
// flen = 8*(1440+12*3+4) + 2*1444*4 = 23392 exactly (no +1-record slack).
export function buildSynJpl() {
  const SS0 = 2451545.0, SS1 = 2451609.0, SS2 = 32.0;
  const KS = 1444, REC = 4 * KS; // 5776
  const NSEG = 2;
  const NB = 8 * (12 * 20 * 3 * NSEG + 2 * 1 * 3 * NSEG * 3 + 2 * NSEG) + 2 * KS * 4;
  const buf = Buffer.alloc(NB, 0);
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  buf.write('SYNTHETIC JPL EPHEMERIS FOR WASM VFS TESTS', 0, 'latin1');
  let o = 252 + 2400;
  for (const v of [SS0, SS1, SS2]) { dv.setFloat64(o, v, true); o += 8; }
  dv.setInt32(o, 400, true); o += 4; // ncon
  dv.setFloat64(o, 1.495978707e11, true); o += 8; // au
  dv.setFloat64(o, 81.30056, true); o += 8; // emrat
  const triple = (i, a, b, c) => {
    dv.setInt32(o + i * 12, a, true);
    dv.setInt32(o + i * 12 + 4, b, true);
    dv.setInt32(o + i * 12 + 8, c, true);
  };
  triple(2, 3, 12, 20); // earth: ksize anchor
  triple(10, 3, 2, 1); // sun (overlaps earth region)
  triple(3, 3, 2, 1); // mars
  triple(9, 3, 2, 1); // moon
  o += 36 * 4;
  dv.setInt32(o, 431, true); o += 4; // numde -> jpldenum 431 >= 403: EOP loads
  o += 3 * 4; // lpt (zeros)
  if (o !== 2856) throw new Error(`jpl header drift: ${o}`);
  // record1 (cval): zeros
  // segment records: [segstart, segend] + 720 earth coeff doubles (ramp)
  for (let s = 0; s < NSEG; s++) {
    const base = REC * (2 + s);
    dv.setFloat64(base, SS0 + SS2 * s, true);
    dv.setFloat64(base + 8, SS0 + SS2 * (s + 1), true);
    for (let k = 0; k < 720; k++) dv.setFloat64(base + 16 + k * 8, (s * 720 + k + 1) * 1e-9, true);
  }
  return { name: 'synJpl.eph', bytes: buf };
}

export function bitsOf(swe, ptr) {
  const dv = new DataView(swe.exports.memory.buffer);
  return Array.from({ length: 6 }, (_, i) => {
    const lo = BigInt(dv.getUint32(ptr + i * 8, true));
    const hi = BigInt(dv.getUint32(ptr + i * 8 + 4, true));
    return (hi << 32n) | lo;
  });
}

// Register a file, freeing the staging buffers immediately: proves the
// copy-on-register contract (VFS must not alias caller memory).
export function registerFile(swe, name, bytes) {
  const nb = Buffer.from(name, 'latin1');
  const np = swe.alloc(nb.length);
  const dp = bytes.length ? swe.alloc(bytes.length) : 0;
  try {
    swe.writeBytes(np, nb);
    if (bytes.length) swe.writeBytes(dp, bytes);
    const rc = swe.exports.swe_vfs_register(np, nb.length, dp, bytes.length);
    if (rc !== 0) throw new Error(`swe_vfs_register(${name}) -> ${rc}`);
  } finally {
    swe.free(np, nb.length);
    if (bytes.length) swe.free(dp, bytes.length);
  }
}

export function setEphePath(swe, dir) {
  const { ptr, len } = swe.writeCString(dir);
  try {
    swe.exports.swe_set_ephe_path(ptr);
  } finally {
    swe.free(ptr, len);
  }
}

export function setJplFile(swe, fname) {
  const { ptr, len } = swe.writeCString(fname);
  try {
    swe.exports.swe_set_jpl_file(ptr);
  } finally {
    swe.free(ptr, len);
  }
}

// Fresh golden lifecycle per comparison: new instances + register + setEphePath
// (the moon probe inside setEphePath is state the golden process also has).
// Never compare goldens against post-swe_close recomputes: close() resets the
// lifecycle (ephepath, epheflag) and recomputation may legitimately differ in
//notes/paths even when the physics is identical.
export async function freshWithFiles(files, ephePath = '/ephe', jplfile = null) {
  const { loadBoth } = await import('./loader.mjs');
  const flavors = await loadBoth();
  for (const name of ['freestanding', 'wasi']) {
    const swe = flavors[name];
    for (const f of files) registerFile(swe, f.name, f.bytes);
    setEphePath(swe, ephePath);
    if (jplfile) setJplFile(swe, jplfile);
  }
  return flavors;
}
