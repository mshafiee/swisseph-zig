# Migration, Troubleshooting, and Error Handling

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. C to Zig Migration Checklist

Migrating from the legacy Astrodienst C library (`sweph.h`) to native `swisseph-zig` requires moving from implicit global/thread-local state to explicit context management and strict buffer ownership.

```
  Legacy C Pattern (Implicit Globals)        Native Zig Pattern (Explicit Contexts)
  ───────────────────────────────────        ──────────────────────────────────────
  swe_set_ephe_path("/path");                swe.set_ephe_path("/path", &swed);
  swe_set_topo(lon, lat, alt);               swe.set_topo(lon, lat, alt, &swed);
  swe_calc_ut(jd, 0, flg, xx, serr);         swe.calc_ut(jd, 0, flg, &xx, &swed, models, &dctx, &serr);
  swe_close();                               swed.deinit(); (or scope cleanup)
```

### Action Items

| Step | Rule & Architectural Requirement | Rationale & Failure Mode |
| :---: | :--- | :--- |
| **1** | **Pass Explicit Context Structs**<br>`Swed`, `DeltatCtx`, `AstroModels`, `HouseCtx` | Legacy C relies on hidden per-thread globals (`SweState`). Native Zig requires explicit context injection to ensure reentrancy and thread safety without locks. |
| **2** | **Initialize the Search Path First**<br>`swe.set_ephe_path(null, &swed);` | Must be invoked before issuing any calculations—even when evaluating analytical Moshier models (`SEFLG_MOSEPH`). It seeds internal file descriptor tables and memory caches. |
| **3** | **Enforce Strict Buffer Capacities**<br>`serr: [256]u8`, `star: [512:0]u8` | Error buffers must be at least 256 bytes (`AS_MAXCH`). Star name buffers must be at least 512 bytes (`2 * SE_MAX_STNAME`) **and writable**; star search routines mutate and normalize the string in place. |
| **4** | **Re-apply Observer State per Workspace**<br>`set_topo()` and `set_sid_mode()` | Topocentric coordinates and custom sidereal modes live inside the `Swed` context. If you run multiple concurrent threads or tasks, each `Swed` instance must be configured individually. |
| **5** | **Replace `SEFLG_SPEED3` with `SEFLG_SPEED`** | Bit flag `128` (`SPEED3`) uses an obsolete, slower 3-point numerical differentiation stencil. Use bit flag `256` (`SPEED`) for analytical or 2-point central finite differences. |
| **6** | **Scope Teardown to the Context Lifetime** | Call `close(&swed)` or `cleanup(&swed)` (`SweState.deinit()`) per worker context upon thread termination. Never invoke teardown in per-calculation hot loops. |

---

### Migration Code Comparison

```c
/* =========================================================================
 * Legacy C (Implicit State & Global Side Effects)
 * ========================================================================= */
#include "sweph.h"

void compute_chart(double jd_ut, double lat, double lon) {
    double xx[6];
    char serr[256];
    
    swe_set_ephe_path("/data/ephe");
    swe_set_topo(lon, lat, 0.0);
    
    if (swe_calc_ut(jd_ut, SE_SUN, SEFLG_SWIEPH | SEFLG_SPEED, xx, serr) < 0) {
        // Handle error in serr
    }
    
    swe_close();
}
```

```zig
// =========================================================================
// Native Zig (Zero Globals, Explicit Allocations, Reentrant)
// =========================================================================
const std = @import("std");
const swe = @import("swisseph");

pub fn computeChart(jd_ut: f64, lat: f64, lon: f64) !void {
    var swed = swe.sweph.Swed{};
    var dctx = swe.deltat.DeltatCtx{};
    const models = swe.swephlib.AstroModels{};
    
    // Explicit initialization
    swe.set_ephe_path("/data/ephe", &swed);
    swe.set_topo(lon, lat, 0.0, &swed);
    defer swe.close(&swed);

    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;

    const status = swe.calc_ut(
        jd_ut,
        swe.sweph.SE_SUN,
        swe.sweph.SEFLG_SWIEPH | swe.sweph.SEFLG_SPEED,
        &xx,
        &swed,
        models,
        &dctx,
        &serr,
    );

    if (status < 0) {
        const msg = std.mem.sliceTo(&serr, 0);
        std.log.err("Ephemeris failure ({d}): {s}", .{ status, msg });
        return error.CalculationFailed;
    }
}
```

