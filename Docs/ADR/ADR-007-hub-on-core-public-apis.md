# ADR-007 — Hub Built Exclusively on Core Public APIs

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Mercantis Hub (`mercantis.app`) is the first-party ERP application built on Mercantis Core. There is a temptation when building a first-party app to take shortcuts: call internal Core methods, access the database directly, or add domain-specific hooks into Core's subsystems. These shortcuts create hidden coupling that makes it impossible to later separate Core from Hub.

## Decision

**Mercantis Hub is built exclusively on Core's public APIs.** Hub is treated as a third-party application. Specifically:

- Hub declares all its domain entities as `DocType` definitions in an `AppManifest`.
- Hub calls only `DocumentEngine`, `PermissionEngine`, `WorkflowEngine`, `ExpressionEvaluator`, and other public Core types.
- Hub does **not** import any internal Core module, access `MercantisDatabase` directly, or write SQL.
- Hub does **not** add any Swift code to Core's subsystem folders.
- Hub registers its manifest via `AppInstaller.install(_:)` — the same path any third-party app would use.

If Hub needs functionality that Core does not yet provide, the correct approach is to **extend Core's public API**, not to bypass it.

## Consequences

**Positive:**
- Proves that Core's public API is sufficient to build a full ERP; if Hub can do it, so can any third party.
- Core can be tested independently of Hub.
- The public/internal boundary in Core is enforced by the Swift module system.
- Hub can be distributed and updated independently of Core.

**Negative:**
- Core must be more deliberately designed: every Hub requirement must translate into a general-purpose Core capability.
- Feature development sometimes requires coordinated changes in both Core and Hub.

**Neutral:**
- Mercantis Hub (`mercantis.app`) is structured as an Xcode project that imports Core as a Swift package or embedded framework.

---

*See also: [ADR-001 — Core / Hub Split](ADR-001-core-hub-split.md), [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md)*
