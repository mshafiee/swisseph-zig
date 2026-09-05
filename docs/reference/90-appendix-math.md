# Appendix B — Core Mathematical Formulations

> Part of the [swisseph-zig documentation](../index.md) · [Methodology Guide](../guide/03-parity.md)

This appendix outlines the reduction pipeline implemented in `src/swephlib.zig`, `src/sweph.zig`, `src/swehouse.zig`, and `src/swecl.zig`. 

> ⚠️ **Parity Notice:** Floating-point evaluation order, trigonometric expansions, and polynomial Horner evaluations in this document reflect the **normative execution sequence**. Deviations from this sequence alter intermediate rounding and break bit-for-bit parity (`==`) against the C reference oracle.

---

## 0. Fundamental Notation

| Symbol | Definition |
|---|---|
| $t$ | Julian Day epoch (Universal Time or Terrestrial Time) |
| $T$ | Julian centuries of 36,525 ephemeris days elapsed since J2000.0: $T = \frac{t - 2451545.0}{36525}$ |
| $c$ | Speed of light in vacuum ($299,792.458 \text{ km/s} \approx 173.14463 \text{ AU/day}$) |
| $\mathbf{r}, \dot{\mathbf{r}}$ | Position and velocity vectors in rectangular heliocentric/geocentric coordinates |
| $\hat{\mathbf{r}}$ | Unit direction vector: $\hat{\mathbf{r}} = \frac{\mathbf{r}}{\|\mathbf{r}\|}$ |
| $\epsilon, \Delta\epsilon$ | Mean obliquity of the ecliptic and nutation in obliquity |
| $\Delta\psi$ | Nutation in ecliptic longitude |

*Unless explicitly indicated in radians ($\text{rad}$), all angular quantities are expressed in degrees.*

---

## 1. Time Systems & Epochs

*Implementation: `src/swedate.zig`, `src/deltat.zig`*

Calendar dates $(y, m, d, \text{UT})$ convert to Julian Day ($\text{JD}$) using standard proleptic Gregorian/Julian algorithms. Terrestrial Time ($\text{TT}$) is derived from Universal Time ($\text{UT1}$) via the observational $\Delta T$ spline:

$$\text{TT} = \text{UT} + \frac{\Delta T(t)}{86400}$$

$$T_{\text{TT}} = \frac{\text{TT} - 2451545.0}{36525}$$

$$\text{GMST}(t_{\text{UT}}) = \theta_0 + \theta_1 T_{\text{UT}} + \theta_2 T_{\text{UT}}^2 + \theta_3 T_{\text{UT}}^3$$

---

## 2. Light-Time Iteration

*Implementation: `src/sweph.zig`*

Planetary and lunar positions are corrected for light-time travel delay $\tau$ using a two-pass Picard iteration:

$$\tau_0 = 0$$

$$\tau_{k+1} = \frac{\|\mathbf{r}_{\text{body}}(t - \tau_k) - \mathbf{r}_{\text{obs}}(t)\|}{c} \quad (k \in \{0, 1\})$$

$$\mathbf{r}_{\text{app}} = \mathbf{r}_{\text{body}}(t - \tau_2) - \mathbf{r}_{\text{obs}}(t)$$

---

## 3. Astrometric Reductions

*Implementation: `src/swephlib.zig`*

### Frame Bias (ICRS to J2000.0 Dynamical)
The International Celestial Reference Frame (ICRS) origin is rotated into the dynamical mean equator and equinox of J2000.0 via the constant IAU 2006 bias matrix $\mathbf{B}$ ($\sim 6.8\text{ mas}$ offset):

$$\mathbf{r}_{\text{J2000}} = \mathbf{B}_{\text{IAU2006}} \, \mathbf{r}_{\text{ICRS}}$$

### Relativistic Gravitational Deflection
Photons grazing a massive body (primarily the Sun) undergo general relativistic space-time curvature deflection:

$$\Delta\theta_{\text{defl}} \approx \frac{4 G M_\odot}{c^2 \rho} = \frac{2 r_s}{\rho} \approx 1.751'' \left(\frac{R_\odot}{\rho}\right)$$

where $\rho$ is the impact parameter (closest approach distance to the center of the deflecting body) and $r_s$ is the Schwarzschild radius.

### Stellar Aberration
Annual aberration caused by the Earth's orbital velocity $\mathbf{v}_{\text{obs}} = \dot{\mathbf{r}}_{\text{obs}}$ shifts apparent positions by up to $\sim 20.496''$:

$$\hat{\mathbf{r}}_{\text{ab}} = \frac{\hat{\mathbf{r}} + \frac{\mathbf{v}_{\text{obs}}}{c} + \left(1 - \sqrt{1 - \frac{v^2}{c^2}}\right) \frac{(\hat{\mathbf{r}} \cdot \mathbf{v}_{\text{obs}}) \mathbf{v}_{\text{obs}}}{v^2}}{1 + \frac{\hat{\mathbf{r}} \cdot \mathbf{v}_{\text{obs}}}{c}}$$

---

## 4. Precession & Nutation

*Implementation: `src/swephlib.zig`*

### Long-Term Precession (Vondrák et al., 2011)
Valid across $\pm 200,000$ years, the precession matrix $\mathbf{P}(T)$ is constructed from high-order polynomials combined with secular Fourier terms:

$$\mathbf{r}(t) = \mathbf{P}_{\text{Vondr\'ak}}(T_{\text{TT}}) \, \mathbf{r}_{\text{J2000}}$$

### Nutation (IAU 2000B Series)
Evaluated using the 77-term truncated series based on the fundamental Delaunay arguments of the Sun and Moon ($\Omega_i, F_i, D_i, l_i, l'_i$):

$$\Delta\psi = \sum_{i=1}^{77} (A_i + A'_i T) \sin(\boldsymbol{\alpha}_i \cdot \mathbf{F}), \qquad \Delta\epsilon = \sum_{i=1}^{77} (B_i + B'_i T) \cos(\boldsymbol{\alpha}_i \cdot \mathbf{F})$$

### True Equator and Obliquity of Date
$$\epsilon_{\text{mean}} = 23^\circ 26' 21.406'' - 46.836769'' T - 0.0001831'' T^2 + \dots$$

$$\epsilon_{\text{true}} = \epsilon_{\text{mean}} + \Delta\epsilon$$

$$\lambda_{\text{true}} = \lambda_{\text{mean}} + \Delta\psi \cos\epsilon_{\text{true}}$$

---

## 5. Astrological Houses & ARMC

*Implementation: `src/swehouse.zig`*

All house systems are anchored to the Right Ascension of the Medium Coeli ($\text{ARMC}$):

$$\text{ARMC} = \left(\text{GMST}(t_{\text{UT}}) + \lambda_{\text{geo}}\right) \pmod{360^\circ}$$

$$\text{MC} = \arctan\left(\frac{\tan \text{ARMC}}{\cos \epsilon}\right)$$

$$\text{ASC} = \arctan\left(\frac{-\cos \text{ARMC}}{\sin \text{ARMC} \cos \epsilon + \tan \phi_{\text{geo}} \sin \epsilon}\right)$$

### Division Systems
* **Equal System:** Fixed $30^\circ$ increments along the ecliptic:
  $$\text{cusp}_k = (\text{ASC} + 30^\circ (k - 1)) \pmod{360^\circ} \quad (k \in \{1, \dots, 12\})$$
* **Placidus / Koch:** Trisect diurnal and nocturnal semi-arcs in time, iteratively solving for the intersection of the horizon plane with each fractional hour circle on the ecliptic.
* **Porphyry:** Direct trisection of quadrant arcs along the ecliptic:
  $$\text{cusp}_{1..3} = \text{ASC} + \frac{k}{3} (\text{IC} - \text{ASC}), \quad \text{cusp}_{4..6} = \text{IC} + \frac{k}{3} (\text{DESC} - \text{IC})$$
* **Gauquelin Sectors:** 36 diurnal sectors dividing rotation relative to the diurnal circle.

---

## 6. Sidereal Zodiac & Ayanamsha

*Implementation: `src/swephlib.zig`*

Sidereal longitudes are obtained by subtracting the ayanamsha angle $A(t)$ from the tropical ecliptic longitude:

$$\lambda_{\text{sid}} = (\lambda_{\text{trop}} - A(\text{mode}, t)) \pmod{360^\circ}$$

The ayanamsha at epoch $t$ is calculated from the initial offset $A_0$ at reference epoch $t_0$, integrated against the rate of precession:

$$A(t) = A_{t_0} + \int_{t_0}^t \left(\frac{dp_{\text{Vondr\'ak}}}{dt} - \frac{dp_{\text{fit}}}{dt}\right) dt$$

---

## 7. Eclipses, Horizon Crossings & Visibility

*Implementation: `src/swecl.zig`, `src/swehel.zig`*

### Solar / Lunar Eclipse Contacts
Contact instants occur when the geocentric angular separation $\theta_{\text{sep}}$ between the bodies matches the sum or difference of their apparent topocentric angular semidiameters:

$$\theta_{\text{sep}} = \arccos(\hat{\mathbf{r}}_{\text{body1}} \cdot \hat{\mathbf{r}}_{\text{body2}}) = R_1 \pm R_2 \pm \rho_{\text{parallax}}$$

### Atmospheric Refraction & Apparent Altitude
Geocentric altitude $h_{\text{geo}}$ is corrected for geographic horizon dip and local atmospheric refraction $R(P, T)$ where $P$ is pressure in $\text{hPa}$ and $T$ is temperature in $^\circ\text{C}$:

$$h_{\text{app}} = h_{\text{geo}} + R(P, T) - d_{\text{dip}}$$

$$R(P, T) \approx \frac{1.02'}{\tan\left(h + \frac{10.3'}{h + 5.11'}\right)} \cdot \left(\frac{P}{1010}\right) \cdot \left(\frac{283}{273 + T}\right)$$

### Heliacal Visibility (Schaefer Criterion)
A celestial body becomes visible at twilight when its apparent magnitude $m_{\text{obj}}$ drops below the limiting visual threshold magnitude $m_{\text{lim}}$ of the human eye:

$$V = m_{\text{obj}} - m_{\text{lim}}(\text{arcus visionis}, m_{\text{moon}}, k_{\text{extinction}}) < 0 \implies \text{Visible}$$

---

## 8. Fractional House Position

*Implementation: `src/swehouse.zig`*

For any ecliptic longitude $\lambda$ located within house cusp interval $[\text{cusp}_k, \text{cusp}_{k+1})$:

$$\Delta\text{arc} = (\text{cusp}_{k+1} - \text{cusp}_k) \pmod{360^\circ}$$

$$\delta = (\lambda - \text{cusp}_k) \pmod{360^\circ}$$

$$\text{pos}(\lambda) = k + \frac{\delta}{\Delta\text{arc}} \quad (k \in \{1, \dots, 12\} \text{ or } \{1, \dots, 36\} \text{ for Gauquelin})$$

*The returned value is a continuous real number in the range $[1.0, 13.0)$ where $1.5$ corresponds to the exact midpoint of House 1.*
