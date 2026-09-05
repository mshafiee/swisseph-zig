# Functions: Eclipses, Occultations, Rise/Transit, Phenomena, Azalt, and Orbitals

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Common Calling Conventions

* **C Declarations**: `include/swephexp.h:843`. Functions maintain thread-local state (`SweState`) and use the `swe_` prefix.
* **Zig Implementation**: Core mechanics implemented in `src/swecl.zig`, re-exported through the primary facade in `src/swisseph.zig:53`. Context dependencies are injected explicitly via `swed: *Swed`, `models: AstroModels`, and `dctx: *DeltatCtx`.
* **Directional Iteration (`backward`)**:
  * `false` (or `0` in C): Evaluates forward in time ($t > t_0$).
  * `true` (or `1` in C): Evaluates backward into historical time ($t < t_0$).
* **Observer Geographic Vector (`geopos[3]`)**:
  * `geopos[0]`: Geographic longitude in decimal degrees (positive East: $[-180^\circ, +180^\circ]$).
  * `geopos[1]`: Geographic latitude in decimal degrees (positive North: $[-90^\circ, +90^\circ]$).
  * `geopos[2]`: Height above sea level in meters ($\text{m}$).
* **Array Layout References**:
  * `tret[10]`: Transition timestamps (Julian Days in TT or UT). Index `[0]` = Maximum eclipse/transit; `[1..4]` = Exterior and interior contacts $C_1 \dots C_4$; `[5..6]` = Penumbral contact boundaries.
  * `attr[20]`: Phenomenological properties. Index `[0]` = Fraction of diameter covered (magnitude); `[1]` = Obscuration (area fraction); `[2]` = Diameter ratio; `[3..4]` = True solar azimuth and elevation; `[5]` = Gamma ($\Gamma$); `[6]` = Saros series; `[7]` = Central phase duration in seconds.

---

## 2. Solar and Lunar Eclipse Solvers

The eclipse calculation suite provides global search solvers, local circumstance predictors, and instantaneous snapshot evaluators.

```
  Search Solvers (Iterate across Syzygies)       Snapshot Solvers (Fixed Epoch tjd)
  ────────────────────────────────────────       ───────────────────────────────────
  sol_eclipse_when_glob() ──> Next Earth-wide    sol_eclipse_where() ──> Sub-solar / path
  sol_eclipse_when_loc()  ──> Next at observer   sol_eclipse_how()   ──> Local disc status
  lun_eclipse_when_loc()  ──> Next visible Moon  lun_occult_where()  ──> Occultation track
```

### Global Solar Search: `sol_eclipse_when_glob`
Searches forward or backward for the next solar eclipse anywhere on Earth matching an eclipse type filter.

```zig
// Zig Facade
pub fn sol_eclipse_when_glob(
    tjd_start: f64,
    iflag: i32,
    ifltype: i32,
    tret: *[10]f64,
    backward: bool,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_sol_eclipse_when_glob(
    double tjd_start,
    int32_t iflag,
    int32_t ifltype,
    double *tret,
    int32_t backward,
    char *serr
);
```

* **Filter Optimization (`ifltype`)**: Restricting `ifltype` to specific geometries (e.g., `SE_ECL_TOTAL`, `SE_ECL_ANNULAR`) significantly accelerates execution. Passing `ifltype = 0` checks all eclipse types sequentially across successive new moons.
* **Return Value**: Returns the bitmask of the detected eclipse geometry (`SE_ECL_*`) on success. Returns `ERR` (`-1`) if no qualifying eclipse is found within the active ephemeris bounds.

---

### Local Solar Circumstances: `sol_eclipse_when_loc`
Computes the next solar eclipse observable from a specific terrestrial station.

```zig
// Zig Facade
pub fn sol_eclipse_when_loc(
    tjd_start: f64,
    iflag: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: bool,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_sol_eclipse_when_loc(
    double tjd_start,
    int32_t iflag,
    double *geopos,
    double *tret,
    double *attr,
    int32_t backward,
    char *serr
);
```

