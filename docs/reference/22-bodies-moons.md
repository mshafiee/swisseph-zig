# Planetary Moons and Centers of Body (COB)

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Indexing Conventions

Swiss Ephemeris models natural planetary satellites and physical planet centers of body (COB) alongside barycentric bodies using compressed numerical integration files derived from JPL satellite ephemerides.

### Source Code Anchors
* **Constants**: `SE_PLMOON_OFFSET = 9000` (`include/swephexp.h:127`), `SEFLG_CENTER_BODY = (1024 * 1024)` (`0x100000`, `include/swephexp.h:216`).
* **Evaluation Engines**: `src/sweph.zig` (astrometric reductions) and `src/swejpl.zig` (Chebyshev evaluation).
* **Ephemeris Data Files**: Binary satellite ephemerides stored in `sat/sepm*.se1` under the configured ephemeris directory.

### Catalog Indexing Scheme
Satellite and COB indices derive from JPL Horizons planetary body numbers using the standard offset formula:

$$\text{ipl} = 9000 + (P \times 100) + M$$

$P$ is the planet base number, $M$ the JPL Horizons moon number.

* **Planetary Base Numbers**: Mars = `4`, Jupiter = `5`, Saturn = `6`, Uranus = `7`, Neptune = `8`, Pluto = `9`.
* **Center of Body (COB)**: Assigned `moon_nr = 99`. Evaluating index `9000 + planet_no * 100 + 99` is functionally identical to passing the base planet index (`ipl = planet_no`) with the bit flag `SEFLG_CENTER_BODY`.
* **Output Vector (`xx[6]`)**: Populates values in standard ecliptic coordinates (geocentric apparent by default):
  * `xx[0..2]`: Ecliptic longitude ($\lambda$, deg), latitude ($\beta$, deg), distance ($r$, AU).
  * `xx[3..5]`: Daily velocities ($\Delta\lambda/\Delta t$, $\Delta\beta/\Delta t$, $\Delta r/\Delta t$) in deg/day and AU/day.

---

### Setup and Integration Example

The engine automatically scans the `sat/` subdirectory inside the path registered with `swe_set_ephe_path`.

```zig
// Zig: compute geocentric position of Io (ID 9501)
swe.set_ephe_path("/data/ephe", &swed);

var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

const result = swe.calc_ut(
    jd_ut,
    9501, // Io
    flg | swe.SEFLG_SPEED,
    &xx,
    &swed,
    models,
    &dctx,
    &serr,
);
```

```c
/* C equivalent */
swe_set_ephe_path("/data/ephe");

double xx[6];
char serr[256];

int result = swe_calc_ut(
    jd,
    9501, // Io
    SEFLG_SPEED,
    xx,
    serr
);
```

---

## 2. Planetary Subsystems Reference

### Mars: 9401 Phobos / 9402 Deimos
* **Physical System**: Ultra-short period inner/outer satellites. Orbital periods: Phobos $\approx 7.65\text{ h}$, Deimos $\approx 30.35\text{ h}$. Geocentric distance: $\approx 0.37\text{ AU}$ to $2.68\text{ AU}$.
* **Provenance**: Compressed JPL satellite ephemerides (`sat/sepm*.se1`).
* **Barycenter vs. COB**: The Martian moon system has negligible mass; the displacement between the Mars-system barycenter and Mars COB is less than $0.2\text{ m}$. For all calculations, the planetary barycenter (`ipl = 4`) and COB (`9499`) are interchangeable.
* **Kinematic Limits**: Due to Phobos's rapid angular velocity ($\approx 1130^\circ/\text{day}$ relative to Mars center), finite-difference velocity calculation via `SEFLG_SPEED` can experience numerical truncation during close approaches. When calculating topocentric transits or occultations, query position-only coordinates (`SEFLG_SPEED` cleared) over fine temporal steps ($\le 1\text{ minute}$).
* **Errors**: Dates outside the 1900–2047 CE window return `BEYOND`. A missing satellite ephemeris file returns `ERR` with `"cannot open sat file"`.

---

### Jupiter: 9501–9504 + 9599 COB
* **Physical System**: The four Galilean satellites:
  * `9501`: Io
  * `9502`: Europa
  * `9503`: Ganymede
  * `9504`: Callisto
  * `9599`: Jupiter Center of Body (COB)
* **Barycentric Offset**: The combined mass of the Galilean satellites displaces Jupiter's physical center from the system barycenter by up to $0.075''$ (as viewed from Earth at close opposition, e.g., JD 2468233.5). While irrelevant for zodiacal signs and house placements, this offset is critical for high-resolution stellar occultations and mutual satellite events relative to Jupiter's $\approx 40''$ planetary disc.
* **COB Equivalence**:
  ```zig
  // Evaluating via flag on planetary index:
  _ = swe.calc_ut(jd, 5, flg | swe.SEFLG_CENTER_BODY, &xx, &swed, models, &dctx, &serr);

  // Is strictly equivalent to evaluating via COB catalog index:
  _ = swe.calc_ut(jd, 9599, flg, &xx, &swed, models, &dctx, &serr);
  ```
* **Performance Strategy**: COB orbits contain high-frequency multi-frequency wobbles, making iterative root finders converge slower. When computing transit or aspect boundaries, perform root isolation using the planetary barycenter (`ipl = 5`), then execute final boundary refinement using `9599` or `SEFLG_CENTER_BODY`.
* **Testing Flag**: Passing the internal bit flag `SEFLG_TEST_PLMOON` forces output of unreduced raw file vectors. This is intended solely for internal engine verification; never expose these vectors in application outputs.

