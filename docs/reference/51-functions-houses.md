# Functions: House Cusps and Gauquelin Sectors

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Reduction Pipelines

House cusp calculations project spatial quadrant divisions onto the celestial sphere. Swiss Ephemeris exposes both high-level, date-driven convenience APIs and decoupled, coordinate-driven engines:

* **Source Truth**: `include/swephexp.h:812`.
* **Zig Modules**: Core geometric algorithms in `src/swehouse.zig`; top-level facade in `src/swisseph.zig:47`.
* **Architecture Distinction (Zig vs. C)**:
  * **C API (`swe_houses_ex2`)**: Accepts Julian Day and geographic coordinates. It calculates GMST, nutation, true obliquity of the ecliptic ($\epsilon$), and Right Ascension of the Midheaven (ARMC) internally before computing cusps.
  * **Zig API (`houses_armc_ex2`)**: Decouples sidereal-time and nutation reductions from house geometry. Callers provide `armc`, `lat`, and `eps` directly alongside a thread-safe workspace (`HouseCtx`). This avoids redundant orbital reductions when generating multiple house system overlays for the same epoch.

---

## 2. Buffer Specifications and Symbolic Offsets

House calculations populate two primary double-precision output slices: `cusps[37]` and `ascmc[10]`.

### 2.1 Cusp Array: `cusps[37]`
* **1-Based Indexing**: `cusps[0]` is unused and set to `0.0`.
* **Standard 12-House Systems**: Populates indices `cusps[1]` through `cusps[12]`. Indices `[13..36]` are set to `0.0`.
* **Gauquelin Sector System (`'G'`)**: Populates indices `cusps[1]` through `cusps[36]`.

```
  cusps Array Layout
  ┌──────────┬──────────┬──────────┬──────────┬─────┬───────────┬──────────┬─────┬───────────┐
  │ cusps[0] │ cusps[1] │ cusps[2] │ cusps[3] │ ... │ cusps[12] │ cusps[13]│ ... │ cusps[36] │
  │  Unused  │  House 1 │  House 2 │  House 3 │     │  House 12 │ Sector 13│     │ Sector 36 │
  └──────────┴──────────┴──────────┴──────────┴─────┴───────────┴──────────┴─────┴───────────┘
```

---

### 2.2 Angular Point Vector: `ascmc[10]`

Stores the primary celestial angles, horizon intersections, and auxiliary polar points:

| Index | Macro Identifier | Output Quantity | Coordinate & Physical Definition |
| :---: | :--- | :--- | :--- |
| `[0]` | `SE_ASC` | **Ascendant (ASC)** | Intersection of the eastern horizon with the ecliptic. |
| `[1]` | `SE_MC` | **Midheaven (MC)** | Medium Coeli; intersection of the local celestial meridian with the ecliptic. |
| `[2]` | `SE_ARMC` | **ARMC** | Right Ascension of the Midheaven ($\alpha_{\text{MC}}$) in degrees ($[0^\circ, 360^\circ)$). |
| `[3]` | `SE_VERTEX` | **Vertex** | Western intersection of the local prime vertical with the ecliptic. |
| `[4]` | `SE_EQUASC` | **Equatorial Ascendant** | "East Point"; right ascension of the Ascendant projected onto the celestial equator. |
| `[5]` | `SE_COASC1` | **Co-Ascendant (Koch)** | Auxiliary polar ascendant defined by Walter Koch. |
| `[6]` | `SE_COASC2` | **Co-Ascendant (Munkasey)**| Auxiliary equatorial angle defined by Michael Munkasey. |
| `[7]` | `SE_POLASC` | **Polar Ascendant** | Polar Ascendant defined by Michael Munkasey. |
| `[8]` | `SE_NASCMC` | **Array Dimension** | Number of valid angular points ($8$ defined items, slots `[8..9]` reserved). |

---

## 3. Supported House Systems (`hsys`)

House systems are selected using an ASCII character passed as a byte or integer:

