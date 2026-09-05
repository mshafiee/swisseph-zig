# Appendix A — Bibliography & Glossary

> Part of the [swisseph-zig documentation](../index.md) · [Technical Reference Suite](../reference/)

---

## 1. Bibliography

The algorithms, reduction constants, and reference standards across `swisseph-zig` derive from the following literature:

### Planetary & Lunar Ephemerides
* **Standish, E. M., et al. (1995).** *JPL Planetary and Lunar Ephemerides, DE403/LE403*. JPL Interoffice Memorandum 314.10-127.  
  *Defines the DE406 compression scheme, planetary mass ratios, and accuracy budgets. Cited in [`10-constants.md`](10-constants.md) §4.*
* **Folkner, W. M., et al. (2014).** *The Planetary and Lunar Ephemeris DE430 and DE431*. Interplanetary Network Progress Report (IPN PR) 42-196.  
  *Long-span numerical integration (13,201 BCE to 17,191 CE) used as the primary dynamical backbone. Implements tidal deceleration constant `SE_TIDAL_DE431` ($-25.80''/\text{cy}^2$).*

### Precession, Nutation & Reference Frames
* **Capitaine, N., Wallace, P. T., & Chapront, J. (2003).** *Expressions for IAU 2000 precession quantities*. Astronomy & Astrophysics, 412(2), 567–586 (P03 model).  
  *High-order polynomials for the IAU 2006 precession equations. Cited in [`11-models.md`](11-models.md).*
* **Vondrák, J., Capitaine, N., & Wallace, P. T. (2011).** *New precession expressions for valid long time intervals*. Astronomy & Astrophysics, 534, A22.  
  *Long-term precession matrix combining P03 with numerical integrations valid over $\pm 200,000$ years.*
* **IERS (1996, 2003, 2010).** *IERS Conventions*. IERS Technical Notes (Nos. 21, 32, 36). Verlag des Bundesamts für Kartographie und Geodäsie.  
  *Frame bias matrix between ICRS and J2000.0 dynamical frames; IAU 2000A/2000B nutation series; accounts for the 53 mas offset relative to JPL Horizons.*

### Earth Rotation & Historical Time Scales ($\Delta T$)
* **Stephenson, F. R., Morrison, L. V., & Hohenkerk, C. Y. (2016).** *Measurement of the Earth's rotation: 720 BC to AD 2015*. Proceedings of the Royal Society A, 472(2196), 20160404.  
  *Default observational $\Delta T$ spline based on historical solar and lunar eclipse records. Cited in [`11-models.md`](11-models.md).*
* **Espenak, F., & Meeus, J. (2006).** *Five Millennium Canon of Solar Eclipses: -1999 to +3000*. NASA Technical Publication NASA/TP-2006-214141.  
  *Legacy polynomial approximations for $\Delta T$ computation.*

### Classical Astrometry & Visibility
* **Meeus, J. (1998).** *Astronomical Algorithms* (2nd ed.). Willmann-Bell.  
  *Fundamental analytical expressions for coordinate conversions, lunar phase angles, solar eclipses, and standard house trigonometric geometry.*
* **Urban, S. E., & Seidelmann, P. K. (Eds.). (2013).** *Explanatory Supplement to the Astronomical Almanac* (3rd ed.). University Science Books.  
  *Reference constants (`HELGRAVCONST`, `MOON_*`), rigorous topocentric reductions, and precision baselines achieving < 0.001" agreement.*
* **Schaefer, B. E. (1993, 2000).** *Astronomy and the Limits of Vision*; *Heliacal Phenomena and Lunar Crescent Visibility*. Vistas in Astronomy.  
  *Extinction, sky brightness, and physiological eye-response models implemented in `swehel.zig` (see [`54-functions-heliacal.md`](54-functions-heliacal.md)).*

### Historical Zodiacs & Specialized Frames
* **Huber, P. (1958).** *Über den Nullpunkt der babylonischen Ekliptik*. Centaurus, 5(3–4), 192–208.  
  *Foundational baseline for Babylonian sidereal ayanamsha systems.*
* **Britton, J. P. (2010).** *Studies in Babylonian Lunar Theory: Part III. The Babylonian Ecliptic and its Zero Point*. Archive for History of Exact Sciences, 64(6), 617–663.  
  *Refined epoch offsets for ancient Mesopotamian astronomical frames.*
* **Liu, J. C., Zhu, Z., & Zhang, H. (2010).** *The reconstructed Galactic coordinate system based on the Hipparcos and 2MASS catalogs*. Astronomy & Astrophysics, 526, A16.  
  *Standard true galactic pole coordinates (`GE-true`) used in coordinate rotations.*

