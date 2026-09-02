# Ephemeris Data Files

The library works out of the box with **no data files** using the built-in
Moshier ephemeris (`SEFLG_MOSEPH`). For higher precision, download the
Swiss Ephemeris data files:

## Standard files (≈100 MB total)

- `sepl_18.se1`, `semo_18.se1`, `seas_18.se1` — planets, moon, main asteroids
  (years 1800–2400). From https://www.astro.com/ftp/swisseph/ephe/
- `sefstars.txt` — fixed star catalog
- `seorbel.txt` — fictitious body elements (optional)

## Asteroid files

Numbered asteroids live in `astN/` subdirectories (`ast0/`–`ast21/`),
downloadable from https://www.astro.com/ftp/swisseph/ephe/ast0/ etc.
≈7.4 GB for the full set (5–21,999).

## JPL files

`de431.eph` (2.6 GB) or `de406.eph` (190 MB) from JPL/astro.com for
`SEFLG_JPLEPH`.

## Layout

```
ephe/
├── sepl_18.se1
├── semo_18.se1
├── seas_18.se1
├── sefstars.txt
├── seorbel.txt
├── ast0/se00001s.se1 ...
└── sat/sepm*.se1
```

Point the library at the directory with `swe_set_ephe_path("path/to/ephe")`.
