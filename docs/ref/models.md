# Astro Models — full depth

Truth: `include/swephexp.h:499`, hooks `swe_set/get_astro_models()`
(`include/swephexp.h:686`), Zig `AstroModels{}` in `src/swephlib.zig` passed
to every calc.
Per-model pattern: definition → units/range → provenance → limits → select
example → error path. Defaults are correct for 99% — change only to reproduce
legacy tables.

## Slots `SE_MODEL_*` (`NSE_MODELS=8`)
`0 DELTAT · 1 PREC_LONGTERM · 2 PREC_SHORTTERM · 3 NUT · 4 BIAS · 5 JPLHOR_MODE
· 6 JPLHORA_MODE · 7 SIDT`. Zig: `const models = swe.swephlib.AstroModels{};`
(all defaults); C: global slots via test hook. Mismatched slots across
threads → irreproducible arcsecond diffs — construct one `models` value and
share read-only.

## Precession 1–11 (default 9 VONDRAK_2011 both terms)
Definition: equinox motion model. Units: arcsec/cy polynomials. Provenance:
1 Lieske 1976 · 2 Laskar 1986 · 3 Will-Eps-Lask · 4 Williams 1994 · 5 Simon
1994 · 6 IAU2000/P03 · 7 Bretagnon 2003 · 8 IAU2006 · 9 Vondrák 2011 (±200 ky,
**use**) · 10 Owen 1990 (Horizons wings) · 11 Newcomb (ayanamsha-fit only).
Limits: pre-1.70 Lieske-window caused 1800/2200 steps; P03 0.05 mas 1000–3000
CE, −3.9" @5000 BCE vs Vondrák, degrees by −20000. Example: keep default; for
Horizons wings set slot to 10 with `JPLHOR` flag. Error: slot 11 in calc path
(not ayanamsha-fit) drifts centuries — never select directly.

## Nutation 1–5 (default 4 = 2000B)
Definition: short-period obliquity/longitude wobble. Units: mas. Provenance:
1 Wahr 1980 (106) · 2 +Herring 1987 (AA ignores) · 3 2000A (1365, µas, slow) ·
4 2000B (77, mas, fast, **default**) · 5 Woolard (IENA legacy). Limits: A↔B
<1 mas; `set_interpolate_nut()` + EOP file needed for sub-mas
(`src/nutdifftest.zig:578`). Error: 2000A cost 10× CPU for no visible gain —
profile before switching.

## Sidereal time 1–4 (default 4 LONGTERM)
Definition: GMST model. Provenance: 1 IAU1976 · 2 IAU2006 (Eo) · 3 IERS2010 ·
4 Vondrák-consistent long-term (**default**). Limits: new−old +1 ms @2000,
−2.5 s @5400 BCE, −57 s at window edge. `sidtime()` honors slot;
`sidtime0(tjd,eps,nut)` bypasses. Error: mixing slots between `houses` and
`sidtime` calls desyncs ASC by seconds — use one `models`.

## Frame bias 1–3 (default 3 IAU2006)
Definition: ICRS→J2000 micro-rotation (~6.8 mas RA). 1 NONE · 2 IAU2000 ·
3 IAU2006 (**default**). Limits: wrong slot = 53 mas Horizons-style RA offset.
Error: `ICRS` flag + bias slot interact — for raw DE406-frame output set flag
`ICRS` and slot NONE together.

## JPL-Horizons 1 / HORA 1–3 (defaults 1 / 3)
Definition: EOP-driven Horizons emulation. `JPLHOR` + daily `dpsi/deps`
1962–today (~1 mas 1799–today); outside, edge values held (continuous,
degraded). `JPLHOR_APPROX` without EOP ~2 mas; HORA 1 recent-model, 2 no-bias
legacy, 3 hybrid (**default**). Limits: needs `eop*.dat` in `$EPHE`;
pre-1962 agreement is continuity, not truth. Error: missing EOP silently
degrades — log file-load status.

## Delta-T 1–5 (default 5 STEPHENSON_ETC_2016)
Definition: TT−UT model. 1 S-M 1984 · 2 S1997 · 3 S-M 2004 · 4 Espenak/Meeus
2006 · 5 Stephenson/Morrison/Hohenkerk 2016 (**default**,
`src/tables_deltat.zig`). `SE_DELTAT_AUTOMATIC=-1E-10` restores;
`set_delta_t_userdef(d)` overrides (days). Tidal `SE_TIDAL_*` couples
pre-1955. Limits: post-1955 <2 s spread; pre-1000 BCE minutes — always cite
model. Error: userdef left set contaminates later calls — reset to AUTOMATIC
in teardown.
