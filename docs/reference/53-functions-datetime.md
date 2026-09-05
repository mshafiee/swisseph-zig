# Functions: Date/Time, Delta-T, Sidereal Time, Coordinate Transformations, and Utilities

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Implementation Mapping

* **Upstream C Declarations**: `include/swephexp.h:771` (Date/Time, Delta-T) and `include/swephexp.h:946` (Transformations and Math Utilities).
* **Zig Module Implementations**:
  * `src/swedate.zig`: Calendar algorithms, Julian Day conversions, UTC/ET timeframes, and local solar time reductions.
  * `src/deltat.zig`: Empirical and analytical $\Delta T$ ($TT - UT1$) models and tidal secular acceleration solvers.
  * `src/swephlib.zig`: Obliquity rotations, sidereal time formulations, angular normalizations, and legacy centisecond formatting.
* **Context Threading in Zig**: High-precision time routines accept an explicit `dctx: *DeltatCtx` to maintain leap-second tables and interpolation state without global variables.

---

## 2. Calendar and Julian Day Conversions

Swiss Ephemeris uses continuous Julian Day (JD) numbers as its primary temporal coordinate. Conversions do not apply automatic calendar cutovers (such as the historical Papal transition from Julian to Gregorian on October 4/15, 1582). Callers explicitly declare the calendar system using `SE_JUL_CAL` (`0`) or `SE_GREG_CAL` (`1`).

### `julday` and `revjul`

Transforms calendar dates into Julian Day numbers, and vice versa.

```zig
// Zig Facades
pub fn julday(year: i32, month: i32, day: i32, hour: f64, gregflag: i32) f64
pub fn revjul(jd: f64, gregflag: i32, year: *i32, month: *i32, day: *i32, hour: *f64) void
```
```c
/* C Signatures */
double swe_julday(int year, int month, int day, double hour, int gregflag);
void swe_revjul(double jd, int gregflag, int *year, int *month, int *day, double *hour);
```

* **Parameters & Units**:
  * `year`: Astronomical year numbering (year `0` = 1 BCE, `-1` = 2 BCE).
  * `month`: Integer $[1, 12]$.
  * `day`: Day of month $[1, 31]$.
  * `hour`: Fractional decimal hours in Universal Time ($0.0 \le \text{hour} < 24.0$; e.g., $18\text{h }30\text{m} = 18.5$).
  * `gregflag`: Calendar selector (`SE_JUL_CAL = 0`, `SE_GREG_CAL = 1`).
* **Returned JD**: Continuous Julian Day number at the given hour UT (epoch noon = $0.0$).
* **Rounding Invariant**: `julday` and `revjul` must invert cleanly across all valid historical ranges:
  $$\text{revjul}(\text{julday}(Y, M, D, H, C), C) \equiv (Y, M, D, H)$$

---

### `date_conversion`

Strict input-validating calendar converter.

```zig
// Zig Facade
pub fn date_conversion(y: i32, m: i32, d: i32, ut: f64, cal: u8, tjd: *f64) i32
```
```c
/* C Signature */
int swe_date_conversion(int y, int m, int d, double ut, char cal, double *tjd);
```

* **Parameters**: `cal` takes ASCII `'g'` / `'G'` for Gregorian or `'j'` / `'J'` for Julian.
* **Validation & Error Path**: Rejects invalid calendar components (e.g., month 13, day 32, hour 25.0, or day 29 in a non-leap year February). On error, returns `ERR` (`-1`) and leaves `*tjd` **unmodified**.

```zig
// Example: Converting standard J2000 epoch
var jd: f64 = undefined;
const status = swe.date_conversion(2000, 1, 1, 12.0, 'g', &jd);
if (status == 0) {
    // jd == 2451545.0
}
```

---

## 3. High-Precision UTC, Time Standards, and Solar Times

Calculations near the present era distinguish between Universal Time ($UT1$, tied to Earth rotation), Coordinated Universal Time ($UTC$, tied to SI seconds with discrete leap second insertions), and Terrestrial Time ($TT$, uniform atomic time).

```
                      Time System Reductions
 
     UTC (Civil Leap Seconds)
        │
        ├── [seleapsec.txt] ──> TAI (International Atomic Time: UTC + Leap Seconds)
        │                         │
        │                         └── TAI + 32.184s ──> TT (Terrestrial Time / ET)
        │                                                 │
        └── IERS (EOP) ───────> UT1 (Earth Rotation) ◄───┘ TT - Delta-T
```

