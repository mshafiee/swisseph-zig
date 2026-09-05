# Functions: Heliacal + Astro Models + Version + Zig Extension — full depth

C: `include/swephexp.h:676` + `:684` + `:1016`. Zig: `src/swehel.zig`, `src/swephlib.zig`. Model: Schaefer visibility; flags/layouts: `flags-eclipse-rise-heliacal.md`.

* `heliacal_ut(tjdstart_ut,geopos[3],datm[4],dobs[6],name,typeevent,iflag,&dret,serr)` → next event JD in `dret[0]` (+details unless `NO_DETAILS`). `name` planet/star (`"Mars"`, `"Sirius"`); events 1–4 (5/6 → `ERR` unimplemented); `iflag` ephemeris + `HELFLAG_*`.
```zig
var dret:[25]f64=undefined;
const r = swe.heliacal_ut(jd, &geopos, &datm, &dobs, "Venus", 1, flg, &dret, &swed, models, &dctx, &serr);
if (dret[0] == 99999999.0) { /* TJD_INVALID: none in window — widen LONG_SEARCH */ }
```
* `heliacal_pheno_ut(tjd,…,&darr[25])` fixed-time details (arcus visionis, contrast, mags); `vis_limit_mag(→&dret[8])` limiting mag + components; `heliacal_angle/topo_arcus_visionis` low-level Reijs geometry.
* Inputs: `geopos` lon°E/lat/alt-m; `datm` press-hPa/temp-°C/humidity/VR-limit; `dobs` age/Snellen/binocular/scope-mag/transmission. `atpress=0`/unphysical `datm` → `ERR`. High-latitude summer → `TJD_INVALID`, not bug.
* `set_astro_models(samod,iflag)` / `get_astro_models` — Dieter test hook for `SE_MODEL_*` (`models.md`); leave defaults except legacy-table repro; mismatched slots across threads → irreproducible diffs.
* `version/get_library_path` (see `funcs-calc.md`). `cleanup()` (`SWE_ZIG_EXTENSIONS`) frees thread fixstar cache; Zig `SweState.deinit()`. Idempotent, teardown-only, never per-call.
