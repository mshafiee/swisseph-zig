// Headless-Chrome sweep gate runner (dependency-free).
// Serves test/chrome/ + zig-out/wasm/swe.wasm over loopback, runs
// sweep.html in headless Chrome, and reads the SWE-RESULT payload the
// page POSTs back to /result — a deterministic handshake. The previous
// --dump-dom + --virtual-time-budget approach raced module-script
// completion (flaky "no payload" on macOS CI), and Chrome's helper
// processes inherit the stdio pipes, so on Windows `close` may never
// fire; here the runner resolves on the HTTP result and tree-kills
// Chrome itself.
// Skips (exit 0) when no Chrome binary is found — CI without Chrome
// still runs the node gates. Override: CHROME_BIN=/path/to/chrome.
// Usage: node test/chrome/run.mjs
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DIR = path.join(ROOT, 'test/chrome');
const WASM = path.join(ROOT, 'zig-out/wasm/swe.wasm');
const TIMEOUT_MS = 120_000;

function killTree(child) {
  if (process.platform === 'win32') {
    try {
      spawnSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
    } catch { /* best effort */ }
  } else {
    // detached:true made Chrome its own process-group leader, so the
    // negative pid kills the browser plus all its helpers.
    try {
      process.kill(-child.pid, 'SIGKILL');
    } catch {
      try { child.kill('SIGKILL'); } catch { /* already gone */ }
    }
  }
}

function findChrome() {
  for (const v of [process.env.CHROME_BIN, process.env.CHROME_PATH]) {
    if (v && fs.existsSync(v)) return v;
  }
  for (const p of [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
  ]) {
    if (fs.existsSync(p)) return p;
  }
  for (const b of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'chrome']) {
    try {
      const r = spawnSync(b, ['--version'], { encoding: 'utf8' });
      if (r.status === 0) return b;
    } catch { /* try next */ }
  }
  return null;
}

const chrome = findChrome();
if (!chrome) {
  console.log('chrome gate: no Chrome binary found — skipping (node gates still run)');
  process.exit(0);
}
if (!fs.existsSync(WASM)) {
  console.log('chrome gate: zig-out/wasm/swe.wasm missing (run `zig build wasm`) — skipping');
  process.exit(0);
}

let resolveResult;
const resultPromise = new Promise((resolve) => { resolveResult = resolve; });
let resolveClosed;
const closedPromise = new Promise((resolve) => { resolveClosed = resolve; });

const server = createServer((req, res) => {
  try {
    if (req.url === '/sweep.html' || req.url === '/') {
      const html = fs.readFileSync(path.join(DIR, 'sweep.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } else if (req.url === '/swe.wasm') {
      const wasm = fs.readFileSync(WASM);
      res.writeHead(200, { 'Content-Type': 'application/wasm', 'Content-Length': wasm.length });
      res.end(wasm);
    } else if (req.url.startsWith('/result?')) {
      const p = new URL(req.url, 'http://localhost').searchParams.get('p') ?? '';
      res.writeHead(204);
      res.end();
      resolveResult(p);
    } else {
      res.writeHead(404);
      res.end('nope');
    }
  } catch (e) {
    res.writeHead(500);
    res.end(String(e));
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;

// Fresh profile per run: a shared default profile dir carries locks and
// state between invocations (flaky empty dumps when a previous Chrome is
// still releasing it).
const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'swe-chrome-'));
const args = [
  '--headless=new',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--no-first-run',
  '--no-default-browser-check',
  `--user-data-dir=${profileDir}`,
  `http://127.0.0.1:${port}/sweep.html`,
];
// detached on POSIX so killTree can take down the whole process group.
// NOTE: async spawn, not spawnSync — the loopback server lives on this
// process's event loop, which a synchronous wait would starve.
const child = spawn(chrome, args, { detached: process.platform !== 'win32' });
let stdout = '';
let stderr = '';
child.stdout.on('data', (d) => (stdout += d));
child.stderr.on('data', (d) => (stderr += d));
child.on('error', () => resolveClosed());
child.on('close', () => resolveClosed());

const timer = setTimeout(() => resolveResult(null), TIMEOUT_MS);
const winner = await Promise.race([
  resultPromise.then((p) => ({ kind: 'result', p })),
  closedPromise.then(() => ({ kind: 'closed' })),
]);
clearTimeout(timer);
// Bounded: even if a Chrome helper lingers on the pipes after the kill,
// never let a stuck `close` stall the runner (the Windows-hang failure
// mode). Termination is forced by the explicit exit codes below.
killTree(child);
await Promise.race([closedPromise, new Promise((r) => setTimeout(r, 5_000))]);
server.close();
fs.rmSync(profileDir, { recursive: true, force: true });
if (winner.kind !== 'result' || !winner.p) {
  const why = winner.kind === 'closed'
    ? 'Chrome exited before reporting a result'
    : 'timed out waiting for the page to report a result';
  console.error(`chrome gate: no SWE-RESULT payload (${why}). output tail:`);
  console.error((stdout + '\n' + stderr).trimEnd().split('\n').slice(-15).join('\n'));
  process.exit(1);
}
let res;
try {
  res = JSON.parse(winner.p.replace(/^SWE-RESULT /, ''));
} catch (e) {
  console.error(`chrome gate: unparsable payload: ${winner.p.slice(0, 300)}`);
  process.exit(1);
}
for (const c of res.checks) console.log(`chrome: ${c.ok ? 'ok' : 'FAIL'} ${c.name}${c.extra ? ` (${c.extra})` : ''}`);
if (!res.pass) {
  console.error('chrome gate: FAILED');
  process.exit(1);
}
console.log('chrome gate: pass');
process.exit(0);
