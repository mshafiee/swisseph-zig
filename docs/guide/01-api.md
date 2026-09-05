# API Tour

> Part of the [swisseph-zig documentation](../index.md) · [Complete Reference Suite](../reference/)
>
> ⚠️ **Network & Hosted API Notice:** Embedding or exposing this library over a network (REST, gRPC, SaaS, or serverless) requires prior written authorization. See [`API-LICENSE`](../../API-LICENSE) and [`license.md`](../license.md).

All snippets below are verified against `examples/zig-native/main.zig` and `readme_check.zig` via `zig build test`.

```zig
const swe = @import("swisseph");
```

---

## 0. Engine Initialization & Lifecycle

### Zig API: Explicit Contexts
The native Zig API avoids global mutable state entirely. All state, scratchpads, and caches must be passed explicitly into calculation routines:

```zig
const swe = @import("swisseph");

// 1. Allocate context bundle (one set per thread)
var swed = swe.sweph.Swed{};               // Ephemeris engine state, file handles, caches
var dctx = swe.deltat.DeltatCtx{};         // Delta-T model state
const models = swe.swephlib.AstroModels{}; // Astronomical reduction theories
var serr: [256]u8 = undefined;

// 2. Configure ephemeris data path (or pass null to force Moshier-only mode)
swe.set_ephe_path("/data/ephe", &swed);
```

### C ABI: Thread-Local State
The C compatibility layer maintains context instances transparently within thread-local storage:

```c
#include "swephexp.h"

char serr[256];
swe_set_ephe_path("/data/ephe"); // Configures state for the calling thread only
```

### Lifecycle Rules
- **Thread Concurrency:** Context bundles (`Swed`, `DeltatCtx`, `HouseCtx`) are **not** thread-safe. Allocate one bundle per thread. Repeat setup on each thread.
- **Teardown:**
  - In Zig: Call `SweState.deinit()` at thread termination.
  - In C: Call `swe_close()` followed by `swe_cleanup()`.
- See the [Threading & Build Guide](../reference/61-threading-build.md) and [C-to-Zig API Map](../reference/62-c-zig-map.md).

---

## 1. Calendar & Time Systems

*Reference: [`functions-datetime.md`](../reference/53-functions-datetime.md)*

Convert calendar dates to Julian Day Ephemeris/UT and back:

```zig
// Convert calendar date (2000-01-01 12:00 UT) to Julian Day
const jd_ut = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL); // Returns 2451545.0

// Reverse conversion from Julian Day to calendar components
var year: i32 = 0;
var month: i32 = 0;
var day: i32 = 0;
var ut_hour: f64 = 0;

swe.revjul(jd_ut, swe.swedate.SE_GREG_CAL, &year, &month, &day, &ut_hour);
```

> **Calendar Systems:** Use `swe.swedate.SE_GREG_CAL` (`1`) for Gregorian or `swe.swedate.SE_JUL_CAL` (`0`) for Julian. There is no automatic cutover. Invalid dates return `ERR` via `date_conversion` or `utc_to_jd`.

---

## 2. Planetary Positions

*Reference: [`functions-calc.md`](../reference/50-functions-calc.md) · [`bodies-planets.md`](../reference/20-bodies-planets.md) · [`flags-calc.md`](../reference/40-flags-calc.md)*

Calculate celestial positions and velocities:

```zig
// Output array: [0] Longitude, [1] Latitude, [2] Distance (AU),
//               [3] Speed in Lon, [4] Speed in Lat, [5] Speed in Dist
var xx: [6]f64 = undefined;

// Calculate Sun (body 0) with apparent geocentric positions and speeds
const result = swe.calc_ut(
    jd_ut,
    0,                                // Body index: 0 = Sun
    swe.sweph.SEFLG_SPEED,            // Flags: Always bitwise-OR SEFLG_SPEED for velocities
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);

if (result < 0) {
    // result == -3 (ERR_BEYOND) means the date is outside the ephemeris range.
    // xx is set to 0.0; do not plot or use coordinates.
    return error.CalcFailed;
}

std.debug.print("Sun: {d:.6}° lon, {d:.6} AU\n", .{ xx[0], xx[2] });
```

### Body Identifiers
- `0` (Sun) to `22` (Priapus)
- `40` to `58` (Fictitious / Uranian bodies)
- `10000 + N` (Asteroid catalogue numbers)
- `9000 + N` (Planetary moons)
- `-10` (Fixed stars)

