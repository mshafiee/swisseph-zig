# API Tour — full guide (verified against `examples/`)

> Exposing this over a network? Prior written permission is required —
> see [`API-LICENSE`](../API-LICENSE) and [`license.md`](license.md).

Import: `const swe = @import("swisseph");` Facade: `src/swisseph.zig:1`. All
snippets below match `examples/zig-native/main.zig:1` and `readme_check.zig:1`
(compiled by `zig build test`).

## 0. Setup first (both APIs)

Zig (explicit contexts — no globals):
```zig
var swed = swe.sweph.Swed{};
var dctx = swe.deltat.DeltatCtx{};
const models = swe.swephlib.AstroModels{};
var serr: [256]u8 = undefined;
swe.set_ephe_path("/data/ephe", &swed); // or NULL for Moshier-only; call always
```
C (per-thread state):
```c
char serr[256];
swe_set_ephe_path("/data/ephe");
```
One bundle per thread; repeat setup per thread. Teardown: Zig
`SweState.deinit()`, C `swe_close()` + `swe_cleanup()`. See
`ref/threading-build.md`, `ref/c-zig-map.md`.

## 1. Calendar (`swedate`, `ref/funcs-datetime.md`)

```zig
const jd_ut = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL); // 2451545.0
var y: i32 = 0; var m: i32 = 0; var d: i32 = 0; var ut: f64 = 0;
swe.revjul(jd_ut, swe.swedate.SE_GREG_CAL, &y, &m, &d, &ut);
```
`SE_JUL_CAL=0` / `SE_GREG_CAL=1` — no auto-cutover. Invalid date → `ERR` from `date_conversion`/`utc_to_jd`.

## 2. Positions (`sweph`, `ref/bodies-*.md`, `ref/flags-calc.md`)

```zig
var xx: [6]f64 = undefined; // lon,lat,dist-AU,dLon,dLat,dDist
const r = swe.calc_ut(jd_ut, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
if (r < 0) return error.CalcFailed; // BEYOND=-3 outside span, xx=0 — don't plot
```
Bodies: `0` Sun … `22` Priapus, `40–58` fict, `10000+N` asteroids, `9000+…`
moons, `-10` stars. `iflag==0` = apparent geocentric; always OR `SEFLG_SPEED`.

## 3. Houses (`swehouse`, `ref/houses-A-Y.md`)

```zig
var cusps: [37]f64 = undefined; var ascmc: [10]f64 = undefined;
var hctx = swe.swehouse.HouseCtx{};
swe.set_topo(8.5, 47.4, 400, &swed); // only for 'T'
_ = swe.houses_armc_ex2(armc, 47.4, eps, 'P', &cusps, &ascmc, null, null, null, &hctx);
// ascmc[0] ASC [1] MC [2] ARMC [3] Vertex; cusps[1..12]; G writes [1..36]
```
Get `eps`/`armc` from body `-1` calc or `sidtime`. Polar |lat|>66.5° → prefer U/Q/L/O/S over P/K.

## 4. Eclipses / rise / stars

```zig
var tret: [10]f64 = undefined; var attr: [20]f64 = undefined;
const m = swe.sol_eclipse_when_glob(jd_ut, 0, 4, &tret, false, &serr, &swed, models, &dctx); // TOTAL
var star: [512]u8 = undefined; @memcpy(star[0.."Spica".len], "Spica");
_ = swe.fixstar_ut(star[0..], jd_ut, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
```
Full signatures: `ref/funcs-eclipse.md`, `ref/stars.md`, `ref/funcs-heliacal.md`.

## Modules

| Module | Scope | Ref |
|---|---|---|
| `swedate` | julday/revjul/utc_* | `funcs-datetime` |
| `deltat` | Delta-T + tidal | `models`, `consts` |
| `swephlib` | precession/nutation/cotrans/models | `models` |
| `swemmoon/swemplan/swejpl` | Moshier/JPL engines | `bodies-*` |
| `sweph` | calc engine, files, fixstars | `funcs-calc` |
| `swehouse` | 26 systems | `houses-A-Y` |
| `swecl` | eclipse/rise/pheno/nodes | `funcs-eclipse` |
| `swehel` | heliacal Schaefer | `funcs-heliacal` |
| `swe_abi` | 107 `swe_*` → libswe | `c-zig-map` |