---

## 2. Robust Error Handling Protocol

Every calculation, search, and transformation API returns an integer status code. **Never assume coordinates in `xx[6]` are valid without verifying the return code.**

```
               Function Status Codes (return value `r`)
 ┌───────────────────────────┬───────┬───────────────────────────────────────────┐
 │ Macro                     │ Value │ Meaning & Required Application Response   │
 ├───────────────────────────┼───────┼───────────────────────────────────────────┤
 │ OK                        │   0   │ Success. Data in target buffers is valid. │
 │ ERR                       │  -1   │ Critical error. Coordinates are zeroed.   │
 │ NOT_AVAILABLE             │  -2   │ Partial success (e.g., speed missing).    │
 │ BEYOND_EPH_LIMITS         │  -3   │ Target epoch exceeds integration window.  │
 └───────────────────────────┴───────┴───────────────────────────────────────────┘
```

### 1. Handling Return Codes $< 0$
When `status < 0`, the coordinate vector `xx[6]` is zeroed or left uninitialized.  
**Critical Pitfall**: If your code ignores the return code and plots or prints `xx[0]`, the body will be rendered at **$0^\circ 00' 00''$ Aries**. Always gate coordinate consumption on `status >= 0`.

### 2. Guarding Target Ephemeris Validity Windows (`BEYOND_EPH_LIMITS`)
Querying chaotic or numerically integrated minor bodies outside their validated interpolation window triggers an immediate `-3` (`BEYOND_EPH_LIMITS`) or `-1` (`ERR`):

```zig
const status = swe.calc_ut(jd, ipl, flg, &xx, &swed, models, &dctx, &serr);

if (status == swe.sweph.ERR_BEYOND_EPH_LIMITS or status < 0) {
    // Specific historical integration boundaries:
    // - Chiron (15):           675 CE to 4650 CE (JD 1967601.5 to 3419437.5)
    // - Pholus (16):          2958 BCE to 7309 CE (JD 640648.5 to 4390617.5)
    // - Planetary Moons (9000+): 1900 CE to 2047 CE
    // - Numerical Asteroids:   Varies by file (e.g., Apollo >= 1870 CE)
    continue; // Skip rendering or log diagnostic notice
}
```

### 3. Detecting the "Silent Moshier Downgrade"
If `SEFLG_SWIEPH` is requested but the required compressed `.se1` file is missing from `$EPHE`, the engine **does not return an error code**. Instead:
1. It silently falls back to the semi-analytical Moshier ephemeris (`SEFLG_MOSEPH`).
2. It writes a warning into `serr` (e.g., `"Swiss Ephemeris file not found, using Moshier"`).
3. It returns `OK` (`0`) or `SEFLG_MOSEPH`.

In automated test pipelines or research-grade systems where precision loss ($> 1''$) is unacceptable, verify which physical ephemeris file served the calculation:

```zig
var fname: [256]u8 = undefined;
swe.swe_abi.swe_get_current_file_data(0, &fname); // Check planetary slot 0

const served = std.mem.sliceTo(&fname, 0);
if (std.mem.startsWith(u8, served, "moshier")) {
    @panic("Test failed: Silent Moshier fallback active! .se1 files missing.");
}
```

---

## 3. Frequently Asked Questions (FAQ)

