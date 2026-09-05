# Threading, Build System, and WebAssembly

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Threading Architecture and Concurrency Contract

* **Source Anchors**: Concurrency contract in `README.md:216`, C ABI thread-local implementation in `src/swe_abi.zig`, stress test suite in `src/test_stress_race.zig`.
* **The Core Invariant**: **Calculations never use shared mutable state without an explicit lock.**

```
  Zig Native (Zero Globals, Reentrant)          C ABI Compatibility (Thread-Local Storage)
  ───────────────────────────────────────       ──────────────────────────────────────────
  Thread A: swed_A, dctx_A, hctx_A              OS Thread A: swe_state (TLS instance A)
  Thread B: swed_B, dctx_B, hctx_B              OS Thread B: swe_state (TLS instance B)
  (Passed explicitly to swe.calc_ut)            (swe_set_* must be called on each thread)
```

### 1.1 Native Zig: Explicit Context Bundles
Native Zig calculations completely decouple runtime memory from global pointers. All mutable state is partitioned into caller-allocated workspace structs:

| Struct | Module Origin | Contained State & Memory Responsibilities |
| :--- | :--- | :--- |
| `Swed` | `swe.sweph.Swed` | Open `.se1` file descriptors, planetary cache lines (`plan_ws`), lunar theories (`moon_ws`), JPL integration handles (`jpl`), and parsed fixed star catalog vectors (`sefstars.txt`). |
| `DeltatCtx` | `swe.deltat.DeltatCtx` | $\Delta T$ ($TT - UT$) spline interpolation caches, leap second tables (`seleapsec.txt`), and tidal acceleration overrides. |
| `HouseCtx` | `swe.swehouse.HouseCtx` | Cusp workspace, ARMC intermediate values, and Sunshine house declination anchors (`saved_sundec`). |
| `SweclCtx` | `swe.swecl.SweclCtx` | Eclipse search state, Besselian plane projection buffers, and Saros cycle counters. |
| `SwehelCtx` | `swe.swehel.SwehelCtx` | Schaefer heliacal visibility buffers, atmospheric extinction matrices, and limiting magnitude caches. |
| `AstroModels` | `swe.swephlib.AstroModels` | **Immutable configuration value struct.** Governs precession, nutation, and frame-bias models. Safe to share read-only across all threads simultaneously. |

#### Thread Safety Rule
**One bundle per thread.** If multiple threads or coroutines must share an instance of `Swed` or `DeltatCtx`, the caller must synchronize access using an external mutex or channel.

```zig
// Native Zig multi-threaded worker pattern
fn workerTask(jd_ut: f64, ipl: i32, models: swe.swephlib.AstroModels) !void {
    // Thread-isolated memory context:
    var swed = swe.sweph.Swed{};
    var dctx = swe.deltat.DeltatCtx{};
    
    swe.set_ephe_path("/var/data/ephe", &swed);
    defer swe.close(&swed);

    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;

    const status = swe.calc_ut(jd_ut, ipl, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
    if (status < 0) return error.CalculationFailed;
}
```

---

### 1.2 C ABI: Thread-Local Storage (TLS)
When consumed as a C drop-in replacement (`libswe.a` or `libswe.so`), `src/swe_abi.zig` routes calls through an internal, thread-local workspace:

```zig
threadlocal var swe_state: SweState = SweState.init();
```

* **Per-Thread Setup Invariant**: Because state is thread-local, configuration calls such as `swe_set_ephe_path()`, `swe_set_topo()`, `swe_set_jpl_file()`, and `swe_set_sid_mode()` configure **only the calling OS thread**. Every new thread spawned in a C/C++ application must invoke its own initialization sequence before issuing calculations.
* **Teardown Protocol**:
  * `swe_close()`: Closes open file descriptors held by the calling thread's `Swed` instance.
  * `swe_cleanup()`: Provided under `SWE_ZIG_EXTENSIONS`. Deallocates dynamic heap buffers (including cached fixed-star records and Moon acceleration buffers) held by the calling thread.