| Char | System Name | Mathematical Division Basis | Polar Status ($|\phi| \ge 66.5^\circ$) |
| :---: | :--- | :--- | :--- |
| `'P'` | **Placidus** | Semi-diurnal and semi-nocturnal time arcs. | **Fails** (Singularities at quadrant circles). |
| `'K'` | **Koch** | Ascensional difference increments along diurnal arc. | **Fails** (Horizon plane parallel to equator). |
| `'O'` | **Porphyry** | Trisection of ecliptic arc between ASC and MC. | **Polar Safe** (Calculable globally). |
| `'R'` | **Regiomontanus** | Equal $30^\circ$ trisection of the Celestial Equator. | **Fails** (Meridian/horizon alignment). |
| `'C'` | **Campanus** | Equal $30^\circ$ trisection of the Prime Vertical. | **Fails** (Prime vertical horizon alignment). |
| `'E'` | **Equal** | $30^\circ$ ecliptic segments measured from Ascendant. | **Polar Safe** (Unconditional). |
| `'V'` | **Vehlow Equal** | Equal houses with Ascendant positioned at $15^\circ$ of House 1. | **Polar Safe** (Unconditional). |
| `'W'` | **Whole Sign** | House 1 spans $0^\circ \dots 30^\circ$ of the sign containing ASC. | **Polar Safe** (Unconditional). |
| `'X'` | **Meridian / Axial** | Equal $30^\circ$ equatorial divisions measured from MC. | **Polar Safe** (Independent of horizon). |
| `'H'` | **Horizon / Azimuthal** | Equal $30^\circ$ division of the Horizon plane. | **Polar Safe** (Horizon system). |
| `'T'` | **Topocentric** | Polich-Page empirical trisection of rotation angles. | **Fails** (Polar asymptote limit). |
| `'B'` | **Alcabitius** | Trisection of right ascension diurnal semi-arc. | **Fails** (Polar divergence). |
| `'M'` | **Morinus** | Equal $30^\circ$ equatorial divisions projected onto ecliptic. | **Polar Safe** (Equatorial basis). |
| `'U'` | **Krusinski** | Trisection of great circle through ASC and Zenith. | **Polar Safe** (Well-conditioned geometry). |
| `'G'` | **Gauquelin Sectors** | Diurnal semi-arc division into 36 statistical sectors. | **Fails** (Polar day/night arc breakdown). |
| `'A'` | **Equal (MC)** | Equal houses measured relative to the Midheaven. | **Polar Safe** (Independent of horizon). |

---

## 4. API Signatures and Usage Patterns

### 4.1 Preferred Production Engines

#### C: `swe_houses_ex2`
Computes cusps, primary angles, and their instantaneous daily velocities.

```c
int swe_houses_ex2(
    double tjd_ut,
    int32_t iflag,
    double geolat,
    double geolon,
    int hsys,
    double *cusps,
    double *ascmc,
    double *cusp_speed,
    double *ascmc_speed,
    char *serr
);
```

#### Zig: `houses_armc_ex2`
The primary Zig house engine. Accepts precomputed coordinates and explicit contexts.

```zig
pub fn houses_armc_ex2(
    armc: f64,
    geolat: f64,
    eps: f64,
    hsys: u8,
    cusps: *[37]f64,
    ascmc: *[10]f64,
    cusp_speed: ?*[37]f64,
    ascmc_speed: ?*[10]f64,
    serr: ?*[256]u8,
    hctx: *HouseCtx,
) i32
```

* **Parameters & Units**:
  * `tjd_ut`: Target Julian Day UT.
  * `geolat` / `geolon`: Geographic latitude and longitude in decimal degrees (positive North and East).
  * `armc`: Right Ascension of the Midheaven in degrees ($[0^\circ, 360^\circ)$).
  * `eps`: True obliquity of the ecliptic ($\epsilon$) in decimal degrees (e.g., from `swe_calc` using `SE_ECL_NUT`).
  * `hsys`: House system character code (`'P'`, `'K'`, etc.).
  * `cusp_speed` / `ascmc_speed`: Optional arrays returning instantaneous speeds in degrees per day ($^\circ/\text{day}$). Passing `null` / `NULL` skips numerical velocity differentiation.
  * `hctx`: House evaluation context (`swe.swehouse.HouseCtx{}`).

---

### 4.2 Implementation Examples

```zig
// Zig: Compute Placidus houses directly from ARMC
const swe = @import("swisseph");

var cusps: [37]f64 = undefined;
var ascmc: [10]f64 = undefined;
var cusp_spd: [37]f64 = undefined;
var ascmc_spd: [10]f64 = undefined;
var serr: [256]u8 = undefined;
var hctx = swe.swehouse.HouseCtx{};

const status = swe.houses_armc_ex2(
    armc,
    lat,
    eps,
    'P', // Placidus
    &cusps,
    &ascmc,
    &cusp_spd,
    &ascmc_spd,
    &serr,
    &hctx,
);

if (status < 0) {
    // Polar latitude singularity: handle fallback
}
```

```c
/* C equivalent */
#include "sweph.h"

double cusps[37];
double ascmc[10];
double cusp_spd[37];
double ascmc_spd[10];
char serr[256];

int status = swe_houses_ex2(
    jd_ut,
    0, // Standard apparent tropical frame
    lat,
    lon,
    'P',
    cusps,
    ascmc,
    cusp_spd,
    ascmc_spd,
    serr
);

if (status < 0) {
    /* Polar latitude failure; inspect serr */
}
```

