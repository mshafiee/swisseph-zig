# Bodies 0–22 and Special Points

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Reduction Pipeline

The core catalog comprises planetary bodies, orbital nodes, dynamic apsides, and reduction probes indexed from `-1` to `22`.

### Source Code Anchors
* **Identifier Constants**: `include/swephexp.h:99` (`SE_ECL_NUT`, `SE_SUN` through `SE_INTP_PERG`).
* **Display Names**: `include/sweph.h:79` (`swe_get_planet_name`).
* **Evaluation Engines**:
  * `src/sweph.zig`: Astrometric coordinate reductions, aberration, light deflection, and topocentric parallax.
  * `src/swemmoon.zig`: Lunar theory and osculating node/apogee solvers.
  * `src/swemplan.zig`: Semi-analytical Moshier ephemeris fallbacks.
  * `src/swejpl.zig`: Direct JPL binary ephemeris integration (`DE431`/`DE441`).

### Coordinate Vector Layout (`xx[6]`)

Calls to `swe_calc` / `swe_calc_ut` populate a 6-element double-precision slice:

| Element | Dimension | Description | Standard Units |
| :--- | :--- | :--- | :--- |
| `xx[0]` | Longitude ($\lambda$) | Geocentric ecliptic longitude referenced to true equinox of date | Decimal degrees ($[0^\circ, 360^\circ)$) |
| `xx[1]` | Latitude ($\beta$) | Geocentric ecliptic latitude | Decimal degrees ($[-90^\circ, +90^\circ]$) |
| `xx[2]` | Distance ($r$) | True geometric/light-time corrected distance | Astronomical Units ($\text{AU}$) |
| `xx[3]` | Speed in $\lambda$ | Daily longitudinal velocity ($\Delta\lambda/\Delta t$) | Degrees per day ($^\circ/\text{day}$) |
| `xx[4]` | Speed in $\beta$ | Daily latitudinal velocity ($\Delta\beta/\Delta t$) | Degrees per day ($^\circ/\text{day}$) |
| `xx[5]` | Speed in $r$ | Daily radial velocity ($\Delta r/\Delta t$) | $\text{AU}$ per day |

* **Flag Semantics**: Passing `iflag = 0` calculates apparent geocentric coordinates referenced to the true equinox of date without velocity components (`xx[3..5] = 0.0`). To populate daily derivatives, include `SEFLG_SPEED` (`256`).
* **Error Discipline**: Always evaluate the function return code. Any value $< 0$ indicates a calculation failure or degraded precision state; inspect the null-terminated diagnostic string in `serr[256]`.

### Basic Usage

```zig
// Zig: apparent position and speed of Venus (ID 3)
var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

const ret = swe.calc_ut(
    jd_ut,
    swe.sweph.SE_VENUS,
    swe.sweph.SEFLG_SPEED,
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);

if (ret < 0) {
    // Handle degradation or missing ephemeris file
}
```

```c
/* C equivalent */
double xx[6];
char serr[256];

int ret = swe_calc_ut(
    jd_ut,
    SE_VENUS,
    SEFLG_SPEED,
    xx,
    serr
);

if (ret < 0) {
    /* Handle error/warning in serr */
}
```

---

## 2. Fundamental Reduction Probe & Luminaries

### -1: `SE_ECL_NUT` (Obliquity and Nutation Probe)
* **Definition**: A dynamic reference probe rather than a physical body. Evaluates Earth's axial orientation parameters for coordinate frame transformations.
* **Vector Mapping**:
  * `xx[0]`: True obliquity of the ecliptic ($\epsilon$, in degrees; includes nutation in obliquity).
  * `xx[1]`: Mean obliquity of the ecliptic ($\epsilon_0$, in degrees; IAU polynomial fit).
  * `xx[2]`: Nutation in ecliptic longitude ($\Delta\psi$, in degrees).
  * `xx[3]`: Nutation in ecliptic obliquity ($\Delta\epsilon$, in degrees).
  * `xx[4..5]`: Unused (`0.0`).
* **Provenance**: Vondrák 2011 precession model paired with IAU 2000B nutation theory.
* **Operational Role**: Extract `xx[0]` to supply the exact `eps` argument required by house division functions like `swe_houses_armc_ex2()`.

