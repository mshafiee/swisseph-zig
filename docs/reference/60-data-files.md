# Data Files and Directory Architecture

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).  
> *This reference supersedes the legacy `../guide/02-data-files.md` overview.*

---

## 1. Path Resolution and Configuration

Swiss Ephemeris resolves external binary ephemerides, text catalogs, and Earth orientation tables through a structured search sequence.

### Search Precedence
1. **Explicit API Declaration**: Paths passed at runtime via `swe_set_ephe_path()` (C) or `swe.set_ephe_path(dir, &swed)` (Zig).
2. **Environment Variable**: The system environment variable `SE_EPHE_PATH` (evaluated if no explicit path was provided or if `NULL` was passed).
3. **Hardcoded Internal Fallback**: `.:/users/ephe2/:/users/ephe/` on POSIX systems, or `\SWEPH\EPHE` on Windows.

> [!WARNING]
> **Path Length and Topology Invariants**  
> * **Buffer Boundary**: Path strings cannot exceed 255 characters (`AS_MAXCH = 256`). Paths exceeding this limit are rejected and overwritten with internal defaults.
> * **Directory Flattening Prohibited**: Auxiliary folders (`ast0/`–`ast21/` and `sat/`) **must** exist as child directories directly inside the primary `$EPHE` root. They cannot be linked as sibling folders.

### Runtime Initialization

```zig
// Zig: explicitly seed ephemeris search path
const swe = @import("swisseph");

var swed = swe.sweph.Swed{};
swe.set_ephe_path("/var/data/ephe", &swed);
```

```c
/* C equivalent */
#include "sweph.h"

swe_set_ephe_path("/var/data/ephe");
```

---

## 2. Directory Layout

A production ephemeris directory tree conforms to the following layout:

```text
$EPHE/
├── sepl_18.se1              # Planets (1800–2400 CE) — Core Demo
├── semo_18.se1              # Moon (1800–2400 CE) — Core Demo
├── seas_18.se1              # Main Asteroids (1800–2400 CE) — Core Demo
├── sepl_*.se1               # Full DE431 planetary span (50 files, 600-yr slices)
├── semo_*.se1               # Full DE431 lunar span (50 files, 600-yr slices)
├── seas_*.se1               # Full DE431 asteroid span (18 files, Ceres/Pallas/Juno/Vesta/Chiron/Pholus)
├── sefstars.txt             # Fixed star coordinate and proper motion catalog
├── seasnam.txt              # Minor planet ID-to-name catalog
├── seorbel.txt              # Keplerian elements for fictitious / user-defined bodies
├── seleapsec.txt            # IERS leap second reference records
├── swe_deltat.txt           # Historical and predictive Delta-T tables
├── eop*.dat                 # Earth Orientation Parameters (Horizons-grade polar motion/UT1)
├── de431.eph                # (Optional) Full JPL DE431 binary integration (2.6 GB)
├── ast0/ ... ast21/         # Extended asteroid library partitioned by catalog thousands
│   ├── se00001.se1          # Long-span numerical orbit for Ceres
│   └── se00433s.se1         # Short-span orbit for Eros (suffix 's')
└── sat/                     # Natural planetary satellites and Center of Body (COB)
    └── sepm*.se1            # Numerical orbits for moons of Mars, Jupiter, Saturn, Uranus, Neptune, Pluto (1900–2047)
```

---

## 3. Ephemeris File Specifications

### 3.1 Planetary and Lunar Compressed Ephemerides (`.se1`)

Swiss Ephemeris planetary files compress JPL integration vectors into Chebyshev polynomial coefficients over discrete 600-year blocks (`NCTIES = 6.0` Julian centuries).

* **Core Demo Suite (~5 MB total)**:
  * `sepl_18.se1`: Sun, Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune, Pluto (1800–2400 CE).
  * `semo_18.se1`: High-precision geocentric Moon (1800–2400 CE).
  * `seas_18.se1`: Asteroids Ceres, Pallas, Juno, Vesta, plus Centaurs Chiron and Pholus (1800–2400 CE).
* **Extended Archive**: Covers 13002 BCE to 17000 CE (50 planetary + 50 lunar slices).
* **Filename Encoding**:
  $$\text{se}[pl|mo|as]\_[m]?\text{NN}\text{.se1}$$
  * Prefix: `sepl` (Planets), `semo` (Moon), `seas` (Main asteroids).
  * Positive Centuries: `18` covers $1800\text{ to }2399\text{ CE}$; `00` covers $0\text{ to }599\text{ CE}$.
  * Negative Centuries ($BCE$): Prefixed with `m` (e.g., `m06` covers $-600\text{ to }-001\text{ BCE}$).

---

### 3.2 Asteroid Libraries (`ast0/` through `ast21/`)

Extended minor planets are stored in subdirectories organized by their Minor Planet Center (MPC) catalog index divided by 1000:

$$\text{subdirectory} = \text{ast}\left(\lfloor \text{MPC id} / 1000 \rfloor\right)$$

* **Examples**:
  * Asteroid `433` Eros $\rightarrow$ `ast0/se00433.se1` (or `ast0/se00433s.se1`).
  * Asteroid `1566` Icarus $\rightarrow$ `ast1/se01566.se1`.
  * Asteroid `101955` Bennu $\rightarrow$ `ast101/se101955.se1`.
