# Functions: Date/Time + Delta-T + Sidtime + Cotrans + Aux — full depth

C: `include/swephexp.h:771` + `:946`. Zig: `src/swedate.zig`, `src/deltat.zig`, `src/swephlib.zig`. Pattern: signature → units → provenance → limits → example → error.

* `julday(y,m,d,hourUT,gregflag)` → JD UT. `revjul(jd,flag,&y,&m,&d,&ut)` inverse. `date_conversion(y,m,d,ut,cal,&tjd)` validates → `OK/ERR` (month 13/day 32/hour 25 → `ERR`, `tjd` untouched). No auto-cutover — caller picks `SE_JUL/GREG_CAL`.
```zig
const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL); // 2451545.0
```
* `utc_to_jd(y,mo,d,h,mi,s,flag,&dret[2])` → `[0]` TT `[1]` UT1 (leap-second aware via `seleapsec.txt`); `jdet_to_utc/jdut1_to_utc` inverse; `utc_time_zone(…tz_east+…,out…)` civil↔UTC. `time_equ(tjd,&te)` EoT days; `lmt_to_lat/lat_to_lmt(tjd,lon,&out)` mean↔apparent at longitude.
* `deltat(tjd)` days fast; `deltat_ex(tjd,iflag,serr)` tidal-aware; `set_tid_acc/get_tid_acc` (`SE_TIDAL_*`, `AUTOMATIC`); `set_delta_t_userdef(d_days)` / `AUTOMATIC` reset. Zig threads `&dctx`. Limits: userdef left set poisons later calls — reset in teardown; pre-1000 BCE model spread minutes (cite model).
* `sidtime(tjd_ut)` GMST hours (current slot); `sidtime0(tjd,eps,nut)` independent; `set_interpolate_nut(b)`. `cotrans(xpo[3],xpn[3],eps)` / `cotrans_sp([6])` — sign of `eps` selects direction. `degnorm/radnorm`, `deg_midp/rad_midp`, `difdegn/difdeg2n/difrad2n`, `split_deg(deg,roundflag,&d,&m,&s,&fr,&sgn)` (`SPLIT_DEG_*`). Placalc `cs*` centisec `int32` helpers (`csnorm/difcsn/difcs2n/csroundsec/d2l/day_of_week Mon0/cs2timestr/cs2lonlatstr/cs2degstr`) — legacy; prefer doubles.
Error: calendar invalid → `ERR`; `utc_to_jd` bad time → `ERR` + `serr`; round-trip `julday→revjul` and `cotrans→cotrans(-eps)` in tests.
