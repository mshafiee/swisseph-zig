# C ↔ Zig API Map

> Exposing these functions over a network? Prior written permission is
> required — see [`API-LICENSE`](../../API-LICENSE) and
> [`license.md`](../license.md).

All 107 `swe_*` (see `funcs-*.md`) ship in `libswe` via `src/swe_abi.zig`; Zig facade in `src/swisseph.zig:26`.

Pattern — C (threadlocal state):
```c
swe_set_ephe_path(NULL);
swe_calc_ut(2451545.0, SE_SUN, SEFLG_SPEED, xx, serr);
swe_close();
```
Zig (explicit contexts):
```zig
var swed = swe.sweph.Swed{}; var dctx = swe.deltat.DeltatCtx{};
const models = swe.swephlib.AstroModels{};
_ = swe.calc_ut(jd, 0, swe.sweph.SEFLG_SPEED, &xx, &swed, models, &dctx, &serr);
```
Exceptions: `houses_armc_ex2` takes `armc/eps` directly in Zig (C `houses_ex`
computes them); `swe_cleanup` is Zig-extension (`SWE_ZIG_EXTENSIONS`).
Return/`serr[256]`/`xx[6]`/`tret/attr` layouts identical. Link C drop-ins
with `dist/<triple>/{lib,include}` without source changes
(`examples/c-abi/main.c:1`).
