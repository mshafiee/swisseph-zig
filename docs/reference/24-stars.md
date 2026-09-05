# Fixed Stars Astrometry and Catalogs

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. System Architecture and Data Structures

Fixed star reductions propagate stellar positions from catalog epochs to arbitrary observation dates, applying space motion, radial velocity perspective acceleration, annual and diurnal parallax, stellar aberration, light deflection, precession, and nutation.

* **Source Truth**: `struct fixed_star` (`include/sweph.h:772`), `SE_STARFILE = "sefstars.txt"` (`include/swephexp.h:387`), `SE_MAX_STNAME = 256`, API declarations `include/swephexp.h:717`.
* **Calculation Engine**: `src/sweph.zig` (coordinate reduction pipeline) and `src/swephlib.zig` (star catalog parsing).
* **Caching & Memory Lifecycle**:
  * Parsed catalog records are cached in memory within the thread-local runtime (`SweState`) in C, or inside the caller-owned workspace in Zig.
  * To release allocated star catalog memory, invoke `swe_cleanup()` in C (under `SWE_ZIG_EXTENSIONS`) or `SweState.deinit()` in Zig during application teardown. Never call teardown in per-calculation hot paths.
* **Coordinate Vector (`xx[6]`)**: Populates the same dimension layout as planetary bodies:
  * `xx[0]`: Ecliptic longitude ($\lambda$, in degrees).
  * `xx[1]`: Ecliptic latitude ($\beta$, in degrees).
  * `xx[2]`: Radial distance ($r$, in AU; derived from parallax as $1/\varpi$).
  * `xx[3..5]`: Daily velocities ($\Delta\lambda/\Delta t$, $\Delta\beta/\Delta t$, $\Delta r/\Delta t$) in $^\circ/\text{day}$ and $\text{AU/day}$.

---

## 2. Catalog Schema: `sefstars.txt`

The default stellar database `sefstars.txt` is derived from the ESA Hipparcos catalog (with cross-identifications from FK5 and traditional nomenclature). Legacy format `fixstars.cat` files are supported via internal detection (`is_old_starfile`).

### Line Record Format

Each non-comment line consists of 12 comma-delimited fields:

```text
skey,starname,starbayer,starno,epoch,ra,de,ramot,demot,radvel,parall,mag
```

| Field Index | Identifier | Unit / Format | Description & Physical Semantics |
| :---: | :--- | :--- | :--- |
| `0` | `skey` | ASCII String | Primary search identifier (often contains a leading comma, e.g., `,alAlcy`). Max length: 40 chars (`SWI_STAR_LENGTH`). |
| `1` | `starname` | ASCII String | Traditional proper name (e.g., `"Sirius"`, `"Aldebaran"`, `"Spica"`). |
| `2` | `starbayer` | ASCII String | Bayer/Flamsteed designation using 2-letter Greek prefixes (e.g., `alCMa`, `alTau`, `zePsc`). |
| `3` | `starno` | Integer String | Catalog index (e.g., Hipparcos `HIP` or `FK5` number). |
| `4` | `epoch` | Julian Day | Catalog reference epoch (typically J2000.0 = `2451545.0`). |
| `5` | `ra` | Decimal Degrees | Right Ascension ($\alpha$) referenced to the ICRS/J2000.0 frame ($[0^\circ, 360^\circ)$). |
| `6` | `de` | Decimal Degrees | Declination ($\delta$) referenced to the ICRS/J2000.0 frame ($[-90^\circ, +90^\circ]$). |
| `7` | `ramot` | $\text{arcsec}/\text{year}$ | Proper motion in Right Ascension ($d\alpha/dt$ without $\cos\delta$ projection). |
| `8` | `demot` | $\text{arcsec}/\text{year}$ | Proper motion in Declination ($d\delta/dt$). |
| `9` | `radvel` | $\text{km}/\text{s}$ | Line-of-sight radial velocity. Governs perspective acceleration over multi-millennium spans. |
| `10` | `parall` | Arcseconds ($''$) | Annual trigonometric parallax ($\varpi$). Heliocentric distance is given by $d = 1/\varpi\text{ parsecs}$. |
| `11` | `mag` | Visual Magnitude | Standard Johnson apparent visual magnitude ($V$). |

---

## 3. Name Lookup Mechanics and Buffer Mutation