* **File Variants**:
  * **Standard (`seNNNNN.se1`)**: Full integration span covering centuries or millennia.
  * **Short (`seNNNNNs.se1`)**: Compact slices covering approximate standard birth epochs ($1800\text{ to }2100\text{ CE}$).

---

### 3.3 Natural Planetary Satellites (`sat/`)

Compressed numerical ephemerides for regular and irregular planetary moons reside exclusively in `sat/`:

* **Filename Format**: `sat/sepm*.se1` (e.g., `sepm04.se1` through `sepm09.se1`).
* **Temporal Scope**: Strictly limited to **1900-01-01 to 2047-12-31 CE**.
* **Bodies Covered**: Galilean satellites, major moons of Saturn, Uranus, Neptune, the Pluto-Charon system, and physical Centers of Body (COB, `9x99`).

---

### 3.4 Text Catalogs and Parameter Files

Text catalogs **must reside directly in the `$EPHE` root directory**; placing them in subdirectories will cause parsing failures.

| Filename | Format | Purpose | Engine Behavior if Missing |
| :--- | :--- | :--- | :--- |
| `sefstars.txt` | Formatted ASCII | Fixed star coordinates, spectral classes, magnitudes, and proper motion vectors. | `swe_fixstar*` aborts with `ERR` (`-1`). |
| `seasnam.txt` | Pipe/Comma ASCII | MPC minor planet number-to-name resolution dictionary. | `swe_get_planet_name` echoes numeric string (e.g. `"#" 101955`) instead of designated name. |
| `seorbel.txt` | Comma-delimited | Orbital elements and polynomial $T$-terms for fictitious bodies (40–999). | Engine falls back silently to 15 compiled-in orbital defaults for IDs 40–54; IDs 55–999 fail with `ERR`. |
| `seleapsec.txt` | IERS Table | Explicit historical and scheduled UTC leap second insertions. | Falls back to internal static leap second array. |
| `swe_deltat.txt` | Numeric ASCII | Empirical historical and projected $\Delta T$ ($TT - UT$) corrections. | Falls back to analytical polynomial drift models (Stephenson/Morrison/Vondrák). |
| `eop*.dat` | Space-delimited | High-precision IERS Earth Orientation Parameters ($x, y$ polar motion, $UT1 - UTC$). | High-precision diurnal frame rotations revert to analytical approximations. |

---

### 3.5 Direct JPL Integration Files (`*.eph`)

Applications requiring uncompressed Chebyshev access can supply raw JPL export files directly:

* `de431.eph` ($\approx 2.6\text{ GB}$): Covers $-13000\text{ to }+17000$.
* `de406.eph` ($\approx 190\text{ MB}$): Legacy compressed long-span baseline.
* **Activation**: Call `swe_set_jpl_file("de431.eph")` and include `SEFLG_JPLEPH` in calculation calls.

---

## 4. Fallback Mechanics and Provenance Verification

The calculation pipeline implements fallback chains when binary files are absent:

```
                  swe_calc(..., iflag, ...)
                             │
            Is SEFLG_JPLEPH set?
            ├── Yes ──> Open *.eph ──[Missing]──> Return ERR (-1)
            │
            └── No  ──> Check SWIEPH (.se1)
                             │
                     File Found in $EPHE?
                     ├── Yes ──> Evaluate Chebyshev .se1 (High Precision)
                     │
                     └── No  ──> Is it an Asteroid (>10000) or Moon (9000+)?
                                 ├── Yes ──> Return ERR (-1) (No analytical model)
                                 │
                                 └── No  ──> Fall back to Moshier Semi-Analytic
                                             • Return OK (0) or SEFLG_MOSEPH
                                             • Write notice into serr
```

### Inspecting Served Ephemeris Source
Because Swiss Ephemeris will silently fall back to Moshier for standard planets (IDs 0–14) when a `.se1` file is missing, mission-critical pipelines must verify which file served the calculation:

```zig
// Zig: inspect file serving the calculation
var fname: [256]u8 = undefined;
swe.swe_abi.swe_get_current_file_data(0, &fname);

const file_used = std.mem.sliceTo(&fname, 0);
if (std.mem.startsWith(u8, file_used, "moshier")) {
    // Evaluation degraded: Moshier fallback active
}
```

```c
/* C equivalent */
char fname[256];
swe_get_current_file_data(0, fname);

if (strncmp(fname, "moshier", 7) == 0) {
    /* Evaluation degraded: Moshier fallback active */
}
```

---

## 5. Upstream Data Source Endpoints

Official compressed ephemerides, catalogs, and expansion archives are maintained by Astrodienst:

* **Primary HTTP / FTP Mirror**:  
  [`https://www.astro.com/ftp/swisseph/ephe/`](https://www.astro.com/ftp/swisseph/ephe/)
* **Asteroid Sub-partitions**:  
  `https://www.astro.com/ftp/swisseph/ephe/ast0/` through `/ast21/`
* **Planetary Satellites**:  
  `https://www.astro.com/ftp/swisseph/ephe/sat/`
* **Minimal Recommended Deployment**:  
  For general astrological and calendar software spanning 1800–2400 CE, deploy the demo core (`sepl_18.se1`, `semo_18.se1`, `seas_18.se1`) alongside `sefstars.txt` and `seorbel.txt` in `$EPHE`.