---

### Saturn: 9601–9608 + 9699 COB
* **Physical System**: The eight classical satellites:
  * `9601`: Mimas · `9602`: Enceladus · `9603`: Tethys · `9604`: Dione
  * `9605`: Rhea · `9606`: Titan · `9607`: Hyperion · `9608`: Iapetus
  * `9699`: Saturn Center of Body (COB)
* **Barycentric Offset**: Dominated by Titan ($m_{\text{Titan}} \approx 1.345 \times 10^{23}\text{ kg}$), producing a maximum Earth-apparent barycenter–COB offset of $0.053''$ (e.g., JD 2463601.5).
* **Rotational Constraints**: Hyperion (`9607`) is in a state of chaotic non-synchronous tumbling; positional ephemerides are precise within the file range, but body-fixed orientations or sub-observer coordinates cannot be extrapolated.
* **Photometry**: Titan is the only Saturnian moon suitable for standard planetary magnitude pipelines (`swe_pheno_ut`).

---

### Uranus: 9701–9705 + 9799 COB
* **Physical System**: Major regular Uranian satellites orbiting a high-obliquity system ($i \approx 97.8^\circ$):
  * `9701`: Ariel · `9702`: Umbriel · `9703`: Titania · `9704`: Oberon · `9705`: Miranda
  * `9799`: Uranus Center of Body (COB)
* **Barycentric Offset**: Maximum displacement is $0.0032''$, which is negligible for general ephemeris applications.
* **Observational Limits**: Faint apparent visual magnitudes ($V \approx 14\text{ to }16.5$). Heliacal rising/setting algorithms (`swe_heliacal_ut`) are not defined for these satellites.

---

### Neptune: 9801, 9802, 9808 + 9899 COB
* **Physical System**:
  * `9801`: Triton (massive retrograde captured KBO)
  * `9802`: Nereid (highly eccentric orbit, $e \approx 0.75$)
  * `9808`: Proteus (faint, irregular inner moon; matches JPL index 808)
  * `9899`: Neptune Center of Body (COB)
* **Barycentric Offset**: Maximum displacement is $0.0036''$.
* **Kinematic Limits**: Nereid's orbital eccentricity ($e \approx 0.751$) causes an orbital speed variance exceeding $5:1$ between apoapsis and periapsis. Transit stepping algorithms must drop below $1\text{ hour}$ when Nereid traverses periapsis to avoid step overshooting.
* **Error Handling on Catalog Gaps**: Unassigned intermediate satellite IDs (e.g., `9803` through `9807`) do not return blank or interpolated structures; the engine halts and returns `ERR` with a missing body notification in `serr`.

---

### Pluto: 9901–9905 + 9999 COB
* **Physical System**: Binary-dwarf system and outer circum-binary moonlets:
  * `9901`: Charon (Pluto I)
  * `9902`: Nix (Pluto II)
  * `9903`: Hydra (Pluto III)
  * `9904`: Kerberos (Pluto IV)
  * `9905`: Styx (Pluto V)
  * `9999`: Pluto Center of Body (COB)
* **The Charon Offset Problem**: Charon possesses $\approx 12.2\%$ of Pluto’s mass, placing the system barycenter outside the physical surface of Pluto. This creates a maximum geocentric angular displacement of **$0.088''$** (e.g., JD 2437372.5)—the largest fractional barycentric displacement of any classical planetary target in the solar system.
* **Critical Distinction**:
  * Default `ipl = 9` (`SE_PLUTO`) evaluates the **Pluto-system barycenter**.
  * Disk-accurate positions, occultation shadow paths, and physical astrometry **must use `9999` or `SEFLG_CENTER_BODY`**.
  * Mixing up `9901` (Charon center) and `9999` (Pluto physical center) is a frequent implementation error. Always assert satellite IDs at integration boundaries.
* **Precision Limits**: While Charon's orbit is resolved to high precision, elements for outer satellites Nix, Hydra, Kerberos, and Styx derived from early compression sets reflect positional uncertainties on the order of arcminutes outside the New Horizons encounter epoch.

---

## 3. Operational Constraints and Error Paths

| Condition | Cause | Engine Behavior | Recovery Strategy |
| :--- | :--- | :--- | :--- |
| **Missing `sat/` directory** | Data files `sepm*.se1` absent from ephemeris search path. | Returns `ERR`, writes `"cannot open sat file"` to `serr`. | Confirm `swe_set_ephe_path()` points to an ephemeris directory containing the `sat/` subfolder. |
| **Out-of-range JD** | Target Julian Day falls outside `1900-01-01` to `2047-12-31`. | Returns `ERR` or status code `BEYOND`. | Clamp queries to the supported 1900–2047 temporal range; planetary moons cannot be evaluated historically or far into the future. |
| **Unmapped Moon ID** | Querying an unassigned satellite slot (e.g., `9804`). | Engine returns `ERR`; output vector remains zeroed. | Verify catalog IDs against the table above; do not assume contiguous satellite enumerations across all planets. |
| **COB on Geocentric Moon** | Applying `SEFLG_CENTER_BODY` or index `9399` to the Moon (`SE_MOON`). | Flag is silently ignored; Earth-Moon barycentric offsets are managed independently via lunar ephemerides. | Do not apply `SE_PLMOON_OFFSET` to planetary index `3`. Use standard flags `SEFLG_HELCTR` / `SEFLG_BARYCTR` instead. |
