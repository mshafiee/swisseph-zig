# Numbered Asteroids, Comets & Minor Bodies

> Part of the [swisseph-zig documentation](../index.md) · [Data Files Guide](../guide/02-data-files.md) · [Bodies Reference](../reference/20-bodies-planets.md)

While the major classical planets (`0`–`22`) and fictitious bodies (`40`–`58`) use reserved compact indices, minor planets, asteroids, and comets are addressed dynamically via catalog offset schemes.

### Core Constants & References
- **Header Definitions:** `include/swephexp.h:127`
- **Asteroid Name Catalog:** `seasnam.txt` (`SE_ASTNAMFILE`)
- **Calculation Engines:** `src/sweph.zig:3074` and `src/swejpl.zig`

| Constant | Value | Purpose |
|---|:---:|---|
| `SE_AST_OFFSET` | `10000` | Base offset for Minor Planet Center (MPC) numbered asteroids |
| `SE_COMET_OFFSET` | `1000` | Base offset for numbered periodic comets |
| `SE_VARUNA` | `30000` | Shorthand alias for minor planet (20000) Varuna (`10000 + 20000`) |

---

## 1. Numbered Asteroids (`ipl = SE_AST_OFFSET + MPC#`)

Any minor planet cataloged by the Minor Planet Center (MPC) is addressed by adding `10000` to its catalog number:

$$\text{ipl} = 10000 + N_{\text{MPC}}$$

### Common Minor Bodies

| MPC # | Body Name | Target ID (`ipl`) | Storage Subdirectory | Primary File |
|:---:|---|:---:|:---:|---|
| `1` | Ceres | `10001` *(or internal `17`)* | `ast0/` | `se00001.se1` (or `seas_18.se1`) |
| `2` | Pallas | `10002` *(or internal `18`)* | `ast0/` | `se00002.se1` (or `seas_18.se1`) |
| `3` | Juno | `10003` *(or internal `19`)* | `ast0/` | `se00003.se1` (or `seas_18.se1`) |
| `4` | Vesta | `10004` *(or internal `20`)* | `ast0/` | `se00004.se1` (or `seas_18.se1`) |
| `433` | Eros | `10433` | `ast0/` | `se00433.se1` |
| `1862` | Apollo | `11862` | `ast1/` | `se01862.se1` |
| `3753` | Cruithne | `13753` | `ast3/` | `se03753.se1` |
| `20000` | Varuna | `30000` (`SE_VARUNA`) | `ast20/` | `se20000.se1` |
| `50000` | Quaoar | `60000` | `ast50/` | `se50000.se1` |

---

## 2. File Organization & Storage Layout

Asteroid ephemeris files are divided across numeric partition directories based on their MPC number:

$$N = \left\lfloor \frac{\text{MPC number}}{1000} \right\rfloor \implies \text{directory ast}N/$$

For example, asteroid **433** resides in `ast0/`, while asteroid **1862** resides in `ast1/`.

### File Types: Long vs. Short Spans
For each asteroid, Astrodienst publishes two file variants:
1. **Long-Span Files (`seNNNNN.se1`):** Cover approximately **3000 BCE to 3000 CE**.
2. **Short-Span Files (`seNNNNNs.se1`):** Cover **1500 CE to 2100 CE** (roughly 10% of the long-span file size).

```
ephe/
├── seasnam.txt            # Master asteroid name table (MUST be in root)
├── seas_18.se1            # Bundled core asteroids: Ceres, Pallas, Juno, Vesta, Chiron, Pholus
├── ast0/
│   ├── se00001.se1        # Ceres (long span)
│   ├── se00433s.se1       # Eros (short span)
│   └── ...
├── ast1/
│   └── se01862.se1        # Apollo
└── ast20/
    └── se20000.se1        # Varuna
```

### Search & Fallback Precedence
When querying an asteroid:
1. The engine looks for the **long-span file** (`seNNNNN.se1`) in directory `astN/`.
2. If absent, it searches for the **short-span file** (`seNNNNNs.se1`) in directory `astN/`.
3. If neither file exists, the engine returns an error (`ERR`). **There is no analytical Moshier model for numbered asteroids.**

> **Storage Budget:** The bundled `seas_18.se1` core file is ~200 KB. Mirroring the complete numbered asteroid catalog (1 to 21,999) requires approximately **7.4 GB** for long-span files or **~800 MB** for short-span files.

---

## 3. Astrodynamic Limits & Chaotic Orbits

Unlike major planets whose orbits are stable across tens of thousands of years, asteroids frequently experience close gravitational encounters with planets (particularly Mars and Jupiter) and non-gravitational perturbations.

Consequently, asteroid files **do not share a uniform time span**:
- **Chaos Horizons:** Numerical integrations terminate when orbital chaos prevents reliable precision.
- **Close Encounters:** For example, **1862 Apollo** experienced an ultra-close encounter with Venus; its ephemeris is valid **only for epochs $\ge$ 1870 CE**.
- **Chiron-Class Objects:** Return `ERR_BEYOND` (`-3`) if evaluated outside their valid numerical integration arc.