### `utc_to_jd` and `jdet_to_utc` / `jdut1_to_utc`

```zig
// Zig Facades
pub fn utc_to_jd(
    y: i32, m: i32, d: i32, h: i32, mi: i32, s: f64,
    gregflag: i32, dret: *[2]f64, serr: *[256]u8, dctx: *DeltatCtx
) i32

pub fn jdet_to_utc(
    tjd_et: f64, gregflag: i32,
    y: *i32, m: *i32, d: *i32, h: *i32, mi: *i32, s: *f64, dctx: *DeltatCtx
) void

pub fn jdut1_to_utc(
    tjd_ut1: f64, gregflag: i32,
    y: *i32, m: *i32, d: *i32, h: *i32, mi: *i32, s: *f64, dctx: *DeltatCtx
) void
```
```c
/* C Signatures */
int swe_utc_to_jd(
    int y, int m, int d, int h, int mi, double s,
    int gregflag, double *dret, char *serr
);
void swe_jdet_to_utc(
    double tjd_et, int gregflag,
    int *y, int *m, int *d, int *h, int *mi, double *s
);
void swe_jdut1_to_utc(
    double tjd_ut1, int gregflag,
    int *y, int *m, int *d, int *h, int *mi, double *s
);
```

* **`utc_to_jd` Output Array (`dret[2]`)**:
  * `dret[0]`: Julian Day number in Terrestrial Time ($TT = ET$).
  * `dret[1]`: Julian Day number in Universal Time ($UT1$).
* **Data Dependency**: Leverages `seleapsec.txt` to account for historical and scheduled leap seconds. If the file is missing, the engine falls back to an internal hardcoded leap-second table.
* **Error Behavior**: Passing invalid time components (e.g., $s \ge 60.0$ on a non-leap-second epoch) returns `ERR` (`-1`) with diagnostic details in `serr`.

---

### Local Solar and Time-Zone Helpers

* **`utc_time_zone`**: Converts between local civil time and UTC:
  $$\text{Hour}_{\text{UTC}} = \text{Hour}_{\text{Local}} - \text{Timezone}_{\text{East}}$$
* **`time_equ`**: Computes the Equation of Time ($EoT$):
  $$EoT = \text{Apparent Solar Time} - \text{Mean Solar Time}$$
  Returns the offset in fractions of a day ($\approx -14\text{ to }+16\text{ minutes}$).
* **`lmt_to_lat` / `lat_to_lmt`**: Interconverts Local Mean Time ($LMT$) and Local Apparent Time ($LAT$, sundial time) for a given geographic longitude.

---

## 4. Dynamic Delta-T ($\Delta T$) and Secular Tidal Acceleration

The offset between uniform dynamic time ($TT$) and rotational time ($UT1$) is defined as:

$$\Delta T = TT - UT1$$

Swiss Ephemeris calculates $\Delta T$ through a combination of spline interpolations over historical eclipse records, modern IERS tabular observations, and long-term parabolic projections (Stephenson & Morrison, 1984; Stephenson, 1997; Stephenson et al., 2016).

### `deltat` and `deltat_ex`

```zig
// Zig Facades
pub fn deltat(tjd: f64, dctx: *DeltatCtx) f64
pub fn deltat_ex(tjd: f64, iflag: i32, serr: ?*[256]u8, dctx: *DeltatCtx) f64
```
```c
/* C Signatures */
double swe_deltat(double tjd);
double swe_deltat_ex(double tjd, int32_t iflag, char *serr);
```

* **Parameters & Units**: `tjd` is the Julian Day number. Return value is $\Delta T$ expressed in **days** (multiply by $86400.0$ to obtain SI seconds).
* **`deltat_ex` Configuration**: Evaluates tidal acceleration coupling matching the ephemeris mode specified in `iflag` (e.g., `SEFLG_SWIEPH`, `SEFLG_JPLEPH`).

---

### Tidal Acceleration Modifiers ($\dot{n}_\text{Moon}$)

Secular acceleration of the Moon due to oceanic tidal drag influences historical $\Delta T$ extrapolations:

```c
/* Set tidal secular acceleration (arcseconds per century squared) */
void swe_set_tid_acc(double t_acc);
double swe_get_tid_acc(void);
```

