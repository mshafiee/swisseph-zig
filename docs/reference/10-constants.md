# Constants Reference

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Source Truth and Global Architectural Invariants

* **Upstream Headers**: `include/swephexp.h:88`, `include/sweph.h:65`, `include/sweodef.h:267`.
* **Zig Module Re-exports**: `src/swephlib.zig`, `src/sweph.zig`, `src/swehouse.zig`, `src/swecl.zig`.
* **Dimensional Conventions**:
  * **Angles**: Decimal degrees ($0.0^\circ \le \theta < 360.0^\circ$ or signed $[-90.0^\circ, +90.0^\circ]$).
  * **Distances**: Astronomical Units ($\text{AU}$) for planetary bodies; meters ($\text{m}$) or kilometers ($\text{km}$) for geodesy and physical dimensions.
  * **Time Coordinates**: Julian Day numbers in Terrestrial Time ($\text{TT}/\text{ET}$) by default. Functions bearing the `_ut` suffix take or return Universal Time ($\text{UT1}/\text{UTC}$).

Every constant in this reference adheres to the standard pattern:  
**Definition $\rightarrow$ Value & Units $\rightarrow$ Provenance $\rightarrow$ Physical / Operational Limits $\rightarrow$ Zig & C Bindings $\rightarrow$ Error Handling**.

---

## 2. Version Identification and Ephemeris File Selectors

### `SE_VERSION`
* **Definition**: Upstream Swiss Ephemeris library release version tracked by this port (`include/sweph.h:65`).
* **Value**: `"2.10.03"` (ASCII String).
* **Usage**: Query at runtime initialization and record alongside published ephemeris tables for auditability.
* **Limits**: Informational only; does not alter calculation paths.
* **Examples**:
  ```zig
  var v: [256]u8 = undefined;
  _ = swe.swe_abi.swe_version(&v); // Populates "2.10.03"
  ```
  ```c
  char v[256];
  swe_version(v);
  ```
* **Error Handling**: An unexpected string indicates a binary-to-header mismatch. Rebuild the consumer application against `dist/<target-triple>/include`.

---

### `SE_DE_NUMBER`, `SE_FNAME_DE431`, `SE_FNAME_DFT`
* **Definition**: Default JPL planetary integration baseline and filename literals.
* **Values**:
  * `SE_DE_NUMBER = 431` (Integer)
  * `SE_FNAME_DE431 = "de431.eph"` (File name literal)
  * `SE_FNAME_DFT = "de431.eph"`
  * `SE_FNAME_DFT2 = "de406.eph"` (Legacy baseline for historical pre-2.0 deployments)
* **Provenance**: NASA JPL Planetary Ephemeris DE431 (Folkner et al., 2014; spanning 13002 BCE to 17000 CE; $\approx 2.6\text{ GB}$).
* **Limits**: The path buffer passed to `swe_set_jpl_file()` is clamped at $256\text{ bytes}$ (`AS_MAXCH`).
* **Examples**:
  ```zig
  swe.set_jpl_file("de431.eph", &swed);
  ```
  ```c
  swe_set_jpl_file("de431.eph");
  ```
* **Error Handling**: If the specified file cannot be opened, the initial call invoking `SEFLG_JPLEPH` returns `ERR` (`-1`) and writes `"cannot open JPL file"` into `serr`.

---

### `SEFLG_DEFAULTEPH`
* **Definition**: The implicit ephemeris calculation mode activated when `iflag = 0`.
* **Value**: Aliased directly to `SEFLG_SWIEPH` (`2`). Directs the engine to evaluate compressed Swiss Ephemeris (`.se1`) files.
* **Fallback Behavior**: If `.se1` files are missing from the search path, the engine falls back to the semi-analytical Moshier ephemeris (`SEFLG_MOSEPH`), writing a fallback notice into `serr` while returning `OK` (`0`). Call `swe_get_current_file_data()` to verify which ephemeris source was evaluated.

---

## 3. Calendar Selectors and Astronomical Epochs

### Calendar Mode Flags
* `SE_JUL_CAL = 0`: Proleptic Julian Calendar.
* `SE_GREG_CAL = 1`: Proleptic Gregorian Calendar.

Used across `swe_julday`, `swe_revjul`, `swe_date_conversion`, and `swe_utc_to_jd`.

