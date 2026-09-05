# Appendix B — Core Math Equations (KaTeX)

Notation: $t$ JD, $T=(t-2451545.0)/36525$ cy, angles deg unless rad marked. Implementation order is normative — `src/swephlib.zig`, `src/sweph.zig`; FP op order preserved for bit-parity (`parity.md`).

## Time
$$JD = julday(y,m,d,UT) \qquad TT = UT + \Delta T(t)/86400 \qquad T_{TT}=(TT-2451545.0)/36525$$

## Light-time (iterated 2×)
$$\tau = |\mathbf{r}_{body}(t-\tau)-\mathbf{r}_{obs}(t)| / c \qquad \mathbf{r}_{app} = \mathbf{r}(t-\tau)$$

## Aberration + deflection + bias
$$\mathbf{r}_{ab} = \mathbf{r} + \dot{\mathbf{r}}_{obs}\times\hat{\mathbf{r}}/c \quad (20") \qquad \theta_{defl} \approx 1.8"\cdot R_\odot/\rho$$
$$ \mathbf{r}_{J2000} = B_{IAU2006}\,\mathbf{r}_{ICRS} \quad (6.8\,mas) $$

## Precession (Vondrák 2011, ±200 ky) + nutation (IAU 2000B, 77 terms)
$$P(t) = P_{Vondr\acute{a}k}(T), \quad N(t) = N_{2000B}(\Omega_i, F_i, D_i)$$
$$\epsilon_{true} = \epsilon_{mean}(T) + \Delta\epsilon, \quad \lambda_{true} = \lambda_{mean} + \Delta\psi\cos\epsilon$$

## Houses (ARMC framework)
$$ARMC = GMST(t_{UT}) + lon_E \qquad MC = \arctan(\tan ARMC / \cos\epsilon)$$
Placidus/Koch: trisect semi-diurnal arcs in time, project to ecliptic. Equal: $cusp_k = ASC + 30°(k-1)$. Porphyry/Sripati: quadrant trisection. Gauquelin: $sector = 36$-fold diurnal rotation.

## Sidereal
$$\lambda_{sid} = \lambda_{trop} - ayanamsa(mode,t) \qquad aya(t) = aya_{t0} + \int_{t_0}^{t} (p_{Vondr\acute{a}k} - p_{fit})\,dt$$

## Eclipse / rise / heliacal
Contacts: $|\theta_{sep}| = R_\odot \pm R_{moon} \pm \rho_{site}$. Rise: $h_{app}(t) = h_{geo} + R(press,temp) - dip$. Heliacal (Schaefer): $V = m_{obj} - m_{lim}(arcus, Moon, extinction) < 0$ visible.

## House position
$$pos = 1 + k + (\lambda - cusp_k)/(cusp_{k+1}-cusp_k), \quad k \in [1,12]\;(36\,for\,G)$$
