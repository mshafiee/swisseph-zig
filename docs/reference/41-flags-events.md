# Eclipse, Rise-Transit, Azalt, and Heliacal Flags

> Part of the [swisseph-zig docs](../index.md) · See also: [Implementation Guides](../guide/).

---

## 1. Eclipse and Occultation Flags (`ifltype`)

The eclipse and occultation engines (`swe_sol_eclipse_*`, `swe_lun_eclipse_*`, `swe_lun_occult_*`) consume an integer bitmask (`ifltype`) that filters the search space by eclipse geometry and specifies which contact phases to evaluate.

* **Source Truth**: `include/swephexp.h:305`.
* **Provenance**: Bessellian fundamental plane projections and Saros contact mechanics implemented in `src/swecl.zig`.

### 1.1 Global Search Filters (Geometric Eclipse Classification)

These bits instruct global search routines (`*_when_glob`) to find the next eclipse satisfying specific geometric criteria:

| Macro Constant | Bit Value | Scope | Geometric Definition & Criteria |
| :--- | :--- | :--- | :--- |
| `SE_ECL_CENTRAL` | `1` (`0x0001`) | Solar | Central axis of the Moon's shadow cone intersects the terrestrial geoid. |
| `SE_ECL_NONCENTRAL` | `2` (`0x0002`) | Solar | Shadow cone intersects Earth, but the shadow axis misses the terrestrial globe. |
| `SE_ECL_TOTAL` | `4` (`0x0004`) | Solar / Lunar | Moon completely obscures the solar photosphere, or Moon is completely immersed in Earth's umbra. |
| `SE_ECL_ANNULAR` | `8` (`0x0008`) | Solar | Umbral cone terminates above Earth's surface; antumbral shadow projects an annulus. |
| `SE_ECL_PARTIAL` | `16` (`0x0010`) | Solar / Lunar | Only the penumbral shadow covers the observer (Solar), or Moon enters umbra partially (Lunar). |
| `SE_ECL_ANNULAR_TOTAL` | `32` (`0x0020`) | Solar | Hybrid eclipse; path transitions between annular and total along the central track. |
| `SE_ECL_PENUMBRAL` | `64` (`0x0040`) | Lunar | Moon passes exclusively through Earth's penumbral shadow; no umbral contact occurs. |
| `SE_ECL_ALLTYPES_SOLAR` | `63` (`0x003F`) | Solar | Bitwise OR of all solar eclipse varieties (`1 | 2 | 4 | 8 | 16 | 32`). |
| `SE_ECL_ALLTYPES_LUNAR` | `84` (`0x0054`) | Lunar | Bitwise OR of all lunar eclipse varieties (`TOTAL | PARTIAL | PENUMBRAL`). |

*Passing `ifltype = 0` defaults to checking all eclipse varieties, triggering a comprehensive, computationally demanding multi-pass search across successive syzygies.*

---

### 1.2 Local Stage Modifiers and Contact Points

When querying local visibility (`*_when_loc`) or planetary occultations (`swe_lun_occult_*`), these bits filter for specific contact phases or observation constraints:

* **`SE_ECL_VISIBLE` (`128`, `0x0080`)**: Filters strictly for events geometrically visible above the observer's local horizon.
* **`SE_ECL_MAX_VISIBLE` (`256`, `0x0100`)**: Requires that the moment of maximum eclipse occurs above the horizon.
* **`SE_ECL_1ST` / `SE_ECL_PARTBEG` (`512`, `0x0200`)**: Solves for First Contact ($C_1$, exterior ingress: partial phase begins).
* **`SE_ECL_2ND` / `SE_ECL_TOTBEG` (`1024`, `0x0400`)**: Solves for Second Contact ($C_2$, interior ingress: totality or annularity begins).
* **`SE_ECL_3RD` / `SE_ECL_TOTEND` (`2048`, `0x0800`)**: Solves for Third Contact ($C_3$, interior egress: totality or annularity ends).
* **`SE_ECL_4TH` / `SE_ECL_PARTEND` (`4096`, `0x1000`)**: Solves for Fourth Contact ($C_4$, exterior egress: partial phase ends).
* **`SE_ECL_PENUMBBEG` (`8192`, `0x2000`) / `SE_ECL_PENUMBEND` (`16384`, `0x4000`)**:
  * *Lunar*: Beginning and ending of the penumbral eclipse phase.
  * *Occultation Alias*: Reused as `SE_ECL_OCC_BEG_DAYLIGHT` and `SE_ECL_OCC_END_DAYLIGHT` to permit daylight contact solutions.
