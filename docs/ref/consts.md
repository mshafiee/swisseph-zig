# Constants Reference — `swisseph-zig` (full depth)

Source truth: `include/swephexp.h:88`, `include/sweph.h:65`, `include/sweodef.h:267`.
Zig re-exports: `src/swephlib.zig`, `src/sweph.zig`, `src/swehouse.zig`, `src/swecl.zig`.
Convention: angles in degrees, distances in AU, time in Julian days (TT/ET unless `_ut` suffix = UT).

Template per entry below: definition → value/units → provenance → limits → Zig + C example → error path.

## 1. Version and ephemeris selector

### `SE_VERSION = "2.10.03"` — definition/value/provenance
Upstream release this port tracks (`include/sweph.h:65`). Check at runtime, log it with every published table.
### Limits
String only; no computation effect.
### Example
```zig
var v: [256]u8 = undefined;
_ = swe.swe_abi.swe_version(&v); // "2.10.03"
```
```c
char v[256]; swe_version(v);
```
### Error path
None. If `swe_version` returns unexpected string, binary/header mismatch — rebuild against `dist/<triple>/include`.

### `SE_DE_NUMBER = 431`, `SE_FNAME_DE431 = "de431.eph"`, `SE_FNAME_DFT`
Definition: default JPL ephemeris number/file. Units: N/A. Provenance: JPL DE431 (Folkner 2014), 2.6 GB, 13002 BCE–17000 CE. Limits: `SE_FNAME_DFT2 = "de406.eph"` legacy only for pre-2.0 files; `swe_set_jpl_file()` arg truncated at 256 bytes (`AS_MAXCH`).
Example:
```zig
swe.set_jpl_file("de431.eph", &swed);
```
```c
swe_set_jpl_file("de431.eph");
```
Error: wrong name → first `swe_calc(...SEFLG_JPLEPH...)` returns `ERR` + `serr="cannot open JPL file"`.

### `SEFLG_DEFAULTEPH = SEFLG_SWIEPH`
`iflag==0` = Swiss `.se1` apparent geocentric. No error path; fallback to Moshier writes notice into `serr` and returns `OK` — assert via `swe_get_current_file_data()` in tests.

## 2. Calendar flags and epochs

### `SE_JUL_CAL = 0` / `SE_GREG_CAL = 1`
Definition: calendar selector for `julday/revjul/date_conversion/utc_to_jd`. Provenance: proleptic Julian vs Gregorian (1582 skip not auto-applied — caller picks). Limits: no auto-cutover; mixing flags across convert/revert shifts by 10–13 days.
Example:
```zig
const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL); // 2451545.0
```
```c
double jd = swe_julday(2000,1,1,12.0,SE_GREG_CAL);
```
Error: `swe_date_conversion` returns `ERR` on month 13 / day 32 / hour 25 with `tjd` untouched.

### `J2000 = 2451545.0`, `B1950 = 2433282.42345905`, `J1900 = 2415020.0`, `B1850 = 2396758.2035810`
Definition: epoch JDs (J = Julian year 365.25 d, B = Besselian ~365.2422 d). Units: days. Provenance: IAU standard epochs; B1950 includes 0.923-day Besselian offset. Limits: exact equality only in TT; UT differs by Delta-T.
Example: ayanamsha `J1900`/`J2000`/`B1950` modes pin `t0` to these; `swe_revjul(J2000,...)` must round-trip to 2000-01-01 12:00.

## 3. Units and physical constants

Each entry: value → unit → provenance → where used → what breaks if wrong.

* `SE_AUNIT_TO_KM = 149597870.700` km — IAU 2012 nominal. `xx[2] AU * this` = km. Wrong → 100 km-level eclipse errors.
* `SE_AUNIT_TO_LIGHTYEAR/PARSEC` — derived `1/63241.077`, `1/206264.8062471` (`648000/π`, IAU B2 2016).
* `AUNIT = 1.49597870700e+11` m — DE431 fit (`include/sweph.h:273`). Light-time = `dist_AU * LIGHTTIME_AUNIT`.
* `CLIGHT = 2.99792458e+8` m/s exact — aberration + light-time.
* `HELGRAVCONST = 1.32712440017987e+20` m³/s² (AA 2006 K6) — fictitious-body mean motion from `a` via `KGAUSS`; `GEOGCONST = 3.98600448e+14` — topocentric parallax; `KGAUSS = 0.01720209895`.
* `LIGHTTIME_AUNIT = 499.0047838362/3600/24` d ≈ 8.3167 min — Moon ~1 s, Jupiter ~40 min.
* `DEGTORAD/RADTODEG/CSTORAD/RADTOCS/CS2DEG`, `DEG..DEG360` centisec ints — `swe_split_deg`/`cs2*` formatting; `KM_S_TO_AU_CTY = 21.095`.
* `pla_diam[]` (`include/sweph.h:315`): Sun 1.392e9 … Vesta 525400 m — `swe_pheno` magnitude/diameter, eclipse contact times. Wrong diameter → 0.1 mag / seconds-level contact error, no crash.
* Earth: `EARTH_RADIUS 6378136.6` m, `OBLATENESS 1/298.25642`, `ROT_SPEED 7.2921151467e-5*86400` rad/d, `SUN_RADIUS 959.63"` , `MOON_MEAN_DIST 384400000.0` m, `INCL 5.1453964°`, `ECC 0.054900489`, `SUN_EARTH_MRAT 332946.050895`, `EARTH_MOON_MRAT 1/0.0123000383` — AA 2006 K6/K7. Used by topocentric, eclipse, pheno.

