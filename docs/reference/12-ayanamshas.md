# Ayanamsha Systems (Modes 0–46 & 255 User-Defined)

> Part of the [swisseph-zig documentation](../index.md) · [API Tour](../guide/01-api.md) · [Reduction Models](../reference/11-models.md)

Sidereal longitudes are obtained by subtracting the ayanamsha angle $A(t)$ from the tropical ecliptic longitude:

$$\lambda_{\text{sidereal}} = (\lambda_{\text{tropical}} - A(t)) \pmod{360^\circ}$$

`swisseph-zig` provides **47 predefined ayanamsha systems** (`SE_NSIDM_PREDEF = 47`, modes `0` through `46`) alongside a fully custom user-defined mode (`255`).

### Sources of Truth
- **Mode Constants:** `include/swephexp.h:238`
- **Reference Table (`aya_init`):** `include/sweph.h:351`
- **Reduction Kernels:** `src/sweph.zig:1248` (frames) and `src/sweph.zig:1382` (star anchors)

---

## Engine Mechanics & Precession Handling

For predefined modes with static definitions:
- **Reference Parameters:** Defined by a zero or anchor epoch $t_0$ (Julian Day) and an initial ayanamsha offset $A(t_0)$ in degrees.
- **Precession Models:** Historical ayanamshas were originally parameterized against older precession models (e.g., Newcomb, IAU 1976). By default, `swisseph-zig` automatically corrects for the difference between the historical model and the modern **Vondrák (2011)** precession curve unless overridden by `SIDBIT_NO_PREC_OFFSET` or `SIDBIT_PREC_ORIG`.
- **Time Scale Flag (`t0_is_UT`):** If set (`Y`), the reference epoch $t_0$ is evaluated in Universal Time ($\text{UT1}$) and adjusted via observational $\Delta T$; otherwise, it is treated as Terrestrial Time ($\text{TT}$).

---

## Quick Start Example

### Native Zig (Explicit Context)
```zig
const std = @import("std");
const swe = @import("swisseph");

// 1. Configure sidereal engine to Lahiri (mode 1)
swe.set_sid_mode(swe.sweph.SE_SIDM_LAHIRI, 0, 0, &swed, null);

// 2. Query ayanamsha value at epoch jd_ut
var aya: f64 = 0;
_ = swe.get_ayanamsa_ex_ut(jd_ut, 0, &aya, &swed, models, &dctx, &serr);

// 3. Compute sidereal planetary coordinates (MUST set SEFLG_SIDEREAL)
var xx: [6]f64 = undefined;
const flags = swe.sweph.SEFLG_SPEED | swe.sweph.SEFLG_SIDEREAL;
_ = swe.calc_ut(jd_ut, 0, flags, &xx, &swed, models, &dctx, &serr);

std.debug.print("Ayanamsha: {d:.6}°, Sun Sidereal Lon: {d:.6}°\n", .{ aya, xx[0] });
```

### C ABI Drop-In
```c
#include "swephexp.h"

swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
double aya = swe_get_ayanamsa_ut(jd_ut);

double xx[6];
char serr[256];
swe_calc_ut(jd_ut, SE_SUN, SEFLG_SPEED | SEFLG_SIDEREAL, xx, serr);
```

---

## Group 1: Tropical-Epoch Indian & Modern Western (0–8, 43–46)

These systems anchor the zodiac by measuring an angular offset $A(t_0)$ relative to a 20th-century tropical epoch:

| ID | Name | Epoch $t_0$ (JD) | Offset $A(t_0)$ | Base Precession | Historical Notes & Nuances |
|:--:|---|:--:|:--:|:--:|---|
| **0** | **Fagan/Bradley** | `2433282.42346`<br>*(1950-01-01)* | $24.0420444^\circ$ | Newcomb | **Default mode.** Aligns Spica to exactly $24^\circ 00' 00''$ Virgo. Standard for Western sidereal astrology. |
| **1** | **Lahiri** | `2435553.5`<br>*(1956-03-21)* | $23.2501828^\circ$<br>$- 0.0046580^\circ$ | IAU 1976 | **Indian Official Standard (IAE 1989).** Matches Indian Ephemeris $\ge 1960$ within $\pm 0.1''$. |
| **2** | **DeLuce** | `1721057.5`<br>*(1 CE Jan 1)* | $0.0^\circ$ | None (UT) | Traditional zero-epoch set to the incarnation epoch. |
| **3** | **B.V. Raman** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 338.98556^\circ$<br>($21.01444^\circ$) | Newcomb | Standard Raman system based on Hindu astronomy revivals. |
| **4** | **Usha/Shashi** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 341.33904^\circ$<br>($18.66096^\circ$) | None | Derived from Indian textbook formulations. |
| **5** | **Krishnamurti (KP)** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 337.63611^\circ$<br>($22.36389^\circ$) | Newcomb | Coincides with tropical zodiac around 291 CE. Used in KP Horary. |
| **6** | **Djwhal Khul** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 333.03690^\circ$<br>($26.96310^\circ$) | None | Theosophical calculation placing the Age of Aquarius at 2117 CE. |
| **7** | **Yukteshwar** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 338.91778^\circ$<br>($21.08222^\circ$) | None | ⚠️ **Warning:** Intended to anchor on Revati, but incorporates an ancient $54''/\text{yr}$ precession rate, leading to a **$\sim 2.5^\circ$ error**. |
| **8** | **J.N. Bhasin** | `2415020.0`<br>*(J1900.0)* | $360^\circ - 338.63444^\circ$<br>($21.36556^\circ$) | None | Modern Indian variation. |
| **43** | **Lahiri (1940)** | `2415020.0`<br>*(J1900.0)* | $22.4459722^\circ$ | Newcomb | Original parameterization by N.C. Lahiri prior to the 1956 Calendar Reform Committee. |
| **44** | **Yukteshwar VP285**| `1825235.24585`<br>*(285 CE)* | $0.0^\circ$ | None | Zero coincidence epoch set to 285 CE. |
| **45** | **Yukteshwar VP291**| `1827424.75226`<br>*(291 CE)* | $0.0^\circ$ | None | Zero coincidence epoch set to 291 CE. |
| **46** | **ICRC (Woolard)** | `2435553.5`<br>*(1956-03-21)* | $23.25^\circ$<br>$- 0.0046421^\circ$ | Newcomb | Indian Calendar Reform Committee definition using Woolard nutation. **Differs from Mode 1 by 1.1 arcseconds**. |

---

## Group 2: Babylonian & Antiquity Reconstructions (9–16, 38, 42)

Reconstructions of ancient cuneiform, Hellenistic, and Persian zodiacs. All treat $t_0$ as Universal Time (`t0_is_UT = Y`):

| ID | Name | Epoch $t_0$ (JD) | Offset $A(t_0)$ | Historical Provenance & Description |
|:--:|---|:--:|:--:|---|
| **9** | **Kugler 1** | `1684532.5` *(−100)* | $-5.667^\circ$ | F.X. Kugler reconstruction (System B texts). |
| **10** | **Kugler 2** | `1684532.5` *(−100)* | $-4.267^\circ$ | Kugler variant. |
| **11** | **Kugler 3** | `1684532.5` *(−100)* | $-3.417^\circ$ | Kugler variant. |
| **12** | **Huber** | `1684532.5` *(−100)* | $-4.467^\circ$ | Peter Huber (1958) cuneiform tablet statistical analysis. |
| **13** | **Mercier** | `1673941.0` *(−129)* | $-5.079^\circ$ | R. Mercier reconstruction; anchors $\eta$ Piscium at $0^\circ$ Aries. |
| **14** | **Aldebaran 15 Tau** | `1684532.5` *(−100)* | $-4.441^\circ$ | Babylonian "norming" system fixing Aldebaran at exactly $15^\circ 00' 00''$ Taurus. |
| **15** | **Hipparchos** | `1674484.0` *(−128)* | $-9.333^\circ$ | Alignment derived from Hipparchus' star observation records. |
| **16** | **Sassanian** | `1927135.87` *(564 CE)*| $0.0^\circ$ | Persian Sassanian astronomical tables (*Zik-i Shahriyar*). |
| **38** | **Britton** | `1721057.5` *(1 CE)* | $-3.200^\circ$ | John P. Britton (2010) revised Babylonian lunar analysis. |
| **42** | **Vettius Valens** | `1775845.5` *(150 CE)*| $-2.9422^\circ$ | Hellenistic astrological practice based on Valens' *Anthologies*. |

