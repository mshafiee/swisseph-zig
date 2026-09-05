# Reference Index

Comprehensive technical documentation for `swisseph-zig`.  
**Canonical Sources:** `include/swephexp.h`, `include/sweph.h`, and `src/*.zig`.

---

### 1. Constants, Frames & Astrometry

| Document | Coverage |
|---|---|
| [`constants.md`](reference/10-constants.md) | Numerical constants, astronomical limits, conversions, and historical provenance. |
| [`models.md`](reference/11-models.md) | Astronomical reduction theories: Precession (1–11), Nutation (1–5), Sidereal Time (1–4), Frame Bias (1–3), JPLHOR/HORA, and Delta-T (1–5). |
| [`ayanamshas.md`](reference/12-ayanamshas.md) | 47 standard ayanamsha systems + 255 user-configurable offsets. |

---

### 2. Celestial Bodies & Objects

| Document | Coverage |
|---|---|
| [`bodies-planets.md`](reference/20-bodies-planets.md) | Sun, Moon, Earth, and major planets (indices `-1` to `22`). |
| [`bodies-fict.md`](reference/21-bodies-fict.md) | Uranian, hypothetical, and fictitious bodies (`40`–`58`, plus user-defined slots `59`–`999`). |
| [`bodies-moons.md`](reference/22-bodies-moons.md) | Natural planetary satellites (`9401`–`9999`) and Center-of-Body (COB) offsets. |
| [`bodies-asteroids.md`](reference/23-bodies-asteroids.md) | Minor planets (`10000+N`), comets, and trans-Neptunian objects (e.g., Varuna). |
| [`stars.md`](reference/24-stars.md) | Fixed star catalogue (`sefstars.txt`) and `swe_fixstar*` query APIs. |

---

### 3. House Systems

| Document | Coverage |
|---|---|
| [`houses.md`](reference/30-houses.md) | 26 house division systems (Placidus default), cusp array layouts (`cusps[37]`), and supplementary angles (`ascmc[10]`). |

---

### 4. Calculation Flags & Data Structures

| Document | Coverage |
|---|---|
| [`flags-calc.md`](reference/40-flags-calc.md) | Core engine flags (`SEFLG_*`), lunar node/apsis bitmasks (`NODBIT_*`), and degree formatting options (`SPLIT_DEG_*`). |
| [`flags-events.md`](reference/41-flags-events.md) | Event calculation bits (eclipses, occultations, rise/set, azimuth/altitude, heliacal events) and buffer layouts (`tret`, `attr`, `datm`, `dobs`). |

---

### 5. Function Reference (All 107 Symbols + `swe_cleanup`)

| Document | Coverage |
|---|---|
| [`functions-calc.md`](reference/50-functions-calc.md) | Engine initialization, file path routing, planetary calculations (`swe_calc*`), and coordinate crossings. |
| [`functions-houses.md`](reference/51-functions-houses.md) | House cusp calculations, ARMC, vertex, and intermediate house positions. |
| [`functions-eclipse.md`](reference/52-functions-eclipse.md) | Solar/lunar eclipses, occultations, rise/set transitions, planetary phenomena, and nodes/apsides. |
| [`functions-datetime.md`](reference/53-functions-datetime.md) | Calendar transformations, Delta-T, sidereal time, coordinate conversions (`swe_cotrans`), and formatting utilities. |
| [`functions-heliacal.md`](reference/54-functions-heliacal.md) | Heliacal rising/setting computations, visibility thresholds, runtime model selection, and version metadata. |

---

### 6. Architecture & Engineering

| Document | Coverage |
|---|---|
| [`data-files.md`](reference/60-data-files.md) | File formats and internal layout for Swiss Ephemeris (`.se1`), asteroids (`.ast`), and satellite data (`.sat`). |
| [`threading-build.md`](reference/61-threading-build.md) | Explicit context structs, thread isolation, pure-Zig math (`-Dpure`), freestanding WASM, and 9 target toolchains. |
| [`c-zig-map.md`](reference/62-c-zig-map.md) | Comprehensive C ABI vs. idiomatic Zig signature mapping. |
| [`migration-faq.md`](reference/63-migration-faq.md) | Migrating from C to Zig, error handling differences, polar house anomalies, and numerical edge cases. |

---

### 7. Appendices

| Document | Coverage |
|---|---|
| [`appendix-math.md`](reference/90-appendix-math.md) | Rigorous mathematical formulas in KaTeX: time systems, light-time iteration, aberration/deflection/bias, Vondrák/IAU 2000B nutation, ARMC/house geometry, sidereal algorithms, and visibility limits. |
| [`appendix-biblio-glossary.md`](reference/91-appendix-biblio-glossary.md) | Primary astronomical sources (JPL, IAU, IERS, Stephenson, Meeus, Schaefer) and astronomical terminology glossary. |

---

### 8. Practical Guides

*Introductory guides for setup and migration:*

- [`guide/01-api.md`](guide/01-api.md) — Quick-start tutorial covering engine setup, dates, planetary coordinates, and house systems.
- [`guide/02-data-files.md`](guide/02-data-files.md) — Downloading, verifying, and configuring ephemeris data files.
- [`guide/03-parity.md`](guide/03-parity.md) — Differential test suite design and the 4.4M-case verification gate against the C oracle.