* **Limits & Traps**: Swiss Ephemeris does **not** auto-detect calendar reform transitions (e.g., the October 1582 cutover). The caller explicitly selects the calendar system. Mismatched flags across calendar conversion and inversion routines will introduce artificial time shifts of $10\text{ to }13\text{ days}$.
* **Examples**:
  ```zig
  // Convert 2000-01-01 12:00:00 UT to Julian Day (Gregorian)
  const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL); // 2451545.0
  ```
  ```c
  double jd = swe_julday(2000, 1, 1, 12.0, SE_GREG_CAL);
  ```
* **Error Handling**: Passing out-of-range dates (e.g., month 13, day 32, hour 25.0) to `swe_date_conversion()` returns `ERR` (`-1`) and leaves the output target `tjd` unmodified.

---

### Astronomical Reference Epochs

| Constant | Julian Day (TT) | Calendar Equivalent (TT) | Epoch Class | Description |
| :--- | :--- | :--- | :--- | :--- |
| `J2000` | `2451545.0` | 2000-01-01 12:00:00 | Julian Epoch | Fundamental modern ICRF/equator epoch ($365.25\text{ days/year}$). |
| `B1950` | `2433282.42345905` | 1950-01-00.923 | Besselian Epoch | Legacy standard equinox ($365.242198781\text{ days/year}$). |
| `J1900` | `2415020.0` | 1900-01-00 12:00:00 | Julian Epoch | Standard reference for classical Newcomb planetary tables. |
| `B1850` | `2396758.2035810` | 1850-01-00.204 | Besselian Epoch | Nineteenth-century astrometric and ayanamsha base epoch. |

* **Limits**: Exact equality applies exclusively in Terrestrial Time ($\text{TT}$). In Universal Time ($\text{UT}$), these epochs differ by the corresponding $\Delta T$ offset (e.g., $\Delta T \approx 64.184\text{ s}$ at J2000).

---

## 4. Physical Constants and Geodetic Parameters

Values from the IAU 2012 / 2016 resolutions and the *Astronomical Almanac* (2006, sections K6–K7).

```
                        Physical & Conversion Constants
  -------------------------------------------------------------------------
  SE_AUNIT_TO_KM          149597870.700 km           Astronomical Unit (exact)
  CLIGHT                  299792458.0 m/s            Speed of light in vacuo
  LIGHTTIME_AUNIT         0.00577551833 d (8.3167m) Light travel time for 1 AU
  HELGRAVCONST            1.32712440018e20 m³/s²     Heliocentric GM (Sun)
  GEOGCONST               3.98600448000e14 m³/s²     Geocentric GM (Earth)
  KGAUSS                  0.01720209895              Gaussian Grav. Constant
  EARTH_RADIUS            6378136.6 m                Equatorial radius (WGS84/IERS)
  OBLATENESS              1.0 / 298.25642            Earth flattening factor (f)
  ROT_SPEED               7.2921151467e-5 rad/s      Nominal Earth rotation rate
```

### Dimensional Conversion Factors
* `SE_AUNIT_TO_KM = 149597870.700`: Exactly defined IAU 2012 scale. Coordinate conversions multiply `xx[2]` ($\text{AU}$) by this factor to obtain $\text{km}$. Inaccurate values cause kilometer-scale trajectory errors during solar eclipse path tracing.
* `SE_AUNIT_TO_LIGHTYEAR = 1.0 / 63241.07708426628`: Derived length conversion.
* `SE_AUNIT_TO_PARSEC = 1.0 / 206264.80624709636`: Derived from $648000 / \pi$ (IAU 2016 Resolution B2).
* `AUNIT = 1.49597870700e+11`: Scale factor in meters (`include/sweph.h:273`).
* `CLIGHT = 2.99792458e+8`: Speed of light in meters per second ($c$). Governs light-deflection equations and planetary aberration corrections.
* `LIGHTTIME_AUNIT = 499.0047838362 / 86400.0` ($\approx 0.00577551833\text{ days}$ $\approx 8.316746\text{ minutes}$): Light-time per AU. At 1 AU, light travel delay is $\approx 499.00\text{ seconds}$; at the Moon's distance, $\approx 1.28\text{ seconds}$; at Jupiter, $\approx 33\text{ to }53\text{ minutes}$.

