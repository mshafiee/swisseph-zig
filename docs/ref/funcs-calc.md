# Functions: Calculation + Crossings + Fixed Stars + Setup — full depth

C: `include/swephexp.h:697`. Zig: `src/swisseph.zig:33` (drops `swe_`, adds `&swed, models, &dctx`). C state = per-thread `SweState`; Zig = caller-owned `Swed{}`, `DeltatCtx{}`, `AstroModels{}`. `serr[256]`, return `OK=0/ERR=-1/BEYOND=-3`. Pattern per fn: signature → params/units → provenance → limits → example → error path.

## Setup
* `set_ephe_path(path581?, &swed)` / `swe_set_ephe_path(path)` — **first call**, even `NULL` (inits `Swed`). Env `SE_EPHE_PATH` overrides arg; >256 B arg → legacy fallback silently. Example: `swe.set_ephe_path("/data/ephe",&swed);`. Error: missing dir surfaces later as fallback notice, not here.
* `set_jpl_file(fname,&swed)` / `swe_set_jpl_file(fname)` — `.eph` basename in ephe path. Error: bad name → next JPLEPH calc `ERR`.
* `close(&swed)` / `swe_close()` — per-thread free; Zig `SweState.deinit()` also drops fixstar vector. Never calc after close without re-setup.
* `version(&buf)` → `"2.10.03"`; `get_library_path` → exe/DLL dir; `get_current_file_data(ifno,&s,&e,&n)` (`0` planet `1` moon `2` main-ast `3` other `4` star; zeros for JPL/star) — assert in tests to catch silent Moshier fallback; `get_planet_name(ipl,buf)` → `SE_NAME_*` or `seorbel/seasnam` name.
* `set_topo(lon°E,lat,alt_m,&swed)` — required before `TOPOCTR`/house `T`; no return. Without it topo = geocenter silently.
* `set_sid_mode(mode,t0,ayan_t0,&swed)` + `get_ayanamsa_ex(jd,iflag,&aya,…)` / `_ex_ut` / `get_ayanamsa(jd)` / `_ut` / `get_ayanamsa_name(mode)` — see `ayanamsha-00-46.md`. Forgetting `SIDEREAL` in calc flag returns tropical with no warning.

## Core `calc_ut / calc / calc_pctr`
* `calc_ut(jd_ut,ipl,iflag,&xx,&swed,models,&dctx,&serr)` — **default**. `calc(jd_et,…)` ET variant (`jd_et=jd_ut+deltat_ex`). `calc_pctr(jd_et,ipl,iplctr,iflag,&xx,…)` any-center planetocentric. `xx[6]` lon/lat/dist-AU/dLon/dLat/dDist-per-day.
```zig
var xx:[6]f64=undefined; var serr:[256]u8=undefined;
const r = swe.calc_ut(jd_ut, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
if (r < 0) { /* log serr, skip */ }
```
```c
double xx[6]; char serr[256];
if (swe_calc_ut(jd, SE_SUN, SEFLG_SPEED, xx, serr) < 0) { /* handle */ }
```
Limits: Chiron/Pholus/moons/Apollo windows (`bodies-*.md`); `SPEED` cheap, `SPEED3` banned. Error: `BEYOND` outside span (`xx=0` — don't plot); fallback notice means wrong file path.

## Crossings + stars
* `solcross/mooncross(xlon,jd,flag)` → next crossing JD (UT variants take UT); `mooncross_node(jd,flag,&lon,&lat)`; `helio_cross(ipl,xlon,jd,iflag,dir,±1,&jd_cross)` → `OK/ERR`. Limits: iterative — seed near target, refine with `calc_ut`; retrograde bodies may return earlier-than-expected JD (verify direction). Error: no crossing → large/`ERR`, check return.
* `fixstar(_ut)/fixstar2(_ut)/fixstar_mag` — `star[512]` writable (`2*SE_MAX_STNAME`); see `stars.md`. Unknown key → `ERR "star not found"`; missing `sefstars.txt` → `ERR` on first call.
