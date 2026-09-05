# Calculation Flags: `SEFLG_*`, `SE_NODBIT_*`, and `SE_SPLIT_DEG_*`

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Architectural Foundations and Default Semantics

The behavior of `swe_calc` and `swe_calc_ut` is controlled by a 32-bit integer bitmask (`iflag`).

* **Source Truth**: `include/swephexp.h:186`.
* **Combination Semantics**: Flags within distinct categories can be combined using bitwise OR (`|`). Conflicting flags within the same category resolve according to strict engine precedence rules.
* **The Default State (`iflag = 0`)**:
  Setting `iflag = 0` invokes `SEFLG_SWIEPH` without speeds:
  * **Frame**: Geocentric apparent ecliptic coordinates referenced to the true equinox and ecliptic of date.
  * **Corrections**: Planetary aberration, light deflection, and nutation are fully applied.
  * **Units**: Ecliptic longitude ($\lambda$) and latitude ($\beta$) in decimal degrees; distance ($r$) in AU.
  * **Kinematics**: Daily velocities are suppressed (`xx[3..5] = 0.0`).

### Basic Usage

```zig
// Zig: Swiss Ephemeris + velocities + sidereal zodiac
const flg = swe.sweph.SEFLG_SWIEPH | swe.sweph.SEFLG_SPEED | swe.sweph.SEFLG_SIDEREAL;

var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

const ret = swe.calc_ut(jd_ut, 0, flg, &xx, &swed, models, &dctx, &serr);
```

```c
/* C equivalent */
int flg = SEFLG_SWIEPH | SEFLG_SPEED | SEFLG_SIDEREAL;
double xx[6];
char serr[256];

int ret = swe_calc_ut(jd_ut, SE_SUN, flg, xx, serr);
```

---

## 2. Ephemeris Engine Selection (Mutually Exclusive)

Select at most **one** ephemeris source. If multiple bits are set, the engine applies internal precedence (`JPLEPH` $\rightarrow$ `SWIEPH` $\rightarrow$ `MOSEPH`).

| Constant | Bit Value | Engine Description | Accuracy vs. JPL | Dependency & Failure Mode |
| :--- | :--- | :--- | :--- | :--- |
| `SEFLG_JPLEPH` | `1` (`0x0001`) | Raw JPL direct integration file (`de431.eph` / `de441.eph`). | Identical (Baseline) | Requires prior call to `swe_set_jpl_file()`. If the file is missing or invalid, evaluation halts and returns `ERR` (`-1`). |
| `SEFLG_SWIEPH` | `2` (`0x0002`) | Compressed Swiss Ephemeris Chebyshev polynomials (`.se1`). **(Default)** | $\approx 0.001''$ ($1\text{ mas}$) | Requires `.se1` files in `$EPHE`. If missing, the engine **silently downgrades** to `MOSEPH`, writing a warning to `serr` while returning `OK` (`0`). |
| `SEFLG_MOSEPH` | `4` (`0x0004`) | Semi-analytical Moshier ephemeris. | $< 1''$ (Planets), arcseconds (Moon) | **Zero external file dependencies.** Valid over 3000 BCE–3000 CE (terrestrial planets accurate from 1350 BCE onward). |

> **Audit Recommendation**: Because `SEFLG_SWIEPH` degrades silently to `SEFLG_MOSEPH` when data files are missing, production test suites should inspect the source of served ephemeris data using `swe_get_current_file_data()` rather than relying solely on return codes.

---

## 3. Coordinate Frames and Reduction Toggles

These bits control the spatial origin of the observer and toggle relativistic or astrometric corrections.

### 3.1 Observer Origin (Select $\le 1$)