* **Behavior**: Evaluates topocentric lunar parallax relative to the solar disc. If an eclipse occurs globally but remains below the observer's horizon or outside the penumbral footprint, the solver iterates forward until a locally visible event occurs.

---

### Lunar Eclipses: `lun_eclipse_when_loc` and `lun_eclipse_how`
Solves for umbral and penumbral immersions of the Moon into Earth's shadow.

```zig
// Zig Facade
pub fn lun_eclipse_when_loc(
    tjd_start: f64,
    iflag: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: bool,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_lun_eclipse_when_loc(
    double tjd_start,
    int32_t iflag,
    double *geopos,
    double *tret,
    double *attr,
    int32_t backward,
    char *serr
);
```

* **Local Horizon Gating**: `lun_eclipse_when_loc` verifies that the Moon is above the local refracted horizon during at least one contact phase. To evaluate pure geocentric shadow crossings regardless of local visibility, call `lun_eclipse_when_glob`.

---

### Instantaneous Eclipse Snapshots: `sol_eclipse_where` and `sol_eclipse_how`
Evaluate geometry at a specific instant without scanning temporal windows.

* **`sol_eclipse_where(tjd, iflag, &geopos, &attr, ...)`**: Calculates the geographic coordinates of the central path (sub-solar point / maximum eclipse point) on Earth for epoch `tjd`.
* **`sol_eclipse_how(tjd, iflag, geopos, &attr, ...)`**: Computes the instantaneous eclipse obscuration, apparent separation, and contact status at observer position `geopos` for epoch `tjd`.

```zig
// Example: Find the next total solar eclipse globally
var tret: [10]f64 = undefined;
var serr: [256]u8 = undefined;

const eclipse_type = swe.sol_eclipse_when_glob(
    jd_start,
    swe.sweph.SEFLG_SWIEPH,
    swe.swecl.SE_ECL_TOTAL,
    &tret,
    false, // search forward
    &serr,
    &swed,
    models,
    &dctx,
);

if (eclipse_type < 0) {
    // Search exceeded ephemeris bounds without matching criteria
}
```

---

## 3. Lunar Occultations and Gauquelin Sectors

### Lunar Occultations: `lun_occult_when_glob` and `lun_occult_when_loc`
Evaluates topocentric lunar occultations of planets or catalog fixed stars.

```zig
// Zig Facade
pub fn lun_occult_when_loc(
    tjd_start: f64,
    ipl: i32,
    starname: ?[*:0]const u8,
    iflag: i32,
    geopos: *const [3]f64,
    tret: *[10]f64,
    attr: *[20]f64,
    backward: bool,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_lun_occult_when_loc(
    double tjd_start,
    int32_t ipl,
    char *starname,
    int32_t iflag,
    double *geopos,
    double *tret,
    double *attr,
    int32_t backward,
    char *serr
);
```

* **Target Selection**:
  * Pass valid body index into `ipl` (e.g., `SE_MARS`) and set `starname = null` to target a planet.
  * Pass `ipl = SE_FIXSTAR` and supply a star identifier in `starname` (e.g., `"Aldebaran"`) to target a fixed star from `sefstars.txt`.
* **Single-Conjunction Constraint (`SE_ECL_ONE_TRY`)**: Bitwise OR `SE_ECL_ONE_TRY` into `iflag` to restrict evaluation exclusively to the immediate upcoming conjunction. If the target body bypasses the lunar limb without an occultation, the solver halts immediately without iterating across subsequent orbital periods.

---

### `gauquelin_sector`
Calculates statistical diurnal sector positions ($1\text{ to }36$) based on diurnal semi-arcs.

```zig
// Zig Facade
pub fn gauquelin_sector(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[*:0]const u8,
    iflag: i32,
    imeth: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    dgsect: *[3]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_gauquelin_sector(
    double t_ut,
    int32_t ipl,
    char *starname,
    int32_t iflag,
    int32_t imeth,
    double *geopos,
    double atpress,
    double attemp,
    double *dgsect,
    char *serr
);
```

