# Bit-Parity Methodology

> Part of the [swisseph-zig documentation](../index.md) · [Threading & Build Reference](../reference/61-threading-build.md)

`swisseph-zig` guarantees **exact bit-for-bit parity** with the upstream Swiss Ephemeris C reference implementation. 

Our porting rule rejects approximation tolerances (e.g., `assert(approxEq(a, b, 1e-9))`). Instead, every ported routine preserves the exact floating-point evaluation order and identical mathematical constants, requiring strict equality (`==`) across full `%.17g` IEEE 754 round-trips against a reference C oracle.

---

## 1. The Fused Multiply-Add (FMA) Trap

The upstream C oracle **must** be compiled with `-ffp-contract=off`.

```sh
# Mandatory compiler flag for reference oracle builds
CFLAGS="-ffp-contract=off"
```

### Why This Matters
- **The Problem:** Compilers like Apple Clang fuse expressions of the form `a * b + c` into a single hardware FMA (Fused Multiply-Add) instruction by default. FMA skips the intermediate rounding step, introducing a sub-ULP (Unit in the Last Place) divergence between platforms (x86 vs. ARM vs. MSVC).
- **The Zig Standard:** Zig evaluates operations strictly in sequence without implicit contraction unless explicitly instructed.
- **The Rule:** Compiling the C oracle without `-ffp-contract=off` is the leading cause of false mismatches during verification.

---

## 2. Floating-Point & `libm` Strategy

Mathematical parity depends on transcendental functions behaving identically across runtimes. We address this using a two-tier strategy implemented in `src/libmshim.c` and `src/libm/cr.zig`:

| Execution Mode | Elementary Functions<br>`sin`, `cos`, `tan`, `log`, `exp`, `fmod` | Inverse / Power Functions<br>`atan`, `asin`, `acos`, `atan2`, `pow` |
|---|---|---|
| **Default Shim** (`libmshim.c`) | Platform `libm` via `dlsym`<br>*(Bit-exact with C)* | Platform `libm` via `dlsym`<br>*(Bit-exact with C)* |
| **Pure Zig** (`-Dpure=true`) | Zig `std.math`<br>*(Bit-identical to libm)* | Correctly-rounded `f128` (Ziv's iteration)<br>*(Controlled 1-ULP bound vs. libm)* |

### Transcendental Rounding & Licensing
Standard C runtime libraries (`libm`) are often not correctly rounded for inverse trigonometric functions. Benchmarked against 60-digit arbitrary-precision arithmetic (`mpmath`), standard `libm` implementations show noticeable deviations on edge cases (`atan` deviates ~4% of the time, `acos` ~15%).

- Apple's Taligent double-double algorithms provide exceptional accuracy but cannot be vendored due to the Apple Public Source License (APSL).
- In `-Dpure=true` mode, inverse functions are backed by Ziv-iteration algorithms in quadruple precision (`f128`), producing mathematically superior results that remain within 1 ULP of host `libm`.
- **Target Defaults:** Builds targeting `wasm32-*` and `x86_64-windows` automatically enforce `-Dpure=true` to eliminate foreign C runtime dependencies.

---

## 3. Test Corpora Breakdown

The verification harness evaluates **4,428,079 unique test cases with 0 failures** across 21 test suites:

| Category | Suite | Test Cases | Scope / Conditions |
|---|---|---|---|
| **Calendars & Time** | `swedate` | 2,200,000 | Julian ↔ Gregorian bidirectional transitions, leap years, extreme epochs |
| | `deltat` | 28,000 | Historical observations, Stephenson models, polynomial fits |
| **Ephemeris Engines** | `calc` (MOSEPH + SWIEPH) | 1,200,000 | Multi-century planetary coordinate sweeps |
| | `swemmoon` | 348,000 | Moshier lunar theory reduction steps |
| | `swemplan` | 195,000 | Moshier analytical planetary series |
| | `swejpl` | 6,500 | Binary DE406 / DE431 integration slices |
| **Coordinate Reductions** | `swehouse` | 338,000 | 25 house systems across equatorial, temperate, and polar latitudes |
| | Sidereal Reductions | 42,000 | All 47 ayanamsha modes (standard + user-defined offsets) |
| | Topocentric Reductions | 10,000 | Surface observer coordinates with atmospheric refraction |
| | Nutation Interpolation | 578 | High-density nutation sampling |
| **Minor & Deep-Sky Bodies**| Asteroids | 26,000 | Main belt, Trojans, Centaurs, and TNOs |
| | Fictitious / Uranian | 7,000 | Cupido, Hades, Zeus, Kronos, Apollon, etc. |
| | Planetary Moons / COB | 3,100 | Natural satellite coordinates and center-of-body offsets |
| | Fixed Stars | 1,700 | Proper motion, parallax, and radial velocity reductions |
| **Orbital & Visual Events**| `swecl` (Eclipse Core) | 12,500 | Global and local occultations |
| | Rise / Set Transitions | 8,900 | Rise, set, transit, and true-horizon crossings |
| | Heliacal Phenomena | 3,500 | Visibility arcus visionis and Schaefer threshold models |
| | Nodes & Apsides | 3,000 | Mean and true lunar nodes/apsides (`swe_nod_aps`) |
| | Planetary Phenomena | 2,700 | Phase angle, elongation, visual magnitude (`swe_pheno`) |
| | Solar / Lunar Eclipses | 282 | Comprehensive eclipse geometry |

---

## 4. Release Gate Pipeline

Before any version tag is cut, the codebase must pass four automated verification gates via the companion repository (`swisseph-zig-verify`):

```sh
# 1. Run all 21 differential corpora (requires 4.4M cases to match with zero failures)
make verify FORCE=1

# 2. Verify all 119 public & shim ABI symbols against C libswe.a
make abi

# 3. Ensure CLI tools produce byte-exact output against upstream C binaries
# (swetest, swemini, obama, swevents)
make tools

# 4. In-repo multi-threaded determinism stress test
# (Executes 32 threads under mixed workloads to verify zero cross-thread state leakage)
zig build run-stress
```

---

## 5. Astronomical Accuracy vs. Parity

Parity measures how faithfully this codebase reproduces the C reference. **Astronomical accuracy** measures how closely the underlying models describe the physical universe:

- **Vs. Astronomical Almanac:** Coordinates agree to within **0.001 arcseconds**.
- **Vs. JPL Horizons On-line Ephemeris:** 
  - **~1 milliarcsecond (mas)** for epochs from 1962 to the present when using full Earth Orientation Parameters (EOP).
  - **~2 mas** using approximate reductions.
- **Ephemeris Differences:**
  - `DE431` vs. `DE406`: < 0.4" for the Sun; < 129" for Pluto over extended multi-millennium spans.

> **Verification Standard:** When citing benchmark figures or astronomical coordinates, always publish the exact theory model, Delta-T configuration, and ephemeris file version used.
