# Bodies 0–22 + Special Points — full depth

ID truth: `include/swephexp.h:99`. Names: `include/sweph.h:79`.
Engine: `src/sweph.zig`, `src/swemmoon.zig`, `src/swemplan.zig`,
`src/swejpl.zig`.
Output: `xx[6]` = lon°, lat°, dist AU, dLon°/d, dLat°/d, dDist AU/d.
`iflag==0` = apparent geocentric, true equinox of date, no speed; add
`SEFLG_SPEED=256`.

Shared pattern per body below: definition → units → provenance (ephemeris
source) → limits → Zig + C example → error path. Check return `<0` and read
`serr[256]` every call.

## -1 `SE_ECL_NUT` — obliquity/nutation probe
Definition: not a body; returns `xx[0]` true obliquity, `[1]` mean obliquity,
`[2]` nutation-lon, `[3]` nutation-obliq, `[4..5]` 0. Units: degrees.
Provenance: Vondrák 2011 + IAU 2000B defaults (`models.md`). Limits: none.
Example:
```zig
_ = swe.calc(jd_et, -1, 0, &xx, &swed, models, &dctx, &serr); // xx[0] → eps for houses
```
```c
swe_calc(jd_et, SE_ECL_NUT, 0, xx, serr);
```
Error: none; use `xx[0]` as `eps` arg to `houses_armc_ex2()`.

## 0 Sun (`SE_SUN`, "Sun")
Definition: geocentric apparent Sun (Earth→Sun vector + corrections). Units:
AU, ~0.983–1.017; light-time ~8.3 min. Provenance: DE431 `.se1`/`.eph`,
Moshier fallback <0.4" (Sun, 3000 BCE–3000 CE). Limits: `SEFLG_BARYCTR` =
SSB-relative; `HELCTR` degenerate. Example:
```zig
_ = swe.calc_ut(jd_ut, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
```
```c
swe_calc_ut(jd_ut, SE_SUN, SEFLG_SPEED, xx, serr);
```
Error: missing `.se1` → Moshier fallback + notice; outside DE window →
`BEYOND=-3`.

## 1 Moon (`SE_MOON`, "Moon")
Definition: geocentric apparent Moon, fastest body 12–15°/d, dist
~0.0024–0.0027 AU. Provenance: `semo_*.se1` / Chapront-Touzé Moshier (few
arcsec). Limits: parallax matters — call `set_topo()` for arcminute work;
tidal `SE_TIDAL_*` couples mean motion (`consts.md`). Example: same pattern
with `ipl=1`. Error: same as Sun + topocentric without `set_topo` silently
uses geocenter.

## 2 Mercury / 3 Venus / 4 Mars
Definition: inferior/superior planets, apparent geocentric. Units: AU; elong
Mercury ≤28°, Venus ≤47°; Mars opposition 780 d. Provenance: DE431; Moshier
<1" (1350 BCE–3000 CE inner planets). Limits: Mercury/Venus never far from
Sun — keep deflection+aberration on (default). Example:
```zig
_ = swe.calc_ut(jd_ut, 3, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr); // Venus
```
```c
swe_calc_ut(jd, SE_VENUS, SEFLG_SPEED, xx, serr);
```
Error: file-missing fallback degrades inferior-planet elongation by ~arcsec —
assert file via `get_current_file_data()` for publications. Phases via
`swe_pheno()`.

## 5 Jupiter / 6 Saturn
Definition: giant-planet barycenters (system mass centers). Units: AU.
Provenance: DE431; DE431–DE406 diff Jupiter <6", Saturn <0.1". Limits:
barycenter≠disc center by up to 0.075" (Jup) / 0.053" (Sat) — use
`SEFLG_CENTER_BODY` or `9599`/`9699` for occultations (`bodies-moons.md`).
Saturn magnitude needs ring tilt (`swe_pheno` attr). Example with COB:
```zig
_ = swe.calc_ut(jd_ut, 5, flg | swe.sweph.SEFLG_CENTER_BODY, &xx, &swed, models, &dctx, &serr);
```

