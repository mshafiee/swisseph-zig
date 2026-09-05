# Data Files — expanded layout

Supersedes thin `../data-files.md`. Set path via `swe.set_ephe_path(dir)` / `swe_set_ephe_path()`; env `SE_EPHE_PATH` overrides.

```
$EPHE/
  sepl_18.se1  semo_18.se1  seas_18.se1   # 1800–2400 demo core (~5 MB)
  sepl_*.se1   semo_*.se1   seas_*.se1    # full 50+50+18-file DE431 span
  sefstars.txt  seasnam.txt  seorbel.txt
  seleapsec.txt  swe_deltat.txt  eop*.dat # leap/EOP (Horizons-grade)
  ast0/ … ast21/   # astN/seNNNNN.se1 long + seNNNNNs.se1 short
  sat/             # sepm*.se1 moons/COB, 1900–2047
  *.eph            # de431.eph (2.6 GB) / de406.eph for SEFLG_JPLEPH
```

Rules: Moshier needs no files. SWIEPH without file → silent Moshier fallback + warning in `serr` — check return. `swe_get_current_file_data()` reports which file served the last call. Keep `sefstars.txt` + `seorbel.txt` in `$EPHE` root, not subdirs. Source: `https://www.astro.com/ftp/swisseph/ephe/` (+`/ast0/`…`/sat/`).
