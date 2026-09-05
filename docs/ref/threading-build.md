# Threading + Build + WASM — engineering reference

Truth: `README.md:216` contract, `build.zig:13`, `src/swe_abi.zig` threadlocal, `src/libm/cr.zig`, `src/test_stress_race.zig`.

## Threading

Zig: all mutable state in `Swed` (+`moon_ws/plan_ws/jpl`/fixstar cache), `DeltatCtx`, `SweclCtx`, `SwehelCtx`, `HouseCtx`. **One bundle per thread; sharing needs external lock.** C ABI: one `SweState` per OS thread (`threadlocal`, mirrors upstream TLS) — `set_*` calls are per-thread, repeat setup on every thread. Teardown: Zig `SweState.deinit()`, C `swe_close()` (files) + `swe_cleanup()` (fixstar cache, `SWE_ZIG_EXTENSIONS`). Verified: 32 threads×4 mixed JPL/SWIEPH/Moshier rounds bit-identical to single-thread (`zig build run-stress`).

## Build / targets / math

`make` → host `dist/<triple>/`; `make all` → 9 triples (linux-gnu×2, freebsd×2, macos×2, windows, wasm-freestanding, wasm-wasi); `make test/lint`. `zig build -Dpure=true` forces `std.math` + `cr.zig` f128-Ziv correctly-rounded `atan/asin/acos/atan2/pow` (1 ULP vs libm by design); default shims platform libm via `libmshim.c` for bit-parity with `-ffp-contract=off` oracle. WASM + Windows force pure (no shim). Tools: `swetest/swevents/swemini/obama/swephgen4` in `src/bin/` + `src/ep4/`, byte-exact vs C oracles (`parity.md`).
