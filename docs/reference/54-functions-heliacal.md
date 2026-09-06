# Functions: Heliacal Events, Astronomical Models, Versioning, and Extensions

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Implementation Mapping

* **C Declarations**: `include/swephexp.h:676` (Astro Models), `include/swephexp.h:684` (Heliacal Phenomena), `include/swephexp.h:1016` (Lifecycle Extensions).
* **Zig Module Implementations**:
  * `src/swehel.zig`: Bradley Schaefer observational visibility theory, atmospheric extinction models, and Victor Reijs geometric routines.
  * `src/swephlib.zig`: Astronomical model dispatch, precession/nutation model switching, version queries, and memory lifecycle routines.
* **Context Threading**: In Zig, heliacal routines accept explicit context pointers (`swed: *Swed`, `models: AstroModels`, `dctx: *DeltatCtx`) rather than reading from mutable global memory.
* **Physical Models**: Implements the Bradley Schaefer visibility model (1985, 1987, 1993), parameterizing sky luminance from astronomical, solar, and lunar sources against human optical physiological limits (photopic, mesopic, and scotopic vision regimes).

---

## 2. Heliacal Rising and Setting Solvers

The heliacal suite determines when celestial bodies first appear or disappear along the dawn or dusk horizon, and computes limiting visual magnitudes and contrast margins.

```
  Heliacal Solvers Overview
  ──────────────────────────────────────────────────────────────────────────
  swe_heliacal_ut()          ──> Root-solves next rising/setting event date
  swe_heliacal_pheno_ut()    ──> Fixed-epoch visibility details & margins
  swe_vis_limit_mag()        ──> Instantaneous naked-eye / telescope limiting V
  swe_topo_arcus_visionis()  ──> Geometric arcus visionis & altitude differences
```

### Event Search: `heliacal_ut`
Iteratively searches forward or backward for the next qualifying heliacal event date.

```zig
// Zig Facade
pub fn heliacal_ut(
    tjdstart_ut: f64,
    geopos: *const [3]f64,
    datm: *const [4]f64,
    dobs: *const [6]f64,
    object_name: [*:0]const u8,
    type_event: i32,
    helflag: i32,
    dret: *[50]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_heliacal_ut(
    double tjdstart_ut,
    double *geopos,
    double *datm,
    double *dobs,
    char *object_name,
    int32_t type_event,
    int32_t helflag,
    double *dret,
    char *serr
);
```

#### Parameters and Units
* `tjdstart_ut`: Starting epoch in Julian Day UT.
* `geopos[3]`: Geographic longitude ($^\circ\text{E}$), latitude ($^\circ\text{N}$), and elevation above sea level ($\text{m}$).
* `datm[4]`: Local atmospheric variables (pressure in $\text{hPa}$, temperature in $^\circ\text{C}$, relative humidity in $\%$, visual range $\text{VR}$ in $\text{km}$).
* `dobs[6]`: Optical and observer physiological parameters (age, visual acuity, binocular toggle, aperture, magnification, transmission).
* `object_name`: Target planetary body name (`"Sun"`, `"Moon"`, `"Mercury"`, `"Venus"`, `"Mars"`, `"Jupiter"`, `"Saturn"`) or catalog star name from `sefstars.txt` (`"Sirius"`, `"Aldebaran"`).
* `type_event`:
  * `1` (`SE_HELIACAL_RISING` / `SE_MORNING_FIRST`): First visible dawn rising.
  * `2` (`SE_HELIACAL_SETTING` / `SE_EVENING_LAST`): Last visible dusk setting.
  * `3` (`SE_EVENING_FIRST`): Acronychal / first visible dusk rising.
  * `4` (`SE_MORNING_LAST`): Cosmical / last visible dawn setting.
  * *Events `5` and `6` are unimplemented; passing them returns `ERR` (`-1`).*
* `helflag`: Configuration bitmask combining `SE_HELFLAG_*` flags (e.g., `LONG_SEARCH`, `HIGH_PRECISION`, `OPTICAL_PARAMS`, `NO_DETAILS`).

#### Output Vector (`dret[50]`)
* `dret[0]`: Julian Day UT of the detected heliacal event.
* `dret[1..4]`: Heliacal phenomenon parameters at the exact moment of visibility (e.g., arcus visionis, Sun depression angle, target object altitude).
* `dret[5..24]`: Photometric parameters (sky brightness, object apparent magnitude, contrast threshold) unless `SE_HELFLAG_NO_DETAILS` is set.

---

