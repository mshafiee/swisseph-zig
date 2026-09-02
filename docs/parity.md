# Bit-Parity Methodology

The port was verified bit-for-bit against the original C code using a
differential-testing harness (the "oracle" pattern):

1. **C oracle** compiled with `-ffp-contract=off` — one IEEE-754 rounding per
   operation, reflecting the operation order *written* in the C source.
2. **Zig port** preserves the exact FP operation order (no reordering, no
   FMA contraction).
3. **Comparison** uses exact `==` on `%.17g`-round-tripped doubles — never
   a tolerance.

## The FMA trap

Apple clang's default `-ffp-contract=on` fuses `a*b+c` into FMA, producing
up to 1-ULP differences that are **not portable** (GCC/MSVC/ARM/x86 all
differ). The oracle must be compiled with `-ffp-contract=off`. Zig's
default (no contraction) matches the no-FMA oracle exactly.

## libm strategy

| Path | `sin/cos/tan/log/log10/exp/fmod` | `atan/asin/acos/atan2/pow` |
|---|---|---|
| Default (shim) | platform libm via `dlsym` — bit-exact | same |
| `-Dpure` | Zig `std.math` — bit-identical to libm | `f128` correctly-rounded — 1 ULP vs libm on some args |

Platform `libm` is itself **not correctly rounded** for `atan/asin/acos/
atan2/pow` (measured vs 60-digit mpmath: `atan` 4% wrong, `acos` 15%).
The `cr.zig` fallback uses `f128` (113-bit) + Ziv rounding — correctly
rounded, but therefore differs from the C libm by design. Vendoring
Apple's actual algorithms (Taligent double-double) is blocked by the
APSL license (GPL-incompatible).

## Corpora

21 corpora cover every code path: swedate (2.2M), delta-T (28k), houses
(338k), Moshier moon (348k), Moshier planets (195k), nutation+sidereal
(17k), swe_calc MOSEPH+SWIEPH (1.2M), sidereal (21k), topocentric (10k),
fictitious (7k), nutation interp (578), JPL (6.5k), fixstars (1.7k),
swecl (12.5k), pheno (2.7k), rise/set (8.9k), heliacal (3.5k), nod_aps
(3k), eclipses (282), asteroids (26k), planetary moons (3.1k).

The verification harness lives in a companion repo (`swisseph-zig-verify`)
and gates every release.
