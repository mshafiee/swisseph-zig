# Houses A–Y + Placidus — full depth

Truth: `src/swehouse.zig:1607` `swe_house_name()`, calc `src/swehouse.zig:1508`, ABI `src/swe_abi.zig:741`.
Buffers: `cusps[37]` (`[1..12]` houses, `[1..36]` only for G), `ascmc[10]` = ASC, MC, ARMC, Vertex, EquASC, CoASC-Koch, CoASC-Munkasey, PolASC, NASCMC, unused.
Letter case-insensitive except `i` vs `I`. `hsys` int holds the char code.

Shared pattern per system: definition → math family → provenance → limits → Zig + C example → error path.
Shared examples use:
```zig
var cusps: [37]f64 = undefined; var ascmc: [10]f64 = undefined;
var hctx = swe.swehouse.HouseCtx{};
_ = swe.houses_armc_ex2(armc, lat, eps, 'P', &cusps, &ascmc, null, null, null, &hctx);
```
```c
double cusps[37], ascmc[10];
swe_houses_ex2(jd_ut, 0, lat, lon, 'P', cusps, ascmc, NULL, NULL, serr);
```
Speeds only from `*_ex2` variants. `swe_house_pos(armc,lat,eps,hsys,xpin)` → 1.0–12.0 (1–36 for G).

## P Placidus (default, `else` branch)
Definition: time-based unequal, diurnal-arc trisection projected to ecliptic. Provenance: Placidus de Titis; SE 2.09 interpolation fix. Limits: fails |lat|>66.5° — engine interpolates, fills `serr`, may return `ERR`. Most-tested (`src/housedifftest.zig:141`). Error: check return; fallback to U/O for polar charts.

## A/E Equal ASC, D Equal MC, N Equal Aries, V Vehlow, W Whole-sign
Definition: 30° equal divisions. A/E from ASC degree; D anchors 10th at MC; N fixes cusp 1 = 0° Aries; V starts 15° before ASC (ASC mid-1st); W cusp N = sign N. Math: ecliptic arithmetic, no time iteration. Provenance: Hellenistic equal/whole-sign revival. Limits: never fail. W maps to E internally (`src/swe_abi.zig:771`). Error: none.

## B Alcabitius
Definition: time-proportioned trisection of semi-diurnal/nocturnal arcs → ecliptic. Provenance: 9th-c. Alcabitius, Placidus precursor. Limits: mild polar stretch, no hard failure. Error: none typical.

## C Campanus / R Regiomontanus / M Morinus
Definition: 3D great-circle. C: prime-vertical 30° → ecliptic. R: equator 30° via hour circles → ecliptic. M: equator via ecliptic-pole great circles (ARMC+eps only, latitude-free). Provenance: Campano da Novara / Regiomontanus / Morin. Limits: robust at poles (M fully independent). Error: none.

## F Carter poli-equ. / J Savard-A
Definition: meridian/poli-equatorial experimental blends. Provenance: Carter / Savard, compatibility-kept. Limits: verify vs C oracle before publishing. Error: rare `ERR` on degenerate lat ±90°.

## G Gauquelin 36 sectors
Definition: 36 × 10° diurnal sectors (rise→ culminate →set→anti-culminate), not 12 houses. Only writer of `cusps[1..36]` (`src/swe_abi.zig:756`). Provenance: Gauquelin statistical work. Limits: needs `geopos` + time; sector speeds differ from house speeds. Use `swe_gauquelin_sector()` / `house_pos(..'G'..)` for placements (returns 1–36). Error: bad `imeth` → `ERR`.

## H Horizon/azimuth
Definition: cusps from azimuth circles (horizontal frame). Provenance: horizontal-system research. Limits: location-sensitive; pair with `swe_azalt()`. Error: none.

## I Sunshine / i Sunshine-alt.
Definition: Sunshine (Stark Fischer) — Sun-declination-weighted ascensional. Needs `HouseCtx.saved_sundec` (`src/swehouse.zig:28`); ABI per-thread `SweState.house`. `i` = altitude variant. Southern MC via `SUNSHINE_KEEP_MC_SOUTH` (`src/swehouse.zig:23`). Provenance: Sunshine Book. Limits: falls back to Porphyry O on failure (`src/swe_abi.zig:791`), sets `ascmc[9]` on `I`-success path. Error: `I`+polar → check fallback flag, don't assume P-like cusps.

## K Koch (GOH)
Definition: time-proportioned from MC with birthplace co-latitude (GOH tablets). Provenance: Koch/GOH school. Limits: polar-sensitive like Placidus. Error: same interpolate + `serr` path as P.

## L Pullen SD / Q Pullen SR
Definition: sinusoidal — SD delta-weighted, SR ratio-weighted. Provenance: Pullen modern. Limits: smooth all latitudes; recommended P/K replacement past ±66.5°. Error: none.

## O Porphyry
Definition: each MC–ASC quadrant split in 3 equal ecliptic degrees. Provenance: Porphyry (3rd c.). Limits: never fails; engine fallback target for I. Error: none.

## S Sripati (Bhava)
Definition: Porphyry-like quadrant trisection, Hindu Bhava usage. Pair with sidereal + `SE_SPLIT_DEG_NAKSHATRA`. Limits: none. Error: none.

## T Polich/Page topocentric
Definition: topocentric MC/ASC (parallax + `geoalt`). Requires `set_topo()` first or degrades to geocentric. Provenance: Polich/Page. Limits: without topo setup results equal geocentric approx — silent. Error: none; assert topo set in tests.

## U Krusinski-Pisa-Goelzer
Definition: equal-ascensional polar-stable (`src/swehouse.zig:1768` branch). Limits: defined past polar circles — default for |lat|>66.5°. Error: none.

## X Meridian / axial rotation
Definition: ARMC-driven meridian houses, horizon-independent. For mundane/rotation studies. Limits: ASC meaningless — read MC/ARMC only. Error: none.

## Y APC
Definition: ascensional APC via `apc_sector()` (`src/swehouse.zig:1639`). Polar-capable quadrant/whole-sign compromise. Limits: needs valid `eps`; degenerate at exact poles. Error: `ERR` at ±90° lat.
