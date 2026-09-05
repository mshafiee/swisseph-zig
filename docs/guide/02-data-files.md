# Ephemeris Data Files

> Part of the [swisseph-zig documentation](../index.md) · [Detailed Binary Layout Reference](../reference/60-data-files.md)

`swisseph-zig` is fully operational **with zero data files**. When no external files are installed, the engine defaults to the built-in analytical **Moshier ephemeris** (`SEFLG_MOSEPH`), providing sub-arcsecond accuracy for planets across historical epochs.

For micro-arcsecond scientific or professional astrological precision, you must download official Swiss Ephemeris (`.se1`) or raw JPL (`.eph`) binary files.

---

## Configuring the Ephemeris Path

Always register the ephemeris path during engine initialization (even when intending to use Moshier):

```zig
// Zig API (explicit Swed context)
swe.set_ephe_path("/path/to/ephe", &swed);

// Or pass null to strictly enforce internal Moshier mode:
swe.set_ephe_path(null, &swed);
```

```c
// C ABI (thread-local state)
swe_set_ephe_path("/path/to/ephe");
```

### Path Resolution Precedence
1. **Environment Variable:** `SE_EPHE_PATH` (if defined, overrides runtime function arguments).
2. **Runtime Call:** Path passed into `swe.set_ephe_path(...)`.
3. **Built-in Fallback:** Current working directory (`./`) or compiled-in defaults.

> ⚠️ **Buffer Limit:** File paths must not exceed **256 bytes**. Paths exceeding this length silently fall back to legacy directory search patterns.

---

## Download Packages

All official ephemeris files are available from Astrodienst:  
🔗 **[astro.com/ftp/swisseph/ephe/](https://www.astro.com/ftp/swisseph/ephe/)**

| Package | Contents | Approx. Size | Time Span / Description |
|---|---|---|---|
| **Core Set**<br>*(Recommended)* | `sepl_18.se1`<br>`semo_18.se1`<br>`seas_18.se1`<br>`sefstars.txt`<br>`seorbel.txt` | ~5 MB | **1800–2400 CE**<br>Planets, Moon, main asteroids (Ceres, Pallas, Juno, Vesta, Chiron, Pholus), fixed stars, and fictitious bodies. |
| **Full DE431 Coverage** | 50 `sepl_*.se1`<br>50 `semo_*.se1`<br>18 `seas_*.se1` | ~100 MB | **5401 BCE – 5399 CE**<br>Complete Swiss Ephemeris span for high-precision historical research. |
| **Numbered Asteroids** | `ast0/` through `ast21/`<br>• `seNNNNN.se1` (long)<br>• `seNNNNNs.se1` (short) | ~7.4 GB (Full)<br>~1.8 GB (Short) | Comprehensive numbered asteroid library.<br>• Short files (`s` suffix): **1500–2100 CE**.<br>• Long files: full orbital calculation span. |
| **Planetary Moons / COB** | `sat/sepm*.se1` | ~50 MB | **1900–2047 CE only**<br>Planetary satellites and Center of Body (COB) coordinates. |
| **Raw JPL Ephemerides** | `de431.eph` (2.6 GB)<br>`de406.eph` (190 MB) | Up to 2.6 GB | Uncompressed JPL Chebyschev coefficients (`SEFLG_JPLEPH`). |
| **EOP & Time Tables** | `seleapsec.txt`<br>`swe_deltat.txt`<br>`eop*.dat` | < 1 MB | Earth Orientation Parameters, historical leap seconds, and observational Delta-T data. |

---

## Recommended Directory Layout

Place all root ephemeris files, catalogs, and subdirectories under your designated ephemeris path:

```
ephe/
├── sepl_18.se1              # Planetary ephemeris (1800–2400)
├── semo_18.se1              # Lunar ephemeris (1800–2400)
├── seas_18.se1              # Main asteroids (1800–2400)
├── sefstars.txt             # Fixed star database (MUST remain in root)
├── seorbel.txt              # Orbital elements for fictitious bodies (MUST remain in root)
├── seleapsec.txt            # Leap seconds table
├── swe_deltat.txt           # Delta-T historical observations
├── de431.eph                # Optional: JPL raw integration file
├── sat/                     # Planetary satellites directory
│   ├── sepm01.se1
│   └── ...
└── ast0/                    # Numbered asteroids partitioned into folders
    ├── se00001s.se1         # Ceres (short span)
    ├── se00002s.se1         # Pallas
    └── ...
```

---

## Critical Operational Rules

### 1. Silent Moshier Fallback (Important)
If a `.se1` file is missing or corrupted, the calculation engine **does not return an error code (`ERR`)**. Instead, it returns `OK`, silently falls back to the Moshier analytical model, and logs an explanatory warning into the `serr` error buffer.

* **In Production & Tests:** Never rely solely on return codes to confirm ephemeris precision. Verify which file provided the data using:
  ```zig
  var file_info: [256]u8 = undefined;
  swe.get_current_file_data(0, &file_info, &swed);
  ```

### 2. Hard Failure on JPL Mode
Unlike `.se1` fallback behavior, if you pass `SEFLG_JPLEPH` and the specified JPL ephemeris file (`.eph`) is missing or invalid, the engine returns an immediate **hard error (`ERR`)**.

### 3. Date Span Boundaries & Special Body Windows
Calculations requested outside a body's valid time window will fail with return code `ERR_BEYOND` (`-3`):
- **Planetary Moons (`sat/`):** Strictly restricted to **1900–2047 CE**.
- **Chiron:** Valid between **675 CE and 4650 CE**.
- **Pholus:** Valid between **2958 BCE and 7309 CE**.
- **Apollo:** Ephemeris begins at **1870 CE**.

### 4. Root Directory Placement
`sefstars.txt` (fixed stars) and `seorbel.txt` (orbital elements for fictitious/hypothetical planets) **must** reside in the root of the ephemeris directory. They cannot be located inside subdirectories like `ast/` or `sat/`.

---

## Verification & Sanity Check

After downloading your files, run `swetest` to confirm file discovery and accuracy:

```sh
./zig-out/bin/swetest -b1.1.2000 -p0 -fPLBRS -g, -head
```

The output must match the reference coordinates printed in the repository `README.md`:

```text
date (dmy) 1.1.2000 greg.   0:00:00 TT    version 2.10.03
UT:  2451544.499261244     delta t: 63.828499 sec
Sun        , 279°51'30.4607,   0° 0' 0.8266,   0.983331864,   1° 1' 9.7787
Moon       , 217°17'36.1194,   5°13'53.0223,   0.002679809,  12° 6'10.7731
```