* **Standard Baselines**: `SE_TIDAL_DE431` ($-25.80''/\text{cy}^2$, default) vs. `SE_TIDAL_DE441` ($-25.936''/\text{cy}^2$).
* **Dynamic Derivation**: Setting `SE_TIDAL_AUTOMATIC` (`999999`) extracts the appropriate acceleration value directly from the active ephemeris header metadata.

---

### Manual User Override: `set_delta_t_userdef`

Forces a static or externally computed $\Delta T$ value:

```zig
// Set static Delta-T = 69.184 seconds
swe.set_delta_t_userdef(69.184 / 86400.0, &dctx);

// CRITICAL: Reset back to automatic interpolation when complete
swe.set_delta_t_userdef(swe.deltat.SE_DELTAT_AUTOMATIC, &dctx);
```

> [!CAUTION]
> **Global Poisoning Risk**  
> Leaving a manual $\Delta T$ active alters all subsequent planetary evaluations that rely on Universal Time (`swe_calc_ut`). Always reset the state in teardown blocks (`SE_DELTAT_AUTOMATIC = -1.0E-10`).
>
> **Historical Divergence**: Prior to 1000 BCE, different astronomical $\Delta T$ models diverge by multiple minutes. Published historical tables should state which model and tidal parameter were active.

---

## 5. Sidereal Time and Coordinate Transformations

### Greenwich Mean Sidereal Time (GMST)

Computes the rotational orientation of the Earth relative to the equinox.

```zig
// Zig Facades
pub fn sidtime(tjd_ut: f64, dctx: *DeltatCtx) f64
pub fn sidtime0(tjd_ut: f64, eps: f64, nut: f64) f64
pub fn set_interpolate_nut(b: bool, swed: *Swed) void
```
```c
/* C Signatures */
double swe_sidtime(double tjd_ut);
double swe_sidtime0(double tjd_ut, double eps, double nut);
void swe_set_interpolate_nut(int32_t b);
```

* **`sidtime(tjd_ut)`**: Evaluates GMST at the requested Julian Day UT. Returns sidereal time in **decimal hours** ($[0.0, 24.0)$).
* **`sidtime0(tjd_ut, eps, nut)`**: Standalone evaluator that bypasses internal ephemeris state by accepting true obliquity `eps` and nutation in longitude `nut` directly (in decimal degrees).
* **`set_interpolate_nut`**: Enables or disables daily nutation interpolation caching.

---

### Ecliptic $\leftrightarrow$ Equatorial Transformations: `cotrans`

Applies 3D rotation matrices to transition coordinates between the ecliptic and the celestial equator:

```zig
// Zig Facades
pub fn cotrans(xpo: *const [3]f64, xpn: *[3]f64, eps: f64) void
pub fn cotrans_sp(xpo: *const [6]f64, xpn: *[6]f64, eps: f64) void
```
```c
/* C Signatures */
void swe_cotrans(const double *xpo, double *xpn, double eps);
void swe_cotrans_sp(const double *xpo, double *xpn, double eps);
```

* **The Obliquity Sign Rule**:
  * Pass **$+\epsilon$** (positive true obliquity) to transform **Ecliptic coordinates $\rightarrow$ Equatorial coordinates**:
    $$\text{Longitude } (\lambda), \text{Latitude } (\beta) \longrightarrow \text{Right Ascension } (\alpha), \text{Declination } (\delta)$$
  * Pass **$-\epsilon$** (negative true obliquity) to transform **Equatorial coordinates $\rightarrow$ Ecliptic coordinates**:
    $$\text{Right Ascension } (\alpha), \text{Declination } (\delta) \longrightarrow \text{Longitude } (\lambda), \text{Latitude } (\beta)$$
* **`cotrans_sp`**: Extends the rotation across the velocity components (`xx[3..5]`), transforming daily rates of change alongside positions.

---

## 6. Angular Utilities and Formatting Routines

### Normalization and Separation