---

### 1.3 Concurrency Verification and Stress Testing
Thread isolation is formally validated by `src/test_stress_race.zig` (`zig build run-stress`):
* Spawns **32 concurrent OS threads** executing across 4 mixed operational rounds.
* Rounds simultaneously interleave high-precision JPL DE431 binary evaluations (`SEFLG_JPLEPH`), compressed Chebyshev evaluations (`SEFLG_SWIEPH`), and analytical Moshier calculations (`SEFLG_MOSEPH`).
* **Parity Assertion**: Every calculation output across all 32 threads is asserted to be **bit-for-bit identical** ($0\text{ ULP}$ difference) to a single-threaded baseline run.

---

## 2. Build System and Cross-Compilation Pipeline

The build architecture is controlled by `build.zig:13` and can be driven via `zig build` or `make`.

### 2.1 Supported Target Matrix (`make all`)
`make all` cross-compiles release artifacts for 9 target triples:

| Target Triple | ABI / Platform Details | Standard Output Binary Artifacts |
| :--- | :--- | :--- |
| `x86_64-linux-gnu` | Linux x86_64, Glibc ABI | `dist/x86_64-linux-gnu/{lib/libswe.a, lib/libswe.so, bin/*}` |
| `aarch64-linux-gnu` | Linux ARM64, Glibc ABI | `dist/aarch64-linux-gnu/{lib/libswe.a, lib/libswe.so, bin/*}` |
| `x86_64-freebsd` | FreeBSD x86_64, native libc | `dist/x86_64-freebsd/{lib/libswe.a, bin/*}` |
| `aarch64-freebsd` | FreeBSD ARM64, native libc | `dist/aarch64-freebsd/{lib/libswe.a, bin/*}` |
| `x86_64-macos` | macOS Intel (Darwin), Mach-O | `dist/x86_64-macos/{lib/libswe.a, lib/libswe.dylib, bin/*}` |
| `aarch64-macos` | macOS Apple Silicon, Mach-O | `dist/aarch64-macos/{lib/libswe.a, lib/libswe.dylib, bin/*}` |
| `x86_64-windows` | Windows x86_64, MSVC/GNU ABI | `dist/x86_64-windows/{lib/swe.lib, bin/swe.dll, bin/*.exe}` |
| `wasm32-freestanding`| WebAssembly embedded / browser | `dist/wasm32-freestanding/{lib/libswe.a, bin/swe.wasm}` |
| `wasm32-wasi` | WebAssembly System Interface | `dist/wasm32-wasi/{lib/libswe.a, bin/swe.wasm}` |

---

### 2.2 Standard Build Invocations

```bash
# Build for host machine into dist/<host-triple>/
make

# Build full cross-platform distribution matrix (9 triples)
make all

# Execute full test suite across native math and C ABI
make test

# Run code style, formatting, and lint checks
make lint
```

---

## 3. Floating-Point Math Strategy: C Libm vs. Pure Correctly-Rounded Math

A primary engineering challenge in porting Swiss Ephemeris is preserving exact bit-for-bit parity with legacy C binaries across varied CPU microarchitectures and compiler backends.

```
                  Floating-Point Engine Selection
 
  Default Mode (Platform Libm)               Pure Math Mode (-Dpure=true)
  ────────────────────────────               ────────────────────────────
  • Links platform libm via libmshim.c       • Pure Zig (std.math + src/libm/cr.zig)
  • Disables FMA (-ffp-contract=off)         • f128 Ziv correctly-rounded math
  • Bit-identical to Astrodienst C oracle    • Bound to <= 1 ULP from true value
  • Used by Linux, macOS, FreeBSD            • Mandatory on WASM and Windows
```

