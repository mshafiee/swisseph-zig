# swisseph-zig

[![CI](https://github.com/mshafiee/swisseph-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/mshafiee/swisseph-zig/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-0.16.x-orange.svg)](https://ziglang.org)

Pure Zig port of Swiss Ephemeris — no C library dependency for the computation
core. Provides planetary positions, houses, eclipses, risings/settings,
heliacal events, fixed stars, asteroids, and more.

## Status

| Component | Verification |
|---|---|
| 9 SWEOBJ modules (swedate…swehel) | 21 differential corpora, 4,428,079 cases, **0 failures** vs C oracle |
| C ABI drop-in (`libswe`, 107 `swe_*` symbols) | `abi-verify.sh` — pure helpers 0 diff vs C |
| CLI tools (`swetest`, `swevents`, `swemini`, `obama`) | byte-exact vs `-ffp-contract=off` C oracles |

## Usage

### Zig dependency

```sh
zig fetch --save git+https://github.com/mshafiee/swisseph-zig
```

```zig
const swe = @import("swisseph");

pub fn main() !void {
    var xx: [6]f64 = undefined;
    var serr: [256]u8 = undefined;
    const jd = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL);
    _ = swe.calc_ut(jd, 0, swe.sweph.SEFLG_SPEED, &xx, &serr); // Sun
    std.debug.print("Sun: {d:.6}\n", .{xx[0]});
}
```

### C ABI drop-in

```sh
make native   # -> dist/<host>/lib/libswe.a|dylib|so, dist/<host>/include/
cc myprog.c -Idist/<host>/include -Ldist/<host>/lib -lswe -lm -o myprog
```

### CLI tools

```sh
make && ./zig-out/bin/swetest -b1.1.2000 -p0 -fPLBRS -g, -head
```

## Targets

| Target | libswe | Tools |
|---|---|---|
| x86_64-linux, aarch64-linux | `.a` + `.so` | `.exe`-less ELF bins |
| x86_64-macos, aarch64-macos | `.a` + `.dylib` | bins |
| x86_64-windows | `.lib` + `.dll` | `.exe` |
| wasm32-freestanding | `.a` only | — |
| wasm32-wasi | `.a` | bins (WASI libc) |

## Build options

| Flag | Effect |
|---|---|
| `-Dpure=true` | Pure Zig `std.math` — no `libm` shim, no `dlfcn`. **Auto-forced on wasm32-\* and Windows.** |
| `-Dtarget=<triple>` | Cross-compile (zig handles toolchains natively) |

The default (non-pure) path uses a `dlsym` shim to call the platform `libm`,
matching the C library bit-for-bit on the 21-corpora gate. Pure mode uses
Zig `std.math` + a correctly-rounded `f128` fallback for `atan/asin/acos/
atan2` — bit-identical for `sin/cos/tan/log/log10/exp/fmod`, up to 1 ULP
on the rest (platform `libm` itself deviates from correctly-rounded there).

See `docs/parity.md` for the full story.

## Data files

Ephemeris data (`.se1`, `.se1` asteroid files, `seorbel.txt`, `sefstars.txt`)
are **not committed**. See `docs/data-files.md`. Moshier mode (`SEFLG_MOSEPH`)
needs no data files at all.

## License

Dual-licensed, same model as upstream Swiss Ephemeris:

- **AGPL-3.0** — open source use ([LICENSE](LICENSE))
- **Commercial** — available from Mohammad Shafiee ([LICENSE.commercial](LICENSE.commercial))

See [NOTICE.md](NOTICE.md) for upstream attribution.
