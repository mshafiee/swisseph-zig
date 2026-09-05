# Functions: Eclipses + Occult + Rise/Transit + Pheno + Azalt + Nodes — full depth

C: `include/swephexp.h:843`. Zig: `src/swecl.zig`, facade `src/swisseph.zig:53`. Flags/layouts: `flags-eclipse-rise-heliacal.md`. `backward`: 0 forward, 1 backward. `geopos[3]` lon°E/lat/alt-m.

* `sol_eclipse_when_glob(tjd,iflag,ifltype,&tret,backward)` → type mask / `ERR`; `tret[10]` max + contacts. Narrow `ifltype` (e.g. `TOTAL`) for speed; `0` sweeps all (slow).
* `sol_eclipse_when_loc(tjd,iflag,geopos,&tret,&attr,backward)` → local; `attr[20]` mag/obscuration/Saros/gamma. `lun_eclipse_when/when_loc/how` mirror (geopos required for observability).
* `sol_eclipse_where/how`, `lun_occult_where/how` — snapshot at `tjd` (sub-point + circumstances), no search.
* `lun_occult_when_glob/when_loc(tjd,ipl,starname,iflag,ifltype,…)` — planet (`ipl`) or star path; `ONE_TRY` tests one conjunction. `gauquelin_sector(t,ipl,star,iflag,imeth,geopos,press,temp,&dgsect)` — `imeth 0..3`, `dgsect[3]` sector + equivalents.
```zig
var tret:[10]f64=undefined; var attr:[20]f64=undefined;
const m = swe.sol_eclipse_when_glob(jd, 0, 4, &tret, false, &serr, &swed, models, &dctx);
if (m < 0) { /* no match in window */ }
```
Limits: search window bounded by ephemeris span; circumpolar/never-visible → `ERR` (not exception). `rise_trans(tjd,ipl,star,ephe,rsmi,geopos,press,temp,&tret[2])` / `true_hor(+horhgt)` — `tret` rise/set or transit pair; twilight/disc modifiers per flags page; `atpress=0` = vacuum.
* `azalt(tjd,flag,geopos,press,temp,xin[3],xaz[3])` / `azalt_rev` inverse — assert round-trip in tests; horizon refraction ±0.5° is model.
* `refrac(inalt,press,temp,dir)` / `refrac_extended(+geoalt,lapse,&dret)` / `set_lapse_rate` (default `SE_LAPSE_RATE`).
* `pheno(_ut)(tjd,ipl,iflag,&attr[20])` — elongation/phase/mag/diameter (needs `pla_diam`; Saturn includes rings). `nod_aps(_ut)(tjd,ipl,iflag,method,&nasc,&ndsc,&peri,&aph[6])` per `NODBIT_*`. `get_orbital_elements(tjd,ipl,iflag,&dret[20])`, `orbit_max_min_true_distance(→&dmax,&dmin,&dtrue)`.
Error: all search fns return `ERR` + `serr` on no-match/edge; snapshot fns return mask; check before reading `tret/attr`.
