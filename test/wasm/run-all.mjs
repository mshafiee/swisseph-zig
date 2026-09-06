// Pinned-count runner for the wasm suite: spawns `node --test` over the
// suite files, forwards TAP verbatim, then fails unless the totals match
// EXPECTED exactly. Guards against silent skips (a file failing to load,
// a loader swallowing cases, an EOP-skip-all): any drift in test count is
// a loud failure. Bump EXPECTED when intentionally adding/removing suites.
// Usage (also from CI): node test/wasm/run-all.mjs
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FILES = [
  'test/wasm/01-smoke.test.mjs',
  'test/wasm/02-moshier.test.mjs',
  'test/wasm/03-vfs-se1.test.mjs',
  'test/wasm/04-vfs-text.test.mjs',
  'test/wasm/05-vfs-bytes.test.mjs',
  'test/wasm/06-vfs-alloc.test.mjs',
  'test/wasm/07-parity.test.mjs',
  'test/wasm/08-wasi.test.mjs',
  'test/wasm/09-eop.test.mjs',
  'test/wasm/10-bridge.test.mjs',
];
const EXPECTED = { tests: 84, pass: 84, fail: 0 };

const child = spawnSync(process.execPath, ['--test', ...FILES], {
  cwd: ROOT,
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024,
});
process.stdout.write(child.stdout ?? '');
process.stderr.write(child.stderr ?? '');
if (child.error) {
  console.error(`run-all: spawn failed: ${child.error.message}`);
  process.exit(2);
}
// TAP summary markers differ by node version (`# tests 66` vs `ℹ tests 66`)
// and by stream (stdout vs stderr): parse leniently over both.
const combined = (child.stdout ?? '') + '\n' + (child.stderr ?? '');
const pick = (name) => {
  const m = combined.match(new RegExp(`^[#\\u2139]\\s*${name}\\s+(\\d+)\\s*$`, 'm'));
  return m ? Number(m[1]) : null;
};
const got = { tests: pick('tests'), pass: pick('pass'), fail: pick('fail') };
const ok =
  child.status === 0 &&
  got.tests === EXPECTED.tests &&
  got.pass === EXPECTED.pass &&
  got.fail === EXPECTED.fail;
if (!ok) {
  console.error(
    `run-all: expected tests=${EXPECTED.tests} pass=${EXPECTED.pass} fail=${EXPECTED.fail}` +
      ` but got tests=${got.tests} pass=${got.pass} fail=${got.fail} (exit=${child.status})`,
  );
  console.error('run-all: output tail:');
  console.error(combined.trimEnd().split('\n').slice(-15).join('\n'));
  process.exit(1);
}