### Q: Why do Placidus (`'P'`) and Koch (`'K'`) house calculations return an error or produce bizarre cusps in high-latitude charts?
**Root Cause**:  
Semi-diurnal time-arc systems divide the diurnal path of the ecliptic between rising and culmination. Above the Arctic or Antarctic circles ($|\phi| \ge 66^\circ 34'$), circumpolar ecliptic degrees never rise or never set. The quadrant curves become tangent to or fail to intersect the horizon plane, causing iterative solvers to diverge.

**Solution**:  
Implement an automated fallback to a polar-safe house system:
* **Krusinski (`'U'`)**: Designed specifically for polar stability using great circles through the Zenith and Ascendant.
* **Pullen Sinusoidal (`'Q'` / `'L'`)**: Replaces quadrant trisection with continuous sinusoidal weighting, eliminating boundary flips.
* **Porphyry (`'O'`)**: Divides the ecliptic quadrant arcs between ASC and MC evenly; calculates unconditionally.
* **Whole Sign (`'W'`)** or **Equal (`'E'`)**: Unconditionally stable across all latitudes.

```zig
var status = swe.houses_armc_ex2(armc, lat, eps, 'P', &cusps, &ascmc, null, null, &serr, &hctx);
if (status < 0) {
    // Polar breakdown: switch to Krusinski ('U') or Porphyry ('O')
    status = swe.houses_armc_ex2(armc, lat, eps, 'U', &cusps, &ascmc, null, null, &serr, &hctx);
}
```

---

### Q: Why does the Osculating Apogee / True Lilith (ID 13) jump by tens of degrees in a few days?
**Root Cause**:  
This is a physical property of Keplerian orbital mechanics, not a bug. Because the Moon's orbit is near-circular ($e \approx 0.055$), external solar gravitational perturbations continually deform the instantaneous ellipse. Whenever the Moon passes through perigee, the orientation of the major axis becomes mathematically ill-conditioned, causing the instantaneous osculating apogee to swing wildly.

**Solution**:  
For standard astrological chart display, use the smoothed, orbit-averaged apsidal points:
* **ID 21 (`SE_INTP_APOG`)**: Interpolated Apogee ("Natural Lilith") via `swi_intp_apsides()`.
* **ID 22 (`SE_INTP_PERG`)**: Interpolated Perigee ("Priapus").
* **ID 12 (`SE_MEAN_APOG`)**: Mean Apogee ("Mean Lilith"), advancing smoothly at $\approx 40.7^\circ/\text{year}$.

---

### Q: Why are my calculated positions offset by $\approx 53\text{ milliarcseconds}$ compared to NASA JPL Horizons?
**Root Cause**:  
Standard Swiss Ephemeris coordinates are referenced to the true equator and equinox of date (or standard J2000 ICRF) without applying high-frequency Earth Orientation Parameter (EOP) corrections ($x, y$ polar motion and $(UT1 - UTC)$ rotational variations).

**Solution**:  
Activate JPL Horizons emulation mode:
1. Place current IERS Earth Orientation tables (`eop*.dat`) into `$EPHE`.
2. Add the flag `SEFLG_JPLHOR` (`262144`) or `SEFLG_JPLHOR_APPROX` (`524288`) to calculation calls.
3. Configure the underlying bias model to `IERS_2010` in `AstroModels`.

---

### Q: Why does `swe_heliacal_ut` return `dret[0] = 99999999.0` (`TJD_INVALID`)?
**Root Cause**:  
`TJD_INVALID` is a sentinel indicating that **no qualifying heliacal event occurred within the evaluated time window**. This happens under two normal astronomical conditions:
1. **Polar Summer / Midnight Sun**: The Sun never drops sufficiently far below the horizon to reach the limiting sky darkness threshold required for the body to become visible.
2. **Search Interval Too Narrow**: The planet was not close enough to solar conjunction during the evaluated orbital interval.

**Solution**:  
* Check `if (dret[0] == swe.swehel.TJD_INVALID)` explicitly.
* Set the flag `SE_HELFLAG_LONG_SEARCH` (`128`) to extend the iteration interval across multiple synodic periods.
* In border conditions, inspect limiting magnitude parameters using `swe_heliacal_pheno_ut()` or relax twilight thresholds with `SE_HELFLAG_VISLIM_DARK`.

---

### Q: Why do multi-threaded calculations produce non-deterministic results or intermittent crashes?
**Root Cause**:  
Sharing a single `Swed` workspace, `DeltatCtx` instance, or `HouseCtx` struct across multiple concurrent OS threads or asynchronous tasks causes data races. While `AstroModels` is immutable (`const`), `Swed` and `DeltatCtx` maintain internal mutable caches, file descriptors, and interpolation states.

**Solution**:  
Allocate independent context structs for each thread or execution task. Never share a `*Swed` pointer across concurrent execution boundaries without an explicit synchronization mutex:

```zig
// Thread-Safe Worker Pattern
fn workerThread(jd: f64, body: i32) !void {
    // Each thread gets its own independent stack or heap context
    var thread_swed = swe.sweph.Swed{};
    var thread_dctx = swe.deltat.DeltatCtx{};
    const models = swe.swephlib.AstroModels{};

    swe.set_ephe_path("/data/ephe", &thread_swed);
    defer swe.close(&thread_swed);

    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;

    _ = swe.calc_ut(jd, body, swe.sweph.SEFLG_SPEED, &xx, &thread_swed, models, &thread_dctx, &serr);
}
```