---

## Group 3: Classical Vedic Zero-Epochs (21–26, 37)

These systems define the zero point as the exact moment of mean-Sun Aries ingress at the meridian of **Ujjain, India** ($75^\circ 46'\text{ E}$) in **499 CE** (`t0_is_UT = Y`):

| ID | Name | Epoch $t_0$ (JD) | Offset $A(t_0)$ | Astronomical Definition |
|:--:|---|:--:|:--:|---|
| **21** | **Surya Siddhanta (SS)** | `1903396.81287` | $0.0^\circ$ | Exact sunrise ingress according to the canonical *Surya Siddhanta*. |
| **22** | **SS (Mean Sun)** | `1903396.81287` | $-0.21463^\circ$ | Correction accounting for the mean Sun at the Ujjain meridian. |
| **23** | **Aryabhata** | `1903396.78953` | $0.0^\circ$ | Exact ingress defined according to the *Aryabhatiya*. |
| **24** | **Aryabhata (Mean Sun)**| `1903396.78953` | $-0.23763^\circ$ | Aryabhata calculation adjusted for the mean Sun. |
| **25** | **SS Revati** | `1903396.81287` | $-0.79167^\circ$ | Anchors $\zeta$ Piscium (Revati) at $359^\circ 50'$ (traditional junction star). |
| **26** | **SS Citra** | `1903396.81287` | $+2.11070^\circ$ | Anchors Spica (Citra) at exactly $180^\circ 00'$ (opposite $0^\circ$ Aries). |
| **37** | **Kali-522** | `1911797.74078` | $0.0^\circ$ | Era marked at Year 522 of the Kali Yuga epoch. |

---

## Group 4: Dynamically Computed Star & Galactic Systems (17, 27–36, 39–41)

Unlike static tables, these systems are **dynamically evaluated at runtime** (`src/sweph.zig:1382`). The engine queries star catalogs or galactic pole coordinates on every call:

| ID | Name | Anchor Target | Target Coordinate | Engine Requirement |
|:--:|---|---|---|---|
| **17** | **Galactic Center** | Galactic Center ($Sgr A^*$) | $0^\circ 00' 00''$ Sagittarius | Mathematical frame |
| **27** | **True Citra** | Star Spica ($\alpha$ Virginis) | $0^\circ 00' 00''$ Libra ($180^\circ$ ecliptic) | Requires `sefstars.txt` |
| **28** | **True Revati** | Star Revati ($\zeta$ Piscium) | $29^\circ 50' 00''$ Pisces | Requires `sefstars.txt` |
| **29** | **True Pushya** | Star Pushya ($\delta$ Cancri) | $16^\circ 00' 00''$ Cancer | Requires `sefstars.txt` |
| **30** | **Gil Brand** | Golden Section calculation | $\Phi$-based division | Mathematical frame |
| **31** | **Galactic Equator (IAU 1958)**| IAU 1958 Radio Pole | Ascending node on ecliptic | Standard pole matrix |
| **32** | **Galactic Equator (True)** | Liu / Zhu / Zhang (2010) pole| Modern high-precision pole | Standard pole matrix |
| **33** | **Galactic Equator (Mula)** | Galactic Equator | Intersection with Mula nakshatra | Mathematical frame |
| **34** | **Mardyks** | Galactic center offset | $30^\circ 00'$ at `2451079.734892` | Mathematical frame |
| **35** | **True Mula** | Star $\lambda$ Scorpii (Shaula) | $0^\circ 00' 00''$ Sagittarius (Chandra Hari) | Requires `sefstars.txt` |
| **36** | **Wilhelm Mula** | Mula Nakshatra boundary | Ernst Wilhelm definition | Mathematical frame |
| **39** | **Sheoran Vedic** | Star $\alpha$ Centauri | Vedic alignment model | Requires `sefstars.txt` |
| **40** | **Cochrane** | Galactic / Supergalactic plane | $0^\circ 00' 00''$ Capricorn | Mathematical frame |
| **41** | **Fiorenza** | Galactic Center | $25.0^\circ$ at J2000 (`2451544.5 UT`) | Mathematical frame |

> ⚠️ **Data File Dependency:** Modes **27, 28, 29, 35, and 39** require `sefstars.txt` to be present in the ephemeris directory. If the file cannot be loaded, these calls will fail with a hard error (`ERR`).

---

## Group 5: Fixed Inertial Frames (18–20) & User Mode (255)

### Fixed Inertial Reference Frames
Modes 18–20 bypass precession adjustments (`prec = 0`). Coordinates are returned directly relative to fixed astronomical frames rather than the moving equinox of date:
- **18 (J2000):** Mean dynamical equinox and equator of J2000.0 (`JD 2451545.0 TT`).
- **19 (J1900):** Standard B1900 / J1900 frame (`JD 2415020.0`).
- **20 (B1950):** FK4 Besselian frame (`JD 2433282.42346`).

### Custom User Mode (Mode 255)
Define a custom ayanamsha by calling `set_sid_mode` with mode `255`, supplying your own reference epoch `t0` and initial offset `ayan_t0`:

```zig
// Configure user-defined sidereal mode
const t0: f64 = 2451545.0;     // Reference JD
const ayan_t0: f64 = 24.50000; // Offset at t0 in degrees

// Combine mode 255 with configuration bitflags
const mode_flags: i32 = 255 | swe.sweph.SIDBIT_USER_UT;

swe.set_sid_mode(mode_flags, t0, ayan_t0, &swed, null);
```

#### User Configuration Bitflags
- `SIDBIT_USER_UT (1024)`: Treat `t0` as Universal Time ($\text{UT1}$), applying $\Delta T$.
- `SIDBIT_ECL_T0 (256)`: Measure positions relative to the ecliptic of epoch $t_0$ rather than the ecliptic of date.
- `SIDBIT_SSY_PLANE (512)`: Measure positions relative to the Solar System Invariable Plane.
- `SIDBIT_ECL_DATE (2048)`: Force reference against the moving ecliptic of date.

---

## Critical Traps & Failure Modes

1. **The Silent Tropical Trap:**  
   Calling `swe.calc_ut` without passing `SEFLG_SIDEREAL` will return **tropical positions silently**, completely ignoring the mode selected with `swe.set_sid_mode`. Always bitwise-OR the flag:
   ```zig
   const iflag = base_flags | swe.sweph.SEFLG_SIDEREAL;
   ```
2. **Out-of-Range Mode Resets:**  
   Passing any mode index $\ge 47$ that is not explicitly `255` causes the engine to **silently reset to Mode 0 (Fagan/Bradley)**. Always validate mode ranges before passing them to the engine.
3. **Discrepancies Between Related Modes:**  
   - Mode 1 (Lahiri modern) and Mode 46 (ICRC historical) differ by **$1.1$ arcseconds**.
   - Mode 7 (Yukteshwar) deviates by **$+2.5^\circ$** from actual star positions due to its erroneous historical precession rate ($54''/\text{yr}$).
