# ADR-001 — Core / Hub Split

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Early prototypes of Mercantis mixed domain-specific logic (sales invoices, stock ledgers, HR records) directly into the application layer. This created tight coupling that made it impossible to reuse the infrastructure for different business domains or to maintain the core platform independently of any particular vertical.

Two concerns needed to be separated:

1. **Platform infrastructure** — documents, metadata, sync, permissions, workflows, expressions — things every business application needs.
2. **Domain logic** — the specific DocTypes, workflows, reports, and rules that define an ERP or any other application.

## Decision

We will maintain two separate repositories with a strict dependency direction:

- **`mercantis.core.app`** — The platform layer. Contains the infrastructure subsystems (Storage, DocumentEngine, MetadataRegistry, SyncEngine, PermissionsEngine, WorkflowEngine, ExpressionEngine, AppRuntime, Notifications). It has **no knowledge** of any specific business domain.
- **`mercantis.app`** (Mercantis Hub) — The first-party ERP application. Declares its domain entities entirely in app manifests (DocTypes, workflows, permissions, reports) and calls only Core's public APIs. It contains **no infrastructure code**.

## Consequences

**Positive:**
- Core can be developed, tested, and released independently of any domain application.
- Third parties can build their own applications on Core using the same plugin model that Hub uses.
- Core's architecture is easier to reason about because it is domain-agnostic.
- Hub can be updated or replaced without touching Core.

**Negative:**
- Two repositories to maintain and keep in sync on public API contracts.
- Hub must wait for Core to stabilise its public APIs before development can fully proceed.

**Neutral:**
- Core is distributed as a Swift package (or embedded framework); Hub declares it as a dependency.

---

*See also: [ADR-007 — Hub Built Exclusively on Core Public APIs](ADR-007-hub-on-core-public-apis.md)*
