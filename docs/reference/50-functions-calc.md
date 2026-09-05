# Functions: Calculation, Crossings, Fixed Stars, and Lifecycle Setup

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Architectural Model and Invocation Contract

* **C Declarations**: `include/swephexp.h:697`. Functions use the canonical `swe_` prefix and depend on thread-local global state (`SweState`).
* **Zig Facade**: `src/swisseph.zig:33`. Drops the `swe_` prefix, standardizes naming to `snake_case`, and replaces hidden globals with explicit caller-owned contexts:
  * `swed: *swe.sweph.Swed`: Core orbital workspace, open file handles, and cache lines.
  * `models: swe.swephlib.AstroModels`: Precession, nutation, and astronomical model configuration.
  * `dctx: *swe.deltat.DeltatCtx`: $\Delta T$ ($TT - UT$) interpolation caches and leap-second tables.
* **Return Code Protocol**:
  * `OK = 0`: Nominal evaluation.
  * `ERR = -1`: Critical failure. Output coordinate buffers are zeroed; inspect null-terminated diagnostic text in `serr[256]`.
  * `NOT_AVAILABLE = -2`: Evaluation succeeded, but requested secondary attribute (e.g., speed) is unavailable.
  * `BEYOND_EPH_LIMITS = -3`: Requested Julian Day lies outside the valid physical integration window.

---

## 2. Setup and Lifecycle Management

### `set_ephe_path`
Registers the filesystem directory containing `.se1` ephemerides, text catalogs, and orbital parameter files.

```zig
// Zig Facade
pub fn set_ephe_path(path: ?[*:0]const u8, swed: *Swed) void
```
```c
/* C Signature */
void swe_set_ephe_path(const char *path);
```

* **Parameters & Units**: `path` is a null-terminated ASCII string. Passing `null` / `NULL` instructs the engine to check the `SE_EPHE_PATH` environment variable, falling back to compiled-in search paths if unset.
* **Operational Invariant**: **This must be the first function invoked**, even when running under file-free Moshier analytical mode (`SEFLG_MOSEPH`). It seeds the internal cache structures inside `Swed`.
* **Limits**: Strings exceeding 255 characters (`AS_MAXCH = 256`) are rejected and silently overwritten with the legacy internal fallback (`\SWEPH\EPHE`).
* **Error Behavior**: Passing a non-existent directory does not fail immediately at setup time; the failure surfaces during subsequent calculation calls as a silent downgrade notice to Moshier mode written into `serr`.

---

### `set_jpl_file`
Configures the explicit filename of a raw JPL binary direct-integration ephemeris.

```zig
// Zig Facade
pub fn set_jpl_file(fname: [*:0]const u8, swed: *Swed) void
```
```c
/* C Signature */
void swe_set_jpl_file(const char *fname);
```

* **Parameters**: `fname` represents the filename literal (e.g., `"de431.eph"` or `"de441.eph"`). The file must reside inside the path registered with `set_ephe_path`.
* **Limits**: Clamped at 256 bytes.
* **Error Behavior**: If the file does not exist or has an unreadable header, the next calculation call using `SEFLG_JPLEPH` fails immediately, returning `ERR` (`-1`) and writing `"cannot open JPL file"` to `serr`.

---

### `close`
Flushes open file descriptors, releases cached orbital integration blocks, and resets state.

```zig
// Zig Facade
pub fn close(swed: *Swed) void
```
```c
/* C Signature */
void swe_close(void);
```

* **Mechanics**: Closes all active `.se1` Chebyshev file descriptors held in `swed`. In the Zig runtime, calling `SweState.deinit()` also frees dynamically allocated fixed-star catalog memory.
* **Lifecycle Rule**: Never issue calculation queries after invoking `close()` without re-initializing the workspace via `set_ephe_path()`.

---

### Auxiliary Runtime Inspection Functions

#### `version`
Returns the upstream Swiss Ephemeris engine release string (`"2.10.03"`).
```zig
var vbuf: [256]u8 = undefined;
_ = swe.swe_abi.swe_version(&vbuf);
```

#### `get_library_path`
Populates a buffer with the absolute directory path of the active loaded shared object or binary executable.

#### `get_current_file_data`
Inspects which physical file served the most recent calculation. Crucial for detecting silent analytical downgrades in automated test suites:
```c
/* C Prototype */
const char* swe_get_current_file_data(
    int ifno,          /* 0=planet, 1=moon, 2=main asteroid, 3=other, 4=star */
    double *start_jd,  /* Populates file start epoch */
    double *end_jd,    /* Populates file end epoch */
    int *den_num       /* JPL DE compilation number */
);
```

#### `get_planet_name`
Resolves body numbers to formal names. Returns canonical macro names for bodies 0–22, or resolves dynamic names from `seorbel.txt` (IDs 40–999) and `seasnam.txt` (IDs 10000+).

---

### Observer Topocentric Positioning

#### `set_topo`
Establishes the geographic coordinates and altitude of the topocentric observer.