---

### 0: `SE_SUN` ("Sun")
* **Definition**: Geocentric apparent Sun, derived by taking the geometric Earth-to-Sun vector and applying light deflection, planetary aberration (light-time correction $\approx 8.3\text{ minutes}$), and nutation.
* **Physical Distance**: $\approx 0.983\text{ AU}$ (perihelion, January) to $1.017\text{ AU}$ (aphelion, July).
* **Provenance**: High-precision JPL `DE431`/`DE441` compressed ephemerides (`.se1`/`.eph`). If files are missing, the engine falls back to the semi-analytic Moshier engine (absolute error $< 0.4''$ between 3000 BCE and 3000 CE).
* **Frame Limits**:
  * Applying `SEFLG_BARYCTR` evaluates the Sun's position relative to the Solar System Barycenter (SSB).
  * Applying `SEFLG_HELCTR` is physically degenerate and returns an error.
* **Error Behavior**: Missing `.se1` files trigger an automatic fallback to Moshier and populate a warning in `serr`. Epochs beyond the numerical integration window return `ERR_BEYOND` (`-3`).

---

### 1: `SE_MOON` ("Moon")
* **Definition**: Geocentric apparent Moon. Fastest-moving catalog body, traversing $12^\circ$ to $15^\circ/\text{day}$ at an average distance of $0.0024\text{ to }0.0027\text{ AU}$ ($\approx 356{,}000\text{ to }406{,}000\text{ km}$).
* **Provenance**: Compressed lunar ephemeris (`semo_*.se1`) derived from Chapront’s ELP 2000-85 theory / JPL integration, with Moshier fallback accurate to a few arcseconds.
* **Topocentric Sensitivity**: Because lunar diurnal parallax reaches up to $\approx 1^\circ$, geocentric coordinates diverge significantly from surface observations. For arcminute-level accuracy, configure geographic observer coordinates using `swe_set_topo()` and activate `SEFLG_TOPOCTR`.
* **Tidal Friction**: Lunar mean motion is coupled to tidal secular acceleration parameters via `SE_TIDAL_*` constants.

---

## 3. Terrestrial and Gas Giant Planets

### 2: Mercury · 3: Venus · 4: Mars
* **Dynamics & Limits**:
  * **Mercury (`2`)**: Maximum solar elongation $\le 28^\circ$. Relativistic perihelion shift is modeled directly.
  * **Venus (`3`)**: Maximum solar elongation $\le 47^\circ$. Near-circular orbit ($e \approx 0.0067$).
  * **Mars (`4`)**: Highly eccentric terrestrial orbit ($e \approx 0.0934$). Synodic period $\approx 780\text{ days}$.
* **Provenance & Accuracy**: JPL `DE431` baseline. Moshier fallback holds errors $< 1''$ for inner planets between 1350 BCE and 3000 CE.
* **Relativistic Corrections**: Because Mercury and Venus remain close to the solar limb, general relativistic gravitational deflection and stellar aberration must remain active (default state).
* **Photometry**: Phase angles, illuminated fractions, and apparent visual magnitudes ($V$) are evaluated using `swe_pheno()`.

---

### 5: Jupiter · 6: Saturn
* **Definition**: Evaluates the **center of mass (barycenter)** of each respective planetary subsystem.
* **Provenance**: JPL `DE431`. Residual positional difference between `DE431` and `DE406` is $< 6''$ for Jupiter and $< 0.1''$ for Saturn.
* **The Center-of-Body (COB) Problem**: The Jovian and Saturnian barycenters deviate from their physical planetary disc centers due to massive satellite systems:
  * Jupiter system displacement reaches **$0.075''$**.
  * Saturn system displacement reaches **$0.053''$**.
  * For stellar occultations or high-resolution planetary transit work, calculate coordinates with `SEFLG_CENTER_BODY` or target explicit COB catalog IDs `9599` / `9699`.
* **Photometric Consideration**: Accurate Saturnian apparent magnitude calculations require accounting for ring inclination and tilt angles, accessible via `swe_pheno()`.

---

