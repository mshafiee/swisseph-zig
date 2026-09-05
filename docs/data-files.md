# Ephemeris Data Files — full guide

Works with **no files** (Moshier `SEFLG_MOSEPH`, <1" planets). For research precision use `.se1`/`.eph` below. Full layout: `ref/data-files.md`. Set path: `swe.set_ephe_path("/data/ephe",&swed)` / `swe_set_ephe_path()`; env `SE_EPHE_PATH` overrides; always call once even for Moshier.

## What to download (verify sizes + `get_current_file_data`)

| Set | Files | Size | Source |
|---|---|---|---|
| Core 1800–2400 | `sepl_18.se1 semo_18.se1 seas_18.se1 sefstars.txt seorbel.txt` | ~5 MB | `astro.com/ftp/swisseph/ephe/` |
| Full DE431 span | 50 `sepl_*` + 50 `semo_*` + 18 `seas_*` | ~100 MB | same |
| Numbered asteroids | `ast0/`…`ast21/seNNNNN.se1` (long) + `seNNNNNs.se1` (short 1500–2100) | 7.4 GB full | `.../ephe/astN/` |
| Moons/COB | `sat/sepm*.se1` (1900–2047 only) | ~50 MB | `.../ephe/sat/` |
| JPL raw | `de431.eph` 2.6 GB / `de406.eph` 190 MB | — | JPL / astro.com |
| Time/EOP | `seleapsec.txt swe_deltat.txt eop*.dat` | KB | astro.com + IERS |

```
ephe/ sepl_18.se1 semo_18.se1 seas_18.se1 sefstars.txt seorbel.txt
      ast0/se00001s.se1 … sat/sepm*.se1 de431.eph
```

## Rules that bite

* Missing `.se1` → silent Moshier fallback + `serr` notice (`OK`, not `ERR`). Assert `swe_get_current_file_data()` in tests.
* Missing `.eph` with `SEFLG_JPLEPH` → hard `ERR`.
* `sat/` range is 1900–2047; outside → `BEYOND=-3`. Chiron 675–4650 CE, Pholus 2958 BCE–7309 CE, Apollo ≥1870 CE.
* `sefstars.txt`/`seorbel.txt` live in `$EPHE` root. Path >256 B → legacy fallback silently.
* Golden check after install: `swetest -b1.1.2000 -p0 -fPLBRS` must match reference output in `README.md`.