---

### 4.3 Legacy and Simplified APIs

* **`houses(tjd_ut, lat, lon, hsys, cusps, ascmc)`**: Legacy basic solver. Bypasses speeds, flag adjustments, and error buffers. Retained for simple UI displays.
* **`houses_ex(tjd_ut, iflag, lat, lon, hsys, cusps, ascmc)`**: Adds `iflag` support (`SEFLG_SIDEREAL`, `SEFLG_RADIANS`), but omits daily velocities.
* **`houses_armc(armc, lat, eps, hsys, cusps, ascmc)`**: Basic coordinate-driven API without speed derivatives.
* **`house_name(hsys)`**: Returns the canonical ASCII display string for the specified house system character code (e.g., `'P'` $\rightarrow$ `"Placidus"`).

---

## 5. Celestial Coordinate Placement: `house_pos`

Calculates the exact fractional house placement of a celestial body given its ecliptic coordinates.

```zig
// Zig Facade
pub fn house_pos(
    armc: f64,
    geolat: f64,
    eps: f64,
    hsys: u8,
    xpin: *const [2]f64,
    serr: *[256]u8,
) f64
```
```c
/* C Signature */
double swe_house_pos(
    double armc,
    double geolat,
    double eps,
    int hsys,
    double *xpin,
    char *serr
);
```

* **Parameters & Units**:
  * `xpin[0]`: Ecliptic longitude of the body ($\lambda$) in degrees.
  * `xpin[1]`: Ecliptic latitude of the body ($\beta$) in degrees.
* **Return Value**:
  * **12-House Systems**: Returns a floating-point value $h \in [1.0, 13.0)$. An output of $1.50$ places the body halfway through the 1st house; $12.99$ places the body near the end of the 12th house (approaching the cusp of House 1).
  * **Gauquelin System (`'G'`)**: Returns a sector position $s \in [1.0, 37.0)$.
* **Error Behavior**: Returns `0.0` on failure and writes error details to `serr`.

---

## 6. Polar Latitudes, Singularities, and Fallback Strategies

### 6.1 Polar Failures in Semi-Arc Systems

Systems relying on diurnal and nocturnal semi-arc trisection—such as **Placidus (`'P'`)**, **Koch (`'K'`)**, and **Topocentric (`'T'`)**—break down within the Arctic and Antarctic circles ($|\phi| \ge 66^\circ 34'$):

1. **Circumpolar Intersections**: The ecliptic no longer crosses the horizon twice daily; large swaths of the zodiac either never rise or never set.
2. **Quadrant Circle Parallelism**: Under extreme geographic tilts, quadrant division curves become tangent to or fail to intersect the horizon, causing iterative root solvers to diverge.

When this occurs, the function returns `ERR` (`-1`) and writes a warning message to `serr`.

---

### 6.2 Recommended Polar Fallback Strategy

Applications evaluating charts near or above the polar circles must detect `status < 0` and route execution to a polar-safe house system:

```zig
// Production pattern: Polar-safe fallback chain
var status = swe.houses_armc_ex2(
    armc, lat, eps, 'P', &cusps, &ascmc, &cusp_spd, &ascmc_spd, &serr, &hctx
);

if (status < 0) {
    // Placidus singular: Fallback to Porphyry ('O') or Whole Sign ('W')
    status = swe.houses_armc_ex2(
        armc, lat, eps, 'O', &cusps, &ascmc, &cusp_spd, &ascmc_spd, &serr, &hctx
    );
}
```

* **Recommended Polar Alternatives**:
  * **Porphyry (`'O'`)**: Preserves true ASC and MC axes while dividing ecliptic quadrants evenly.
  * **Whole Sign (`'W'`)**: Aligns houses cleanly to zodiac sign boundaries based on the sign containing the Ascendant.
  * **Equal (`'E'`)**: Projects $30^\circ$ increments directly from the Ascendant.
  * **Meridian (`'X'`)**: Uses the Midheaven as an anchor, remaining unaffected by geographic horizon tilt.

---

### 6.3 System-Specific Nuances

* **Topocentric (`'T'`)**: Must be paired with valid topocentric observer coordinates if evaluating with topocentric planetary positions.
* **Sunshine / Treindl System (`'I'`)**: Requires an active `HouseCtx` in Zig or internal thread state in C. If context state is absent, the engine falls back silently to **Porphyry (`'O'`)**.
* **Speed Derivative Invariant**: Accurate cusp and angle velocities ($^\circ/\text{day}$) are computed exclusively via the `*_ex2` functions (`swe_houses_ex2` / `houses_armc_ex2`). Simplified APIs set velocity arrays to zero.
