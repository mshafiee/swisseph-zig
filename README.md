<div align="center">
  <img src="assets/readme/hero.svg" alt="swisseph-zig — Swiss Ephemeris in pure Zig" width="100%">

  # swisseph-zig

  **Swiss Ephemeris, engineered in pure Zig.**  
  *Bit-for-bit identical to the C reference across 4.4M+ test cases.*

  [![CI](https://github.com/mshafiee/swisseph-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/mshafiee/swisseph-zig/actions/workflows/ci.yml)
  [![Zig](https://img.shields.io/badge/zig-0.16.x-orange.svg)](https://ziglang.org)
  [![License](https://img.shields.io/badge/license-AGPL--3.0%20%7C%20Commercial-blue.svg)](LICENSE)
</div>

---

## Overview

Upstream Swiss Ephemeris is the undisputed gold standard for astronomical computation, but it relies on legacy C patterns: implicit global state, manual memory allocations, and tricky cross-compilation toolchains.

**swisseph-zig** is a complete, ground-up rewrite in memory-safe Zig. It delivers identical high-precision astronomical algorithms—planetary positions, houses, eclipses, rise/set times, heliacal events, and fixed stars—without the overhead of `libc` or undefined behavior.

### Why swisseph-zig?

| Feature | Upstream C Library | swisseph-zig |
|---|---|---|
| **Core Implementation** | C (9 monolithic `.c` files) | **Pure Zig** (12 modular components) |
| **Bit Parity** | Reference implementation | **Exact match (`==`)** across 4.4M cases |
| **Cross-Compilation** | Toolchain-dependent per platform | **Built-in:** `zig build -Dtarget=<triple>` |
| **WebAssembly** | Requires custom patches & emulation | **Native WASM** (`wasm32-freestanding`, no libc) |
| **State & Concurrency** | Global mutable hidden state | **Explicit context structs** / Thread-safe |
| **Memory Safety** | Unchecked pointer math, `malloc`/`free` | Safe slices, custom allocators, bounds checking |

---

## Highlights

- **100% C ABI Drop-in:** Exports all 107 upstream `swephexp.h` symbols. Replace `libswe` without changing a single line of your existing C code.
- **Zero-Allocation Computations:** Core calculations run with caller-supplied buffers and explicit contexts.
- **Out-of-the-box Moshier Engine:** Run planetary ephemeris offline with zero external data files required, or mount official Swiss Ephemeris `.se1` files for maximum precision.

---

## Quick Start

### 1. Using as a Zig Dependency

Add the package to your `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/mshafiee/swisseph-zig
```

Then consume it in your code with explicit state tracking:

```zig
const std = @import("std");
const swe = @import("swisseph");

pub fn main() !void {
    var swed = swe.sweph.Swed{};               // Ephemeris engine state (files & caches)
    var dctx = swe.deltat.DeltatCtx{};         // Delta-T models
    const models = swe.swephlib.AstroModels{}; // Standard astronomical models

    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;

    // Julian day for 2000-01-01 12:00 UT
    const jd_ut = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL);

    // Compute Sun coordinates (body index 0)
    _ = swe.calc_ut(jd_ut, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);

    std.debug.print("Sun Longitude: {d:.6}°\n", .{xx[0]});
}
```

> **Note:** All computation state is passed explicitly. Nothing is concealed in module-level global variables. See [Threading Model](#threading-model).

---

### 2. Using as a C ABI Drop-in

Compile the native C-compatible library:

```sh
make native
cc myprog.c -Idist/<host>/include -Ldist/<host>/lib -lswe -lm -o myprog
```

Existing code targeting `swephexp.h` compiles directly with no source modifications.

---

### 3. Running the CLI Tools

Compile and run the included `swetest` utility:

```sh
make && ./zig-out/bin/swetest -b1.1.2000 -p0 -fPLBRS -g, -head
```

Output:
```text
date (dmy) 1.1.2000 greg.   0:00:00 TT    version 2.10.03
UT:  2451544.499261244     delta t: 63.828499 sec
Sun        , 279°51'30.4607,   0° 0' 0.8266,   0.983331864,   1° 1' 9.7787
Moon       , 217°17'36.1194,   5°13'53.0223,   0.002679809,  12° 6'10.7731
Mercury    , 271° 6'42.4502,  -0°56'44.2866,   1.413694653,   1°33'13.5807
...
```

---

## Prebuilt Binaries & Supported Targets

Every release automatically compiles and tests 9 target architectures:

| Platform / Triple | Archive | Library Format | Binaries |
|---|---|---|---|
| `x86_64-linux-gnu` / `aarch64-linux-gnu` | `.tar.gz` | `.a` + `.so` | ELF |
| `x86_64-macos` / `aarch64-macos` | `.tar.gz` | `.a` + `.dylib` | Mach-O |
| `x86_64-freebsd` / `aarch64-freebsd` | `.tar.gz` | `.a` + `.so` | ELF |
| `x86_64-windows` | `.zip` | `.lib` + `.dll` | PE (`.exe`) |
| `wasm32-freestanding` | `.tar.gz` | `.a` (libc-free) | — |
| `wasm32-wasi` | `.tar.gz` | `.a` | WASI |

Artifacts and their `SHA256SUMS` files are hosted on the [GitHub Releases page](https://github.com/mshafiee/swisseph-zig/releases).

#### macOS Linking Note
The prebuilt dynamic library uses `@rpath`. When linking dynamically on macOS:
```sh
cc myprog.c -Iswisseph-zig-<triple>/include -Lswisseph-zig-<triple>/lib \
   -Wl,-rpath,"$PWD/swisseph-zig-<triple>/lib" -lswe -lm -o myprog
```
*To avoid runtime dynamic library resolution altogether, link statically against `lib/libswe.a`.*

---

## Architecture

The codebase cleanly separates ephemeris logic, astronomical reductions, and interface layers:

```
src/
├── swisseph.zig    # Facade module: primary import entrypoint
├── sweph.zig       # swe_calc engine, file I/O, fixstars, and asteroids
├── swephlib.zig    # Coordinate transformations, nutation, obliquity, precession
├── swemmoon.zig    # Moshier lunar calculation engine
├── swemplan.zig    # Moshier planetary theory & fictitious bodies (seorbel)
├── swejpl.zig      # JPL binary ephemeris reader (DE200, DE406, DE441)
├── swehouse.zig    # 25 house calculation systems
├── swecl.zig       # Eclipses, rise/set, pheno, azimuth/altitude, Gauquelin sectors
├── swehel.zig      # Heliacal phenomena and visual limits
├── swedate.zig     # Calendar systems and Julian/Gregorian conversions
├── deltat.zig      # Historical and predictive Delta-T implementations
├── swe_abi.zig     # C ABI compatibility layer (107 exported functions)
└── libm/cr.zig     # Correctly-rounded f128 math kernels (for -Dpure)
```

<details>
<summary><strong>View all 107 exported C-ABI symbols</strong></summary>

Full compatibility with `swephexp.h`:

`swe_calc`, `swe_calc_ut`, `swe_calc_pctr`, `swe_fixstar`, `swe_fixstar2`, `swe_fixstar_mag`, `swe_houses`, `swe_houses_ex`, `swe_houses_ex2`, `swe_houses_armc`, `swe_houses_armc_ex2`, `swe_house_pos`, `swe_house_name`, `swe_cotrans`, `swe_cotrans_sp`, `swe_sol_eclipse_where`, `swe_sol_eclipse_how`, `swe_sol_eclipse_when_glob`, `swe_sol_eclipse_when_loc`, `swe_lun_eclipse_how`, `swe_lun_eclipse_when`, `swe_lun_eclipse_when_loc`, `swe_lun_occult_where`, `swe_lun_occult_when_glob`, `swe_lun_occult_when_loc`, `swe_pheno`, `swe_pheno_ut`, `swe_refrac`, `swe_refrac_extended`, `swe_azalt`, `swe_azalt_rev`, `swe_rise_trans`, `swe_rise_trans_true_hor`, `swe_nod_aps`, `swe_nod_aps_ut`, `swe_get_orbital_elements`, `swe_orbit_max_min_true_distance`, `swe_gauquelin_sector`, `swe_heliacal_ut`, `swe_heliacal_pheno_ut`, `swe_heliacal_angle`, `swe_vis_limit_mag`, `swe_topo_arcus_visionis`, `swe_set_topo`, `swe_set_sid_mode`, `swe_set_ephe_path`, `swe_set_jpl_file`, `swe_set_interpolate_nut`, `swe_set_tid_acc`, `swe_get_tid_acc`, `swe_set_delta_t_userdef`, `swe_set_lapse_rate`, `swe_deltat`, `swe_deltat_ex`, `swe_time_equ`, `swe_julday`, `swe_revjul`, `swe_date_conversion`, `swe_utc_to_jd`, `swe_jdet_to_utc`, `swe_jdut1_to_utc`, `swe_utc_time_zone`, `swe_get_ayanamsa`, `swe_get_ayanamsa_ex`, `swe_get_ayanamsa_ex_ut`, `swe_get_ayanamsa_ut`, `swe_get_ayanamsa_name`, `swe_get_planet_name`, `swe_get_current_file_data`, `swe_close`, `swe_version`, `swe_get_library_path`, `swe_degnorm`, `swe_radnorm`, `swe_difdeg2n`, `swe_difrad2n`, `swe_difdegn`, `swe_deg_midp`, `swe_rad_midp`, `swe_split_deg`, `swe_csnorm`, `swe_difcsn`, `swe_difcs2n`, `swe_csroundsec`, `swe_d2l`, `swe_day_of_week`, `swe_cs2timestr`, `swe_cs2lonlatstr`, `swe_cs2degstr`... and the `swe_cleanup` memory extension.
</details>

---

## Build System & Options

```sh
# Standard workflows
make              # Builds host target into dist/<host-triple>/
make all          # Compiles all 9 platform releases
make test         # Runs full unit-test suite
make lint         # Checks formatting with zig fmt

# Zig CLI invocations
zig build                          # Default build (uses libm shim for strict bit parity)
zig build -Dpure=true              # Pure-Zig math (zero libm dependency; auto on wasm/win)
zig build -Dtarget=x86_64-windows  # Cross-compile target out of the box
```

---

## Threading Model

### In Pure Zig
All mutable internal state is contained in explicit context structs:
- `Swed` (file descriptors, planetary caches, and lunar scratchpads)
- `DeltatCtx`, `SweclCtx`, `SwehelCtx`, `HouseCtx`

**Rule:** One context bundle per thread. Never mutate a single context concurrently across multiple threads without an external synchronization lock.

### In C ABI
The compatibility wrapper (`swe_abi.zig`) maintains an isolated `SweState` instance per OS thread via `threadlocal`:
- State configured through the C interface (`swe_set_ephe_path`, `swe_set_sid_mode`, etc.) is isolated to that specific thread.
- Context setup must be performed on every worker thread that interacts with the C ABI.
- Call `SweState.deinit()` (or `swe_cleanup`) to free cached thread memory during thread teardown.

*Stress-tested with 32 threads running non-monotonic, multi-engine computations concurrently without precision degradation or data races.*

---

## Parity & Ephemeris Data Files

- **Built-in Moshier Model:** Operates out of the box without downloading any files (`SEFLG_MOSEPH`).
- **Swiss Ephemeris Data Files:** For micro-arcsecond precision, download compressed `.se1` files from [astro.com/ftp/swisseph/ephe](https://www.astro.com/ftp/swisseph/ephe/) and register them with `swe_set_ephe_path("ephe/")`.
- **Strict Parity:** Each ported calculation was verified with identity comparison (`==`) against the C reference compiled under `-ffp-contract=off`.

Read the [Parity & Methodology Guide](docs/guide/03-parity.md) and [Data Files Setup Guide](docs/guide/02-data-files.md) for deeper implementation details.

---

## Documentation Index

- [Getting Started & API Guide](docs/guide/01-api.md) — Initialization, houses, dates, and planetary reductions.
- [Data File Configuration](docs/guide/02-data-files.md) — Setting up ephemeris databases.
- [Parity Verification Report](docs/guide/03-parity.md) — How the 4.4M-case validation suite works.
- [Full API Reference](docs/index.md) — Complete 23-document directory detailing all symbols, structs, and constants.

---

## License

> **Public / Hosted Service Requirement**  
> Any hosted API usage (REST, gRPC, GraphQL, SaaS, serverless workers, or networked microservices) incorporating this library requires **prior written permission** from Mohammad Shafiee ([muhammad.shafiee@gmail.com](mailto:muhammad.shafiee@gmail.com)) prior to launch, documented via [`API-LICENSE`](API-LICENSE). This applies to both open-source and AGPL-compliant deployments.

The project is dual-licensed, matching the upstream Swiss Ephemeris model:

1. **GNU AGPLv3** — For open-source, non-hosted software ([LICENSE](LICENSE)).
2. **Commercial License** — Available directly from Mohammad Shafiee ([LICENSE.commercial](LICENSE.commercial)).

*Upstream Swiss Ephemeris is Copyright © 1997–2021 [Astrodienst AG](https://www.astro.com/swisseph/). See [NOTICE.md](NOTICE.md) for full attribution notices.*