### Error Handling Protocol
When a date falls outside an asteroid's integration arc:
- The function returns `ERR_BEYOND` (`-3`).
- All coordinates in `xx[0..5]` are **zeroed out**.
- An error description is written to the `serr` buffer.

*Always inspect the return code before reading coordinate buffers.*

---

## 4. Code Examples

### Querying an Asteroid in Zig
```zig
const std = @import("std");
const swe = @import("swisseph");

pub fn getAsteroidCoordinates() !void {
    var swed = swe.sweph.Swed{};
    var dctx = swe.deltat.DeltatCtx{};
    const models = swe.swephlib.AstroModels{};
    var serr: [256]u8 = undefined;

    swe.set_ephe_path("/data/ephe", &swed);

    // MPC #433 (Eros) -> 10000 + 433 = 10433
    const eros_id: i32 = swe.sweph.SE_AST_OFFSET + 433;

    // 1. Resolve asteroid name from seasnam.txt
    var name_buf: [40]u8 = undefined;
    _ = swe.get_planet_name(eros_id, &name_buf, &swed);
    std.debug.print("Body: {s}\n", .{name_buf});

    // 2. Compute coordinates (2000-01-01 12:00 UT)
    const jd_ut = swe.julday(2000, 1, 1, 12.0, swe.swedate.SE_GREG_CAL);
    var xx: [6]f64 = undefined;

    const result = swe.calc_ut(
        jd_ut,
        eros_id,
        swe.sweph.SEFLG_SPEED,
        &xx,
        &swed,
        models,
        &dctx,
        &serr,
    );

    if (result < 0) {
        std.debug.print("Calculation failed: {s}\n", .{serr});
        return error.EphemerisLookupFailed;
    }

    std.debug.print("Longitude: {d:.6}°, Distance: {d:.6} AU\n", .{ xx[0], xx[2] });
}
```

### C ABI Equivalent
```c
#include <stdio.h>
#include "swephexp.h"

void query_eros(double jd_ut) {
    swe_set_ephe_path("/data/ephe");

    int eros_id = SE_AST_OFFSET + 433;
    char name[40];
    swe_get_planet_name(eros_id, name);

    double xx[6];
    char serr[256];
    int res = swe_calc_ut(jd_ut, eros_id, SEFLG_SPEED, xx, serr);

    if (res < 0) {
        fprintf(stderr, "Error: %s\n", serr);
        return;
    }

    printf("%s: Lon=%.6f deg, Dist=%.6f AU\n", name, xx[0], xx[2]);
}
```

---

## 5. Comets & Non-Gravitational Bodies (`SE_COMET_OFFSET`)

Periodic comets are designated using `SE_COMET_OFFSET` (`1000`):

$$\text{ipl} = \text{comet offset} + N_{\text{comet}}$$

### Why Comets Require Osculating Elements
Unlike asteroids, comets experience significant non-gravitational acceleration caused by outgassing jets near perihelion. As a result:
- Orbital elements **change significantly between apparitions**.
- Calculations cannot use a single static ellipse across multiple centuries.
- You must load an apparition-specific osculating element file (`seocom*.se1`) or import high-precision state vectors directly from **JPL Horizons** using the ephemeris generator utility (`swephgen4` in `src/ep4/`).

To verify which osculating ellipse was selected for a specific epoch, inspect the active orbital parameters using:
```zig
var elem: [50]f64 = undefined;
_ = swe.get_orbital_elements(jd_ut, comet_id, &elem, &swed, &serr);
```

---

## 6. Trans-Neptunian Objects & The `SE_VARUNA` Shorthand

In the early 2000s, minor planet **(20000) Varuna** was assigned a dedicated convenience constant:

```c
#define SE_VARUNA 30000  // Exactly SE_AST_OFFSET + 20000
```

Varuna resolves to directory `ast20/` and file `se20000.se1` through the standard asteroid engine.

### Other Trans-Neptunian Objects (TNOs)
Other major TNOs and dwarf planets discovered after Varuna do **not** have dedicated `SE_*` defines. They are accessed using standard MPC catalog arithmetic:
- **(50000) Quaoar:** `10000 + 50000 = 60000` (resides in `ast50/se50000.se1`)
- **(90377) Sedna:** `10000 + 90377 = 100377` (resides in `ast90/se90377.se1`)
- **(90482) Orcus:** `10000 + 90482 = 100482` (resides in `ast90/se90482.se1`)
- **(136199) Eris:** `10000 + 136199 = 146199` (resides in `ast136/se136199.se1`)
- **(136472) Makemake:** `10000 + 136472 = 146472` (resides in `ast136/se136472.se1`)
