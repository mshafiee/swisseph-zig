# Astronomical Models Configuration

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Architectural Role and Context Threading

Swiss Ephemeris incorporates modular models for coordinate reductions, precession, nutation, frame bias, sidereal time, and $\Delta T$.

* **Header Declarations**: `include/swephexp.h:499` (model enumerations), `include/swephexp.h:686` (`swe_set_astro_models`, `swe_get_astro_models`).
* **Implementation**: Model evaluation and rotation pipelines reside in `src/swephlib.zig`.
* **State Management (Zig vs. C)**:
  * **Zig Facade (`swe.swephlib.AstroModels`)**: Models are encapsulated in an **immutable, thread-safe value struct**. It is passed explicitly into calculation calls (`swe.calc_ut`, `swe.calc`, etc.). Because it is read-only, a single `const models = swe.swephlib.AstroModels{};` instance can be shared across all worker threads without locking.
  * **C ABI (`swe_set_astro_models`)**: Modifies an internal global array across 8 model slots. In multi-threaded C applications, altering model configurations globally can introduce non-deterministic, sub-arcsecond discrepancies between concurrent calculations.

> [!TIP]
> **Production Baseline**  
> Compiled-in defaults (`Vondrák 2011 Precession`, `IAU 2000B Nutation`, `IAU 2006 Frame Bias`, `Stephenson 2016 Delta-T`) provide optimal numerical stability and physical accuracy. Modify these settings only when reproducing historical tables, matching legacy software baselines, or aligning with NASA JPL Horizons outputs.

---

## 2. Model Slots Overview (`NSE_MODELS = 8`)

The configuration consists of 8 model slots:

| Slot Index | Macro Constant | Phenomenological Target | Default Model Setting |
| :---: | :--- | :--- | :--- |
| `0` | `SE_MODEL_DELTAT` | $\Delta T$ ($TT - UT1$) historical interpolation | `5` (`STEPHENSON_ETC_2016`) |
| `1` | `SE_MODEL_PREC_LONGTERM` | Secular precession (long-term span) | `9` (`VONDRAK_2011`) |
| `2` | `SE_MODEL_PREC_SHORTTERM` | Precession (contemporary centuries) | `9` (`VONDRAK_2011`) |
| `3` | `SE_MODEL_NUT` | Nutation in longitude ($\Delta\psi$) and obliquity ($\Delta\epsilon$) | `4` (`IAU_2000B`) |
| `4` | `SE_MODEL_BIAS` | Frame bias between ICRS and dynamical J2000 | `3` (`IAU_2006`) |
| `5` | `SE_MODEL_JPLHOR_MODE` | NASA JPL Horizons daily EOP interpolation mode | `1` (`JPLHOR_DEFAULT`) |
| `6` | `SE_MODEL_JPLHORA_MODE`| NASA JPL Horizons approximate mode (no EOP) | `3` (`JPLHORA_HYBRID`) |
| `7` | `SE_MODEL_SIDT` | Greenwich Mean Sidereal Time (GMST) | `4` (`LONGTERM_VONDRAK`) |

### Setting Configuration

```zig
// Zig: construct custom immutable models struct
var models = swe.swephlib.AstroModels{};
models.set_model(swe.swephlib.SE_MODEL_NUT, 3); // Switch to IAU 2000A
```

```c
/* C equivalent: modify global slot state */
swe_set_astro_models("NUT=IAU_2000A", 0);
```

---

## 3. Precession Formulations (Slots 1 & 2)

Controls the motion of the mean equinox and ecliptic of date relative to the ICRF/J2000.0 fixed frame. Slot 1 governs long-term historical epochs; Slot 2 governs modern epochs.

```
  Precession Long-Term Divergence vs. Vondrák 2011
 
     0" ─────── IAU 2006 / P03 (0.05 mas diff between 1000 and 3000 CE)
               │
    -1" ───────┼─────────────────────────────────────────────
               │
    -4" ───────┴─────────────────────────────── (-3.9" at 5000 BCE)
              5000 BCE                        J2000.0
```