### Gravitational and Angular Constants
* `HELGRAVCONST = 1.32712440017987e+20\text{ m}^3/\text{s}^2$: Heliocentric gravitational constant ($G M_\odot$). Determines mean daily motion $n$ for fictitious bodies when derived from semi-major axis $a$.
* `GEOGCONST = 3.98600448e+14\text{ m}^3/\text{s}^2$: Geocentric gravitational constant ($G M_\oplus$). Used in topocentric parallax reductions.
* `KGAUSS = 0.01720209895`: Gaussian gravitational constant ($k = \sqrt{G M_\odot}$, in $\text{AU}^{3/2} \text{d}^{-1} M_\odot^{-1/2}$).
* `KM_S_TO_AU_CTY = 21.095`: Conversion scalar mapping $\text{km/s}$ to $\text{AU per Julian century}$.

### Angular and Centisecond Conversion Primitives
* `DEGTORAD = \pi / 180.0 \approx 0.017453292519943295`
* `RADTODEG = 180.0 / \pi \approx 57.29577951308232`
* Centisecond integers for coordinate split operations (`swe_split_deg`, `cs2deg`):
  * `DEG = 360000` (Centiseconds per degree)
  * `DEG360 = 360 * 360000 = 129600000` (Centiseconds per circle)

### Planetary Radii Table (`pla_diam[]`)
Declared in `include/sweph.h:315`. Supplies equatorial diameters in meters:
* Sun: $1.392 \times 10^9\text{ m}$
* Mercury: $4{,}879{,}400\text{ m}$
* Venus: $12{,}103{,}600\text{ m}$
* Earth: $12{,}756{,}273.2\text{ m}$
* Moon: $3{,}474{,}800\text{ m}$
* Mars: $6{,}792{,}400\text{ m}$
* Jupiter: $142{,}984{,}000\text{ m}$
* Saturn: $120{,}536{,}000\text{ m}$
* Uranus: $51{,}118{,}000\text{ m}$
* Neptune: $49{,}528{,}000\text{ m}$
* Pluto: $2{,}376{,}600\text{ m}$
* Ceres: $939{,}400\text{ m}$
* Vesta: $525{,}400\text{ m}$

*Operational Effect*: Used in `swe_pheno()` for apparent planetary disc size, apparent visual magnitude calculations, and eclipse contact timings. Inaccurate values shift eclipse contact predictions by seconds without triggering software errors.

### Geodetic and Lunar Mechanics Constants
* `EARTH_RADIUS = 6378136.6\text{ m}`: Mean equatorial radius (IERS/WGS84 compromise).
* `OBLATENESS = 1.0 / 298.25642`: Earth flattening factor ($f$).
* `ROT_SPEED = 7.2921151467e-5 * 86400.0\text{ rad/day}`: Nominal terrestrial rotation velocity.
* `SUN_RADIUS = 959.63''`: Standard solar angular semi-diameter at $1\text{ AU}$.
* `MOON_MEAN_DIST = 384400000.0\text{ m}`: Semi-major axis of the Moon's geocentric orbit.
* `INCL = 5.1453964^\circ`: Mean lunar orbital inclination relative to the ecliptic.
* `ECC = 0.054900489`: Mean eccentricity of the lunar orbit.
* `SUN_EARTH_MRAT = 332946.050895`: Ratio of solar mass to Earth mass ($M_\odot / M_\oplus$).
* `EARTH_MOON_MRAT = 1.0 / 0.0123000383`: Ratio of Earth mass to Lunar mass ($M_\oplus / M_L$).

---

## 5. Ephemeris Validity Bounds and Segmentations