* **`SE_ECL_ONE_TRY` (`32768`, `0x8000`)**: Restricts solver iteration strictly to the single upcoming syzygy/conjunction. If the event does not qualify, the search halts immediately rather than iterating through subsequent lunations.

---

### 1.3 Output Arrays: `tret[10]` and `attr[20]`

Calls to eclipse routines populate timing vectors and physical attribute buffers:

```
  tret Array (Timing Coordinates - Julian Days)
  ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬─────────────┐
  │ tret[0]  │ tret[1]  │ tret[2]  │ tret[3]  │ tret[4]  │ tret[5]  │ tret[6..9]  │
  │ Max Time │ C1 (Beg) │ C2 (Tot) │ C3 (End) │ C4 (Fin) │ Penumbral│ Aux / Spare │
  └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘

  attr Array (Eclipse Phenomena Attributes)
  ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬─────────────┐
  │ attr[0]  │ attr[1]  │ attr[2]  │ attr[3]  │ attr[4]  │ attr[5]  │ attr[6..19] │
  │ Fraction │ Obscur.  │ Diam Rat │ Sun Az   │ Sun Alt  │ Gamma    │ Saros/Dur.  │
  └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘
```

* **`tret[10]` (Time Results)**:
  * `tret[0]`: Julian Day of maximum eclipse.
  * `tret[1]`: Time of first contact ($C_1$, partial phase begins).
  * `tret[2]`: Time of second contact ($C_2$, totality/annularity begins).
  * `tret[3]`: Time of third contact ($C_3$, totality/annularity ends).
  * `tret[4]`: Time of fourth contact ($C_4$, partial phase ends).
  * `tret[5]`: Penumbral contact start (lunar).
  * `tret[6]`: Penumbral contact end (lunar).
* **`attr[20]` (Phenomenological Attributes)**:
  * `attr[0]`: Eclipse magnitude (fraction of solar/lunar diameter obscured).
  * `attr[1]`: Eclipse obscuration (fraction of solar disc area obscured).
  * `attr[2]`: Ratio of lunar apparent diameter to solar apparent diameter.
  * `attr[3]`: True solar azimuth at maximum eclipse ($^\circ$).
  * `attr[4]`: True solar elevation at maximum eclipse ($^\circ$).
  * `attr[5]`: Least umbral axis distance to Earth center ($\Gamma$, in Earth equatorial radii).
  * `attr[6]`: Saros series designation number.
  * `attr[7]`: Central duration of totality/annularity (seconds).

### Usage Example

```zig
// Zig: find the next total solar eclipse globally
var tret: [10]f64 = undefined;
var attr: [20]f64 = undefined;
var serr: [256]u8 = undefined;

const ret = swe.sol_eclipse_when_glob(
    jd_ut,
    swe.sweph.SEFLG_SWIEPH,
    swe.swecl.SE_ECL_TOTAL,
    &tret,
    false, // search forward in time
    &attr,
    &serr,
    &swed,
    models,
    &dctx,
);

if (ret < 0) {
    // Handle ephemeris boundary or search failure
}
```

```c
/* C equivalent */
double tret[10];
double attr[20];
char serr[256];

int ret = swe_sol_eclipse_when_glob(
    jd_ut,
    SEFLG_SWIEPH,
    SE_ECL_TOTAL,
    tret,
    0, // forward search
    attr,
    serr
);
```

* **Error Behavior**: Passing `backward = true` scans into historical epochs; reaching the edge of the active ephemeris returns `ERR` (`-1`) without buffer wrap. Unimplemented event types (e.g. types `5` and `6`) return an explicit error.

---

## 2. Rise, Set, and Transit Flags (`rsmi`)

Horizon crossing and meridian transit calculations (`swe_rise_trans`, `swe_rise_trans_true_hor`) evaluate geographic observer events using an event mask (`rsmi`).

### 2.1 Fundamental Transit Operations (Select $\ge 1$)

* **`SE_CALC_RISE` (`1`, `0x0001`)**: Local horizon rising.
* **`SE_CALC_SET` (`2`, `0x0002`)**: Local horizon setting.
* **`SE_CALC_MTRANSIT` (`4`, `0x0004`)**: Upper meridian transit (culmination; local apparent noon when evaluating the Sun).
* **`SE_CALC_ITRANSIT` (`8`, `0x0008`)**: Lower meridian transit (antimeridian transit; nadir / true midnight).

---

