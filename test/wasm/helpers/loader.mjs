// Loader for the wasm-test artifacts (zig-out/wasm-test/*.wasm).
// Zero dependencies: WebAssembly globals + node:wasi only.
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ARTIFACT_DIR = path.resolve(HERE, '../../../zig-out/wasm-test');

function freshU8(exports) {
  return new Uint8Array(exports.memory.buffer);
}

function freshDV(exports) {
  return new DataView(exports.memory.buffer);
}

// snprintf stub for wasm32-freestanding (no libc): the only C import.
// swe_abi calls it in swe_cs2degstr + swe_utc_to_jd error paths. The stub
// NULs the buffer and returns 0; tests avoid asserting those messages.
function makeSnprintf(holder) {
  return (bufPtr, n) => {
    try {
      const mem = holder.instance?.exports.memory;
      if (mem && bufPtr !== 0 && n > 0) freshU8({ memory: mem })[bufPtr] = 0;
    } catch { /* memory may be momentarily detached; still return 0 */ }
    return 0;
  };
}

class SweWasm {
  constructor(instance, flavor) {
    this.instance = instance;
    this.exports = instance.exports;
    this.flavor = flavor;
  }

  alloc(n) {
    const p = this.exports.swe_wasm_alloc(n);
    if (p === 0) throw new Error(`swe_wasm_alloc(${n}) failed`);
    return p;
  }

  free(ptr, n) {
    this.exports.swe_wasm_free(ptr, n);
  }

  writeBytes(ptr, bytes) {
    freshU8(this.exports).set(bytes, ptr);
  }

  readBytes(ptr, n) {
    return freshU8(this.exports).slice(ptr, ptr + n);
  }

  // Stage a NUL-terminated C string; caller must free(ptr, len+1).
  writeCString(str) {
    const enc = new TextEncoder().encode(str);
    const ptr = this.alloc(enc.length + 1);
    const mem = freshU8(this.exports);
    mem.set(enc, ptr);
    mem[ptr + enc.length] = 0;
    return { ptr, len: enc.length + 1 };
  }

  readCString(ptr, maxLen = 4096) {
    const mem = freshU8(this.exports);
    let end = ptr;
    while (end < ptr + maxLen && mem[end] !== 0) end++;
    return new TextDecoder().decode(mem.slice(ptr, end));
  }

  allocF64(n) {
    return this.alloc(n * 8);
  }

  readF64(ptr, n) {
    const out = new Array(n);
    const dv = freshDV(this.exports);
    for (let i = 0; i < n; i++) out[i] = dv.getFloat64(ptr + i * 8, true);
    return out;
  }

  writeF64(ptr, values) {
    const dv = freshDV(this.exports);
    values.forEach((v, i) => dv.setFloat64(ptr + i * 8, v, true));
  }

  allocI32(n) {
    return this.alloc(n * 4);
  }

  readI32(ptr, n) {
    const out = new Array(n);
    const dv = freshDV(this.exports);
    for (let i = 0; i < n; i++) out[i] = dv.getInt32(ptr + i * 4, true);
    return out;
  }

  // 256-byte serr buffer helper: returns {ptr, read()}.
  serrBuf() {
    const ptr = this.alloc(256);
    const self = this;
    return {
      ptr,
      read: () => self.readCString(ptr, 256),
      free: () => self.free(ptr, 256),
    };
  }
}

export async function loadFreestanding() {
  const bytes = await readFile(path.join(ARTIFACT_DIR, 'swe-test-freestanding.wasm'));
  const holder = {};
  const { instance } = await WebAssembly.instantiate(bytes, {
    env: { snprintf: makeSnprintf(holder) },
  });
  holder.instance = instance;
  return new SweWasm(instance, 'freestanding');
}

export async function loadWasi(preopens = {}) {
  const wasi = new WASI({ version: 'preview1', preopens });
  const bytes = await readFile(path.join(ARTIFACT_DIR, 'swe-test-wasi.wasm'));
  const { instance } = await WebAssembly.instantiate(bytes, {
    wasi_snapshot_preview1: wasi.wasiImport,
  });
  // Entry-disabled binary: no _start to run; call it only if present.
  if (typeof instance.exports._start === 'function') {
    try {
      wasi.start(instance);
    } catch (err) {
      if (err?.code !== 'ERR_WASI_NOT_STARTED' && err?.name !== 'WASIExitError') throw err;
    }
  }
  return new SweWasm(instance, 'wasi');
}

// Both flavors; tests iterate to prove freestanding+VFS ≡ wasi+FS.
export async function loadBoth(preopens = {}) {
  const [freestanding, wasi] = await Promise.all([loadFreestanding(), loadWasi(preopens)]);
  return { freestanding, wasi };
}

export { ARTIFACT_DIR };