* **Sector Methods (`imeth`)**:
  * `0`: Standard sector position using modified diurnal arcs ($[1.0, 36.0]$).
  * `1`: Classical Gauquelin sector definition without geographic latitude modifications.
  * `2` / `3`: Sector mappings derived from plane projections and right ascension semi-arcs.
* **Output Vector (`dgsect[3]`)**:
  * `dgsect[0]`: Primary sector index ($1.0 \le s < 37.0$).
  * `dgsect[1]`: Equivalent sector normalized to a 12-house framework ($1.0 \le h < 13.0$).
  * `dgsect[2]`: Diurnal arc fraction ($0.0 \le f < 1.0$).

---

## 4. Rise, Set, and Meridian Transit Solvers

Calculates local observer horizon crossings and meridian culminations.

```zig
// Zig Facades
pub fn rise_trans(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[*:0]const u8,
    epheflag: i32,
    rsmi: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    tret: *[2]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32

pub fn rise_trans_true_hor(
    tjd_ut: f64,
    ipl: i32,
    starname: ?[*:0]const u8,
    epheflag: i32,
    rsmi: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    horhgt: f64,
    tret: *[2]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signatures */
int32_t swe_rise_trans(
    double tjd_ut,
    int32_t ipl,
    char *starname,
    int32_t epheflag,
    int32_t rsmi,
    double *geopos,
    double atpress,
    double attemp,
    double *tret,
    char *serr
);

int32_t swe_rise_trans_true_hor(
    double tjd_ut,
    int32_t ipl,
    char *starname,
    int32_t epheflag,
    int32_t rsmi,
    double *geopos,
    double atpress,
    double attemp,
    double horhgt,
    double *tret,
    char *serr
);
```

* **Event Output (`tret[2]`)**:
  * For rising/setting queries (`SE_CALC_RISE`, `SE_CALC_SET`): `tret[0]` returns the exact Julian Day UT of the horizon crossing.
  * For meridian transit queries (`SE_CALC_MTRANSIT`, `SE_CALC_ITRANSIT`): `tret[0]` returns the transit culmination time.
* **Atmospheric Vacuum Mode**: Setting `atpress = 0.0` disables refraction models, treating the horizon as an airless geometric plane.
* **Circumpolar Failure Path**: If the body never crosses the horizon (e.g., perpetual midnight sun or circumpolar stars), the function returns `ERR` (`-1`) and writes `"body never rises"` or `"body never sets"` into `serr`. This condition must be caught explicitly rather than treated as a fatal software crash.

---

## 5. Horizontal Transformations and Atmospheric Refraction

### Celestial $\leftrightarrow$ Horizontal Transformations: `azalt` and `azalt_rev`

Rotates coordinates between equatorial/ecliptic systems and the observer's local horizontal horizon plane.

```zig
// Zig Facades
pub fn azalt(
    tjd_ut: f64,
    calc_flag: i32,
    geopos: *const [3]f64,
    atpress: f64,
    attemp: f64,
    xin: *const [3]f64,
    xaz: *[3]f64,
    dctx: *DeltatCtx,
) void

pub fn azalt_rev(
    tjd_ut: f64,
    calc_flag: i32,
    geopos: *const [3]f64,
    xaz: *const [3]f64,
    xin: *[3]f64,
    dctx: *DeltatCtx,
) void
```
```c
/* C Signatures */
void swe_azalt(
    double tjd_ut,
    int32_t calc_flag,
    double *geopos,
    double atpress,
    double attemp,
    double *xin,
    double *xaz
);

void swe_azalt_rev(
    double tjd_ut,
    int32_t calc_flag,
    double *geopos,
    double *xaz,
    double *xin
);
```