### 2.2 Disc Geometry and Reduction Modifiers

* **Upper Limb vs. Disc Center**: By default, rising and setting times for the Sun and Moon are defined by the **upper limb** touching the refracted horizon.
  * **`SE_BIT_DISC_CENTER` (`256`, `0x0100`)**: Overrides upper limb semantics; computes event when the geometric center of the body's disc crosses the horizon.
  * **`SE_BIT_DISC_BOTTOM` (`8192`, `0x2000`)**: Solves for the lower limb contacting the horizon.
* **`SE_BIT_NO_REFRACTION` (`512`, `0x0200`)**: Disables atmospheric refraction, computing geometric horizon intersections in vacuo.
* **`SE_BIT_GEOCTR_NO_ECL_LAT` (`128`, `0x0080`)**: Forces geocentric calculations while zeroing ecliptic latitude ($\beta = 0.0^\circ$).
* **`SE_BIT_FIXED_DISC_SIZE` (`16384`, `0x4000`)**: Forces a constant standard semi-diameter ($16'$ for Sun, Moon), bypassing dynamic topocentric distance scaling.
* **`SE_BIT_HINDU_RISING`**: Preconfigured composite macro used in classical Indian astronomy:
  $$\text{Hindu rising} = \text{disc center} \mid \text{no refraction} \mid \text{geocentric, no ecliptic latitude}$$

---

### 2.3 Twilight Altitude Angles

When calculating solar rise/set, these flags override the standard apparent horizon with solar depression angles:

| Twilight Macro | Bit Value | Target Solar Depression Angle | Physical / Operational Definition |
| :--- | :--- | :--- | :--- |
| `SE_BIT_CIVIL_TWILIGHT` | `1024` (`0x0400`) | $-6.0^\circ$ below horizon | Terrestrial horizon visible; artificial lighting generally unnecessary outdoors. |
| `SE_BIT_NAUTIC_TWILIGHT` | `2048` (`0x0800`) | $-12.0^\circ$ below horizon | Sea horizon indistinguishable; navigational stars visible to mariners. |
| `SE_BIT_ASTRO_TWILIGHT` | `4096` (`0x1000`) | $-18.0^\circ$ below horizon | Atmospheric scattered sunlight reaches zero; true astronomical darkness. |

---

### 2.4 Parameters and Environmental Constraints

* **`geopos[3]`**: Double array containing observer coordinates:
  * `geopos[0]`: Geographic longitude in decimal degrees (positive East of Greenwich).
  * `geopos[1]`: Geographic latitude in decimal degrees (positive North of Equator).
  * `geopos[2]`: Height above sea level in meters ($\text{m}$).
* **`atpress`**: Atmospheric surface pressure in millibars/hectopascals ($\text{hPa}$). Setting `atpress = 0.0` disables atmospheric refraction. Standard mean sea level default is $1013.25\text{ hPa}$.
* **`attemp`**: Ambient temperature in degrees Celsius ($^\circ\text{C}$). Standard default is $10.0^\circ\text{C}$.
* **`horhgt`**: Angular depression or elevation of the local horizon in degrees (used exclusively in `swe_rise_trans_true_hor`).

```zig
// Zig: compute Nautical Sunrise at sea level
var tret: f64 = undefined;
var serr: [256]u8 = undefined;
const geopos = [3]f64{ 8.5417, 47.3769, 410.0 }; // Zurich

const flags = swe.sweph.SE_CALC_RISE | swe.sweph.SE_BIT_NAUTIC_TWILIGHT;

const status = swe.rise_trans(
    jd_ut,
    0, // SE_SUN
    null,
    swe.sweph.SEFLG_SWIEPH,
    flags,
    &geopos,
    1013.25,
    10.0,
    &tret,
    &serr,
    &swed,
    models,
    &dctx,
);

if (status < 0) {
    // Body is circumpolar or calculation out of range
}
```

* **Limits & Errors**: If a target body is circumpolar (never sets or never rises at the requested latitude), the function fails, returning `ERR` (`-1`) and writing `"body never rises"` or `"body never sets"` into `serr`. Twilight flags are invalid without `SE_CALC_RISE` or `SE_CALC_SET`.

---

## 3. Horizontal Coordinate Transformation and Refraction Flags

Functions `swe_azalt`, `swe_azalt_rev`, and `swe_refrac_extended` perform frame conversions between celestial and local horizontal coordinates, including atmospheric refraction corrections.

### 3.1 Frame Selection (`calc_flag`)

* **`SE_ECL2HOR` (`0`) / `SE_HOR2ECL` (`0`)**: Transforms between ecliptic ($\lambda, \beta$) and local horizontal coordinates (Azimuth, Altitude).
* **`SE_EQU2HOR` (`1`) / `SE_HOR2EQU` (`1`)**: Transforms between equatorial ($\alpha, \delta$) and local horizontal coordinates (Azimuth, Altitude).

### 3.2 Refraction Direction Mode

* **`SE_TRUE_TO_APP` (`0`)**: Transforms true geometric altitude into apparent (observed) altitude by adding the atmospheric refraction angle:
  $$h_{\text{app}} = h_{\text{true}} + R(h_{\text{true}}, P, T)$$
* **`SE_APP_TO_TRUE` (`1`)**: Corrects an observed apparent altitude back to true geometric altitude by subtracting refraction:
  $$h_{\text{true}} = h_{\text{app}} - R'(h_{\text{app}}, P, T)$$

### 3.3 Conventions and Lapse Rate

* **Coordinate Slices**:
  * Input `xin[3]`: Longitude/RA ($^\circ$), Latitude/Dec ($^\circ$), Radial Distance ($\text{AU}$).
  * Output `xaz[3]`:
    * `xaz[0]`: Local Azimuth ($0^\circ \le \text{Az} < 360^\circ$; measured from **South** eastward/westward: $0^\circ = \text{South}$, $90^\circ = \text{West}$, $180^\circ = \text{North}$, $270^\circ = \text{East}$).
    * `xaz[1]`: True geometric altitude without refraction ($[-90^\circ, +90^\circ]$).
    * `xaz[2]`: Apparent refracted altitude ($[-90^\circ, +90^\circ]$).
* **Atmospheric Lapse Rate**: Configured via `swe_set_lapse_rate(rate)`. The default value `SE_LAPSE_RATE = 0.0065\text{ K/m}$ ($6.5\text{ K/km}$) represents the international standard atmosphere lapse rate.
* **Physical Limits**: Near the horizon ($h \approx 0^\circ$), standard atmospheric refraction is $\approx 34'$ ($0.566^\circ$), with variations of up to $\pm 0.5^\circ$ caused by temperature inversions and pressure fluctuations. Treat horizon-adjacent results as modeled approximations rather than exact observations.

---

## 4. Heliacal Rising and Setting Flags (`helflag` and `TypeEvent`)

The heliacal engine evaluates visibility phenomena for stars and planets immersed in dawn or dusk twilight based on the Bradley Schaefer observational visibility model (`src/swehel.zig`).

### 4.1 Heliacal Event Classifications (`TypeEvent`)

```
  Evening Twilight (Dusk)                          Morning Twilight (Dawn)
  Sun Sets ──>                                     ──> Sun Rises
  ┌──────────────────────────────┐                 ┌──────────────────────────────┐
  │ Type 2: Heliacal Setting     │                 │ Type 1: Heliacal Rising      │
  │ ("Evening Last" / Acronychal)│                 │ ("Morning First")            │
  │ Body sets just after Sun     │                 │ Body rises just before Sun   │
  ├──────────────────────────────┤                 ├──────────────────────────────┤
  │ Type 3: Evening First        │                 │ Type 4: Morning Last         │
  │ Body becomes visible in dusk │                 │ Body fades into dawn twilight│
  └──────────────────────────────┘                 └──────────────────────────────┘
```

1. **`SE_HELIACAL_RISING` / `SE_MORNING_FIRST` (`1`)**: Heliacal rising. The body emerges from solar conjunction, making its first visible morning appearance in the dawn twilight before sunrise.
2. **`SE_HELIACAL_SETTING` / `SE_EVENING_LAST` (`2`)**: Heliacal setting. The body approaches solar conjunction, making its final visible evening appearance in the dusk twilight after sunset.
3. **`SE_EVENING_FIRST` (`3`)**: Acronychal rising/first visibility. The body becomes visible in the evening dusk for the first time.
4. **`SE_MORNING_LAST` (`4`)**: Cosmical setting/last visibility. The body sets at dawn, marking its final morning visibility.
* *Values `5` and `6` are reserved for specialized historical variants and are currently unimplemented; passing them returns `ERR` (`-1`).*

---

### 4.2 Algorithm Modifiers (`helflag`)

* **`SE_HELFLAG_LONG_SEARCH` (`128`, `0x0080`)**: Extends the root-finding window across multiple synodic periods if no qualifying visibility threshold is satisfied within the initial interval.
* **`SE_HELFLAG_HIGH_PRECISION` (`256`, `0x0100`)**: Enforces fine-tolerance iterative root-solving down to arcsecond precision.
* **`SE_HELFLAG_OPTICAL_PARAMS` (`512`, `0x0200`)**: Instructs the visibility engine to evaluate user-supplied optical instrument and physiological observer parameters (`dobs`) and local atmosphere variables (`datm`).
* **`SE_HELFLAG_NO_DETAILS` (`1024`, `0x0400`)**: Skips computing detailed physical ephemerides (such as arcus visionis, extinction coefficients, and contrast margins), returning event dates faster.
* **`SE_HELFLAG_SEARCH_1_PERIOD` (`2048`, `0x0800`)**: Confines iteration strictly to a single orbital period.

---

### 4.3 Visual Physiology and Atmospheric Extinction

* **`SE_HELFLAG_VISLIM_DARK` (`4096`, `0x1000`)**: Forces sky brightness calculations to assume an unpolluted, moonless astronomical night background.
* **`SE_HELFLAG_VISLIM_NOMOON` (`8192`, `0x2000`)**: Suppresses lunar phase and elevation contributions to sky brightness.
* **Photopic vs. Scotopic Vision Selection**:
  * `SE_HELFLAG_PHOTOPIC` (`16384`, `0x4000`): Daytime cone vision.
  * `SE_HELFLAG_SCOTOPIC` (`32768`, `0x8000`): Nighttime rod vision.
  * *Default*: Intermediate mesopic/mixedopic vision (`MIXEDOPIC = 2`), transitioning dynamically based on integrated background sky luminance.
* **Aerosol Extinction Bands**: `SE_HELFLAG_AV` / `SE_HELFLAG_VR` (`65536`, `0x00010000`) select between visual and photographic extinction calibrations, alongside variants `PTO`, `MIN7`, and `MIN9`.

---

### 4.4 Parameter Buffers and Boundary Sentinel

* **`datm[4]` (Atmospheric Vector)**:
  * `datm[0]`: Barometric pressure in $\text{hPa}$ ($1013.25\text{ hPa}$ nominal).
  * `datm[1]`: Surface temperature in $^\circ\text{C}$ ($15.0^\circ\text{C}$ nominal).
  * `datm[2]`: Relative humidity in percent ($[0.0\%, 100.0\%]$).
  * `datm[3]`: Meteorological visual range ($\text{VR}$) in kilometers ($\text{km}$).
* **`dobs[6]` (Observer & Instrument Vector)**:
  * `dobs[0]`: Observer age in years (modulates crystalline lens transmission and pupil diameter; default $30$).
  * `dobs[1]`: Snellen visual acuity ratio (default $1.0$ for $20/20$ vision).
  * `dobs[2]`: Monocular vs. Binocular flag ($0 = \text{monocular}$, $1 = \text{binocular}$).
  * `dobs[3]`: Telescope clear objective aperture in millimeters ($\text{mm}$; $0 = \text{naked eye}$).
  * `dobs[4]`: Telescope optical magnification power ($0 = \text{naked eye}$).
  * `dobs[5]`: Optical transmission efficiency factor ($[0.0, 1.0]$; typically $0.7\text{ to }0.85$).
* **The No-Event Sentinel (`TJD_INVALID`)**:
  Defined as `TJD_INVALID = 99999999.0`.
  At high terrestrial latitudes during summer (midnight sun), twilight never darkens to the threshold required for stars to become visible; heliacal risings and settings do not occur. When this occurs, the engine returns `TJD_INVALID`. This is a physical sky condition, not an internal calculation error.

```zig
// Zig: evaluate heliacal rising of Sirius
var darr: [50]f64 = undefined;
var tret: f64 = undefined;
var serr: [256]u8 = undefined;

const hel_flags = swe.swehel.SE_HELFLAG_HIGH_PRECISION
                | swe.swehel.SE_HELFLAG_OPTICAL_PARAMS;

const status = swe.heliacal_ut(
    jd_ut,
    &geopos,
    &datm,
    &dobs,
    "Sirius",
    swe.swehel.SE_HELIACAL_RISING,
    hel_flags,
    &darr,
    &tret,
    &serr,
    &swed,
    models,
    &dctx,
);

if (tret == swe.swehel.TJD_INVALID) {
    // Body is circumpolar or sun never drops low enough (e.g. polar summer)
} else if (status < 0) {
    // Physical parameter error (e.g., negative pressure)
}
```
