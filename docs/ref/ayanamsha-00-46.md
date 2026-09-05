# Ayanamsha 0–46 + 255 User — full depth

Truth: IDs `include/swephexp.h:238`, table `aya_init ayanamsa[]`
`include/sweph.h:351`, engine `src/sweph.zig:1248` + `:1382`.
API: `set_sid_mode(mode,t0,ayan_t0)` / `get_ayanamsa_ex(jd,iflag,&aya)` /
`get_ayanamsa_ex_ut`; `SE_NSIDM_PREDEF=47`.
Per-group pattern: definition → t0/ayan_t0 units → provenance → limits → Zig
+ C example → error path.
`t0_is_UT=Y` = epoch in UT (Delta-T applied); `prec_offset` = fitted
precession model, engine corrects to Vondrák 2011 unless
`SIDBIT_NO_PREC_OFFSET/PREC_ORIG`.

Shared example:
```zig
swe.set_sid_mode(1, 0, 0, &swed, null); // Lahiri
var aya: f64 = 0;
_ = swe.get_ayanamsa_ex_ut(jd_ut, 0, &aya, &swed, models, &dctx, &serr);
_ = swe.calc_ut(jd_ut, 0, flg | swe.sweph.SEFLG_SIDEREAL, &xx, &swed, models, &dctx, &serr);
```
```c
swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
double aya = swe_get_ayanamsa_ut(jd_ut);
```

## Tropical-epoch Indian/modern (0–8, 43–46)
Definition: 20th-c. fitted offsets to tropical ephemeris; `ayan_t0` deg at
`t0` JD.
* 0 Fagan/Bradley `2433282.42346, 24.042044444` N/NEWCOMB — default;
  Spica-based Western sidereal. 1 Lahiri `2435553.5,
  23.250182778−0.004658035` N/IAU_1976 — IAE 1989 standard; reproduces IENA
  ≥1960 means (±0.1" true residual). 2 DeLuce `1721057.5, 0` Y/0 — true zero
  at Jesus epoch. 3 Raman `J1900, 360−338.98556` NEWCOMB. 4 Usha/Shashi
  `360−341.33904` −1 (unverified book). 5 KP `360−337.636111` NEWCOMB (291 CE
  zero). 6 Djwhal `360−333.0369024` 0 (Aquarius 2117). 7 Yukteshwar
  `360−338.917778` −1 — Revati-intended but 2.5° off (54"/yr SS rate error).
  8 Bhasin `360−338.634444` −1. 43 Lahiri-1940 `J1900, 22.44597222` NEWCOMB.
  44 VP285 `1825235.2458513028, 0` 0. 45 VP291 `1827424.752255678, 0` 0.
  46 ICRC `2435553.5, 23.25−0.00464207` NEWCOMB — pre-1985 Woolard; differs
  (1) by 1.1".
Limits: mixing (1) vs (46) shifts charts 1.1"; (7) shifts 2.5°. Error:
`mode≥47 && ≠255` silently resets to 0 — validate mode range.

## Babylonian/ancient (9–16, 38, 42)
Definition: cuneiform-zodiac reconstructions, all `t0_is_UT=Y, prec=−1`
except 14 (`prec=0`). 9–11 Kugler −5.667/−4.267/−3.417 @1684532.5; 12 Huber
−4.467; 13 Mercier −5.079 @1673941 (eta Psc); 14 Aldebaran −4.441 @1684532.5
(15 Tau −100, exact); 15 Hipparchos −9.333 @1674484; 16 Sassanian 0
@1927135.87; 38 Britton −3.2 @1721057.5; 42 Valens −2.9422 @1775845.5.
Provenance: Huber 1958, Britton 2010, Holden/Valens. Limits: research-only;
precession mismatch dominates (arcminutes). Error: same mode-range reset.

## Sidereal-epoch Indian (21–26, 37)
Definition: zero = mean-Sun Aries ingress Ujjain 499 CE, all Y/0. 21 SS
`1903396.8128654, 0`; 22 SS-mean-Sun −0.21463; 23 Aryabhata `1903396.7895321,
0`; 24 Arya-mean-Sun −0.23763; 25 SS-Revati −0.79167 (zePsc 359°50′); 26
SS-Citra +2.11070 (Spica 180°); 37 Kali-522 `1911797.740782065, 0`.
Provenance: Suryasiddhanta/Aryabhata sunrise tables. Limits: ingress defined
noon LMT Ujjain — UT conversion needs longitude; ±arcmin disputes between
schools live here. Error: none beyond mode reset.

## Star/galactic runtime (17, 27–36, 39–41)
Definition: computed from star/frame each call (`src/sweph.zig:1382`), `t0=0`
placeholder. 17 Gal-Center 0 Sag; 27 True Citra (Spica 0 Lib); 28 True Revati
(zePsc 29°50′ Psc); 29 True Pushya (deCnc 16 Cnc); 30 Gil Brand
golden-section; 31 GE-IAU1958; 32 GE-true (Liu/Zhu/Zhang pole); 33 GE-Mula;
34 Mardyks `2451079.734892, 30`; 35 True Mula (Chandra Hari code path); 36
Wilhelm Mula; 39 Sheoran Vedic; 40 Cochrane 0 Cap; 41 Fiorenza `2451544.5,
25.0` UT. Limits: star PM + galactic-pole revision shift results vs frozen
modes — state mode number in publications. Needs `sefstars.txt` for
star-anchored. Error: missing star file → `ERR` on 27–29/35.

## Fixed-frame 18–20 + user 255
18 J2000 / 19 J1900 / 20 B1950 (`prec=0`) — no offset; RA/Dec returned in
reference-epoch frame (others: mean-equinox-of-date, `src/sweph.zig:1248`).
255 USER: pass `(t0,ayan_t0)` + `SIDBIT_USER_UT=1024` if UT; combine
`ECL_T0=256` / `SSY_PLANE=512` / `ECL_DATE=2048`. Error: forgetting `SIDEREAL`
flag in `calc` returns tropical silently — always OR `SEFLG_SIDEREAL`.
