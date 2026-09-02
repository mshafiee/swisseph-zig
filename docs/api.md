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
var xx: [6]f64 = undefined;
var serr: [256]u8 = undefined;
const jd_et = jd + swe.deltat_ex(jd, -1);
_ = swe.calc(jd_et, 0, 256, &xx, &serr); // Sun, SEFLG_SPEED
// xx[0]=longitude, xx[1]=latitude, xx[2]=distance, xx[3]=speed
```

## Houses (swehouse)

```zig
var cusps: [37]f64 = undefined;
var ascmc: [10]f64 = undefined;
_ = swe.houses_ex(jd_ut, 0, 48.5, 11.0, 'P', &cusps, &ascmc);
```

## Eclipses (swecl)

```zig
var tret: [10]f64 = undefined;
const flag = swe.sol_eclipse_when_glob(jd, 0, 0, &tret, 0, &serr);
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