### Fixed-Epoch Circumstances: `heliacal_pheno_ut`
Evaluates observational visibility parameters at an exact time without searching for event boundaries.

```zig
// Zig Facade
pub fn heliacal_pheno_ut(
    tjd_ut: f64,
    geopos: *const [3]f64,
    datm: *const [4]f64,
    dobs: *const [6]f64,
    object_name: [*:0]const u8,
    type_event: i32,
    helflag: i32,
    darr: *[50]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_heliacal_pheno_ut(
    double tjd_ut,
    double *geopos,
    double *datm,
    double *dobs,
    char *object_name,
    int32_t type_event,
    int32_t helflag,
    double *darr,
    char *serr
);
```

Populates `darr[50]` with detailed physical quantities:
* `darr[0]`: Geometric Arcus Visionis ($AV$, angular elevation difference between the center of the Sun and the target object).
* `darr[1]`: Topocentric apparent altitude of the object ($h_{\text{obj}}$).
* `darr[2]`: Apparent geocentric solar depression angle ($h_\odot$).
* `darr[3]`: Azimuthal separation between Sun and object ($\Delta\text{Az}$).
* `darr[4]`: Actual apparent visual magnitude ($V$) of the object under atmospheric extinction.
* `darr[5]`: Visual limiting magnitude ($V_{\text{lim}}$) of the sky at the object's position.
* `darr[6]`: Visibility margin ($\Delta m = V_{\text{lim}} - V_{\text{extinct}}$). A positive margin indicates the object is visible to the observer.

---

### Low-Level Visibility and Geometric Primitives

* **`vis_limit_mag(tjd, geopos, datm, dobs, name, helflag, &dret[8], serr, ...)`**:  
  Calculates the limiting visual magnitude of the sky background for a specific target direction. Returns $V_{\text{lim}}$ in `dret[0]` alongside constituent background sky luminance, eye pupil dilation, and extinction components in `dret[1..7]`.
* **`topo_arcus_visionis(tjd, flag, geopos, name, &dret, ...)`**:  
  Computes geometric topocentric angular elevation and azimuth separations between the target body and the solar disc center according to Victor Reijs’ formulations.

---

### Input Parameter Validation and Edge Cases

#### Atmospheric Conditions (`datm[4]`)
1. `datm[0]`: Barometric pressure ($P$, nominal $1013.25\text{ hPa}$). Passing $P \le 0.0$ or values $> 1200.0\text{ hPa}$ returns `ERR` (`-1`).
2. `datm[1]`: Ambient surface temperature ($T$, nominal $15.0^\circ\text{C}$). Clamped internally within physical bounds ($[-80.0^\circ\text{C}, +60.0^\circ\text{C}]$).
3. `datm[2]`: Relative humidity ($RH$, nominal $50.0\%$, valid range $[0.0, 100.0]$).
4. `datm[3]`: Meteorological visual range ($\text{VR}$, nominal $20.0\text{ km}$; values $\le 0.0$ cause mathematical divergence).

#### Observer Parameters (`dobs[6]`)
1. `dobs[0]`: Observer age in years (default $30.0$; values $< 0$ default to 30).
2. `dobs[1]`: Snellen visual acuity ratio (default $1.0$ for $20/20$; $1.25$ for $20/16$).
3. `dobs[2]`: Monocular vs. Binocular flag ($0.0 = \text{monocular}$, $1.0 = \text{binocular}$).
4. `dobs[3]`: Clear telescope objective aperture diameter in $\text{mm}$ ($0.0 = \text{naked eye}$).
5. `dobs[4]`: Telescope optical magnification power ($0.0 = \text{naked eye}$).
6. `dobs[5]`: Optical transmission efficiency factor ($0.0 = \text{naked eye}$; otherwise $[0.5, 0.9]$).

#### The Boundary Sentinel (`TJD_INVALID = 99999999.0`)
At high geographic latitudes during polar summer, twilight never darkens to the threshold required for stars or minor planets to become visible. When this occurs, `heliacal_ut` sets:

$$\text{dret}[0] = 99999999.0 \quad \text{(no event)}$$

This indicates a physical absence of the phenomenon within the searched timeframe, not an engine error.