### 3.1 Default Mode: Platform `libm` Shim (`libmshim.c`)
By default, desktop POSIX builds link against the host system’s standard C mathematics library (`libm`) via an internal shim (`libmshim.c`).
* **Compiler Flags**: Enforces strict IEEE-754 semantics with fused multiply-add disabled (`-ffp-contract=off`).
* **Design Goal**: Guarantees identical rounding behavior to upstream C Swiss Ephemeris binaries, passing strict bit-level regression suites without delta tolerances.

### 3.2 Pure Math Mode: Correctly-Rounded Math (`-Dpure=true`)
When configured with `-Dpure=true`, the build system bypasses external C libraries, delegating all transcendental math to native Zig (`std.math`) and an internal multi-precision engine (`src/libm/cr.zig`):
* **Ziv Multi-Precision Iteration**: Transcendental primitives (`atan`, `asin`, `acos`, `atan2`, `pow`) evaluate via high-precision polynomial expansions backed by 128-bit floating-point arithmetic (`f128`). If initial polynomial evaluation bounds fall close to a rounding boundary, Ziv’s iterative loop widens precision until the correctly-rounded nearest 64-bit IEEE float (`f64`) is resolved.
* **Precision Invariant**: Operates within **$\le 1\text{ ULP}$** (Unit in the Last Place) of exact mathematical truth.
* **Platform Invariant**: **WASM targets (`wasm32-freestanding`, `wasm32-wasi`) and Windows automatically force `-Dpure=true`**, eliminating external C runtime library linkages.

---

## 4. WebAssembly (WASM) Deployment Guide

`swisseph-zig` provides first-class support for WebAssembly in both browser and standalone serverless environments.

### 4.1 Target Flavors
* **`wasm32-wasi`**: Targets runtimes supporting the WebAssembly System Interface (Wasmtime, Wasmer, Node.js WASI). Provides full filesystem access, allowing direct reads of `.se1`, `sefstars.txt`, and `seorbel.txt` files mapped from host directories.
* **`wasm32-freestanding`**: Targets embedded browser environments without POSIX filesystem abstractions. In this mode:
  * Pure analytical Moshier calculations (`SEFLG_MOSEPH`) evaluate with zero external dependencies.
  * Ephemeris data files (`.se1`) must be loaded into memory and accessed via custom memory-buffer streams or emulated virtual filesystems.

### 4.2 Building WebAssembly Modules

```bash
# Compile standalone WASI binary with pure correctly-rounded math
zig build -Dtarget=wasm32-wasi -Dpure=true -Doptimize=ReleaseFast

# Compile browser-targeted freestanding binary
zig build -Dtarget=wasm32-freestanding -Dpure=true -Doptimize=ReleaseSmall
```

---

## 5. Verification Tools and Reference Binaries

The repository provides CLI testing utilities in `src/bin/` and `src/ep4/`. These binaries match upstream reference tools:

| Utility Binary | Source Location | Functional Purpose & Diagnostic Role |
| :--- | :--- | :--- |
| `swetest` | `src/bin/swetest.zig` | The primary diagnostic CLI. Evaluates bodies, houses, sidereal modes, eclipses, and coordinate systems. Mirrors upstream `swetest`. |
| `swevents` | `src/bin/swevents.zig` | Scans for eclipse contacts, planetary occultations, stationary points, and aspect crossings over extended time windows. |
| `swemini` | `src/bin/swemini.zig` | Minimal integration example. Computes planets 0 through 15 in a concise loop (`src/bin/swemini.zig:56`). |
| `obama` | `src/bin/obama.zig` | Benchmark validation suite computing natal, transit, progression, and harmonic charts for a fixed reference epoch. |
| `swephgen4` | `src/ep4/swephgen4.zig` | Ephemeris file generator. Compresses raw JPL numerical integration Chebyshev intervals into Swiss Ephemeris binary `.se1` files. |

### Running the Parity Verification Suite

```bash
# Execute unit tests and parity validation against upstream C test vectors
zig build test

# Run multi-threaded stress and race detection tests
zig build run-stress

# Evaluate swetest directly from Zig
zig build run-swetest -- -p0 -b1.1.2000 -fPLBRS -n1
```