### 7: Uranus · 8: Neptune · 9: Pluto
* **Definition**: Barycenters of the outer planets. ID `9` represents the **Pluto–Charon barycenter**, not the physical surface center of Pluto.
* **Barycenter Displacement (Pluto)**: Because Charon possesses $\approx 12.2\%$ of Pluto's mass, the barycenter lies outside the physical body of Pluto. High-precision disc targeting requires COB ID `9999` or `SEFLG_CENTER_BODY`.
* **Provenance**: JPL `DE431`. Residuals between `DE431` and `DE406` reach $< 28''$ (Uranus), $< 53''$ (Neptune), and $< 129''$ (Pluto).
* **Engine Constraints**: Moshier fallback performance degrades rapidly for outer planets. Research-grade calculations must verify the presence of binary Swiss Ephemeris (`.se1`) or JPL files via `swe_get_current_file_data()`.

---

## 4. Lunar Dynamic Points and Apsides

```
Perigee (Closest, high speed)                   Apogee (Furthest, low speed)
       ● Earth                                             ○
       |------------------- Major Axis --------------------|
  ID 22: Intp. Perigee (Priapus)               ID 12: Mean Apogee (Lilith)
                                               ID 13: Osculating Apogee (True Lilith)
                                               ID 21: Intp. Apogee (Natural Lilith)
```

### 10: Mean Lunar Node · 11: True Lunar Node
* **Definition**: Points of intersection between the lunar orbital plane and the ecliptic plane:
  * **Mean Node (`10`)**: Smooth, fictitious uniform regression of the nodal line with an 18.61-year period ($\approx 19.34^\circ/\text{year}$, strictly retrograde).
  * **True Node (`11`)**: The instantaneous osculating intersection. Incorporates short-term solar perturbations; can pause and turn briefly direct.
* **Characteristics**: Nodes are mathematical points on the celestial sphere, not physical bodies; distance is undefined (`xx[2] = 1.0\text{ AU}` nominal). Light-time corrections and stellar aberrations are bypassed.
* **Eclipse Gating**: Central and partial solar/lunar eclipse solvers (`src/swecl.zig:939`) evaluate the node's latitude proximity to confirm eclipse thresholds.

---

### 12, 13, 21: The Black Moon / Lunar Apogee Variants

The apogee of the Moon's eccentric orbit ($e \approx 0.0549$) advances along the ecliptic at $\approx 40.7^\circ/\text{year}$ (an anomalistic period of $\approx 8.85\text{ years}$). Swiss Ephemeris implements three primary representations:

| ID | Constant | Name | Kinematic Profile | Recommended Application |
| :--- | :--- | :--- | :--- | :--- |
| **12** | `SE_MEAN_APOG` | Mean Apogee ("Mean Lilith") | Linear, smooth forward progression ($\approx 40.7^\circ/\text{year}$). | Broad astrological trend evaluation and longitudinal cycles. |
| **13** | `SE_OSCU_APOG` | Osculating Apogee ("True Lilith") | Instantaneous Keplerian apogee; undergoes extreme, rapid angular excursions near perigee. | Specialized celestial mechanics. Do not use if smooth motion is expected. |
| **21** | `SE_INTP_APOG` | Interpolated Apogee ("Natural Lilith") | Orbit-averaged curve fit calculated via `swi_intp_apsides()`. Smooth, continuous progression. | **Recommended standard** for modern astrological charts requiring a stable Black Moon. |
| **22** | `SE_INTP_PERG` | Interpolated Perigee ("Priapus") | Directly opposite ($180^\circ$) Natural Lilith along the averaged apsidal line. | Baseline for lunar perigee tracking and distance extrema. |

> **Operational Warning on ID 13 (Osculating Apogee)**: Because the lunar orbit is near-circular ($e \approx 0.055$), external solar perturbations continuously deform the instantaneous ellipse. Whenever the Moon passes through perigee, the orientation of the major axis becomes mathematically ill-conditioned, causing the osculating apogee to jump by several tens of degrees in days. This is physical osculating behavior, not a numerical defect.

---

## 5. Earth and Asteroid Baselines