## 7 Uranus / 8 Neptune / 9 Pluto
Definition: outer-planet barycenters; Pluto = Pluto–Charon barycenter unless
COB `9999`. Provenance: DE431 full range; DE431–DE406 diff <28"/53"/129".
Limits: Moshier fallback is coarse — require SWIEPH/JPL for outer-planet
research. Error: same file-fallback pattern.

## 10 Mean Node / 11 True Node
Definition: lunar ascending node — mean = uniform 18.61-yr regression (always
retrograde); true = osculating with periodic terms (briefly direct). Units:
degrees, no distance. Provenance: Moshier lunar theory / SWIEPH
interpolation; window `MOSHNDEPH`. Limits: no light-time/apparent correction
applied. Example:
```zig
_ = swe.calc_ut(jd_ut, 10, 0, &xx, &swed, models, &dctx, &serr); // mean
```
Error: none special; eclipse code gates on node latitude
(`src/swecl.zig:939`).

## 12 Mean Apogee (Mean Lilith) / 13 Osculating Apogee (True Lilith)
Definition: lunar apogee — mean advances ~40.7°/yr smooth; osculating jumps
degrees near perigee (physical, not bug). Units: degrees. Provenance: lunar
theory. Limits: prefer 21/22 for stable charts; use 13 only when osculating
definition required. Error: jumps misread as bug — document in output.

## 14 Earth (`SE_EARTH`)
Definition: heliocentric Earth (= −Sun vector) when `HELCTR`, else
observer-center probe. Provenance: same as Sun. Limits: geocentric+Earth is
degenerate. Use: `calc_pctr` center, heliocentric charts. Error: none beyond
Sun's.

## 15 Chiron (MPC 2060) / 16 Pholus (MPC 5145)
Definition: centaurs, a≈13.7 / 20 AU, Saturn-perturbed chaotic. Provenance:
`seas_*.se1` / `ast15/` files; 5° tolerance inside window. Limits (hard):
Chiron 675–4650 CE (`1967601.5`–`3419437.5`), Pholus 2958 BCE–7309 CE
(`640648.5`–`4390617.5`) — outside returns `ERR`/`BEYOND` + zero. Example loop
(`src/bin/swemini.zig:56`):
```zig
var p: i32 = 0; while (p <= 15) : (p += 1) {
    const r = swe.calc_ut(jd_ut, p, flg, &xx, &swed, models, &dctx, &serr);
    if (r < 0) continue; // Chiron gap: log serr, skip
}
```
Error: must branch on `r<0`; never plot `xx=0` as position.

## 17 Ceres (1) / 18 Pallas (2) / 19 Juno (3) / 20 Vesta (4)
Definition: main-belt asteroids, diameters 939/545/247/525 km. Provenance:
`seas_18.se1` demo core (1800–2400) + long `seas_*.se1` to 5401 BCE–5399 CE.
Limits: need `seas_*.se1` for SWIEPH; else Moshier-less fallback errors.
Example: `ipl=17`. Error: missing file → `ERR`, not silent fallback (no
analytic theory).

## 21 Intp. Apogee (Natural Lilith) / 22 Intp. Perigee (Priapus)
Definition: orbit-averaged apsides via `swi_intp_apsides()`
(`include/sweph.h:670`) — smooth, anomalistic-month period. Limits: none;
preferred stable Black Moon. Error: none.

## -10 `SE_FIXSTAR` + offsets pointer
`-10` routes to `fixstar*` (`stars.md`); `10000+N` asteroid
(`bodies-asteroids.md`); `9000+P*100+M` moon (`bodies-moons.md`); `40..58`
fictitious (`bodies-fict.md`). `SE_NPLANETS=23` is a count, not a body.