| ID | Model Identifier | Publication / Provenance | Valid Temporal Scope | Characteristics & Tradeoffs |
| :---: | :--- | :--- | :--- | :--- |
| `1` | `LIESKE_1976` | Lieske et al. (1977, IAU 1976) | 1800 CE – 2200 CE | Legacy standard. Outside 1800–2200, produces artificial step artifacts. |
| `2` | `LASKAR_1986` | J. Laskar (1986) | 10000 BCE – 10000 CE | Extended polynomial fit based on numerical integration. |
| `3` | `WILL_EPS_LASK` | Williams (1994) $\epsilon$ + Laskar | 10000 BCE – 10000 CE | Hybrid formulation incorporating updated J2000 obliquity. |
| `4` | `WILLIAMS_1994` | J. G. Williams (1994) | 3000 BCE – 3000 CE | Validated against lunar laser ranging observations. |
| `5` | `SIMON_1994` | Simon et al. (1994) | 2000 BCE – 4000 CE | Compact polynomial series with improved secular rates. |
| `6` | `IAU_2000` | Capitaine et al. (P03) | 1000 BCE – 3000 CE | Precursor to IAU 2006; truncates higher-order time polynomials. |
| `7` | `BRETAGNON_2003` | P. Bretagnon et al. (2003) | 4000 BCE – 8000 CE | High-order Poisson series for the ecliptic and equator. |
| `8` | `IAU_2006` | Capitaine et al. (2003, P03) | 1000 CE – 3000 CE | IAU standard. Outside 1000–3000 CE, diverges by $-3.9''$ at 5000 BCE. |
| `9` | `VONDRAK_2011` | Vondrák, Capitaine, Wallace | $\mathbf{\pm 200{,}000\text{ years}}$ | **Default setting.** Stable across deep time; fits IAU 2006 near J2000. |
| `10`| `OWEN_1990` | W. M. Owen (JPL, 1990) | Extrapolated | Used in NASA JPL Horizons outside modern tabular boundaries. |
| `11`| `NEWCOMB_1898` | Simon Newcomb (1898) | Modern era only | **Never use for coordinate calculations.** Retained solely for ayanamsha fits. |

> [!WARNING]
> **Newcomb (11) Hazard**  
> Never select `NEWCOMB_1898` for standard planetary calculations. Its cubic time secular rates diverge by arcminutes to degrees over historical epochs. It exists strictly for internal calibration of traditional sidereal ayanamshas.

---

## 4. Nutation Models (Slot 3)

Models the high-frequency periodic nodding of Earth's rotational axis caused by lunar and solar gravitational torque on Earth's equatorial bulge.

| ID | Model Identifier | Periodic Terms | Target Resolution | Computational Profile |
| :---: | :--- | :---: | :---: | :--- |
| `1` | `WAHR_1980` | 106 | $\approx 1\text{ mas}$ | IAU 1980 standard. Rigid-Earth baseline with non-rigid corrections. |
| `2` | `HERRING_1987` | 106+ | $\approx 1\text{ mas}$ | Adds ocean-tide and mantle anelasticity corrections. |
| `3` | `IAU_2000A` | 1365 | $\approx 0.001\text{ mas}$ ($1\ \mu\text{as}$) | Full IERS multi-wave non-rigid Earth series. **High CPU overhead.** |
| `4` | `IAU_2000B` | 77 | $\approx 1\text{ mas}$ | **Default setting.** Truncated series matching 2000A to within $1\text{ mas}$. |
| `5` | `WOOLARD_1953`| Legacy | Coarse | Historical standard used in pre-1984 national ephemerides. |

* **Performance Analysis**: `IAU_2000A` requires evaluating 1365 trigonometric terms per coordinate calculation, increasing CPU overhead roughly tenfold compared to `IAU_2000B` (77 terms). Because the maximum difference between 2000A and 2000B is $< 1\text{ mas}$ ($0.001''$) between 1900 and 2100 CE, `IAU_2000B` is the recommended default for production workloads.
* **Sub-Milliarcsecond Precision**: Obtaining true sub-milliarcsecond nutation requires loading daily observed Earth Orientation Parameter files (`eop*.dat`) and activating `set_interpolate_nut()`.

---

## 5. Sidereal Time Reductions (Slot 7)

Governs Greenwich Mean Sidereal Time (GMST) and Earth rotation angle reductions.

| ID | Model Identifier | Standard Epoch Fit | Drift vs. Vondrák at Window Limits |
| :---: | :--- | :--- | :--- |
| `1` | `IAU_1976` | Newcomb / Aoki et al. (1982) | Diverges significantly prior to 1000 CE. |
| `2` | `IAU_2006` | P03 Equation of the Origins ($Eo$) | $\approx 0.05\text{ mas}$ at J2000; drifts at historical bounds. |
| `3` | `IERS_2010` | IERS Technical Note 36 | Modern ultra-precise Earth orientation baseline. |
| `4` | `LONGTERM_VONDRAK`| Vondrák et al. (2011) consistent | **Default setting.** Matches IAU 2006 at J2000; smooth across $\pm 200\text{ ky}$. |

* **Secular Divergence**: At J2000.0, the difference between modern models and legacy IAU 1976 is $+1\text{ ms}$. At 5400 BCE, this difference grows to $-2.5\text{ seconds}$, reaching $-57\text{ seconds}$ at the limits of the DE431 integration.
* **API Behavior**: Calling `swe_sidtime()` honors the model selected in Slot 7. In contrast, `swe_sidtime0(tjd, eps, nut)` bypasses Slot 7, calculating sidereal time from the explicit obliquity and nutation parameters passed by the caller.

