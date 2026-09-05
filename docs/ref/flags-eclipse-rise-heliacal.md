# Eclipse / Rise-Transit / Azalt / Heliacal Flags — full depth

Truth: `include/swephexp.h:305`. Per-flag pattern: definition → units/effect → provenance → limits → example → error path.

## Eclipse `ifltype` filter + stages
Definition: bitmask selecting which eclipses/occults the `when_*` search returns. Units: N/A (filter). Provenance: Saros/contact geometry in `src/swecl.zig`.
* Solar: `CENTRAL=1` (center line hits Earth) · `NONCENTRAL=2` · `TOTAL=4` · `ANNULAR=8` · `PARTIAL=16` · `ANNULAR_TOTAL/HYBRID=32`; `ALLTYPES_SOLAR` = OR of all.
* Lunar: `TOTAL|PARTIAL|PENUMBRAL=64`; `ALLTYPES_LUNAR` likewise.
* Stages (local fns): `VISIBLE=128` · `MAX_VISIBLE=256` · `1ST/PARTBEG=512` · `2ND/TOTBEG=1024` · `3RD/TOTEND=2048` · `4TH/PARTEND=4096` · `PENUMBBEG=8192/PENUMBEND=16384` (lunar; same bits = `OCC_BEG/END_DAYLIGHT` for occult). `ONE_TRY=32768` tests next conjunction only.
* `tret[10]`: `[0]` max JD, `[1..6]` C1–C4 + totality bounds, `[7..9]` aux; `attr[20]`: mag, obscuration, diameter ratio, Saros, gamma.
Limits: `0` filter = all types (expensive sweep); narrow to expected type for speed. `backward=1` searches past — ephemeris edge returns `ERR`, not wrap.
Example:
```zig
var tret: [10]f64 = undefined; var attr: [20]f64 = undefined;
_ = swe.sol_eclipse_when_glob(jd, 0, swe.swecl.SE_ECL_TOTAL, &tret, false, &serr, &swed, models, &dctx);
```
Error: no match in window → `ERR` + `serr`; `5/6` acronychal/cosmical heliacal-adjacent codes are unimplemented — don't pass here.

## Rise/transit `rsmi`
Definition: `CALC_RISE=1` · `CALC_SET=2` · `CALC_MTRANSIT=4` (upper) · `CALC_ITRANSIT=8` (lower); OR modifiers: `DISC_CENTER=256` (center vs upper-limb default) · `DISC_BOTTOM=8192` (lower limb) · `GEOCTR_NO_ECL_LAT=128` (ignore lat, geocentric) · `NO_REFRACTION=512` · twilights `CIVIL=1024` (−6°) / `NAUTIC=2048` (−12°) / `ASTRO=4096` (−18°) · `FIXED_DISC_SIZE=16384` (ignore distance) · `HINDU_RISING=DISC_CENTER|NO_REFRACTION|GEOCTR_NO_ECL_LAT` (classical sunrise). Units: `geopos[3]` lon°E/lat/alt-m; `atpress` hPa (0 = vacuum); `attemp` °C; `horhgt` deg only in `true_hor`.
Limits: circumpolar bodies have no rise/set — `ERR`; twilight flags only meaningful with `CALC_RISE/SET`. `atpress=0` disables refraction model (vacuum). Error: pressure/temp out of range clamps silently — validate inputs for publications.

## Azalt / refraction `calc_flag`
Definition: `ECL2HOR/HOR2ECL=0` ecliptic↔horizontal; `EQU2HOR/HOR2EQU=1` equatorial↔horizontal. `TRUE_TO_APP=0` / `APP_TO_TRUE=1` for `refrac` (lapse via `set_lapse_rate`, default `SE_LAPSE_RATE`). Units: `xin[3]` in-frame → `xaz[3]` az/alt + apparent. Limits: near-horizon refraction ±0.5° — model, not measurement. Error: inverted direction flag swaps transform silently — assert round-trip `azalt→azalt_rev` in tests.

## Heliacal `TypeEvent` + `helflag`
Definition: Schaefer-visibility search. Events `RISING/MORNING_FIRST=1` · `SETTING/EVENING_LAST=2` · `EVENING_FIRST=3` · `MORNING_LAST=4`; `5/6` unimplemented → `ERR`. Search: `LONG_SEARCH=128` (extend window) · `HIGH_PRECISION=256` (arcsec iterate) · `OPTICAL_PARAMS=512` (honor `datm/dobs`) · `NO_DETAILS=1024` (dates only, fast) · `SEARCH_1_PERIOD=2048`. Sky: `VISLIM_DARK=4096` · `VISLIM_NOMOON=8192` · `PHOTOPIC=16384/SCOTOPIC=32768` (`MIXEDOPIC=2` auto) · `AV/VR=65536` + `PTO/MIN7/MIN9` estimator variants. Units: `datm[4]` press/temp/humidity/VR-limit; `dobs[6]` age/Snellen/binocular/scope/transmission; `TJD_INVALID=99999999.0` = none found.
Limits: high-latitude summer = no heliacal event (not an error in sky — handle `TJD_INVALID`). `NO_DETAILS` skips `darr` fill. Error: `5/6` → `ERR`; unphysical `datm` (negative pressure) → `ERR`.
