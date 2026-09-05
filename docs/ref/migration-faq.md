# Migration + FAQ + Error Handling

## C → Zig checklist

1. Add explicit `Swed/DeltatCtx/AstroModels/HouseCtx` params (see `c-zig-map.md`). 2. Call `set_ephe_path(NULL)` first even for Moshier. 3. Size `serr[256]`, star buffers 512. 4. Repeat `set_topo/set_sid_mode` per thread. 5. Replace `SPEED3` with `SPEED`. 6. Free per thread (`deinit`/`cleanup`), not once globally.

## Errors

Check `<0` **every** call. `ERR` + `serr` = bad flag/file/date; `BEYOND_EPH_LIMITS` = outside span (Chiron 675–4650 CE, Pholus 2958 BCE–7309 CE, moons 1900–2047, Apollo ≥1870 CE); `0` position + message = chaotic-arc gap, not valid data. SWIEPH-missing fallback returns Moshier with notice — assert `get_current_file_data()` in tests.

## FAQ

* Polar houses blow up (P/K)? → use U/Q/L/O/S (`houses-A-Y.md`).
* Osculating Lilith jumps? → physical; use intp. 21/22 for smooth.
* 53 mas vs Horizons? → set `SEFLG_JPLHOR` + EOP file (`models.md`).
* Heliacal `TJD_INVALID`? → widen window (`LONG_SEARCH`) or relax sky (`VISLIM_*`).
* Thread flakiness? → shared bundle without lock; give each thread its own.