```zig
// Zig Facade
pub fn set_topo(geolon: f64, geolat: f64, geoalt: f64, swed: *Swed) void
```
```c
/* C Signature */
void swe_set_topo(double geolon, double geolat, double geoalt);
```

* **Parameters & Units**:
  * `geolon`: Geographic longitude in decimal degrees (positive East of Greenwich: $[-180.0^\circ, +180.0^\circ]$).
  * `geolat`: Geographic latitude in decimal degrees (positive North of Equator: $[-90.0^\circ, +90.0^\circ]$).
  * `geoalt`: Observer elevation above sea level in meters ($\text{m}$).
* **Failure Mode Warning**: `set_topo` has no return code. If topocentric coordinates are requested (`SEFLG_TOPOCTR` or house method `'T'`) without prior configuration, the engine **silently defaults to geocentric coordinates** without raising an error.

---

### Sidereal Zodiac Configuration

#### `set_sid_mode`
Configures the reference frame and ayanamsha algorithm for sidereal computations.

```zig
// Zig Facade
pub fn set_sid_mode(sid_mode: i32, t0: f64, ayan_t0: f64, swed: *Swed) void
```
```c
/* C Signature */
void swe_set_sid_mode(int32_t sid_mode, double t0, double ayan_t0);
```

* **Parameters**: `sid_mode` selects standard models (e.g., `SE_SIDM_LAHIRI`, `SE_SIDM_FAGAN_BRADLEY`, or `SE_SIDM_USER`). `t0` and `ayan_t0` define custom reference epochs and offsets. Modifiers from `SE_SIDBIT_*` must be bitwise OR'd into `t0` or `ayan_t0` at setup, never passed to `swe_calc`.
* **Ayanamsa Accessors**: `swe_get_ayanamsa_ex()`, `swe_get_ayanamsa_ex_ut()`, `swe_get_ayanamsa()`, and `swe_get_ayanamsa_ut()` query the calculated angular offset at an epoch.
* **Failure Mode Warning**: Evaluating calculations with `SEFLG_SIDEREAL` without calling `set_sid_mode()` causes the engine to default silently to the **Fagan/Bradley** ayanamsha without emitting a diagnostic warning.

---

## 3. Core Ephemeris Calculation Engines

### `calc_ut`
Evaluates apparent, geometric, or topocentric positions referenced to Universal Time (UT1/UTC). **Standard default for all user-facing applications.**

```zig
// Zig Facade
pub fn calc_ut(
    jd_ut: f64,
    ipl: i32,
    iflag: i32,
    xx: *[6]f64,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    serr: *[256]u8,
) i32
```
```c
/* C Signature */
int32_t swe_calc_ut(
    double tjd_ut,
    int32_t ipl,
    int32_t iflag,
    double *xx,
    char *serr
);
```

* **Parameters & Units**:
  * `jd_ut`: Target Julian Day in Universal Time ($UT1$). Internally computes $\Delta T$ using `dctx` to derive Ephemeris Time ($TT$).
  * `ipl`: Target body catalog index (e.g., `0` Sun, `1` Moon, `15` Chiron, `9501` Io, `10001` Ceres).
  * `iflag`: Configuration bitmask (`SEFLG_*`).
  * `xx`: Output array of 6 double-precision floats ($\lambda, \beta, r, \dot{\lambda}, \dot{\beta}, \dot{r}$).
* **Operational Limits**:
  * Chiron (ID 15) is clamped to **675 CE – 4650 CE**; Pholus (ID 16) is clamped to **2958 BCE – 7309 CE**.
  * Natural planetary satellites (IDs 9000+) are valid strictly from **1900 CE to 2047 CE**.
* **Speed Flag Best Practice**: Always set `SEFLG_SPEED` (`256`) when velocity is required. Avoid `SEFLG_SPEED3` (`128`), which uses a slower, less accurate 3-point numerical differentiation formula.

---

### `calc`
Evaluates coordinates referenced to Terrestrial Time ($\text{TT}$) / Ephemeris Time ($\text{ET}$).

```zig
// Zig Facade
pub fn calc(
    jd_et: f64,
    ipl: i32,
    iflag: i32,
    xx: *[6]f64,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    serr: *[256]u8,
) i32
```
```c
/* C Signature */
int32_t swe_calc(
    double tjd_et,
    int32_t ipl,
    int32_t iflag,
    double *xx,
    char *serr
);
```

* **Behavior**: Evaluates celestial mechanics directly along the uniform $\text{TT}$ time axis. Identical to `calc_ut` without the internal $\Delta T$ reduction pass:
  $$JD_{\text{ET}} = JD_{\text{UT}} + \Delta T$$

---

### `calc_pctr`
Calculates planetocentric coordinates of body `ipl` referenced to an arbitrary central body `iplctr`.

```zig
// Zig Facade
pub fn calc_pctr(
    jd_et: f64,
    ipl: i32,
    iplctr: i32,
    iflag: i32,
    xx: *[6]f64,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
    serr: *[256]u8,
) i32
```
```c
/* C Signature */
int32_t swe_calc_pctr(
    double tjd_et,
    int32_t ipl,
    int32_t iplctr,
    int32_t iflag,
    double *xx,
    char *serr
);
```

