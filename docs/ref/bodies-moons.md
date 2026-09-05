# Planetary Moons + Centers of Body (COB) — full depth

Truth: `SE_PLMOON_OFFSET=9000` (`include/swephexp.h:127`),
`SEFLG_CENTER_BODY=(1024*1024)` (`include/swephexp.h:216`), engine
`src/sweph.zig` + `src/swejpl.zig`, files `sat/sepm*.se1`.
Rule: `ipl = 9000 + planet_no*100 + moon_nr` (Horizons index); COB
`moon_nr=99`, or `ipl=planet_no` + `CENTER_BODY`. `xx[6]` deg/AU/deg-day,
geocentric apparent by default.
Per-group pattern: definition → units/offsets → provenance → limits → Zig + C
example → error path.

Shared setup/validation:
```zig
swe.set_ephe_path("/data/ephe", &swed); // sat/ auto-searched
_ = swe.calc_ut(jd_ut, 9501, flg, &xx, &swed, models, &dctx, &serr); // Io
```
```c
swe_set_ephe_path("/data/ephe");
swe_calc_ut(jd, 9501, SEFLG_SPEED, xx, serr);
```

## Mars 9401 Phobos / 9402 Deimos
Definition: inner/outer Martian moons, periods 7.7 h / 30.3 h. Units:
geocentric AU (~0.5–2.5 AU total). Provenance: JPL satellite theory compressed
to `sat/`. Limits: bary–COB ~0.2 m — irrelevant; use barycenter always. Fast
motion → `SEFLG_SPEED` differentiator stressed; prefer position-only + 1-min
steps for transits. Error: outside 1900–2047 → `BEYOND`; missing `sat/` →
`ERR "cannot open sat file"`.

## Jupiter 9501–9504 + 9599 COB (Io/Europa/Ganymede/Callisto)
Definition: Galilean moons + Jupiter system COB. Max bary–COB 0.075"
@2468233.5 (disc ~40" — relevant for occultations, irrelevant for houses).
Provenance: JPL `sepm*.se1`. Limits: 1900–2047; COB transit search converges
slower — search on barycenter (`ipl=5`), refine contacts with `9599` or
`CENTER_BODY`. Example COB equivalence:
```zig
_ = swe.calc_ut(jd, 5, flg | swe.sweph.SEFLG_CENTER_BODY, &xx, &swed, models, &dctx, &serr);
// ≡ swe.calc_ut(jd, 9599, flg, &xx, ...);
```
Error: `SEFLG_TEST_PLMOON` combo returns raw file vectors — validation only,
never publish.

## Saturn 9601–9608 + 9699 (Mimas…Iapetus)
Definition: 8 classical moons; Titan brightest (`pheno` mag path). Bary–COB
0.053" @2463601.5. Limits/provenance/error: same 1900–2047 + `sat/` pattern as
Jupiter. Hyperion chaotic rotation — orientation N/A, position fine.

## Uranus 9701–9705 + 9799 (Ariel/Umbriel/Titania/Oberon/Miranda)
Definition: 5 major Uranian moons, retrograde system (i≈98°). Bary–COB
0.0032" — negligible. Limits: faint; heliacal N/A. Error: same file/range
pattern.

## Neptune 9801 Triton / 9802 Nereid / 9808 Proteus + 9899
Definition: Triton retrograde captured KBO; Nereid e=0.75; Proteus faint
inner. Bary–COB 0.0036". Limits: Nereid speed varies 5× — transit step <1 h
near periapsis. Error: moon_nr gap (9803–9807 unassigned) → `ERR`, not empty
result.

## Pluto 9901 Charon / 9902 Nix / 9903 Hydra / 9904 Kerberos / 9905 Styx + 9999 COB
Definition: binary-dwarf system; Charon 12% Pluto mass — bary–COB 0.088"
@2437372.5, largest fractional offset. Default `ipl=9` = barycenter; disc work
needs `9999`. Limits: 1900–2047; Styx/Kerberos faint, few-arcmin file
accuracy. Error: confusing 9901 (Charon) with 9999 (COB) is top user error —
assert ID in code review.
