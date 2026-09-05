# Bit-Parity Methodology — full guide

Port rule: exact FP op order, exact constants/tables, `==` compare on `%.17g` round-trip — never tolerance. Oracle C compiled `-ffp-contract=off`. Detail: `ref/threading-build.md`.

## FMA trap (why `-ffp-contract=off`)

Apple clang fuses `a*b+c` by default → ≤1 ULP, non-portable across GCC/MSVC/ARM/x86. Zig never contracts → matches no-FMA oracle exactly. Forgetting the flag is the #1 false-mismatch cause.

## libm strategy (`src/libmshim.c`, `src/libm/cr.zig`)

| Path | `sin/cos/tan/log/exp/fmod` | `atan/asin/acos/atan2/pow` |
|---|---|---|
| Default shim | platform libm via `dlsym`, bit-exact | bit-exact |
| `-Dpure` | Zig `std.math`, bit-identical | `f128` Ziv correctly-rounded → 1 ULP vs libm by design |

libm itself is unrounded for the right column (vs 60-digit mpmath: `atan` 4%, `acos` 15% off). Vendoring Apple Taligent double-double blocked by APSL. WASM/Windows force pure.

## Corpora: 4,428,079 cases, 0 failures

swedate 2.2M · calc MOSEPH+SWIEPH 1.2M · Moshier moon 348k · houses 338k · Moshier planets 195k · asteroids 26k · sidereal 21k+21k · swecl 12.5k · topocentric 10k · rise/set 8.9k · JPL 6.5k · fict 7k · heliacal 3.5k · moons 3.1k · nod_aps 3k · pheno 2.7k · fixstars 1.7k · nut-interp 578 · eclipses 282 · Delta-T 28k.

## Release gate (companion `swisseph-zig-verify`)

```sh
make verify FORCE=1  # 21 corpora, 4.4M, 0 failures required
make abi             # 119 symbols, helper parity vs C libswe.a
make tools           # swetest/swemini/obama/swevents byte-exact
zig build run-stress # 32-thread mixed-workload determinism (in-repo)
```

External accuracy (not parity): vs Astronomical Almanac 0.001", vs Horizons ~1 mas 1962–today with EOP (~2 mas approx), DE431–DE406 <0.4" Sun / <129" Pluto. State model + file set with every published number.