* **Default (No Origin Bits Set)**: Geocentric coordinates (origin at Earth's center of mass).
* **`SEFLG_HELCTR` (`8`, `0x0008`)**: Heliocentric coordinates (origin at the center of the Sun).
* **`SEFLG_BARYCTR` (`16384`, `0x4000`)**: Barycentric coordinates (origin at the Solar System Barycenter, SSB).
* **`SEFLG_TOPOCTR` (`32768`, `0x8000`)**: Topocentric coordinates (origin at the observer's geographic surface position).
  * *Operational Requirement*: Requires calling `swe_set_topo(geo_lon, geo_lat, geo_alt)`. If `swe_set_topo()` has not been called, the engine defaults silently to geocentric coordinates without returning an error.
  * *Note on Bit Re-use*: `SEFLG_ORBEL_AA` shares the integer value `32768` (`0x8000`) within Keplerian orbit routines to trigger *Astronomical Almanac* algorithm modes.

### 3.2 Relativistic and Astrometric Reduction Modifiers

```
Raw Physical Vector (JPL/SWIEPH)
  │
  ├── [SEFLG_TRUEPOS] ──> Bypasses all corrections (Geometric position)
  │
  ├── Light-Time Iteration (Calculates light delay τ)
  │     │
  │     ├── [SEFLG_ASTROMETRIC = NOABERR | NOGDEFL] ──> Retains light-time only
  │     │
  │     ├── Relativistic Light Deflection (Sun/Planets) ──[SEFLG_NOGDEFL disables]
  │     └── Stellar & Planetary Aberration ──────────────[SEFLG_NOABERR disables]
  │
  └── Equinox Precession & Nutation
        ├── [SEFLG_J2000] ──> Coordinates locked to standard J2000.0 equinox
        ├── [SEFLG_NONUT] ──> Mean equinox of date (nutation suppressed)
        └── Default ───────> True equinox of date
```

* **`SEFLG_TRUEPOS` (`16`, `0x0010`)**: Evaluates geometric position at target time $t$. Bypasses light travel time delay, stellar aberration, and gravitational light bending. Coordinates can deviate by up to $20''$ from apparent positions.
* **`SEFLG_J2000` (`32`, `0x0020`)**: Transforms coordinates into the fixed ICRF/J2000.0 equinox frame, bypassing precession between J2000.0 and calculation date $t$.
* **`SEFLG_NONUT` (`64`, `0x0040`)**: References coordinates to the **mean equinox of date** by suppressing periodic nutation corrections.
* **`SEFLG_NOGDEFL` (`512`, `0x0200`)**: Disables general relativistic gravitational light deflection caused by the Sun and major planets.
* **`SEFLG_NOABERR` (`1024`, `0x0400`)**: Disables stellar and planetary aberration corrections caused by Earth's orbital and diurnal velocity.
* **`SEFLG_ASTROMETRIC` (`1536`, `0x0600`)**: Bitwise combination of `SEFLG_NOABERR | SEFLG_NOGDEFL`. Produces light-time corrected positions suitable for direct comparison against astrometric reference catalogs (such as Hipparcos or Gaia).

### Invalidation and Conflict Rules
* `SEFLG_TRUEPOS | SEFLG_TOPOCTR`: Fully supported; computes geometric topocentric coordinates.
* `SEFLG_HELCTR | SEFLG_TOPOCTR`: Mutually exclusive and geometrically invalid; the engine gives precedence to `SEFLG_HELCTR`.

---

## 4. Coordinate Output Formats and Reference Frames

### 4.1 Kinematics
* **`SEFLG_SPEED` (`256`, `0x0100`)**: Computes daily velocities returned in `xx[3..5]`. Derived analytically or via high-precision 2-point central finite differences. Recommended for standard production use.
* **`SEFLG_SPEED3` (`128`, `0x0080`)**: Deprecated 3-point numerical differentiation method. Slower and less numerically stable than `SEFLG_SPEED`. **Avoid use.**

### 4.2 Coordinate System Transformations

| Constant | Bit Value | Resulting Layout in `xx[0..2]` | Resulting Layout in `xx[3..5]` |
| :--- | :--- | :--- | :--- |
| **Default** | `0` | Ecliptic Lon ($\lambda$), Lat ($\beta$), Dist ($r$ in AU) | $d\lambda/dt$, $d\beta/dt$, $dr/dt$ ($^\circ/\text{day}$, $\text{AU/day}$) |
| `SEFLG_EQUATORIAL` | `2048` (`0x0800`) | Right Ascension ($\alpha$), Declination ($\delta$), Dist ($r$) | $d\alpha/dt$, $d\delta/dt$, $dr/dt$ ($^\circ/\text{day}$, $\text{AU/day}$) |
| `SEFLG_XYZ` | `4096` (`0x1000`) | Rectangular Cartesian coordinates: $X, Y, Z$ (AU) | Velocity components: $dX/dt, dY/dt, dZ/dt$ ($\text{AU/day}$) |
| `SEFLG_RADIANS` | `8192` (`0x2000`) | Angular outputs converted from degrees to **radians** | Velocity angles converted to **radians/day** |

*Note: Formatting routines like `swe_split_deg` expect degree inputs. If `SEFLG_RADIANS` is enabled, convert values back to degrees before passing them to degree-splitting or zodiac-formatting utilities.*

### 4.3 Reference Frames and Specialized Ephemeris Modes
* **`SEFLG_TROPICAL` (`0`)**: Default tropical ecliptic system based on the intersection of the ecliptic and the Earth's equator of date.
* **`SEFLG_SIDEREAL` (`65536`, `0x00010000`)**: Evaluates positions in the sidereal zodiac.
  * *Operational Trap*: Call `swe_set_sid_mode()` beforehand to configure the desired ayanamsha. If omitted, the engine defaults silently to the **Fagan/Bradley** ayanamsha without warning.
* **`SEFLG_ICRS` (`131072`, `0x00020000`)**: International Celestial Reference System (ICRS) alignment. When transforming DE406 vectors to J2000, frame bias rotations are eliminated (pair with `bias = NONE` in `AstroModels`).
* **`SEFLG_JPLHOR` (`262144`, `0x00040000`) / `SEFLG_JPLHOR_APPROX` (`524288`, `0x00080000`)**: Emulates NASA JPL Horizons ephemeris outputs by integrating Earth Orientation Parameters (EOP tables `eop*.dat`).
* **`SEFLG_CENTER_BODY` (`1048576`, `0x00100000`)**: Directs the engine to compute the physical **Center of Body (COB)** rather than the system barycenter for Jupiter, Saturn, or Pluto.

---

## 5. Sidereal Modification Bits: `SE_SIDBIT_*`

`SE_SIDBIT_*` flags are **never passed to `swe_calc`**. They are combined into the `t0` or mode arguments of `swe_set_sid_mode()` to adjust how custom ayanamshas are calculated:

```zig
// Zig: configure a user-defined ayanamsha referencing the solar-system invariant plane
swe.set_sid_mode(
    swe.sweph.SE_SIDM_USER,
    t0,
    ayan_t0 | swe.sweph.SE_SIDBIT_SSY_PLANE,
    &swed,
);
```

* **`SE_SIDBIT_ECL_T0` (`256`)**: Projects the reference point onto the ecliptic of epoch $t_0$ rather than the ecliptic of date.
* **`SE_SIDBIT_SSY_PLANE` (`512`)**: References the ayanamsha orientation to the Solar System Invariant Plane rather than the terrestrial ecliptic.
* **`SE_SIDBIT_USER_UT` (`1024`)**: Interprets the custom reference epoch parameter $t_0$ as Universal Time ($\text{UT}$) rather than Terrestrial Time ($\text{TT}$).
* **`SE_SIDBIT_ECL_DATE` (`2048`)**: Projects reference stars onto the ecliptic of date.
* **`SE_SIDBIT_NO_PREC_OFFSET` (`4096`) / `SE_SIDBIT_PREC_ORIG` (`8192`)**: Diagnostic test flags used to evaluate precession formulation differences. Do not use in production.

---

## 6. Node and Apsides Method Selection: `SE_NODBIT_*`

The `swe_nod_aps()` and `swe_nod_aps_ut()` routines require a method bitmask to specify which orbital mechanics model to evaluate:

| Constant | Value | Computation Method | Physical Characteristics |
| :--- | :--- | :--- | :--- |
| `SE_NODBIT_MEAN` | `1` (`0x0001`) | Secular Mean Node / Apsis | Smooth, uniform secular progression. **(Default if `0` is passed)**. |
| `SE_NODBIT_OSCU` | `2` (`0x0002`) | True Osculating Orbit | Instantaneous Keplerian two-body state relative to central body. |
| `SE_NODBIT_OSCU_BAR` | `4` (`0x0004`) | Osculating Barycentric | Instantaneous Keplerian state relative to system barycenter. |
| `SE_NODBIT_FOPOINT` | `256` (`0x0100`) | Second Focal Point | OR'd with the methods above; replaces the apogee/aphelion position with the second, empty geometric focus of the orbital ellipse. |

> **Behavioral Invariant**: When computing osculating lunar apogees (`SE_NODBIT_OSCU`), the apogee will exhibit large, rapid shifts when the Moon traverses perigee. This is a consequence of instantaneous Keplerian geometry in near-circular orbits, not a software bug.

---

## 7. Coordinate Formatting: `SE_SPLIT_DEG_*`

The `swe_split_deg()` function decomposes an angular coordinate into degrees, minutes, seconds, and fractions of a second based on a configuration bitmask (`roundflag`):

### 7.1 Precision and Rounding Modifiers (Select 1)
* **`SE_SPLIT_DEG_ROUND_SEC` (`1`)**: Rounds to the nearest whole integer second ($1''$).
* **`SE_SPLIT_DEG_ROUND_MIN` (`2`)**: Rounds to the nearest whole integer minute ($1'$).
* **`SE_SPLIT_DEG_ROUND_DEG` (`4`)**: Rounds to the nearest whole integer degree ($1^\circ$).

### 7.2 Division Frameworks
* **`SE_SPLIT_DEG_ZODIACAL` (`8`)**: Splits output into a zero-indexed zodiacal sign ($0\text{ to }11$) and degrees within that sign ($0^\circ \le \text{deg} < 30^\circ$).
* **`SE_SPLIT_DEG_NAKSHATRA` (`1024`)**: Splits output into 27 Vedic Nakshatra divisions ($13^\circ 20'$ per sector). Can be combined with `SE_SPLIT_DEG_ZODIACAL`.

### 7.3 Boundary Carry Suppression
* **`SE_SPLIT_DEG_KEEP_SIGN` (`16`)**: Suppresses rounding-induced carry into adjacent zodiac signs. For example, without this flag, $29^\circ 59' 59.9''$ Aries rounded to the nearest second carries over to $0^\circ 00' 00''$ Taurus. When set, the output remains clamped to the current sign ($29^\circ 59' 60''$ Aries).
* **`SE_SPLIT_DEG_KEEP_DEG` (`32`)**: Suppresses degree carry-over; clamps minutes to $60'$ rather than rolling over to the next whole degree.

```zig
// Zig: format coordinate into zodiac sign, rounding to seconds while preserving sign boundary
const split_flags = swe.sweph.SE_SPLIT_DEG_ROUND_SEC 
                  | swe.sweph.SE_SPLIT_DEG_ZODIACAL 
                  | swe.sweph.SE_SPLIT_DEG_KEEP_SIGN;

var deg: i32 = undefined;
var min: i32 = undefined;
var sec: i32 = undefined;
var dsec: f64 = undefined;
var sign: i32 = undefined;

swe.split_deg(xx[0], split_flags, &deg, &min, &sec, &dsec, &sign);
```
