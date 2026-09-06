# Fictitious Bodies (IDs 40–58) and User-Defined Orbitals

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Architectural Overview & Indexing Rules

Swiss Ephemeris supports fictitious, hypothetical, and historical planetary bodies through analytical Keplerian and polynomial orbit propagators.

* **Source Anchors**: `include/swephexp.h:131`, `include/sweph.h:104`, solver engine `src/swemplan.zig`, orbit parameter file `seorbel.txt` (`SE_FICTFILE`).
* **Offset Formula**:
  $$\text{ipl} = 39 + \text{line number}$$
  The line number is 1-based within `seorbel.txt`.
  Where `SE_FICT_OFFSET = 40`. The first entry (line 1) maps to index `40` (`SE_CUPIDO`). The engine supports custom slots up to index `999` (`MAX = 999`).
* **Built-in Slots**: `NFICT_ELEM = 15` statically compiled fallbacks ensure IDs 40–54 evaluate even if `seorbel.txt` is missing.
* **Coordinate Vector**: Evaluations populate `xx[6]` using standard planetary conventions:
  * `xx[0]`: Ecliptic longitude ($\lambda$, degrees)
  * `xx[1]`: Ecliptic latitude ($\beta$, degrees)
  * `xx[2]`: Radial distance ($r$, AU; or geocentric distance for `, geo` bodies)
  * `xx[3]`: Longitude speed ($\Delta\lambda/\Delta t$, degrees/day)
  * `xx[4]`: Latitude speed ($\Delta\beta/\Delta t$, degrees/day)
  * `xx[5]`: Radial speed ($\Delta r/\Delta t$, AU/day)

### Usage Example

```zig
// Zig: evaluate Kronos (ID 43)
var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;

const result = swe.calc_ut(
    jd_ut,
    43, // SE_KRONOS
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
double xx[6];
char serr[256];

int result = swe_calc_ut(
    jd,
    SE_KRONOS, // 43
    SEFLG_SPEED,
    xx,
    serr
);
```

---

## 2. Standard Catalog: Bodies 40–58

### 40–47: Hamburg School / Uranian Trans-Neptunians

Developed by Alfred Witte and Friedrich Sieggrün (1920s) for symmetric astrology, later refitted with modern orbital elements by James Neely.

* **Elements**: Circular/near-circular ($e \approx 0$), coplanar ($i \approx 0^\circ$), J1900 equinox. Semi-major axes $a$ range from 40 to 84 AU. Mean daily motion $n$ is derived directly from $a$ via the Gaussian gravitational constant `KGAUSS` ($\mu = k^2$), unless an explicit polynomial $T$-term is declared in $M_0$.
* **Catalog Identifiers & Asteroid Disambiguation**:
  * **40 Cupido** (`SE_CUPIDO`) — *(Do not confuse with Main-Belt Asteroid `763 Cupido`)*
  * **41 Hades** (`SE_HADES`)
  * **42 Zeus** (`SE_ZEUS`) — *(Do not confuse with Jupiter Trojan `5731 Zeus`)*
  * **43 Kronos** (`SE_KRONOS`)
  * **44 Apollon** (`SE_APOLLON`) — *(Do not confuse with Apollo Asteroid `1862 Apollo`)*
  * **45 Admetos** (`SE_ADMETOS`)
  * **46 Vulkanus** (`SE_VULKANUS`) — *(Do not confuse with hypothetical `55 Vulcan` or asteroid `4464 Vulcano`)*
  * **47 Poseidon** (`SE_POSEIDON`) — *(Do not confuse with Apollo Asteroid `4341 Poseidon`)*
* **Limits & Constraints**: The ephemeris does not clamp evaluation dates. While valid for any Julian Day, these elements are empirical fits calibrated strictly for the **1800–2400 CE** epoch window. They must always be presented as hypothetical. Always assert numeric IDs (`40–47`) rather than matching string labels to prevent collision with actual IAU-named minor planets.
* **Error Semantics**: If `seorbel.txt` is absent, the engine falls back silently to compiled-in defaults. If a custom record in `seorbel.txt` is malformed, calculation returns `ERR` and writes the offending line number to `serr`.

---

### 48: Isis / Transpluto