| Routine (Zig / C) | Input Units | Output Range | Description |
| :--- | :--- | :--- | :--- |
| `degnorm` / `swe_degnorm` | Degrees | $[0.0^\circ, 360.0^\circ)$ | Normalizes any real angle into a single circle. |
| `radnorm` / `swe_radnorm` | Radians | $[0.0, 2\pi)$ | Normalizes an angle in radians. |
| `deg_midp` / `swe_deg_midp` | Degrees | $[0.0^\circ, 360.0^\circ)$ | Computes the shortest-arc angular midpoint between two coordinates. |
| `rad_midp` / `swe_rad_midp` | Radians | $[0.0, 2\pi)$ | Computes the shortest-arc angular midpoint in radians. |
| `difdegn` / `swe_difdegn` | Degrees | $[0.0^\circ, 360.0^\circ)$ | Directed angular difference ($\text{deg}_1 - \text{deg}_2$). |
| `difdeg2n` / `swe_difdeg2n` | Degrees | $[-180.0^\circ, +180.0^\circ)$ | Shortest signed distance between two angles. |
| `difrad2n` / `swe_difrad2n` | Radians | $[-\pi, +\pi)$ | Shortest signed distance between two angles in radians. |

---

### Degree Splitting: `split_deg`

Decomposes a floating-point coordinate into base-60 sexagesimal subdivisions.

```zig
// Zig Facade
pub fn split_deg(
    ddeg: f64, roundflag: i32,
    deg: *i32, min: *i32, sec: *i32, dsec: *f64, sign: *i32
) void
```
```c
/* C Signature */
void swe_split_deg(
    double ddeg, int32_t roundflag,
    int32_t *ideg, int32_t *imin, int32_t *isec, double *dsecfrac, int32_t *isgn
);
```

* **Modifier Bitmask (`roundflag`)**: Accepts configuration constants from `SE_SPLIT_DEG_*`:
  * `ROUND_SEC` (`1`), `ROUND_MIN` (`2`), `ROUND_DEG` (`4`).
  * `ZODIACAL` (`8`): Outputs zero-indexed zodiac sign ($[0, 11]$) into `sign` and relative degrees ($[0^\circ, 30^\circ)$) into `deg`.
  * `NAKSHATRA` (`1024`): Splits into 27 lunar mansions ($13^\circ 20'$ each).
  * `KEEP_SIGN` (`16`): Suppresses rounding carry-over across zodiac sign boundaries (clamps $29^\circ 59' 59.9''$ to $29^\circ 59' 60''$ rather than shifting into $0^\circ$ of the next sign).

---

### Legacy Placalc Centisecond Primitives (`cs*`)

The `swephlib` module retains legacy integer centisecond utilities (where $1^\circ = 360{,}000\text{ centiseconds}$):
* Normalization and math: `swe_csnorm`, `swe_difcsn`, `swe_difcs2n`, `swe_csroundsec`, `swe_d2l`.
* Calendar: `swe_day_of_week` (returns day of week where $\text{Monday} = 0, \dots, \text{Sunday} = 6$).
* String serialization: `swe_cs2timestr`, `swe_cs2lonlatstr`, `swe_cs2degstr`.

*Recommendation*: These functions are maintained for backward compatibility with legacy Placalc codebases. New systems should use standard floating-point operations.

---

## 7. Verification Invariants and Test Assertions

Automated test suites can confirm engine integrity by validating these mathematical and functional round-trips:

1. **Calendar Inversion**:
   ```zig
   var y: i32 = undefined; var m: i32 = undefined; var d: i32 = undefined; var h: f64 = undefined;
   const target_jd = 2451545.0;
   swe.revjul(target_jd, swe.swedate.SE_GREG_CAL, &y, &m, &d, &h);
   try std.testing.expectEqual(target_jd, swe.julday(y, m, d, h, swe.swedate.SE_GREG_CAL));
   ```

2. **Coordinate Frame Orthogonality**:
   ```zig
   var x_equ: [3]f64 = undefined;
   var x_ecl: [3]f64 = undefined;
   const x_orig = [3]f64{ 124.5, 12.3, 1.05 }; // Longitude, Latitude, Distance
   const eps = 23.4392911;

   // Forward transform: Ecliptic -> Equatorial (+eps)
   swe.cotrans(&x_orig, &x_equ, eps);

   // Reverse transform: Equatorial -> Ecliptic (-eps)
   swe.cotrans(&x_equ, &x_ecl, -eps);

   try std.testing.expectApproxEqAbs(x_orig[0], x_ecl[0], 1e-10);
   try std.testing.expectApproxEqAbs(x_orig[1], x_ecl[1], 1e-10);
   try std.testing.expectApproxEqAbs(x_orig[2], x_ecl[2], 1e-10);
   ```
