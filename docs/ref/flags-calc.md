# Calculation Flags `SEFLG_*` + `NODBIT` + `SPLIT_DEG` — full depth

Truth: `include/swephexp.h:186`. Combine with `|`; `iflag==0` = SWIEPH apparent geocentric ecliptic deg, true equinox of date, no speed.
Per-flag pattern: definition → effect/units → provenance → limits → example → error path.

Shared example:
```zig
const flg = swe.sweph.SEFLG_SWIEPH | swe.sweph.SEFLG_SPEED | swe.sweph.SEFLG_SIDEREAL;
_ = swe.calc_ut(jd_ut, 0, flg, &xx, &swed, models, &dctx, &serr);
```
```c
int flg = SEFLG_SWIEPH | SEFLG_SPEED;
swe_calc_ut(jd, SE_SUN, flg, xx, serr);
```

## Ephemeris select (pick ≤1)
* `JPLEPH=1` — raw `.eph` (highest fidelity, 2.6 GB). Needs `set_jpl_file`; missing → `ERR`.
* `SWIEPH=2` (**default**) — compressed `.se1` (1 mas vs JPL). Missing → Moshier fallback + `serr` notice (silent downgrade — assert file in tests).
* `MOSEPH=4` — analytic (no files; <1" planets, arcsec Moon). Valid 3000 BCE–3000 CE (inner 1350 BCE+).
* Multiple set → last-wins per engine order, don't combine. None set → SWIEPH.

## Frame / correction toggles
* `HELCTR=8` Sun-centered; `BARYCTR=16384` SSB-centered; `TOPOCTR=32768` observer-centered (needs `set_topo`, else geocenter silently). `ORBEL_AA=TOPOCTR` reuses bit for Kepler AA mode.
* `TRUEPOS=16` geometric (no light-time/aberration/deflection — up to 20" off apparent). `J2000=32` no precession; `NONUT=64` mean equinox. `NOGDEFL=512` / `NOABERR=1024` drop bend/aberration; `ASTROMETRIC=1536` = light-time only.
* Limits: `TRUEPOS` + `TOPOCTR` combine fine; `HELCTR` + `TOPOCTR` is contradictory — engine prioritizes helio. Error: topo-without-setup has no error return — audit call order.

## Output shape
* `SPEED=256` analytic `xx[3..5]` (cheap — default on). `SPEED3=128` **never use** (3-point, slower, worse).
* `EQUATORIAL=2048` RA/Dec (+speed); `XYZ=4096` cartesian AU; `RADIANS=8192` rad. Combinable.
* `TROPICAL=0` default; `SIDEREAL=65536` needs `set_sid_mode` (else Fagan default silently). `ICRS=131072` raw DE406 frame (pair with bias-NONE, `models.md`). `JPLHOR=262144` / `JPLHOR_APPROX=524288` Horizons emulation (needs EOP). `CENTER_BODY=1048576` COB vs barycenter.
* `SIDBIT_*` (OR into `set_sid_mode`'s `t0` handling, not calc): `ECL_T0=256`, `SSY_PLANE=512`, `USER_UT=1024`, `ECL_DATE=2048`, `NO_PREC_OFFSET=4096`/`PREC_ORIG=8192` test-only.
* Limits: `RADIANS` + `split_deg` formatters expect degrees — convert back first. Error: `SIDEREAL` without `set_sid_mode` yields Fagan with no warning.

## `NODBIT_*` method (`swe_nod_aps`)
`MEAN=1` smooth · `OSCU=2` true osculating · `OSCU_BAR=4` barycentric-motion · `FOPOINT=256` focal point (OR with above, aphelion→focus). Limits: OSCU jumps near perigee — expected. Error: `0` method = MEAN silently.

## `SPLIT_DEG roundflag`
`ROUND_SEC=1` / `ROUND_MIN=2` / `ROUND_DEG=4` precision; `ZODIACAL=8` sign+deg output; `NAKSHATRA=1024` 27-mansion; `KEEP_SIGN=16` / `KEEP_DEG=32` suppress carry (29°59'59" stays). Limits: `NAKSHATRA` + `ZODIACAL` combine; rounding without KEEP carries (29.9999°→30° next sign). Error: none — display only.
