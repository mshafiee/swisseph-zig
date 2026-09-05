# Licensing

`swisseph-zig` is distributed under a dual-licensing framework reflecting the upstream Swiss Ephemeris model by Astrodienst AG, alongside a specific usage policy for hosted and network-accessible services.

---

## License Matrix

| Use Case | Permitted License | Source Code Disclosure | API Grant Needed? |
|---|---|---|---|
| **Open Source (Local CLI, Desktop, Offline)** | GNU AGPLv3 | **Required** (Copyleft) | No |
| **Hosted / SaaS / Network Service** | AGPLv3 or Commercial + `API-LICENSE` | Depends on track | **Yes (Prior written grant)** |
| **Proprietary / Closed-Source App** | Commercial License | **Not required** | Covered under commercial agreement |

---

## 1. Open Source (GNU AGPLv3)

You may freely use, modify, and distribute this software under the terms of the **GNU Affero General Public License v3.0** ([LICENSE](LICENSE)).

- **Reciprocity:** Any derivative work or application bundling this library must also be licensed under the AGPLv3 (or compatible copyleft license) and provide complete corresponding source code.
- **Scope:** Applies out of the box to local binaries, offline tools, desktop clients, and embedded systems with no network exposure.

---

## 2. Hosted Services & Network API Policy

> **Important:** Network deployment requires a separate authorization grant prior to launch.

Any deployment that exposes this library over a network requires **prior written authorization** from Mohammad Shafiee ([muhammad.shafiee@gmail.com](mailto:muhammad.shafiee@gmail.com)), formalized via an `API-LICENSE` agreement. 

This requirement applies **regardless of whether your service is open-source or AGPL-compliant**.

### What Requires an API Grant?
- **Requires a Grant:**
  - Public or private HTTP/REST, gRPC, GraphQL, or WebSocket endpoints (e.g., a `/positions` or `/chart` route).
  - SaaS platforms, multi-tenant web applications, or cloud microservices.
  - Serverless workers, Lambda functions, or backend APIs embedding the library.
- **Allowed Without an API Grant:**
  - Local terminal utilities (CLI).
  - Native desktop applications (macOS, Linux, Windows).
  - Embedded systems and offline mobile applications with no remote calculation server.

To request an `API-LICENSE`, email [muhammad.shafiee@gmail.com](mailto:muhammad.shafiee@gmail.com) with details regarding your service architecture and launch timeline.

---

## 3. Commercial Licensing (Closed Source)

If you intend to integrate `swisseph-zig` into proprietary, closed-source software or cannot comply with the copyleft provisions of the AGPLv3, commercial licenses are available.

- **Inquiries & Purchase:** Mohammad Shafiee ([muhammad.shafiee@gmail.com](mailto:muhammad.shafiee@gmail.com))
- **Upstream Rights Notice:** Commercial licensing of this Zig port is subject to Astrodienst AG's upstream intellectual property. Commercial licensees must independently ensure compliance with, or obtain the corresponding commercial rights from, [Astrodienst AG](https://www.astro.com/swisseph/) for the underlying Swiss Ephemeris C engine.

---

## 4. Copyright & Attribution

- **Swiss Ephemeris C Library:** Copyright © 1997–2021 [Astrodienst AG](https://www.astro.com/swisseph/).
- **Moshier Astronomical Engine:** Public domain (Stephen L. Moshier).
- **swisseph-zig:** Mohammad Shafiee.

See [NOTICE.md](../NOTICE.md) for complete historical attributions and third-party notices.