* **Frame Selection (`calc_flag`)**:
  * `SE_ECL2HOR` (`0`): `xin[3]` is treated as Ecliptic Longitude, Latitude, Distance.
  * `SE_EQU2HOR` (`1`): `xin[3]` is treated as Right Ascension, Declination, Distance.
* **Output Vectors**:
  * `xaz[0]`: Local Azimuth ($0^\circ \le \text{Az} < 360^\circ$; measured from **South** eastward/westward: $0^\circ = \text{South}$, $90^\circ = \text{West}$, $180^\circ = \text{North}$, $270^\circ = \text{East}$).
  * `xaz[1]`: True geometric altitude without atmospheric refraction ($[-90^\circ, +90^\circ]$).
  * `xaz[2]`: Apparent observed altitude including atmospheric refraction.

---

### Atmospheric Refraction Primitives

Evaluates angular ray-bending caused by Earth's atmospheric pressure and temperature gradient.

```zig
// Zig Facades
pub fn refrac(inalt: f64, atpress: f64, attemp: f64, dir: i32) f64

pub fn refrac_extended(
    inalt: f64,
    atpress: f64,
    attemp: f64,
    geoalt: f64,
    lapse_rate: f64,
    dir: i32,
    dret: *[4]f64,
) f64

pub fn set_lapse_rate(lapse_rate: f64, swed: *Swed) void
```
```c
/* C Signatures */
double swe_refrac(double inalt, double atpress, double attemp, int32_t dir);
double swe_refrac_extended(
    double inalt,
    double atpress,
    double attemp,
    double geoalt,
    double lapse_rate,
    int32_t dir,
    double *dret
);
void swe_set_lapse_rate(double lapse_rate);
```

* **Direction Mode (`dir`)**:
  * `SE_TRUE_TO_APP` (`0`): Geometric altitude $\rightarrow$ Apparent altitude ($h_{\text{app}} = h_{\text{true}} + R$).
  * `SE_APP_TO_TRUE` (`1`): Observed apparent altitude $\rightarrow$ Geometric altitude ($h_{\text{true}} = h_{\text{app}} - R$).