### 14: `SE_EARTH` ("Earth")
* **Definition**: Earth position vector.
* **Frame Semantics**:
  * Under standard geocentric conditions (`iflag = 0`), this returns a null vector (`xx = 0`) because the observer resides at the origin.
  * When `SEFLG_HELCTR` is asserted, it evaluates the true heliocentric Earth position vector, which is identical to the negated Sun vector ($-\vec{r}_{\odot}$).
* **Application**: Used to establish solar-system barycentric origins and heliocentric planetary charts.

---

### 15: Chiron · 16: Pholus (Centaurs)
* **Definition**: Outer-system Centaurs occupying chaotic orbits crossing the gas giants:
  * **Chiron (`15`)**: Semi-major axis $a \approx 13.7\text{ AU}$, orbital period $\approx 50.7\text{ years}$. Strongly perturbed by Saturn.
  * **Pholus (`16`)**: Semi-major axis $a \approx 20.3\text{ AU}$, orbital period $\approx 91.8\text{ years}$. Deep-space perihelion near Saturn, aphelion past Neptune.
* **Provenance**: Compressed numeric integration files `seas_*.se1` (or individual asteroid slices in the `ast15/` directory).
* **Strict Temporal Validity Bounds**: Centaur orbits are chaotic; numerical integrations diverge outside validated historical windows:
  * **Chiron (`15`)**: Valid only from **675 CE to 4650 CE** (Julian Days `1967601.5` to `3419437.5`).
  * **Pholus (`16`)**: Valid only from **2958 BCE to 7309 CE** (Julian Days `640648.5` to `4390617.5`).
* **Error Handling Loop Pattern**:
  Querying outside these windows returns `ERR` or `ERR_BEYOND` and leaves coordinate memory cleared. Never render an unverified vector, as a failure defaults to longitude $0.0^\circ$:

```zig
// Correctly guarding a planetary batch calculation:
var p: i32 = 0;
while (p <= 15) : (p += 1) {
    const ret = swe.calc_ut(jd_ut, p, flg, &xx, &swed, models, &dctx, &serr);
    if (ret < 0) {
        // Log error in serr and skip rendering
        continue;
    }
    render_body(p, xx);
}
```

---

### 17–20: The "Big Four" Asteroids
* **Definition**: Main-Belt Asteroids:
  * `17`: **Ceres** (1) · Diameter $\approx 939\text{ km}$ (Dwarf Planet)
  * `18`: **Pallas** (2) · Diameter $\approx 545\text{ km}$ ($i \approx 34.8^\circ$)
  * `19`: **Juno** (3) · Diameter $\approx 247\text{ km}$
  * `20`: **Vesta** (4) · Diameter $\approx 525\text{ km}$ (High-albedo basaltic crust)
* **Data Sources**: Evaluated via short-range ephemeris file `seas_18.se1` (1800–2400 CE) or extended integration files `seas_*.se1` (5401 BCE to 5399 CE).
* **Hard File Dependency**: Unlike the major planets, **the Big Four asteroids do not have a semi-analytic Moshier fallback model**. If `.se1` files are missing, the calculation aborts immediately, returns `ERR`, and populates `serr`.

---

## 6. Catalog Routing and Extension Offsets

The constant `SE_NPLANETS = 23` denotes the total number of primary catalog slots (`0` through `22`). It is an array dimension and upper iteration boundary, **not a queryable body ID**.

To query bodies outside the 0–22 baseline, route calls via dedicated catalog offsets:

```
[ -10 ]                      SE_FIXSTAR: Fixed stars (swe_fixstar / stars.md)
[  -1 ]                      SE_ECL_NUT: Nutation & Obliquity probe
[0 .. 22]                    Standard Planets, Nodes, Apsides, and Centaurs (SE_NPLANETS = 23)
[40 .. 58]                   SE_FICT_OFFSET: Fictitious & Uranian bodies (bodies-fict.md)
[59 .. 999]                  seorbel.txt: User-defined orbital elements (bodies-fict.md)
[9000 + P*100 + M]           SE_PLMOON_OFFSET: Planetary Moons and Centers of Body (bodies-moons.md)
[10000 + N]                  SE_AST_OFFSET: General Minor Planets & MPC Asteroids (bodies-asteroids.md)
```