* **Application**: Used to calculate non-Earth-centric planetary frames (e.g., Martian coordinates of Phobos, or Jupiter-centric positions of the Galilean satellites).

### Production Calculation Example

```zig
// Zig: evaluate geocentric apparent coordinates and daily speeds for Mars
var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

const flags = swe.sweph.SEFLG_SWIEPH | swe.sweph.SEFLG_SPEED;

const status = swe.calc_ut(
    jd_ut,
    swe.sweph.SE_MARS,
    flags,
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);

if (status < 0) {
    // Evaluation failed: output vector is zeroed; inspect serr
    const msg = std.mem.sliceTo(&serr, 0);
    std.log.err("Ephemeris failure: {s}", .{msg});
    return error.CalculationFailed;
}

// Coordinates successfully populated:
// xx[0] = Longitude, xx[1] = Latitude, xx[2] = Distance (AU)
// xx[3] = Lon speed (deg/day), xx[4] = Lat speed, xx[5] = Radial speed
```

```c
/* C equivalent */
double xx[6];
char serr[256];

int status = swe_calc_ut(
    jd_ut,
    SE_MARS,
    SEFLG_SWIEPH | SEFLG_SPEED,
    xx,
    serr
);

if (status < 0) {
    fprintf(stderr, "Ephemeris failure: %s\n", serr);
    return -1;
}
```

---

## 4. Longitudinal Crossings and Nodal Intersections

Root-solving utilities determine when dynamic bodies cross specific ecliptic longitudes or pass through orbital nodes.

### Crossing Functions

| Function (Zig / C) | Central Body | Target Phenomenon | Output |
| :--- | :--- | :--- | :--- |
| `solcross` / `solcross_ut` | Sun | Crosses specified ecliptic longitude `xlon`. | Julian Day of crossing event. |
| `mooncross` / `mooncross_ut` | Moon | Crosses specified ecliptic longitude `xlon`. | Julian Day of crossing event. |
| `mooncross_node` / `_node_ut` | Moon | Crosses instantaneous lunar orbital plane ascending or descending node. | Julian Day of crossing, plus node latitude and longitude. |
| `helio_cross` | Planet (`ipl`) | Heliocentric crossing of specified longitude `xlon`. | Populates target `jd_cross` return parameter. |

* **Kinematic Limits**: Solvers use iterative interpolation. To avoid root skipping, provide a seed Julian Day within a few days or weeks of the expected crossing.
* **Retrograde Anomaly**: For planets or the true lunar node, retrograde loops can cause the solver to return a crossing timestamp earlier than the seed epoch if the body loops back across the target longitude. Validate the returned velocity vector to confirm crossing directionality.

---

## 5. Fixed Star Astrometry

Evaluates fixed stars from the external catalog `sefstars.txt`.

### API Signatures

```zig
// Zig Facades
pub fn fixstar_ut(
    star: [*:0]u8,
    jd_ut: f64,
    iflag: i32,
    xx: *[6]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32

pub fn fixstar2_ut(
    star: [*:0]u8,
    jd_ut: f64,
    iflag: i32,
    xx: *[6]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32

pub fn fixstar_mag(star: [*:0]u8, mag: *f64, serr: *[256]u8, swed: *Swed) i32
```
```c
/* C Signatures */
int32_t swe_fixstar_ut(char *star, double tjd_ut, int32_t iflag, double *xx, char *serr);
int32_t swe_fixstar2_ut(char *star, double tjd_ut, int32_t iflag, double *xx, char *serr);
int32_t swe_fixstar_mag(char *star, double *mag, char *serr);
```

### Buffer Mutation Invariant
The input string buffer `star` **must be writable** and sized to at least $512\text{ bytes}$ (`2 * SE_MAX_STNAME`).  
When querying a star by traditional name or catalog prefix (e.g. `",alAlcy"` or `"Sirius"`), the engine matches the catalog entry, formats the canonical designation, and **writes the normalized name back into the buffer**. Passing an immutable string literal in C causes a memory segmentation fault.

```zig
// Correct Zig star buffer allocation:
var star_buf: [512:0]u8 = undefined;
@memcpy(star_buf[0..6], "Sirius");
star_buf[6] = 0; // Ensure explicit null-termination

const status = swe.fixstar_ut(
    &star_buf,
    jd_ut,
    swe.sweph.SEFLG_SWIEPH,
    &xx,
    &serr,
    &swed,
    models,
    &dctx,
);

if (status < 0) {
    // Star not found in sefstars.txt or catalog missing
}
```

* **Differences Between `fixstar` and `fixstar2`**: `fixstar2` is an updated variant that handles non-standard proper motion vectors and includes expanded Bayer/Flamsteed search prefixes.
* **Error Behavior**: An unrecognized star designation returns `ERR` (`-1`) and writes `"star not found"` to `serr`. If `sefstars.txt` is missing from `$EPHE`, the initial call aborts and reports an unreadable star file. Query photometric visual magnitudes separately using `fixstar_mag()`.
