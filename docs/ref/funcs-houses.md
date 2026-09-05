# Functions: Houses + Gauquelin — full depth

C: `include/swephexp.h:812`. Zig: `src/swehouse.zig`, facade `src/swisseph.zig:47`. Systems: `houses-A-Y.md`. Buffers `cusps[37]`/`ascmc[10]` (0 ASC 1 MC 2 ARMC 3 Vertex 4 EquASC 5 CoASC-K 6 CoASC-M 7 PolASC 8 NASCMC). `hsys` int = char (`'P'`).

* `houses(tjd_ut,lat,lon,hsys,cusps,ascmc)` — basic, no speeds/serr. Use only for quick display.
* `houses_ex(+iflag)` — adds SIDEREAL/EQUATORIAL; eps auto. `houses_ex2(+cusp_speed,ascmc_speed,serr)` — **prefer**; speeds °/day.
* `houses_armc(armc,lat,eps,…)` / `houses_armc_ex2(+speeds)` — ARMC-driven, no date; Zig primary:
```zig
var hctx = swe.swehouse.HouseCtx{};
_ = swe.houses_armc_ex2(armc, lat, eps, 'P', &cusps, &ascmc, null, null, null, &hctx);
```
```c
swe_houses_ex2(jd_ut, 0, lat, lon, 'P', cusps, ascmc, cusp_spd, ascmc_spd, serr);
```
* `house_pos(armc,lat,eps,hsys,xpin[2],serr)` → 1.0–12.0 (1–36 G); `xpin` lon/lat. `house_name(hsys)` → name string.
Limits: P/K fail |lat|>66.5° (interpolate + `serr`); G writes 36 cusps; T needs `set_topo`; I needs `HouseCtx`/thread state (falls back O). Error: polar `ERR` — switch to U/Q/L/O/S; speeds only from `*_ex2`.