Example (km + light-time):
```zig
var xx: [6]f64 = undefined;
_ = swe.calc_ut(jd, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
const km = xx[2] * 149597870.700;
const lt_min = xx[2] * 8.316753719;
```
Error path: none (constants); mis-scaling surfaces as systematic offset — catch via `swetest -b1.1.2000 -p0 -fPLBRS` golden compare.

## 4. Validity windows

| Const | JD | Meaning | Out-of-range behavior |
|---|---|---|---|
| `JPL_DE431_START/END` | −3027215.5 / 7930192.5 | 13002 BCE–17000 CE | `BEYOND_EPH_LIMITS=-3` |
| `MOSHPLEPH/LUEPH` | 625000.5 / 2818000.5 | ≈3000 BCE–3000 CE | `ERR`, `xx=0` |
| `MOSHNDEPH` | −3100015.5 / 8000016.5 | Nodes wide | same |
| `CHIRON_START/END` | 1967601.5 / 3419437.5 | 675–4650 CE (5° tolerance) | `ERR`, handle explicitly |
| `PHOLUS_START/END` | 640648.5 / 4390617.5 | 2958 BCE–7309 CE | same |
| `SEI_ECL_GEOALT_MAX/MIN` | 25000 / −500 m | Eclipse altitude clamp | clamped, no error |
| `NCTIES` | 6.0 cy/file | `.se1` 600-yr segmentation | wrong file = wrong planet silently — verify with `get_current_file_data` |

Example guard:
```zig
const r = swe.calc_ut(jd, 15, flg, &xx, &swed, models, &dctx, &serr);
if (r == -3) { /* Chiron outside 675–4650: skip, log serr */ }
```

## 5. Files, paths, buffers

`SE_STARFILE="sefstars.txt"`, `SE_ASTNAMFILE="seasnam.txt"`, `SE_FICTFILE="seorbel.txt"`, `SE_FILE_SUFFIX="se1"`, fallback `SE_EPHE_PATH=".:/users/ephe2/:/users/ephe/"`, `AS_MAXCH=256`.
Limits: path >256 bytes → silently replaced by `\SWEPH\EPHE` legacy default; `ast0/`…`ast21/`, `sat/` must be subdirs of ephe path, not siblings.
Example:
```zig
swe.set_ephe_path("/data/ephe", &swed);
```
Error: missing file → Moshier fallback + `serr` notice; JPL missing → `ERR`. Always call `set_ephe_path(NULL)` first even for pure-Moshier runs (inits `Swed`).

## 6. Return codes

`OK=0`, `ERR=-1` (+`serr`), `NOT_AVAILABLE=-2`, `BEYOND_EPH_LIMITS=-3` (`include/sweph.h:251`). `serr` 256 B: Zig `var serr:[256]u8=undefined`, C `char serr[256]`. Never ignore return; never print `xx` when `r<0`.

## 7. Tidal acceleration (Delta-T coupling, arcsec/cy²)

`DE200 −23.8946`, `DE403/404 −25.580`, `DE405/406 −25.826`, `DE421/422 −25.85`, `DE430 −25.82`, `DE431 −25.80` (default), `DE441 −25.936`, `STEPHENSON_2016 −25.85`, `AUTOMATIC 999999` (derive from file), `MOSEPH=DE404`. Set via `set_tid_acc`, read via `get_tid_acc`. Affects pre-1955 Delta-T at seconds level; wrong value → ancient-eclipse misses by minutes. No crash path.

## 8. Speed sampling steps (days, `include/sweph.h:298`)

`MOON 0.00005` (4.32 s), `PLAN 0.0001` (8.64 s), `MEAN_NODE 0.001`, `NODE 0.0001` (MOSH 0.1), `NUT 0.0001`, `DEFL 0.0000005`. Finite-difference steps for `SEFLG_SPEED` where analytic unavailable. Do not tune — bit-parity (`docs/parity.md`) depends on exact values.
