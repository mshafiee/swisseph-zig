# Fixed Stars — full depth

Truth: `struct fixed_star` (`include/sweph.h:772`), `SE_STARFILE="sefstars.txt"` (`include/swephexp.h:387`), `SE_MAX_STNAME=256`, API `swe_fixstar*` (`include/swephexp.h:717`), cache in `src/sweph.zig` per-thread `SweState` (free: `swe_cleanup` / `SweState.deinit()`).
Pattern per section: definition → units → provenance → limits → Zig + C example → error path. `xx[6]` deg/AU/deg-day like planets.

## Catalog line: `skey,starname,starbayer,starno,epoch,ra,de,ramot,demot,radvel,parall,mag`
Definition: proper-motion-propagated J2000-frame star. Units: `epoch` JD; `ra/de` deg; `ramot/demot` "/yr; `radvel` km/s (perspective); `parall` " (distance = 1/parall pc); `mag` visual. Provenance: Hipparcos-derived `sefstars.txt` (legacy `fixstars.cat` via `is_old_starfile`). Limits: `SWI_STAR_LENGTH=40` per key field; `skey` may carry leading comma; search is case-insensitive substring — Bayer (`alVir`, `zePsc`, `alTau`) beats traditional name for uniqueness. Output name needs `2*SE_MAX_STNAME` (512 B) — returned name may expand. `ramot/demot/radvel/parall` propagate to `tjd`; only `fixstar2` puts proper-motion speed into `xx[3..5]`.

## Canonical 20 anchors (verify against shipped file)
Sirius, Canopus, Arcturus, Vega, Capella, Rigel, Procyon, Betelgeuse, Achernar, Hadar, Altair, Aldebaran (ayanamsha 14 anchor), Antares, Spica/Citra (27), Regulus, Pollux, Deneb, Algol, Revati/zePsc (28), Pushya/deCnc (29). Galactic modes 17/30/36/40 + equator modes 31–33 + Mula 33/35/36 key off these frame points (`ayanamsha-00-46.md`). Limits: high-proper-motion stars (Sirius, Arcturus) need `fixstar2` for speed; `fixstar` speed is geometric-only.

## API with examples
* `fixstar(star,tjd_et,iflag)` / `fixstar_ut(star,tjd_ut,…)` → `xx[6]`; `fixstar2(_ut)` adds rigorous speed; `fixstar_mag/fixstar2_mag(star,&mag)` magnitude only (no ephemeris files needed).
* `iflag`: `EQUATORIAL/XYZ/RADIANS/SIDEREAL/J2000/NONUT/SPEED` as planets; `HELCTR/BARYCTR/TOPOCTR` apply via `parall`.
```zig
var star: [512]u8 = undefined; // writable copy; engine may normalize
@memcpy(star[0.."Spica".len], "Spica");
_ = swe.fixstar_ut(star[0..], jd_ut, flg, &xx, &swed, models, &dctx, &serr);
var mag: f64 = 0; _ = swe.fixstar_mag(star[0..], &mag, &swed, &serr);
```
```c
char star[512] = "Spica";
swe_fixstar_ut(star, jd_ut, SEFLG_SPEED, xx, serr);
double mag; swe_fixstar_mag(star, &mag, serr);
```
Error: unknown key → `ERR` + `"star not found"` (check spelling/Bayer, not position); `star` buffer <512 → truncation/UB; first call parses file → `ERR "cannot open sefstars.txt"` if `$EPHE` wrong; cache is per-thread — set path + call on same thread, free once at teardown, never per-call.
