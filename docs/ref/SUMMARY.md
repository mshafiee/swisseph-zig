# Reference Index — exhaustive `docs/ref/`

Complete set (20 files). Source truth: `include/swephexp.h`, `include/sweph.h`, `src/*.zig`.

**Constants & frames:** `consts.md` (values+provenance) · `models.md` (precession 1–11, nutation 1–5, sidtime 1–4, bias 1–3, JPLHOR/HORA, Delta-T 1–5) · `ayanamsha-00-46.md` (47+255).

**Bodies:** `bodies-00-22.md` (−1…22) · `bodies-fict.md` (40–58 + 59…999 user) · `bodies-moons.md` (9401…9999 + COB) · `bodies-asteroids.md` (10000+N, comets, Varuna) · `stars.md` (sefstars + fixstar API).

**Houses:** `houses-A-Y.md` (26 codes + Placidus default, cusps[37]/ascmc[10]).

**Flags:** `flags-calc.md` (SEFLG_*, NODBIT_*, SPLIT_DEG_*) · `flags-eclipse-rise-heliacal.md` (eclipse/rise/azalt/heliacal bits + tret/attr/datm/dobs layouts).

**Functions (all 107 + swe_cleanup):** `funcs-calc.md` (setup/calc/crossings) · `funcs-houses.md` · `funcs-eclipse.md` (eclipse/occult/rise/pheno/nodes) · `funcs-datetime.md` (calendar/Delta-T/sidtime/cotrans/aux) · `funcs-heliacal.md` (heliacal/models/version).

**Engineering:** `data-files.md` (se1/sat/ast layout) · `threading-build.md` (contexts, WASM/-Dpure, 9 targets, tools) · `c-zig-map.md` (C↔Zig signature pattern) · `migration-faq.md` (C→Zig, errors, polar/chaos cases).

**Appendices:** `appendix-math.md` (KaTeX: time, light-time, aberration/deflection/bias, Vondrák+2000B, ARMC/houses, sidereal, eclipse/rise/heliacal, house-pos) · `appendix-biblio-glossary.md` (JPL/IAU/IERS/Stephenson/Meeus/Schaefer sources + glossary).

Top-level companions (thin, to expand): `../api.md`, `../data-files.md`, `../parity.md`.