---

## 2. Glossary

### Astrological Angles & Coordinate Frames
* **ARMC (Right Ascension of the Medium Coeli):** The right ascension of the local upper meridian, measured in degrees ($0^\circ \le \text{ARMC} < 360^\circ$) along the celestial equator. Equivalent to Local Sidereal Time (LST).
* **ASC / MC / Vertex / EquASC:**
  * **ASC (Ascendant):** The eastern intersection of the local horizon with the ecliptic.
  * **MC (Medium Coeli / Midheaven):** The upper intersection of the local meridian with the ecliptic.
  * **Vertex:** The western intersection of the prime vertical with the ecliptic.
  * **EquASC (Equatorial Ascendant):** The intersection of the eastern horizon with the celestial equator, projected onto the ecliptic along hour circles.
* **Ecliptic Planes:**
  * **Ecliptic of Date:** The instantaneous mean or true orbital plane of the Earth at the epoch of calculation.
  * **Ecliptic J2000.0:** The fixed mean ecliptic at the standard epoch J2000.0 (JD 2451545.0 TT).
  * **Ecliptic $t_0$:** A custom reference epoch used in secular perturbation models.
  * **SSY (Solar System Invariable Plane):** The plane perpendicular to the total angular momentum vector of the Solar System.

### Dynamical Reference Points
* **Barycenter:** The center of mass of the Solar System (SSB) or of an individual planet-satellite system.
* **COB (Center of Body):** The physical center of the target sphere/ellipsoid, disregarding barycentric orbital wobbles caused by large moons (e.g., the Earth-Moon barycenter vs. the geocenter).
* **Photocenter:** The apparent center of reflected or emitted light from a celestial body's illuminated crescent or disk, differing from the COB based on phase angle.

### Time Standards & Calendars
* **ET (Ephemeris Time):** The legacy gravitational time standard (replaced by TT).
* **TT (Terrestrial Time):** The uniform dynamical time scale used for planetary ephemerides, related to atomic time by $\text{TT} = \text{TAI} + 32.184\text{ s}$.
* **UT1 (Universal Time):** The astronomical time scale based on the Earth's physical rotation angle, affected by secular tidal deceleration and core-mantle coupling.
* **UTC (Coordinated Universal Time):** Civil atomic time maintained within $\pm 0.9\text{ s}$ of UT1 through the insertion of discrete leap seconds.
* **$\Delta T$ (Delta-T):** The difference between uniform dynamical time and irregular Earth rotation: $\Delta T = \text{TT} - \text{UT1}$.
* **JD (Julian Day):** Continuous decimal count of days elapsed since Greenwich mean noon on January 1, 4713 BCE (Julian proleptic calendar).
* **GMST / LMST:** Greenwich Mean Sidereal Time and Local Mean Sidereal Time.

### Sidereal Astrometry & Eclipses
* **Ayanamsha:** The angular arc between the tropical zodiac (vernal equinox) and a sidereal zodiac ($A = \lambda_{\text{tropical}} - \lambda_{\text{sidereal}}$).
* **Nakshatra:** A division of the sidereal zodiac into 27 (or 28) equal lunar mansions of $13^\circ 20'$ each.
* **Saros Cycle:** An eclipse recurrence period of approximately 6,585.3 days (18 years, 11 days, 8 hours).
* **Gamma ($\gamma$):** The minimum distance from the axis of the Moon's shadow cone to the center of the Earth at eclipse maximum, expressed in units of Earth's equatorial radius.
* **Arcus Visionis:** The angular altitude difference between the Sun below the horizon and a star or planet on the horizon at the exact threshold of visibility (heliacal rising or setting).

### Architecture & Implementation Internals
* **Context Bundles (`Swed`, `DeltatCtx`, `AstroModels`, `HouseCtx`):** Explicit Zig structs containing scratchpad memory, file descriptors, caches, and astronomical theory switches. Thread-safe by isolation (one bundle per thread).
* **`SweState`:** The thread-local composite wrapper that bundles all context instances internally to drive the 107 C ABI compatibility functions without global variables.
* **FMA (Fused Multiply-Add) Contraction:** A floating-point instruction that evaluates $a \times b + c$ with a single rounding step. Disallowed in parity runs (`-ffp-contract=off`) to guarantee identical, portable IEEE 754-2008 results across x86, ARM, and WebAssembly targets.
* **`%.17g` Round-Trip Comparison:** The 17-digit decimal serialization format mathematically guaranteed to round-trip back into identical 64-bit IEEE 754 floating-point values, serving as the benchmark standard for differential testing against the C oracle.