---

## 6. Celestial Frame Bias (Slot 4)

Accounts for the constant spatial offset between the International Celestial Reference System (ICRF/ICRS) and the dynamical mean equator and equinox of J2000.0.

* **Physical Magnitudes**: The ICRS origin is offset from the dynamical J2000 frame by a fixed frame-bias rotation:
  $$\Delta\alpha_0 = -14.6\text{ mas}, \quad \xi_0 = -4.16\text{ mas}, \quad \eta_0 = -6.81\text{ mas}$$
* **Total Arc Offset**: The combined vector offset is approximately $53\text{ milliarcseconds}$ in Right Ascension.

| ID | Setting Macro | Rotation Semantics | Intended Use Case |
| :---: | :--- | :--- | :--- |
| `1` | `FRAME_BIAS_NONE` | Zero frame rotation ($I$). | Evaluates coordinates directly in the raw, unrotated DE406 frame. |
| `2` | `FRAME_BIAS_IAU2000` | IAU 2000 frame bias matrix $B$. | Precursor frame bias formulation. |
| `3` | `FRAME_BIAS_IAU2006` | IAU 2006 / IERS 2010 matrix $B$. | **Default setting.** Standard alignment with modern ICRF catalog stars. |

* **Raw DE406 Emulation**: To extract unrotated, barycentric DE406/DE431 vectors, pair the calculation flag `SEFLG_ICRS` with `FRAME_BIAS_NONE`.

---

## 7. NASA JPL Horizons Emulation (Slots 5 & 6)

Controls Earth Orientation Parameter (EOP) corrections to match NASA JPL Horizons ephemerides.

### Slot 5: `SE_MODEL_JPLHOR_MODE` (Full Emulation)
* `1` (`JPLHOR_DEFAULT`): When `SEFLG_JPLHOR` is active, interpolates daily observed EOP polar motion and nutation corrections ($\Delta\psi, \Delta\epsilon$) from `eop*.dat`. Spans **1962 to present**, agreeing with Horizons to within $\approx 1\text{ mas}$.
* **Boundary Extrapolation**: For dates outside the EOP observation window (prior to 1962 or beyond the latest table entry), boundary values are held flat to preserve continuous transitions without numerical step discontinuities.

### Slot 6: `SE_MODEL_JPLHORA_MODE` (Approximate Emulation)
Activated when `SEFLG_JPLHOR_APPROX` is passed without external `eop*.dat` files:
* `1` (`JPLHORA_RECENT`): Applies modern analytical approximations without tabular EOP data.
* `2` (`JPLHORA_NO_BIAS`): Legacy approximation without frame bias rotations.
* `3` (`JPLHORA_HYBRID`): **Default approximate mode.** Balances computational performance with $\approx 2\text{ mas}$ accuracy relative to Horizons.

---

## 8. Dynamic Time: Delta-T Models (Slot 0)

Determines the calculation of $\Delta T = TT - UT1$ across historical and predictive epochs.

| ID | Model Identifier | Authors & Reference | Empirical Data Fit Baseline |
| :---: | :--- | :--- | :--- |
| `1` | `DELTAT_STEPHENSON_1984` | Stephenson & Morrison (1984) | Early standard for ancient and medieval solar eclipses. |
| `2` | `DELTAT_STEPHENSON_1997` | F. R. Stephenson (1997 monograph) | Revised spline analysis of Babylonian and Chinese records. |
| `3` | `DELTAT_STEPHENSON_2004` | Stephenson & Morrison (2004) | Updated historical lunar occultation datasets. |
| `4` | `DELTAT_ESPENAK_MEEUS_2006`| F. Espenak & J. Meeus (2006) | Standard baseline used in NASA Eclipse Bulletins. |
| `5` | `DELTAT_STEPHENSON_2016` | Stephenson, Morrison, Hohenkerk | **Default setting.** Analyzes historical records from 720 BCE to 2015 CE. |

* **Secular Acceleration Coupling**: Pre-1955 historical $\Delta T$ values are coupled to the active lunar tidal acceleration parameter ($\dot{n}_\text{Moon}$). Set this parameter via `swe_set_tid_acc()` (default `SE_TIDAL_DE431 = -25.80''/\text{cy}^2`).
* **Model Divergence**: Between 1955 and the present, all models track identical atomic and IERS clock data, with differences remaining $< 2\text{ seconds}$. Prior to 1000 BCE, differing extrapolation polynomials diverge by several minutes. Publications presenting ancient historical charts should always cite the active model.
* **Manual Overrides**: Calling `swe_set_delta_t_userdef(days)` forces a manual $\Delta T$ offset. To restore automatic interpolation, reset the parameter during teardown:
  ```zig
  swe.set_delta_t_userdef(swe.deltat.SE_DELTAT_AUTOMATIC, &dctx);
  ```
