# Architecture Decision Records

This directory contains the Architecture Decision Records (ADRs) for **Mercantis Core**.

ADRs document significant architectural decisions: the context that motivated them, the decision made, and the consequences. They are written once and not modified (superseding an ADR means writing a new one).

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-core-hub-split.md) | Core / Hub Split | Accepted |
| [ADR-002](ADR-002-sqlite-local-source-of-truth.md) | SQLite as Local Source of Truth | Accepted |
| [ADR-003](ADR-003-metadata-defined-doctypes.md) | Metadata-Defined DocTypes | Accepted |
| [ADR-004](ADR-004-declarative-app-plugin-model.md) | Declarative App / Plugin Model | Accepted |
| [ADR-005](ADR-005-sync-via-mutation-log.md) | Sync via Mutation Log | Accepted |
| [ADR-006](ADR-006-financial-inventory-conflict-policy.md) | Financial & Inventory Conflict Policy | Accepted |
| [ADR-007](ADR-007-hub-on-core-public-apis.md) | Hub Built Exclusively on Core Public APIs | Accepted |
| [ADR-008](ADR-008-no-executable-plugins-ios.md) | No Arbitrary Downloaded Executable Plugins on iOS | Accepted |

## How to Read an ADR

Each ADR follows this structure:
- **Title & Status** — What was decided and whether it is Accepted, Deprecated, or Superseded.
- **Context** — The situation or forces that required a decision.
- **Decision** — What was decided.
- **Consequences** — Positive, neutral, and negative outcomes of the decision.