* **Lapse Rate Configuration**: `set_lapse_rate()` configures the vertical temperature gradient $dT/dz$ in Kelvin per meter. The international standard atmosphere baseline is `SE_LAPSE_RATE = 0.0065\text{ K/m}$ ($6.5\text{ K/km}$).

---

## 6. Planetary Phenomena, Nodes, and Keplerian Elements

### Planetary Phenomena: `pheno` and `pheno_ut`
Computes phase angle, disc illumination fraction, apparent brightness, and angular diameter.

```zig
// Zig Facade
pub fn pheno_ut(
    tjd_ut: f64,
    ipl: i32,
    iflag: i32,
    attr: *[20]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_pheno_ut(
    double tjd_ut,
    int32_t ipl,
    int32_t iflag,
    double *attr,
    char *serr
);
```

* **Phenomenon Vector (`attr[20]`)**:
  * `attr[0]`: Phase angle in degrees ($[0^\circ, 180^\circ]$).
  * `attr[1]`: Phase / illuminated fraction of the disc ($[0.0, 1.0]$).
  * `attr[2]`: Solar elongation angle in degrees ($[0^\circ, 180^\circ]$).
  * `attr[3]`: Apparent angular diameter in arcseconds (uses `pla_diam[]`).
  * `attr[4]`: Apparent visual magnitude ($V$). For Saturn, includes photometric ring inclination and tilt contributions.

---

### Orbital Nodes and Apsides: `nod_aps` and `nod_aps_ut`
Computes the ascending node, descending node, perihelion/perigee, and aphelion/apogee vectors.

```zig
// Zig Facade
pub fn nod_aps_ut(
    tjd_ut: f64,
    ipl: i32,
    iflag: i32,
    method: i32,
    nasc: *[6]f64,
    ndsc: *[6]f64,
    peri: *[6]f64,
    aph: *[6]f64,
    serr: *[256]u8,
    swed: *Swed,
    models: AstroModels,
    dctx: *DeltatCtx,
) i32
```
```c
/* C Signature */
int32_t swe_nod_aps_ut(
    double tjd_ut,
    int32_t ipl,
    int32_t iflag,
    int32_t method,
    double *nasc,
    double *ndsc,
    double *peri,
    double *aph,
    char *serr
);
```

* **Method Selector (`method`)**: Configured via `SE_NODBIT_*`:
  * `SE_NODBIT_MEAN` (`1`): Secular mean nodes and apsides.
  * `SE_NODBIT_OSCU` (`2`): Instantaneous osculating two-body state.
  * `SE_NODBIT_FOPOINT` (`256`): Replaces the aphelion/apogee coordinate array (`aph`) with the spatial coordinates of the empty second focal point of the Keplerian ellipse.
* **Coordinate Output**: Arrays `nasc`, `ndsc`, `peri`, and `aph` each populate a complete 6-element coordinate vector ($\lambda, \beta, r, \dot{\lambda}, \dot{\beta}, \dot{r}$).

---

### Analytic Orbital Elements: `get_orbital_elements` and `orbit_max_min_true_distance`

Extracts osculating Keplerian orbital parameters and radial distance extrema:

```c
/* C Signatures */
int32_t swe_get_orbital_elements(
    double tjd,
    int32_t ipl,
    int32_t iflag,
    double *dret,
    char *serr
);

int32_t swe_orbit_max_min_true_distance(
    double tjd,
    int32_t ipl,
    int32_t iflag,
    double *dmax,
    double *dmin,
    double *dtrue,
    char *serr
);
```

* **Orbital Elements Vector (`dret[20]`)**:
  * `dret[0]`: Semi-major axis ($a$, in AU).
  * `dret[1]`: Eccentricity ($e$, dimensionless).
  * `dret[2]`: Inclination ($i$, in degrees).
  * `dret[3]`: Longitude of the ascending node ($\Omega$, in degrees).
  * `dret[4]`: Argument of perihelion ($\omega$, in degrees).
  * `dret[5]`: Mean anomaly at epoch ($M_0$, in degrees).
  * `dret[6]`: True anomaly ($\nu$, in degrees).
  * `dret[7]`: Orbital period ($P$, in tropical years).
* **Distance Extrema Output**: Populates maximum distance at aphelion (`dmax`), minimum distance at perihelion (`dmin`), and instantaneous true radial distance (`dtrue`) in Astronomical Units.

---

## 7. Verification Invariants and Test Patterns

Automated validation suites should assert the following physical and mathematical constraints:

1. **Horizontal Transformation Reversibility**:
   ```zig
   var xaz: [3]f64 = undefined;
   var xin_rev: [3]f64 = undefined;
   const xin = [3]f64{ 85.25, -12.33, 1.25 }; // RA, Dec, Dist
   const geopos = [3]f64{ 8.5417, 47.3769, 410.0 };

   // Forward transformation: Equatorial -> Horizontal
   swe.azalt(jd_ut, swe.sweph.SE_EQU2HOR, &geopos, 1013.25, 10.0, &xin, &xaz, &dctx);

   // Inverse transformation: Horizontal -> Equatorial
   swe.azalt_rev(jd_ut, swe.sweph.SE_EQU2HOR, &geopos, &xaz, &xin_rev, &dctx);

   try std.testing.expectApproxEqAbs(xin[0], xin_rev[0], 1e-9);
   try std.testing.expectApproxEqAbs(xin[1], xin_rev[1], 1e-9);
   try std.testing.expectApproxEqAbs(xin[2], xin_rev[2], 1e-9);
   ```

2. **Snapshot and Circumstance Validation**:
   * Always verify that `eclipse_type >= 0` before reading from `tret[10]` or `attr[20]`.
   * For local horizon crossings (`rise_trans`), catch return code `-1` explicitly to handle circumpolar conditions without halting execution.
