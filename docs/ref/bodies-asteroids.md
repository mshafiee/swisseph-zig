# Numbered Asteroids + Comets + Varuna — exhaustive reference

Truth: `SE_AST_OFFSET=10000`, `SE_COMET_OFFSET=1000`, `SE_VARUNA=30000`
(`include/swephexp.h:127`), names `seasnam.txt` (`SE_ASTNAMFILE`), engine
`src/sweph.zig:3074` + `src/swejpl.zig`.

## Numbered asteroids: `ipl = 10000 + MPC_number`

Examples: `10001` Ceres (dup of 17), `10433` Eros, `130375`
Cruithne-adjacent sets, up to `21999` in full mirror. `seasnam.txt` maps
number→name; `swe_get_planet_name(10433)` returns file name.

Files: `astN/seNNNNNs.se1` short (1500–2100, ~1/10 size) vs
`astN/seNNNNN.se1` long (3000 BCE–3000 CE). Engine tries long, falls back to
short. Dirs: number 0–999 → `ast0/`, 1000–1999 → `ast1/`, … 21000–21999 →
`ast21/`. Full set 5–21999 ≈ 7.4 GB; demo needs only `seas_18.se1`
(main-belt Ceres/Pallas/Juno/Vesta).

Limits: no global clamp like Chiron — per-object chaos instead. E.g. 1862
Apollo valid only ≥1870 CE (Venus encounter); Chiron-class objects error
outside their arc with `BEYOND_EPH_LIMITS`. Always check return; position `0`
+ `serr` on failure.

Zig: `swe.calc_ut(jd, 10000+433, SEFLG_SPEED, &xx, ...)` (Eros). C:
`swe_calc_ut(jd, SE_AST_OFFSET+433, ...)`.

## Comets / interstellar: `SE_COMET_OFFSET` scheme + JPL path

Numbered periodic comets resolve via `seasnam.txt`-style `seocom*.se1` or JPL
Horizons import (`swephgen4` in `src/ep4/`). Elements change per apparition —
use osculating file for the target epoch, not a generic ID.
`swe_get_orbital_elements()` verifies which ellipse was actually used.

## Varuna: `SE_VARUNA = 30000` (= 10000+20000)

KBO 20000 Varuna shorthand. Same file path as asteroids
(`ast20/se20000*.se1`). Other TNOs use plain `10000+N` (e.g. `50000` Quaoar →
`60000` range not special-cased).
