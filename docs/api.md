# API Tour

Import the facade:

```zig
const swe = @import("swisseph");
```

## Calendar (swedate)

```zig
const jd = swe.julday(2000, 1, 1, 12.0, 1); // SE_GREG_CAL
var y: i32 = 0; var m: i32 = 0; var d: i32 = 0; var ut: f64 = 0;
swe.revjul(jd, 1, &y, &m, &d, &ut);
```

## Planetary positions (sweph)

```zig
var swed = swe.sweph.Swed{};
var dctx = swe.deltat.DeltatCtx{};
const models = swe.swephlib.AstroModels{};
var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;
const jd_et = jd + swe.deltat_ex(&dctx, jd, -1);
_ = swe.sweph.swe_calc(jd_et, 0, 256, &xx, &swed, models, &dctx, &serr);
// xx[0]=longitude, xx[1]=latitude, xx[2]=distance, xx[3]=speed
```

## Houses (swehouse)

```zig
var cusps: [37]f64 = undefined;
var ascmc: [10]f64 = undefined;
var hctx = swe.swehouse.HouseCtx{};
_ = swe.houses_armc_ex2(armc, 48.5, 23.4367, 'P', &cusps, &ascmc, null, null, null, &hctx);
// C's swe_houses/swe_houses_ex convenience wrappers live in the C-ABI layer
// (they need engine-computed obliquity); at the Zig API level you pass armc
// and obliquity yourself via swe.houses_armc_ex2.
```

## Eclipses (swecl)

```zig
var swed = swe.sweph.Swed{};
var dctx = swe.deltat.DeltatCtx{};
const models = swe.swephlib.AstroModels{};
var tret: [10]f64 = undefined;
var serr: [256]u8 = undefined;
const flag = swe.swecl.swe_sol_eclipse_when_glob(jd, 0, 0, &tret, false, &serr, &swed, models, &dctx);
```

## Modules

| Module | Scope |
|---|---|
| `swedate` | julday, revjul, date_conversion, utc_time_zone |
| `deltat` | delta-T models |
| `swephlib` | precession, nutation, obliquity, coordinate transforms |
| `swemmoon` | Moshier moon |
| `swemplan` | Moshier planets + fictitious bodies |
| `swejpl` | JPL binary file reader |
| `sweph` | swe_calc engine, file machinery, fixstars, asteroids |
| `swehouse` | 25 house systems |
| `swecl` | eclipses, rise/set, azalt, pheno, nod_aps, gauquelin |
| `swehel` | heliacal events, visibility |
| `swe_abi` | 107 C-ABI `swe_*` exports → libswe |

## Contexts & threading

Every mutable library state lives in explicit per-instance context structs.
Computations take their contexts as parameters — nothing is hidden in
module-level globals:

```zig
var swed = swe.sweph.Swed{};      // engine state: pldat, ephemeris files, caches
var dctx = swe.deltat.DeltatCtx{}; // delta-T state
const models = swe.swephlib.AstroModels{};

var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;
_ = swe.sweph.swe_calc(jd_et, 0, 0, &xx, &swed, models, &dctx, &serr);
```

**One bundle per thread.** Pass your `Swed` + ctx pointers to whichever
thread needs them; threads with separate bundles never interact. Sharing a
bundle across threads requires external locking (then results are
deterministic — verified by `zig build test`).

The C-ABI layer exposes the same engine behind a `threadlocal SweState`
(one isolated C-API instance per OS thread, mirroring C TLS statics):

```zig
swe.swe_abi.SweState.deinit(...); // frees the fixstar buffer at teardown
```

See the “Threading contract” section in README.md.
