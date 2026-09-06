// Headless-Chrome sweep gate runner (dependency-free).
// Serves test/chrome/ + zig-out/wasm/swe.wasm over loopback, runs
// sweep.html in headless Chrome, and asserts the SWE-RESULT payload.
// Skips (exit 0) when no Chrome binary is found — CI without Chrome
// still runs the node gates. Override: CHROME_BIN=/path/to/chrome.
// Usage: node test/chrome/run.mjs
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DIR = path.join(ROOT, 'test/chrome');
const WASM = path.join(ROOT, 'zig-out/wasm/swe.wasm');

function findChrome() {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  for (const p of [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
  ]) {
    if (fs.existsSync(p)) return p;
  }
  for (const b of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']) {
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

const args = [
  '--headless=new',
  '--disable-gpu',
  '--no-first-run',
  '--no-default-browser-check',
  `--virtual-time-budget=60000`,
  '--dump-dom',
  `http://127.0.0.1:${port}/sweep.html`,
];
// NOTE: async spawn, not spawnSync — the loopback server lives on this
// process's event loop, which a synchronous wait would starve (Chrome
// would hang with an empty DOM dump).
const out = await new Promise((resolve, reject) => {
  const child = spawn(chrome, args, { timeout: 120000 });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (d) => (stdout += d));
  child.stderr.on('data', (d) => (stderr += d));
  child.on('error', reject);
  child.on('close', () => resolve(stdout + '\n' + stderr));
});
server.close();
const m = out.match(/SWE-RESULT (\{.*\})/);
if (!m) {
  console.error('chrome gate: no SWE-RESULT payload. output tail:');
  console.error(out.trimEnd().split('\n').slice(-15).join('\n'));
  process.exit(1);
}
let res;
try {
  res = JSON.parse(m[1]);
} catch (e) {
  console.error(`chrome gate: unparsable payload: ${m[1].slice(0, 300)}`);
  process.exit(1);
}
for (const c of res.checks) console.log(`chrome: ${c.ok ? 'ok' : 'FAIL'} ${c.name}${c.extra ? ` (${c.extra})` : ''}`);
if (!res.pass) {
  console.error('chrome gate: FAILED');
  process.exit(1);
}
console.log('chrome gate: pass');