```zig
// Example: Computing the heliacal rising of Sirius
var dret: [50]f64 = undefined;
var serr: [256]u8 = undefined;

const geopos = [3]f64{ 31.1342, 29.9792, 60.0 }; // Giza, Egypt
const datm = [4]f64{ 1013.25, 20.0, 40.0, 25.0 }; // Standard desert air
const dobs = [6]f64{ 30.0, 1.0, 1.0, 0.0, 0.0, 0.0 }; // Naked-eye binocular

const status = swe.heliacal_ut(
    jd_start,
    &geopos,
    &datm,
    &dobs,
    "Sirius",
    swe.swehel.SE_HELIACAL_RISING,
    swe.swehel.SE_HELFLAG_HIGH_PRECISION | swe.swehel.SE_HELFLAG_OPTICAL_PARAMS,
    &dret,
    &serr,
    &swed,
    models,
    &dctx,
);

if (status < 0) {
    // Parameter validation failure or missing catalog
} else if (dret[0] == swe.swehel.TJD_INVALID) {
    // No rising occurred within the search interval; expand with SE_HELFLAG_LONG_SEARCH
} else {
    const jd_rising = dret[0];
    const arcus_visionis = dret[1];
}
```

```c
/* C equivalent */
double dret[50];
char serr[256];
double geopos[3] = { 31.1342, 29.9792, 60.0 };
double datm[4] = { 1013.25, 20.0, 40.0, 25.0 };
double dobs[6] = { 30.0, 1.0, 1.0, 0.0, 0.0, 0.0 };

int status = swe_heliacal_ut(
    jd_start,
    geopos,
    datm,
    dobs,
    "Sirius",
    SE_HELIACAL_RISING,
    SE_HELFLAG_HIGH_PRECISION | SE_HELFLAG_OPTICAL_PARAMS,
    dret,
    serr
);

if (status >= 0 && dret[0] != 99999999.0) {
    double jd_rising = dret[0];
}
```

---

## 3. Astronomical Models Dispatcher

Configures low-level precession, nutation, and frame-bias models used across coordinate reduction pipelines.

```zig
// Zig Facades
pub fn set_astro_models(samod: [*:0]const u8, iflag: i32, swed: *Swed) void
pub fn get_astro_models(samod: *[256]u8, iflag: i32, swed: *Swed) void
```
```c
/* C Signatures */
void swe_set_astro_models(const char *samod, int32_t iflag);
void swe_get_astro_models(char *samod, int32_t iflag);
```

* **Purpose & Heritage**: Developed by Dieter Koch as an internal verification harness to benchmark Swiss Ephemeris against historical models (IAU 1976 Precession, IAU 1980 Nutation, Laskar 1986, Bretagnon 2003, Vondrák 2011).
* **Model String (`samod`)**: Comma-delimited key-value configuration string modifying reduction stages:
  * `PRECESSION`: `VONDRAK_2011` (Default), `IAU_2006`, `IAU_2000`, `LASKAR_1986`, `IAU_1976`.
  * `NUTATION`: `IAU_2000B` (Default), `IAU_2000A`, `IAU_1980`.
  * `FRAME_BIAS`: `IERS_2010`, `NONE`.
  * `JPL_HORIZONS`: Direct alignment switches.

> [!CAUTION]
> **Production Recommendation**  
> Leave astronomical models set to defaults (`Vondrák 2011 + IAU 2000B`). Modifying models across asynchronous worker threads or execution contexts in C introduces thread-local state inconsistencies that can result in sub-arcsecond discrepancies between identical queries.

---

## 4. Library Metadata and Lifecycle Extensions

### Runtime Version and Path Inspection

* **`version` / `swe_version`**: Populates a character slice with the upstream library version string (`"2.10.03"`).
* **`get_library_path` / `swe_get_library_path`**: Populates a character slice with the absolute filesystem path of the running executable or linked dynamic library (`libswe.so`, `libswe.dylib`, `sweph.dll`).

---

### Extended Lifecycle Management: `cleanup` (`SWE_ZIG_EXTENSIONS`)

```zig
// Zig Facade
pub fn cleanup(swed: *Swed) void
```
```c
/* C Extension Signature */
#if defined(SWE_ZIG_EXTENSIONS)
void swe_cleanup(void);
#endif
```

* **Mechanics**: While `close()` / `swe_close()` flushes open `.se1` file descriptors and resets calculation caches, `cleanup()` performs a complete teardown of allocated heap blocks, including:
  * Dynamically allocated fixed-star catalog buffers from `sefstars.txt`.
  * Planetary moon acceleration caches.
  * Internal Delta-T spline anchor buffers.
* **Zig Memory Model**: In native Zig runtimes, this corresponds to calling `SweState.deinit()`, releasing memory back to the parent allocator.
* **Usage Invariant**: **Teardown-only.** `cleanup()` is idempotent and should be called once when tearing down a worker process or testing harness. Never invoke `cleanup()` in per-calculation hot paths.
