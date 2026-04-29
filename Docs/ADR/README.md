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
| [ADR-009](ADR-009-single-documents-table.md) | Single Documents Table with JSON Payload | Accepted |
| [ADR-010](ADR-010-pure-client-side-architecture.md) | Pure Client-Side Architecture (No Server Component) | Accepted |
| [ADR-011](ADR-011-multi-level-permission-model.md) | Multi-Level Permission Evaluation Model | Accepted |
| [ADR-012](ADR-012-eventbus-internal-pubsub.md) | EventBus for Internal Pub/Sub | Superseded by ADR-020 |
| [ADR-013](ADR-013-submit-cancel-amend-lifecycle.md) | Submit / Cancel / Amend Document Lifecycle | Accepted |
| [ADR-014](ADR-014-document-naming-strategy.md) | Document Naming Strategy | Accepted |
| [ADR-015](ADR-015-declarative-hooks-app-extension.md) | Declarative Extension Points for App Extension | Accepted |
| [ADR-016](ADR-016-metadata-driven-generic-ui.md) | Metadata-Driven Generic UI | Accepted |
| [ADR-017](ADR-017-expression-engine-scope-sandboxing.md) | Expression Engine Scope and Sandboxing | Accepted |
| [ADR-018](ADR-018-cloud-adapter-protocol-boundary.md) | Cloud Adapter as Protocol Boundary | Accepted |
| [ADR-019](ADR-019-automation-execution-model.md) | Automation Execution Model | Accepted |
| [ADR-020](ADR-020-typed-event-system.md) | Typed Event System | Accepted |
| [ADR-021](ADR-021-metadata-composition-resolved-meta.md) | Metadata Composition and ResolvedMeta | Accepted |
| [ADR-022](ADR-022-document-validation-pipeline.md) | Document Validation Pipeline | Accepted |
| [ADR-023](ADR-023-optimistic-concurrency-modified-timestamp.md) | Optimistic Concurrency via Modified Timestamp | Accepted |
| [ADR-024](ADR-024-document-versioning-diff-tracking.md) | Document Versioning and Field-Level Diff Tracking | Accepted |
| [ADR-025](ADR-025-automation-action-registry.md) | Automation Action Registry | Accepted |
| [ADR-026](ADR-026-three-layer-extensibility-model.md) | Three-Layer Extensibility Model | Accepted |
| [ADR-027](ADR-027-doctype-creation-strategy.md) | DocType Creation Tooling — Phased Strategy | Accepted |
| [ADR-028](ADR-028-sync-queue-pruning.md) | Sync Queue Pruning Strategy | Accepted |
| [ADR-029](ADR-029-cross-document-lookup.md) | Cross-Document `lookup()` in the Expression Engine | Accepted |
| [ADR-030](ADR-030-link-field-search-picker.md) | Link Field Search Picker | Accepted |
| [ADR-031](ADR-031-child-table-inline-editor.md) | Child-Table Inline Editor | Accepted |

## How to Read an ADR

Each ADR follows this structure:
- **Title & Status** — What was decided and whether it is Accepted, Deprecated, or Superseded.
- **Context** — The situation or forces that required a decision.
- **Decision** — What was decided.
- **Consequences** — Positive, neutral, and negative outcomes of the decision.