| Boundary Constant | Julian Day (TT) | Calendar Equivalent | Scope / Engine | Behavior on Violation |
| :--- | :--- | :--- | :--- | :--- |
| `JPL_DE431_START` | `-3027215.5` | 13002 BCE Dec 21 | JPL DE431 File Limits | Halts; returns `BEYOND_EPH_LIMITS` (`-3`). |
| `JPL_DE431_END` | `+7930192.5` | 17000 CE Jan 18 | JPL DE431 File Limits | Halts; returns `BEYOND_EPH_LIMITS` (`-3`). |
| `MOSHPLEPH_START` | `625000.5` | 3001 BCE Jan 01 | Moshier Analytical Planets | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `MOSHPLEPH_END` | `2818000.5` | 3000 CE Dec 31 | Moshier Analytical Planets | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `MOSHLUEPH_START` | `625000.5` | 3001 BCE Jan 01 | Moshier Analytical Moon | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `MOSHLUEPH_END` | `2818000.5` | 3000 CE Dec 31 | Moshier Analytical Moon | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `MOSHNDEPH_START` | `-3100015.5` | Historical baseline | Analytical Lunar Nodes | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `MOSHNDEPH_END` | `+8000016.5` | Extended baseline | Analytical Lunar Nodes | Aborts; returns `ERR` (`-1`); zeros `xx[6]`. |
| `CHIRON_START` | `1967601.5` | 0675 CE Jan 01 | Chiron Numeric Orbit | Clamped; returns `ERR` (`-1`) or `-3`. |
| `CHIRON_END` | `3419437.5` | 4650 CE Jan 01 | Chiron Numeric Orbit | Clamped; returns `ERR` (`-1`) or `-3`. |
| `PHOLUS_START` | `640648.5` | 2958 BCE May 20 | Pholus Numeric Orbit | Clamped; returns `ERR` (`-1`) or `-3`. |
| `PHOLUS_END` | `4390617.5` | 7309 CE Sep 04 | Pholus Numeric Orbit | Clamped; returns `ERR` (`-1`) or `-3`. |

### Supplemental Limits
* `SEI_ECL_GEOALT_MAX = 25000\text{ m}` / `SEI_ECL_GEOALT_MIN = -500\text{ m}`: Safe altitude clamps for the solar eclipse projection cylinder. Input observer elevations outside this window are clamped silently without raising errors.
* `NCTIES = 6.0`: Standard temporal span in Julian centuries per Swiss Ephemeris (`.se1`) compressed file segment ($600\text{ Julian years}$).

```zig
// Guarding against numerical boundary faults:
const r = swe.calc_ut(jd, swe.sweph.SE_CHIRON, flg, &xx, &swed, models, &dctx, &serr);
if (r == swe.sweph.ERR_BEYOND_EPH_LIMITS or r < 0) {
    // Chiron out of range [675, 4650 CE]; do not use xx coordinates
    return error.EphemerisLimitsExceeded;
}
```

---

## 6. Filesystem Targets, Buffer Limits, and Search Rules

### Canonical File Literals
* `SE_STARFILE = "sefstars.txt"`: Fixed star catalog definitions and proper motion components.
* `SE_ASTNAMFILE = "seasnam.txt"`: Mapping table for Asteroid catalog numbers and designated names.
* `SE_FICTFILE = "seorbel.txt"`: Keplerian orbital parameters for fictitious and user-defined bodies (IDs 40–999).
* `SE_FILE_SUFFIX = "se1"`: Default file extension for compressed Swiss Ephemeris planetary files.
* `SE_EPHE_PATH = ".:/users/ephe2/:/users/ephe/"`: Hardcoded UNIX fallback path checked when neither `swe_set_ephe_path()` nor `$SE_EPHE_PATH` are declared.
* `AS_MAXCH = 256`: Maximum static buffer capacity allocated for filenames and path resolution strings.

### Filesystem Search Constraints
1. **Path String Truncation**: Path strings exceeding 255 characters are rejected and silently overwritten with the legacy internal fallback string (`\SWEPH\EPHE`).
2. **Directory Hierarchy**: The asteroid subdirectories (`ast0/` through `ast21/`) and planetary satellite directory (`sat/`) must exist directly inside the path passed to `swe_set_ephe_path()`. They cannot be configured as sibling directories.
3. **Initialization Requirement**: Always execute `swe_set_ephe_path(NULL)` or provide an explicit directory before making calculation calls. This seeds the internal `Swed` structure and confirms runtime allocation sanity even for pure-analytical Moshier runs.

---

## 7. Library Status Codes

Defined in `include/sweph.h:251`:

