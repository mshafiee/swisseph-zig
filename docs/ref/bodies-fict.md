# Fictitious Bodies 40–58 + User-Defined — full depth

Truth: `include/swephexp.h:131`, `include/sweph.h:104`, solver `src/swemplan.zig`, file `seorbel.txt` (`SE_FICTFILE`).
Rule: `ipl = 39 + line_no`; `SE_FICT_OFFSET=40`, `MAX=999`, `NFICT_ELEM=15` built-in slots. `xx[6]` same units as planets (deg/AU/deg-day).
Per-body pattern: definition → elements/units → provenance → limits → Zig + C example → error path.

Shared example:
```zig
_ = swe.calc_ut(jd_ut, 43, flg, &xx, &swed, models, &dctx, &serr); // Kronos
```
```c
swe_calc_ut(jd, SE_KRONOS, SEFLG_SPEED, xx, serr);
```

## 40–47 Hamburg/Uranian (Witte/Sieggrün, Neely refinement)
Definition: heliocentric circular/coplanar approx planets for symmetrical Hamburg-school technique. Elements: J1900 equinox, small-e, `a` 40–84 AU; mean motion from `a` via `KGAUSS` unless M0 T-term present. Provenance: Witte 1920s, Neely refit; compiled-in defaults = `seorbel.txt` lines 1–8.
* 40 Cupido (≠ asteroid 763) · 41 Hades · 42 Zeus (≠ 5731 Zeus) · 43 Kronos · 44 Apollon (≠ 1862 Apollo) · 45 Admetos · 46 Vulkanus (≠ 55 Vulcan, ≠ 4464 Vulcano) · 47 Poseidon (≠ 4341 Poseidon).
Limits: no date clamp — valid any JD but meaningless outside 1800–2400 fit window; always label "hypothetical". Name collisions above are the top user error — assert ID, not name. Error: missing `seorbel.txt` → built-ins used silently; custom line malformed → `ERR` + line number in `serr`.

## 48 Isis/Transpluto — definition/elements/provenance/limits
Strubell *Die Sterne* 1952: epoch 1772.76 (JD 2368547.66), equinox 1945 (JD 2431456.5), `a=77.775, e=0.3`. Fitted to match ASTRON tables, not physics. Limits: high-e → speed varies 10×; transit search needs small steps. Error: same file path as above.

## 49 Nibiru — Woeltge `a=234.8921, e=0.981092, i=158.708°` retrograde, `node=-44.567, argp=103.966`
Limits: e≈0.98 — near-perihelion speed extreme; `SEFLG_SPEED` finite-difference degrades; prefer position-only + own differentiator. Label hypothetical.

## 50 Harrington — AJ 96(4)1988 `a=101.2, e=0.411, i=32.4°, node=275.4, argp=208.5` J2000
Limits: TNO-zone, slow (centuries/deg) — `house_pos` fine, `rise_trans` pointless.

## 51/52 Leverrier/Adams Neptunes, 53/54 Lowell/Pickering Plutos
Definition: 19th/early-20th-c. Planet-X hypotheses (Hoyt). Elements: 51 `a=36.15 e=0.108`, 52 `a=37.25 e=0.121`, 53 `a=43 e=0.202`, 54 `a=55.1 e=0.31 i=15°`. Provenance: Hoyt *Planets X and Pluto*. Limits: historical interest only; never use for prediction. Error: none beyond generic.

## 55 Vulcan (intramercurial, ≠ 46 Vulkanus)
Definition: non-Keplerian demo with M0 T-term `252.8987988+707550.7341*T` overriding Kepler speed; `J1900,JDATE` equinox-of-date line. Limits: T-term speed preserved verbatim for C-compat — physics-violating by design; document as such. Error: editing the line's T-term changes speed discontinuously — re-validate with `swetest -p55`.

## 56 White Moon/Selena (geo)
Definition: geocentric monthly oscillator (`", geo"` suffix, `a≈0.0528` AU-equiv, `M0=242.22°` J2000). Limits: geocentric — `HELCTR/BARYCTR` flags meaningless; `TOPOCTR` adds parallax correctly. Error: heliocentric-file lookup never attempted.

## 57 Proserpina / 58 Waldemath
Keplerian Uranian-school extensions; no `SE_NAME_*` macro — `get_planet_name()` echoes `seorbel.txt` name. Limits: same as 40–47.

## `seorbel.txt` line grammar + user 59…999
`epoch, equinox, M0, a, e, argp, node, incl, Name[, geo]`; `epoch/equinox` JD or `J1900/B1950/J2000/JDATE`; T-terms `+r*T`, `T*T/T2/T3`, `T=(tjd-epoch)/36525`; `M0/argp/node/incl` deg, `a` AU (geocentric-radius if `, geo`); `#` comment. Speed from `a` unless M0 has T-term. Lookup `$EPHE/seorbel.txt` else built-ins; append lines 16…960 → `ipl 59…999`; validate `swetest -p59 -b1.1.2000 -fPLBRS`; no date clamps — caller owns validity; malformed line → `ERR` with line number.
