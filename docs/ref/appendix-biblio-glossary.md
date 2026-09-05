# Appendix A — Bibliography + Glossary

## Bibliography (cited by `ref/*.md`)

* Standish et al., JPL Planetary and Lunar Ephemerides DE403/LE403, IOM
  314.10-127 (1995) — DE406 accuracy budget (`consts.md` §4).
* Folkner et al., JPL DE431 (2014); IPN PR 42-196 — default ephemeris,
  `SE_TIDAL_DE431`.
* Capitaine / Wallace / Chapront, P03 precession (2003); Vondrák et al., A&A
  534 A22 (2011) — `models.md` precession.
* IAU 1976/2000/2006 resolutions; IERS Conventions 1996/2003/2010 — bias,
  nutation 2000A/B, 53 mas Horizons offset.
* Stephenson / Morrison / Hohenkerk, Proc. Roy. Soc. A (2016) — Delta-T
  default; Espenak/Meeus (2006) legacy.
* Meeus, *Astronomical Algorithms* — eclipse/house algorithms background.
* Huber, Centaurus 5 (1958); Britton, Arch. Hist. Exact Sci. 64 (2010) —
  Babylonian ayanamshas.
* Liu / Zhu / Zhang, A&A (2010) — galactic pole (GE-true).
* Schaefer (1993+) — heliacal visibility model (`swehel`).
* Astronomical Almanac + Explanatory Supplement — AA constants
  (`HELGRAVCONST`, `MOON_*`), 0.001" agreement claim.

## Glossary

ARMC (RA of MC) · ASC/MC/Vertex/EquASC · Barycenter vs COB vs photocenter ·
Ecliptic (date/J2000/t0/SSY-plane) · ET/TT/UT1/UTC/JD · GMST/LMST · Ayanamsha
(tropical minus sidereal) · Nakshatra · Saros/gamma · Arcus visionis ·
`Swed/DeltatCtx/AstroModels/HouseCtx` (per-thread bundles) · `SweState` (ABI
threadlocal) · FMA contraction · `%.17g` round-trip compare.