| Identifier | Value | Return Category | Meaning / Engine Action |
| :--- | :--- | :--- | :--- |
| `OK` | `0` | Success | Calculation completed to nominal precision. |
| `ERR` | `-1` | Critical Error | Calculation failed. Output vector is zeroed or invalid. Detailed error written to `serr`. |
| `NOT_AVAILABLE` | `-2` | Minor Alert | Calculation completed, but requested optional property (e.g., speed) is unavailable. |
| `BEYOND_EPH_LIMITS` | `-3` | Boundary Fault | Target Julian Day falls outside valid ephemeris interpolation range. |

```zig
// Diagnostic validation pattern
var serr: [256]u8 = undefined;
const status = swe.calc_ut(jd, ipl, flg, &xx, &swed, models, &dctx, &serr);

if (status < 0) {
    // Determine exact cause from serr slice
    const err_msg = std.mem.sliceTo(&serr, 0);
    std.log.err("Ephemeris failure ({d}): {s}", .{ status, err_msg });
    return error.CalculationFailed;
}
```

---

## 8. Lunar Secular Tidal Acceleration ($\dot{n}_\text{Moon}$)

Declared in arcseconds per Julian century squared ($\text{arcsec/cy}^2$). This value parameterizes the Moon’s secular acceleration due to oceanic and mantle tidal dissipation, directly coupling the lunar ephemeris to $\Delta T$ ($TT - UT1$) backward in time.

| Calibration Macro | Value ($\text{arcsec/cy}^2$) | Ephemeris Fit / Research Provenance |
| :--- | :--- | :--- |
| `SE_TIDAL_DE200` | `-23.8946` | JPL DE200 |
| `SE_TIDAL_DE403` / `404` | `-25.580` | JPL DE403 / DE404 |
| `SE_TIDAL_DE405` / `406` | `-25.826` | JPL DE405 / DE406 |
| `SE_TIDAL_DE421` / `422` | `-25.85` | JPL DE421 / DE422 |
| `SE_TIDAL_DE430` | `-25.82` | JPL DE430 |
| `SE_TIDAL_DE431` | `-25.80` | JPL DE431 (**Default Swiss Ephemeris baseline**) |
| `SE_TIDAL_DE441` | `-25.936` | JPL DE441 |
| `SE_TIDAL_STEPHENSON_2016`| `-25.85` | F. R. Stephenson et al. (2016 historical eclipse records) |
| `SE_TIDAL_AUTOMATIC` | `999999` | Dynamically derives tidal value from header metadata of loaded file |
| `SE_TIDAL_MOSEPH` | `-25.580` | Standard setting when running under analytical Moshier mode |

* **Runtime Accessors**: Set with `swe_set_tid_acc(val)`, query with `swe_get_tid_acc()`.
* **Historical Impact**: Modifying this parameter shifts historical Delta-T values before 1955 CE. In ancient eclipse predictions (e.g., 500 BCE), altering tidal acceleration from $-25.80$ to $-23.89$ shifts the calculated geographic eclipse path across continents and moves contact times by minutes.

---

## 9. Numerical Differentiation Step Intervals

Defined in `include/sweph.h:298`. When analytical derivatives are unavailable and `SEFLG_SPEED` is enabled, the engine calculates instantaneous velocities using two-point central finite differences:

$$v = \frac{r(t + \delta t) - r(t - \delta t)}{2 \cdot \delta t}$$

| Differentiation Target | Step Interval ($\delta t$, in days) | Real-Time Temporal Equivalent |
| :--- | :--- | :--- |
| `SWE_SPEED_INTV_MOON` | `0.00005` | $4.32\text{ seconds}$ |
| `SWE_SPEED_INTV_PLAN` | `0.001` (or `0.0001` depending on model) | $8.64\text{ seconds}$ |
| `SWE_SPEED_INTV_MEAN_NODE` | `0.001` | $86.4\text{ seconds}$ |
| `SWE_SPEED_INTV_NODE` | `0.0001` (Moshier mode: `0.1`) | $8.64\text{ seconds}$ (Moshier: $2.4\text{ hours}$) |
| `SWE_SPEED_INTV_NUT` | `0.0001` | $8.64\text{ seconds}$ |
| `SWE_SPEED_INTV_DEFL` | `0.0000005` | $0.0432\text{ seconds}$ |

> **Parity Invariant**: Do not modify these step intervals. Maintaining bit-for-bit velocity parity with the upstream C implementation depends directly on using these exact step sizes. Altering them disrupts speed outputs and causes root-finding divergence in transit solvers.
