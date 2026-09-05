# C ↔ Zig API Map

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

> [!WARNING]
> **Network Service Licensing Requirement**  
> If you expose these functions or derived ephemeris data over a network (e.g., via HTTP, RPC, or WebSocket APIs), prior written permission is required. Review [`API-LICENSE`](../../API-LICENSE) and [`license.md`](../license.md) for compliance terms before deployment.

---

## 1. Architectural Model: Implicit State vs. Explicit Contexts

`swisseph-zig` provides a dual interface:

1. **Standard C ABI (`src/swe_abi.zig`)**: Implements all 107 canonical `swe_*` functions and compiles into `libswe.a` / `libswe.so`. It serves as a byte-compatible, drop-in replacement for the original Astrodienst C library, relying on thread-local global state.
2. **Idiomatic Zig Facade (`src/swisseph.zig:26`)**: Bypasses global state entirely. Every function accepts explicit context structs, enabling thread-safe, reentrant, and allocation-transparent operations without hidden side effects.

### Pattern Comparison

```c
/* =========================================================================
 * C Pattern: Implicit Thread-Local State
 * ========================================================================= */
#include "sweph.h"

double xx[6];
char serr[256];

// Configure thread-local ephemeris path (NULL = default search rules)
swe_set_ephe_path(NULL);

// State is maintained implicitly across subsequent calls
int ret = swe_calc_ut(2451545.0, SE_SUN, SEFLG_SPEED, xx, serr);

// Releases thread-local caches, file handles, and allocations
swe_close();
```

```zig
// =========================================================================
// Zig Pattern: Explicit Context Dependency Injection
// =========================================================================
const swe = @import("swisseph");

var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

// Explicit runtime instances — zero hidden globals
var swed = swe.sweph.Swed{};              // File handles & orbital cache
var dctx = swe.deltat.DeltatCtx{};        // Delta-T calculation state
const models = swe.swephlib.AstroModels{}; // Precession/nutation models

const ret = swe.calc_ut(
    2451545.0,
    0, // SE_SUN
    swe.sweph.SEFLG_SPEED,
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);

// swed and dctx clean up deterministically when their scope terminates
```

---

## 2. Context Structs Reference (Zig)

When targeting the native Zig interface, implicit globals are decomposed into three explicit parameter types:

| Struct | Origin | Lifetime / Mutability | Responsibilities |
| :--- | :--- | :--- | :--- |
| `Swed` | `swe.sweph.Swed` | Mutable (`var`) | Open `.se1`/`.eph` file descriptors, planetary cache lines, active ephemeris search paths, and interpolation buffers. |
| `DeltatCtx` | `swe.deltat.DeltatCtx` | Mutable (`var`) | $\Delta T$ ($TT - UT$) interpolation caches, leap second tables, and historical drift anchors. |
| `AstroModels` | `swe.swephlib.AstroModels` | Constant (`const`) | Precession/nutation formulation flags (e.g., Vondrák 2011 vs. IAU models). |

By instantiating independent `Swed` and `DeltatCtx` structs per OS thread or async worker, native Zig applications can evaluate charts concurrently without locking or thread-local contention.

---

## 3. Notable Divergences and Extensions

While the C ABI maintains strict 1:1 parity with the legacy interface, the native Zig interface differs in two specific areas:

### 1. House Division Pipelines
* **In C (`swe_houses_ex` / `swe_houses_armc`)**: The high-level `swe_houses_ex()` routine calculates intermediate values—such as the ARMC (Right Ascension of the Midheaven) and true obliquity of the ecliptic ($\epsilon$)—internally before delegating to the core house engine.
* **In Zig (`swe.houses_armc_ex2`)**: The Zig interface decouples coordinate reduction from house cusp geometry. Callers calculate or provide `armc` and `eps` directly to `houses_armc_ex2`. This prevents redundant nutation and sidereal-time calculations when generating multiple house overlays for the same epoch.

### 2. Extension Functions (`SWE_ZIG_EXTENSIONS`)
* **`swe_cleanup`**: An extended lifecycle API provided under `SWE_ZIG_EXTENSIONS`. While standard `swe_close()` frees open file descriptors, `swe_cleanup()` provides a complete reset of all internal memory pools, allocator states, and thread-local handles within the Zig runtime layer.

---

## 4. ABI Layout & Binary Invariants

All data structures passed between C and Zig share binary compatibility without marshalling overhead:

* **Error Buffers (`serr`)**: Fixed-size `[256]u8` in Zig $\leftrightarrow$ `char serr[256]` in C. Null-terminated ASCII/UTF-8.
* **Coordinate Vectors (`xx`)**: Fixed-size `[6]f64` in Zig $\leftrightarrow$ `double xx[6]` in C. Same dimension ordering ($\lambda, \beta, r, \dot{\lambda}, \dot{\beta}, \dot{r}$).
* **Timing & Phenomenon Arrays**: `tret` transit arrays and `attr` phenomenon slices maintain identical `f64` alignments and stride offsets across both targets.
* **Status Return Codes**: Return values $< 0$ denote errors (e.g., `ERR = -1`, `ERR_BEYOND = -3`); values $\ge 0$ denote success or degraded fallback flags (e.g., `SEFLG_MOSEPH`).

---

## 5. Linking `libswe` in Existing C Toolchains

Pre-built binaries generated by `swisseph-zig` serve as drop-in replacements for existing C/C++ builds without source-code modifications.

### Artifact Topology
```text
dist/<target-triple>/
├── include/
│   ├── sweph.h
│   └── swephexp.h
└── lib/
    ├── libswe.a
    └── libswe.so (or .dylib / .dll)
```

### Direct Compilation Example

Reference implementation: `examples/c-abi/main.c`.

```bash
# Compile and link a legacy C consumer against the Zig-produced libswe artifact
gcc -O2 examples/c-abi/main.c \
    -I dist/x86_64-linux-gnu/include \
    -L dist/x86_64-linux-gnu/lib \
    -lswe -lm \
    -o calc_demo
```