Star queries match against `skey`, `starname`, `starbayer`, or `starno` using a case-insensitive substring search.

### The 512-Byte Buffer Mutation Invariant

> [!CAUTION]
> **Buffer Capacity and Mutability Requirement**  
> The input parameter `star` passed to `swe_fixstar*` is an **in-out parameter** that must point to a **writable buffer sized to at least 512 bytes** (`2 * SE_MAX_STNAME`).  
>
> When a match is found, the engine overwrites the contents of `star` with the canonical catalog entry string formatted as:  
> `"TraditionalName, BayerDesignation"`  
>
> * Passing an immutable string literal (e.g. `"Sirius"` in C) causes a memory write fault / segmentation violation.
> * Passing a buffer smaller than 512 bytes causes memory corruption.

### Lookup Precedence Rules
1. **Leading Comma Search**: Prefixing a query with a comma (e.g., `",alTau"`) restricts searches strictly to the `skey` or `starbayer` field, bypassing traditional proper names.
2. **Bayer Uniqueness**: Because traditional common names vary between translations and historical texts, **Bayer designations are preferred for programmatically unambiguous lookups** (e.g., `alVir` for Spica, `zePsc` for Revati, `alTau` for Aldebaran).

---

## 4. Astrometric Anchors and Sidereal Frames

Swiss Ephemeris anchors several fundamental fiducial stars to define sidereal ayanamshas, galactic coordinate baselines, and historical frames:

| Catalog Name | Bayer Code | Hipparcos ID | Proper Motion ($\mu_\alpha, \mu_\delta$) | Ayanamsha & Frame Relevance |
| :--- | :--- | :---: | :---: | :--- |
| **Aldebaran** | `alTau` | 21421 | $+0.063'', -0.189''$ | Defines Rohini; anchor of **Ayanamsha 14** (Aldebaran at $15^\circ$ Taurus). |
| **Spica (Chitra)** | `alVir` | 65474 | $-0.042'', -0.032''$ | Primary anchor of **Ayanamsha 27** (True Chitra / Lahiri; Spica fixed at $0^\circ$ Libra). |
| **Revati** | `zePsc` | 5447 | $+0.024'', -0.009''$ | Traditional Vedic boundary star; anchor of **Ayanamsha 28** (Revati at $29^\circ 50'$ Pisces). |
| **Pushya** | `deCnc` | 42911 | $-0.039'', -0.015''$ | Anchor of **Ayanamsha 29** (Pushya middle). |
| **Mula** | `laSco` | 85927 | $-0.009'', -0.023''$ | Galactocentric alignment anchors for **Ayanamshas 33, 35, and 36**. |
| **Sirius** | `alCMa` | 32349 | $-0.546'', -1.223''$ | High proper motion anchor; Egyptian Sothic cycles. |
| **Arcturus** | `alBoo` | 69673 | $-1.093'', -1.999''$ | High proper motion ($> 2''/\text{yr}$). Requires `fixstar2` for velocity accuracy. |
| **Regulus** | `alLeo` | 49669 | $-0.249'', +0.006''$ | Royal star; historical fiducial for Persian/Babylonian equinox alignment. |

* **Galactic and Equatorial Frames**: Specialized ayanamsha modes (Galactic modes 17, 30, 36, 40; Equator modes 31–33) evaluate dynamic offsets relative to these specific stellar coordinates (see `ayanamshas.md`).

---

## 5. API Reference: `fixstar` vs. `fixstar2`

The library provides two evaluation engines:

```
  swe_fixstar / swe_fixstar_ut
  └─ Evaluates space position (coordinates xx[0..2]).
  └─ Velocity in xx[3..5] reflects geometric Earth orbital motion only.

  swe_fixstar2 / swe_fixstar2_ut (Recommended)
  └─ Evaluates space position (coordinates xx[0..2]).
  └─ Rigorously projects space motion vectors (μ_α, μ_δ, radvel) into xx[3..5].
```

### Signatures

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

### Supported Calculation Flags (`iflag`)
* **Coordinate Systems**: `SEFLG_EQUATORIAL` (RA/Dec), `SEFLG_XYZ` (Cartesian AU), `SEFLG_RADIANS`.
* **Zodiac / Reference Frames**: `SEFLG_SIDEREAL` (projects into active ayanamsha), `SEFLG_J2000` (ICRF J2000.0 frame), `SEFLG_NONUT` (mean equinox of date).
* **Parallax Reductions**: `SEFLG_HELCTR` (heliocentric), `SEFLG_BARYCTR` (barycentric), `SEFLG_TOPOCTR` (topocentric; incorporates diurnal parallax from `parall` and `swe_set_topo`).
* **Velocity**: `SEFLG_SPEED` (populates `xx[3..5]`).

---

## 6. Implementation Examples

```zig
// Zig: Compute apparent topocentric position, daily speed, and magnitude of Spica
const std = @import("std");
const swe = @import("swisseph");

pub fn evaluateStar(jd_ut: f64, swed: *swe.sweph.Swed, dctx: *swe.deltat.DeltatCtx) !void {
    const models = swe.swephlib.AstroModels{};
    
    // Allocate mutable 512-byte buffer initialized with null termination
    var star_buf: [512:0]u8 = undefined;
    @memset(&star_buf, 0);
    const query = ",alVir"; // Target Spica via unambiguous Bayer code
    @memcpy(star_buf[0..query.len], query);

    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;

    const flags = swe.sweph.SEFLG_SWIEPH | swe.sweph.SEFLG_SPEED | swe.sweph.SEFLG_TOPOCTR;

    // Use fixstar2_ut for rigorous space motion derivatives
    const status = swe.fixstar2_ut(
        &star_buf,
        jd_ut,
        flags,
        &xx,
        &serr,
        swed,
        models,
        dctx,
    );

    if (status < 0) {
        const err_msg = std.mem.sliceTo(&serr, 0);
        std.log.err("Fixed star evaluation failed: {s}", .{err_msg});
        return error.StarNotFound;
    }

    // Query visual magnitude (bypasses ephemeris files)
    var mag: f64 = 0.0;
    _ = swe.fixstar_mag(&star_buf, &mag, &serr, swed);

    // star_buf now contains the normalized name: "Spica, alVir"
    const resolved_name = std.mem.sliceTo(&star_buf, 0);
    std.log.info("Star: {s} | Lon: {d:.6}° | Lat: {d:.6}° | Mag: {d:.2}", .{
        resolved_name, xx[0], xx[1], mag,
    });
}
```

```c
/* C equivalent */
#include <stdio.h>
#include <string.h>
#include "sweph.h"

void evaluate_star(double jd_ut) {
    // 512-byte writable buffer
    char star_buf[512];
    double xx[6];
    char serr[256];
    double mag = 0.0;

    // Search via Bayer code
    strncpy(star_buf, ",alVir", sizeof(star_buf));

    int status = swe_fixstar2_ut(
        star_buf,
        jd_ut,
        SEFLG_SWIEPH | SEFLG_SPEED | SEFLG_TOPOCTR,
        xx,
        serr
    );

    if (status < 0) {
        fprintf(stderr, "Fixed star error: %s\n", serr);
        return;
    }

    swe_fixstar_mag(star_buf, &mag, serr);

    // star_buf has been normalized to "Spica, alVir"
    printf("Star: %s | Lon: %.6f | Lat: %.6f | Mag: %.2f\n", star_buf, xx[0], xx[1], mag);
}
```

---

## 7. Diagnostics and Error Handling

| Error Symptom | Root Cause | Engine Diagnostic in `serr` | Mitigation / Solution |
| :--- | :--- | :--- | :--- |
| **`status == -1` on first call** | Missing `sefstars.txt` in `$EPHE` path. | `"cannot open sefstars.txt"` | Verify `swe_set_ephe_path()` points to a directory containing the valid star catalog. |
| **`status == -1` (file present)** | Star identifier string does not match any entry. | `"star ... not found"` | Check query string; prefer explicit Bayer designations (e.g., `",alTau"`) over vernacular names. |
| **Segmentation fault / Crash** | `star` buffer is immutable (string literal) or $< 512\text{ bytes}$. | *(None — Memory violation)* | Allocate an explicit `char star[512]` array or `var star_buf: [512:0]u8` before calling the API. |
| **Zero velocity in `xx[3..5]`** | Used `fixstar` instead of `fixstar2`, or omitted `SEFLG_SPEED`. | *(None — Status is OK)* | Call `fixstar2_ut()` with `SEFLG_SPEED` to incorporate proper motion into daily speeds. |