* **Definition**: Hypothetical ultra-Plutonian planet proposed by Emil Strubell (*Die Sterne*, 1952) to explain remaining outer-planet residuals.
* **Elements**:
  * Epoch: 1772.76 (JD 2368547.66)
  * Equinox: 1945.0 (JD 2431456.5)
  * $a = 77.775\text{ AU}$, $e = 0.3$
* **Provenance**: Fitted empirically against ASTRON ephemeris tables rather than integrated $N$-body physics.
* **Limits**: Moderate eccentricity ($e = 0.3$) produces a tenfold orbital speed variance between perihelion and aphelion. Aspect/transit searches across Isis require step sizes smaller than standard outer planets ($< 5$ days) to avoid root skipping.

---

### 49: Nibiru

* **Definition**: Sitchin-inspired hypothetical extreme-eccentricity body parameterized by Woeltge.
* **Elements**:
  * $a = 234.8921\text{ AU}$, $e = 0.981092$
  * $i = 158.708^\circ$ (retrograde)
  * $\Omega = -44.567^\circ$, $\omega = 103.966^\circ$
* **Limits**: Extreme eccentricity ($e \approx 0.981$) results in severe perihelion velocity spikes. The standard finite-difference speed engine (`SEFLG_SPEED`) suffers numerical degradation near perihelion. For high-precision rates, evaluate position-only coordinates (`SEFLG_SPEED` cleared) and compute analytic or adaptive finite differences externally.

---

### 50: Harrington

* **Definition**: Robert S. Harrington’s Planet-X hypothesis calculated to account for perceived perturbations in Uranus and Neptune (*Astronomical Journal* 96(4), 1988).
* **Elements**:
  * $a = 101.2\text{ AU}$, $e = 0.411$, $i = 32.4^\circ$
  * $\Omega = 275.4^\circ$, $\omega = 208.5^\circ$, Epoch/Equinox: J2000
* **Limits**: Trans-Neptunian orbital period ($P \approx 1018$ years; displacement rates measured in centuries per degree). Astrological house placement (`swe_house_pos`) is valid, but horizon crossing solvers (`swe_rise_trans`) are degenerate due to near-zero diurnal parallax/motion.

---

### 51–54: Historical Planet X Predictions

Historical celestial-mechanics hypotheses compiled in William Graves Hoyt's *Planets X and Pluto*:

| ID | Macro | Theorist | Semi-Major Axis ($a$) | Eccentricity ($e$) | Inclination ($i$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **51** | `SE_NEPTUNE_LEVERRIER` | Urbain Le Verrier (Neptune prediction) | $36.15\text{ AU}$ | $0.108$ | — |
| **52** | `SE_NEPTUNE_ADAMS` | John Couch Adams (Neptune prediction) | $37.25\text{ AU}$ | $0.121$ | — |
| **53** | `SE_PLUTO_LOWELL` | Percival Lowell (Planet X) | $43.00\text{ AU}$ | $0.202$ | — |
| **54** | `SE_PLUTO_PICKERING` | William H. Pickering (Planet O) | $55.10\text{ AU}$ | $0.310$ | $15.0^\circ$ |

* **Limits**: Provided strictly for the history of celestial mechanics; these orbits must never be used for real astronomical propagation or predictive work.

---

### 55: Vulcan (Intramercurial)

* **Definition**: Hypothetical intra-Mercurial body postulated by Le Verrier to explain Mercury’s perihelion advance (prior to General Relativity).
* **Non-Keplerian Override**: Demonstrates an explicit mean anomaly polynomial overriding standard Keplerian orbital velocity:
  $$M_0(T) = 252.8987988^\circ + 707550.7341^\circ \cdot T$$
  Equinox parameters are mapped as `J1900, JDATE`.
* **Limits**: The $T$-term speed calculation violates Newtonian conservation laws by design to maintain backward compatibility with original C Swiss Ephemeris tables. Modifying the $T$-term coefficients induces velocity step-discontinuities. Verify custom changes with `swetest -p55`.

---

### 56: White Moon / Selena (Geocentric Oscillator)

* **Definition**: Geocentric monthly lunar-phase companion oscillator used in Eastern European astrology.
* **Elements**: Flagged with `, geo` designation. Epoch equinox J2000, $M_0 = 242.22^\circ$, effective radius $a \approx 0.0528\text{ AU}$ ($\approx 20.55\text{ Earth radii}$).
* **Limits**: Intrinsically geocentric. Applying `SEFLG_HELCTR` or `SEFLG_BARYCTR` returns invalid coordinates or error codes. Topocentric reductions (`SEFLG_TOPOCTR`) evaluate properly, adding diurnal parallax based on the effective geocentric distance.

---

### 57–58: Proserpina & Waldemath

* **57 Proserpina**: Hypothetical outer planet used by Russian/Hamburg-influenced traditions.
* **58 Waldemath**: The dark/second moon hypothesis proposed by Georg Waldemath (1898).
* **Limits**: Keplerian extensions. Neither body possesses a dedicated `SE_NAME_*` C preprocessor macro; `swe_get_planet_name()` returns the string literal parsed directly from `seorbel.txt`.

---

## 3. `seorbel.txt` Line Grammar & Custom Slots (IDs 59–999)

Custom fictitious bodies can be introduced by appending orbital elements to `seorbel.txt`.

### Record Schema

Each non-comment line consists of 9 comma-separated fields:

```text
epoch, equinox, M0, a, e, argp, node, incl, Name[, geo]
```

| Field | Type / Unit | Allowed Representations / Rules |
| :--- | :--- | :--- |
| `epoch` | Julian Day or Constant | Explicit Julian Day number (e.g. `2451545.0`) or symbolic tag: `J1900`, `B1950`, `J2000`. |
| `equinox` | Julian Day or Constant | Reference frame equinox: Julian Day, `J1900`, `B1950`, `J2000`, or `JDATE` (equinox of date). |
| `M0` | Degrees (+ polynomials) | Mean anomaly at epoch. May contain $T$-polynomial terms: `+ r*T`, `+ r*T2`, `+ r*T3`. |
| `a` | AU | Semi-major axis in Astronomical Units (or geocentric distance if `, geo` is present). |
| `e` | Unitless ($0.0 \le e < 1.0$) | Orbital eccentricity. |
| `argp` | Degrees | Argument of perihelion ($\omega$). |
| `node` | Degrees | Longitude of the ascending node ($\Omega$). |
| `incl` | Degrees | Orbital inclination ($i$) relative to the ecliptic plane. |
| `Name` | ASCII String | Display name returned by `swe_get_planet_name()`. Appending `, geo` designates a geocentric body. |

### Polynomial $T$-Term Syntax

When an orbital parameter varies over time, append polynomial coefficients in terms of Julian centuries ($T$) elapsed since `epoch`:

$$T = \frac{\text{JD} - \text{epoch}}{36525}$$

* Linear: `+123.456*T`
* Quadratic: `+0.0123*T2` (or `*T*T`)
* Cubic: `+0.00012*T3`

*Note: If $M_0$ contains no $T$-terms, the engine calculates mean motion $n$ strictly from semi-major axis $a$ via Kepler's third law. If a $T$-term is detected in $M_0$, Keplerian motion derivation is bypassed and the explicit derivative of $M_0(T)$ is used instead.*

### File Lookup and Parsing Mechanics

1. **Resolution Order**: The engine searches `$EPHE/seorbel.txt`, then the working directory, and finally fallback paths declared via `swe_set_ephe_path()`.
2. **Built-in Fallback**: If `seorbel.txt` cannot be found, internal static records provide data for IDs `40` to `54`. Custom slots (`59+`) will return an error indicating the file is missing.
3. **Line Index Mapping**:
   * Lines 1–15 $\rightarrow$ Built-in slots (IDs 40–54)
   * Lines 16–19 $\rightarrow$ Extensions (IDs 55–58)
   * Lines 20+ $\rightarrow$ User-defined custom bodies (IDs 59 through 999)
4. **Validation and Diagnostics**:
   To inspect the parsed solution for custom index `59` at standard epoch:
   ```bash
   swetest -p59 -b1.1.2000 -fPLBRS -n1
   ```
   If a syntax or floating-point parse failure occurs, the engine halts evaluation and writes:
   ```text
   error in line <line_no> of seorbel.txt
   ```
   Caller applications must check return codes: dates are not bounded or checked for physical validity by the engine. Users are responsible for confirming their orbital elements are well-conditioned over the target calculation epoch.
