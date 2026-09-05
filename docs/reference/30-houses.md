# Houses A–Y and Placidus

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Buffer Specifications

Swiss Ephemeris supports 22 house systems, designated by ASCII characters passed via `hsys`.

* **Source Anchors**: System name lookup `src/swehouse.zig:1607` (`swe_house_name()`), cusp calculation engine `src/swehouse.zig:1508`, C ABI dispatch `src/swe_abi.zig:741`.
* **Case Sensitivity**: System codes are case-insensitive with one critical exception: **`'I'` (Sunshine standard) vs. `'i'` (Sunshine altitude variant)**.
* **Cusp Buffer (`cusps[37]`)**:
  * Double-precision array indexed $0 \dots 36$.
  * Standard 12-house systems populate indices `cusps[1]` through `cusps[12]`. `cusps[0]` is an unused sentinel set to `0.0`.
  * The Gauquelin system (`'G'`) is the **sole system** that populates the full array across `cusps[1]` through `cusps[36]`.
* **Angle Buffer (`ascmc[10]`)**:
  * Populates primary celestial and auxiliary polar angles:
    `[0]` ASC, `[1]` MC, `[2]` ARMC, `[3]` Vertex, `[4]` Equatorial Ascendant (East Point), `[5]` Co-Ascendant (Koch), `[6]` Co-Ascendant (Munkasey), `[7]` Polar Ascendant (Munkasey), `[8]` Array Dimension (`SE_NASCMC = 8`), `[9]` Context flag (used by system `'I'`).

### Standard Calling Pattern

```zig
// Zig: decoupled ARMC calculation with explicit workspace
var cusps: [37]f64 = undefined;
var ascmc: [10]f64 = undefined;
var hctx = swe.swehouse.HouseCtx{};

const status = swe.houses_armc_ex2(
    armc,
    lat,
    eps,
    'P', // Placidus
    &cusps,
    &ascmc,
    null, // optional cusp_speed
    null, // optional ascmc_speed
    null, // optional serr
    &hctx,
);
```

```c
/* C equivalent */
double cusps[37], ascmc[10];
char serr[256];

int status = swe_houses_ex2(
    jd_ut,
    0, // SEFLG_TROPICAL default
    lat,
    lon,
    'P',
    cusps,
    ascmc,
    NULL, // optional cusp_speed
    NULL, // optional ascmc_speed
    serr
);
```

* *Note on Daily Velocities*: Instantaneous speeds ($^\circ/\text{day}$) for cusps and angles are populated **only** when calling the `*_ex2` function variants.
* *Planetary House Ingress*: Calling `swe_house_pos(armc, lat, eps, hsys, xpin, serr)` returns the fractional house position of a celestial body ($[1.0, 13.0)$ for 12-house systems; $[1.0, 37.0)$ for `'G'`).

---

## 2. Time-Arc and Semi-Diurnal Quadrant Systems (`P`, `K`, `B`, `T`)

```
  Equator / Time Space                            Ecliptic Projection
  ────────────────────                            ───────────────────
  Trisect Diurnal / Nocturnal Semi-Arcs ────────> Project along spatial circles
  (Placidus / Koch / Alcabitius)                  to yield intermediate cusps
```