---

## 3. Astrological Houses & Angles

*Reference: [`houses.md`](../reference/30-houses.md) · [`functions-houses.md`](../reference/51-functions-houses.md)*

```zig
var cusps: [37]f64 = undefined; // Cusps array (1-indexed; index 0 is unused)
var ascmc: [10]f64 = undefined; // Key angles
var hctx = swe.swehouse.HouseCtx{};

// Set geographic observer coordinates: lon, lat, altitude (meters)
// (Required for topocentric systems like 'T')
swe.set_topo(8.5, 47.4, 400.0, &swed);

// Calculate cusps from ARMC, latitude, obliquity (eps), and house system ('P' = Placidus)
_ = swe.houses_armc_ex2(
    armc,
    47.4,       // Geographic latitude
    eps,        // True obliquity of the ecliptic
    'P',        // House system code
    &cusps,
    &ascmc,
    null, null, null,
    &hctx,
);
```

### Output Layout
- **Key Angles (`ascmc`):**
  - `ascmc[0]`: Ascendant (ASC)
  - `ascmc[1]`: Midheaven (MC)
  - `ascmc[2]`: ARMC (Right Ascension of the MC)
  - `ascmc[3]`: Vertex
- **Cusps (`cusps`):** Standard systems populate `cusps[1..12]`. Gauquelin sectors (`'G'`) populate `cusps[1..36]`.

> **Polar Latitudes (`|lat| > 66.5°`):** Quadrant systems (e.g., Placidus `'P'`, Koch `'K'`) collapse near polar circles. Use non-quadrant systems like Porphyry (`'O'`), Whole Sign (`'W'`), Equal (`'A'`), or Meridian (`'X'`).

---

## 4. Eclipses, Rise/Set & Fixed Stars

*Reference: [`functions-eclipse.md`](../reference/52-functions-eclipse.md) · [`stars.md`](../reference/24-stars.md)*

### Solar Eclipse Search
```zig
var tret: [10]f64 = undefined; // Timing attributes (maximum, start, end, etc.)
var attr: [20]f64 = undefined; // Eclipse magnitude and fractional parameters

// Find the next global solar eclipse (flag 4 = Total)
const eclipse_type = swe.sol_eclipse_when_glob(
    jd_ut,
    0,                  // Ephemeris flag (0 = default)
    4,                  // Total eclipse filter
    &tret,
    false,              // false = search forward in time
    &serr,
    &swed,
    models,
    &dctx,
);
```

### Fixed Star Coordinates
```zig
var star_name: [512]u8 = undefined;
@memcpy(star_name[0.."Spica".len], "Spica");

_ = swe.fixstar_ut(
    star_name[0..],
    jd_ut,
    swe.sweph.SEFLG_SPEED,
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);

std.debug.print("Spica Longitude: {d:.6}°\n", .{ xx[0] });
```

---

## 5. Module Map

| Module | Scope & Core Responsibilities | Reference Doc |
|---|---|---|
| `swedate` | Calendar conversions (`julday`, `revjul`, `utc_*`) | [`functions-datetime.md`](../reference/53-functions-datetime.md) |
| `deltat` | Delta-T calculations and tidal deceleration models | [`models.md`](../reference/11-models.md), [`constants.md`](../reference/10-constants.md) |
| `swephlib` | Precession, nutation, coordinate rotations (`swe_cotrans`) | [`models.md`](../reference/11-models.md) |
| `swemmoon` / `swemplan` / `swejpl` | Analytical Moshier series and binary JPL readers | [`bodies-planets.md`](../reference/20-bodies-planets.md) |
| `sweph` | Core calculation engine, file operations, fixed stars | [`functions-calc.md`](../reference/50-functions-calc.md) |
| `swehouse` | 26 astrological house division algorithms | [`houses.md`](../reference/30-houses.md) |
| `swecl` | Eclipses, occultations, rise/set times, lunar nodes | [`functions-eclipse.md`](../reference/52-functions-eclipse.md) |
| `swehel` | Heliacal phenomena and visibility algorithms (Schaefer) | [`functions-heliacal.md`](../reference/54-functions-heliacal.md) |
| `swe_abi` | 107 exported `swe_*` C ABI bridge functions | [`c-zig-map.md`](../reference/62-c-zig-map.md) |