### P: Placidus
* **Definition**: Unequal quadrant system trisecting the diurnal and nocturnal semi-arcs of each degree of the ecliptic into equal temporal thirds.
* **Math Family**: Semi-diurnal time-proportional quadrant division. Cusp cusps represent points whose diurnal semi-arcs are $1/3$ and $2/3$ complete.
* **Provenance**: Placidus de Titis (1657); Swiss Ephemeris 2.09 introduced an iterative interpolation refinement to resolve cusp crossings near polar thresholds.
* **Limits & Failures**: **Breaks down at polar latitudes ($|\phi| \ge 66^\circ 34'$)** or whenever the diurnal semi-arc of a zodiacal degree does not intersect the horizon plane. In polar regions, the engine attempts an interpolation fallback, writing a warning to `serr`, and returns `ERR` (`-1`) on mathematical divergence.
* **Error Recovery**: Catch return codes $< 0$ and route calculations to polar-safe alternatives such as Krusinski (`'U'`) or Porphyry (`'O'`).

---

### K: Koch (GOH / Geburtsortshäuser)
* **Definition**: Unequal quadrant system dividing the diurnal semi-arc of the Midheaven rather than the Ascendant, computing intermediate cusps using the birthplace co-latitude.
* **Math Family**: Time-proportional right-ascension projection based on MC ascensional differences.
* **Provenance**: Walter Koch and Friedrichanz (1960s).
* **Limits & Failures**: Fails at polar latitudes ($|\phi| \ge 66.5^\circ$) when the horizon plane is parallel to the equator or when quadrant division curves fail to intersect the ecliptic. Follows the same fallback and `serr` warning mechanisms as Placidus.

---

### B: Alcabitius
* **Definition**: Precursor to Placidus. Trisects the right-ascension semi-arc of the Ascendant using hour circles projected through the celestial poles onto the ecliptic.
* **Math Family**: Semi-diurnal right-ascension trisection.
* **Provenance**: Al-Qabisi (10th century); standard European medieval system prior to Regiomontanus.
* **Limits**: Stretches significantly at high latitudes, but maintains mathematical convergence longer than Placidus or Koch.

---

### T: Polich/Page Topocentric
* **Definition**: Empirical approximation of Placidus based on rotation angles on the celestial equator, incorporating topocentric parallax and observer elevation.
* **Math Family**: Equator rotation-angle trisection.
* **Provenance**: Nelson Polich and Anthony Page (1960s).
* **Limits & Invariants**: **Requires calling `swe_set_topo()` prior to evaluation**. If observer coordinates are unset, the topocentric correction degrades silently to standard geocentric coordinates without returning an error. Fails at polar latitudes ($|\phi| \ge 66.5^\circ$).

---

## 3. Equal and Sign-Based Systems (`A`/`E`, `D`, `N`, `V`, `W`)

Equal systems bypass iterative time calculations, dividing the ecliptic circle into twelve uniform $30^\circ$ sectors.

| Code | System Name | Cusp 1 Anchor | Subsequent Cusps ($C_n$) | Polar Behavior |
| :---: | :--- | :--- | :--- | :--- |
| **`A` / `E`** | **Equal (ASC)** | Exact Ascendant longitude ($\lambda_{\text{ASC}}$) | $C_n = \lambda_{\text{ASC}} + (n - 1) \times 30^\circ$ | **Polar Safe** (Unconditional) |
| **`D`** | **Equal (MC)** | Midheaven longitude minus $90^\circ$ ($\lambda_{\text{MC}} - 90^\circ$) | $C_{10} = \lambda_{\text{MC}}$; $C_n = C_1 + (n - 1) \times 30^\circ$ | **Polar Safe** (Unconditional) |
| **`N`** | **Equal (Aries)** | Fixed at $0^\circ 00' 00''$ Aries | $C_n = (n - 1) \times 30^\circ$ (Signs $\equiv$ Houses) | **Polar Safe** (Universal) |
| **`V`** | **Vehlow Equal** | Ascendant minus $15^\circ$ ($\lambda_{\text{ASC}} - 15^\circ$) | Ascendant sits at the exact midpoint ($15^\circ$) of House 1 | **Polar Safe** (Unconditional) |
| **`W`** | **Whole Sign** | $0^\circ 00' 00''$ of the zodiac sign containing ASC | $C_n = 0^\circ$ of each subsequent zodiacal sign | **Polar Safe** (Unconditional) |

* **Whole Sign Implementation Invariant**: The ABI dispatcher (`src/swe_abi.zig:771`) internally maps `'W'` to Equal mode (`'E'`), aligning cusp longitudes to integer multiples of $30^\circ$ based on $\lfloor \lambda_{\text{ASC}} / 30^\circ \rfloor \times 30^\circ$.
* **Failure Modes**: Equal systems never fail mathematically, making them the primary fallback when polar charts cause quadrant systems to diverge.

---

## 4. 3D Great-Circle Space Systems (`C`, `R`, `M`, `H`, `U`)

These systems divide a selected 3D reference circle into twelve equal $30^\circ$ increments, then project those division points onto the ecliptic via great circles.

```
  Campanus (C)                Regiomontanus (R)           Morinus (M)
  ────────────                ─────────────────           ───────────
  Trisects Prime Vertical     Trisects Celestial Equator  Trisects Celestial Equator
  via North/South horizon     via Celestial Poles         via Ecliptic Poles
  meridian intersections.     (Hour Circles).             (Zero latitude dependency).
```

### C: Campanus
* **Definition**: Trisects the local Prime Vertical into twelve $30^\circ$ arcs, projecting the cusps onto the ecliptic along great circles passing through the North and South points of the horizon.
* **Math Family**: Prime Vertical division.
* **Provenance**: Campano da Novara (13th century).
* **Limits**: At extreme latitudes, cusps crowd near the Ascendant and Midheaven; fails at the geographic poles ($|\phi| = 90^\circ$).

---

### R: Regiomontanus
* **Definition**: Trisects the Celestial Equator into twelve $30^\circ$ segments, projecting the division boundaries onto the ecliptic along great circles passing through the North and South horizon points.
* **Math Family**: Equatorial space division.
* **Provenance**: Johannes Müller (Regiomontanus, 15th century).
* **Limits**: Degenerates at the geographic poles ($|\phi| = 90^\circ$).

---

### M: Morinus
* **Definition**: Trisects the Celestial Equator into twelve $30^\circ$ arcs, projecting them onto the ecliptic along great circles passing through the **ecliptic poles**.
* **Math Family**: Equatorial-ecliptic coordinate transformation.
* **Provenance**: Jean-Baptiste Morin (17th century).
* **Limits**: **Completely independent of geographic latitude ($\phi$)**. Calculation requires only the ARMC and true obliquity ($\epsilon$). Operates without distortion across the polar circles and at the geographic poles.

---

### H: Horizon / Azimuthal
* **Definition**: Divides the local Horizon circle into twelve equal $30^\circ$ azimuthal sectors, starting from the East point and projecting along vertical circles to the ecliptic.
* **Math Family**: Horizontal coordinate system.
* **Provenance**: Azimuthal astrological research. Pair with `swe_azalt()`.

---

### U: Krusinski-Pisa-Goelzer
* **Definition**: Equal-ascensional polar-stable system dividing the great circle that passes through both the Ascendant and the local Zenith into twelve equal $30^\circ$ arcs.
* **Math Family**: Great circle trisection passing through Zenith and ASC (`src/swehouse.zig:1768`).
* **Provenance**: Bogdan Krusinski (1995), Milan Pisa, and Georg Goelzer.
* **Limits**: **Designed specifically to remain stable across polar regions**. Does not degenerate at latitudes $|\phi| \ge 66.5^\circ$; primary recommended quadrant-like replacement for Placidus in polar circles.

---

## 5. Ecliptic Quadrant and Proportional Systems (`O`, `S`, `L`, `Q`)

These systems calculate the primary celestial angles (ASC and MC) and divide the intervening ecliptic arcs or angles mathematically.

### O: Porphyry
* **Definition**: Divides each of the four ecliptic quadrants formed by the ASC and MC axes into three equal longitudinal parts:
  $$C_{11} = \lambda_{\text{MC}} + \frac{\lambda_{\text{ASC}} - \lambda_{\text{MC}}}{3}$$
* **Provenance**: Porphyry of Tyre (3rd century CE).
* **Limits**: Operates unconditionally across all latitudes except the exact geographic poles ($\pm 90^\circ$), where the Ascendant becomes undefined. Serves as the internal engine fallback target for system `'I'`.

---

### S: Sripati (Bhava Chalita)
* **Definition**: Quadrant trisection system used in Indian Vedic astrology. Quadrant arcs between ASC and MC are divided equally into three segments, with cusps representing the midpoints (*Bhava Madhyas*) of the houses rather than the boundary ingresses.
* **Provenance**: Sripati (11th century CE).
* **Operational Recommendation**: Combine with sidereal mode (`swe_set_sid_mode()`) and degree formatting using `SE_SPLIT_DEG_NAKSHATRA`.

---

### L: Pullen Sinusoidal Delta (SD) & Q: Pullen Sinusoidal Ratio (SR)
* **Definition**: Sinusoidal proportional quadrant systems developed by Bob Pullen.
  * **`L` (SD)**: Adjusts quadrant trisection using a sinusoidal delta curve based on latitude and quadrant elongation.
  * **`Q` (SR)**: Adjusts trisection via continuous ratio weighting.
* **Provenance**: Bob Pullen (modern).
* **Limits**: Maintains smooth, continuous cusp motion across all latitudes without the sudden boundary flips observed in semi-arc systems. Highly stable alternative for high-latitude charts.

---

## 6. Specialized, Experimental, and Statistical Systems (`G`, `I`/`i`, `X`, `Y`, `F`, `J`)

### G: Gauquelin 36 Sectors
* **Definition**: Divides the diurnal path of celestial bodies into 36 sectors of $10^\circ$ each (Rise $\rightarrow$ Culmination $\rightarrow$ Set $\rightarrow$ Anti-culmination). Used for statistical correlation studies.
* **Output Buffer Exception**: **Writes to all 36 slots in `cusps[1..36]`** (`src/swe_abi.zig:756`).
* **Provenance**: Michel and Françoise Gauquelin.
* **Limits**: Sector angular velocities differ significantly from standard house speeds. Use `swe_gauquelin_sector()` for individual body placement ($[1.0, 37.0)$).

---

### I: Sunshine / i: Sunshine Alternative
* **Definition**: Sun-declination-weighted ascensional house system developed by Stark Fischer.
  * **`'I'`**: Standard declination-weighted model.
  * **`'i'`**: Altitude-weighted variant.
* **Internal State Requirement**: Relies on `HouseCtx.saved_sundec` (`src/swehouse.zig:28`). In C, uses thread-local `SweState.house`.
* **Southern MC Handling**: Inverts southern midheaven orientation unless configured with `SUNSHINE_KEEP_MC_SOUTH` (`src/swehouse.zig:23`).
* **Fallback Behavior**: If calculations fail at extreme latitudes, the engine **silently falls back to Porphyry (`'O'`)** (`src/swe_abi.zig:791`). When system `'I'` succeeds, the engine sets `ascmc[9] = 1.0` as an internal confirmation flag.

---

### X: Meridian / Axial Rotation
* **Definition**: Divides the celestial equator into twelve equal $30^\circ$ increments measured from the ARMC, then projects these points onto the ecliptic along hour circles.
* **Math Family**: Horizon-independent equatorial rotation.
* **Provenance**: David Cope (Zariel, early 20th century).
* **Limits**: Horizon-independent. The Ascendant has no physical bearing on the house cusps; applications should evaluate positions relative to MC and ARMC.

---

### Y: APC (Alternative Porphyry Compound)
* **Definition**: Ascensional house system calculated via `apc_sector()` (`src/swehouse.zig:1639`). Acts as a polar-capable hybrid between quadrant and whole-sign methods.
* **Limits**: Requires valid ecliptic obliquity ($\epsilon$). Degenerates into a singularity at the exact geographic poles ($\phi = \pm 90^\circ$).

---

### F: Carter Poli-Equatorial & J: Savard-A
* **Definition**: Experimental hybrid systems blending meridian hour circles with polar-equatorial arcs. Retained for backward compatibility with specialized historical research databases.
* **Limits**: Verify outputs against canonical C reference testbeds prior to deployment. Degenerates at exact geographic poles.

---

## 7. Comparative Diagnostic Matrix

| System Code | Identifier Character | Mathematical Basis | Valid Latitude Range | Polar Fallback Recommendation |
| :---: | :---: | :--- | :--- | :--- |
| `P` | `'P'` | Semi-Diurnal Time Arc | $|\phi| < 66^\circ 34'$ | Fall back to `'U'` or `'O'` |
| `K` | `'K'` | Semi-Diurnal Time Arc (MC) | $|\phi| < 66^\circ 34'$ | Fall back to `'U'` or `'O'` |
| `O` | `'O'` | Ecliptic Quadrant Trisection | $|\phi| < 90^\circ$ | Universal baseline |
| `C` | `'C'` | Prime Vertical Space Division | $|\phi| < 90^\circ$ | Fall back to `'M'` or `'E'` |
| `R` | `'R'` | Equatorial Space Division | $|\phi| < 90^\circ$ | Fall back to `'M'` or `'E'` |
| `E` / `A` | `'E'` / `'A'` | Equal Ecliptic from Ascendant | Global ($[-90^\circ, +90^\circ]$) | Always valid |
| `W` | `'W'` | Whole Sign ($30^\circ$ Sign Boundaries) | Global ($[-90^\circ, +90^\circ]$) | Always valid |
| `M` | `'M'` | Equatorial via Ecliptic Poles | Global ($[-90^\circ, +90^\circ]$) | Always valid (Latitude-free) |
| `U` | `'U'` | Great Circle (Zenith–ASC) | Global ($[-90^\circ, +90^\circ]$) | Standard polar quadrant choice |
| `T` | `'T'` | Topocentric Rotation Angles | $|\phi| < 66^\circ 34'$ | Requires `set_topo()` |
| `G` | `'G'` | 36 Diurnal Sectors | $|\phi| < 66^\circ 34'$ | Populates `cusps[1..36]` |
| `I` | `'I'` | Solar Declination Weighted | Dynamic | Falls back silently to `'O'` |
| `X` | `'X'` | Axial Meridian Equator | Global ($[-90^\circ, +90^\circ]$) | Horizon-independent |
