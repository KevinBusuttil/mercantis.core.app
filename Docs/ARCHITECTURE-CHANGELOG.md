# Mercantis Core — Architecture Changelog

## Revision: 2026-04-14

This revision reflects an architecture assessment comparing Mercantis Core against Frappe v16. The goal was to identify areas where the architecture documentation needed to be made more explicit and to ensure the ADR set accurately reflects the intended foundation. Mercantis's original direction (offline-first, pure client-side, declarative-only plugins, metadata-driven) is preserved.

---

## Updated Files

### `ARCHITECTURE.md`

| Section | Summary of Change |
|---|---|
| §3 Architecture Diagram | Added MetaComposer/ResolvedMeta, ValidationPipeline, PermissionEvaluator Chain, NamingStrategy Registry, Typed EventBus, AutomationActionRegistry, VersioningDiffTracker. |
| §4.1 Metadata Engine | Added MetaComposer and ResolvedMeta description. Tied CustomizationEngine write path to MetaComposer read path. |
| §4.2 Document Engine | Added ValidationPipeline (7 ordered stages), optimistic concurrency via `modifiedAt`, and versioning/diff tracking (DocumentVersion). |
| §4.4 Permissions Engine | Redesigned as an evaluator chain with `PermissionEvaluator` protocol and `PermissionDecision` enum. |
| §4.7 Expression Engine | Noted AST-based parsing (not string-walking). Added benefits: static field reference analysis, constant folding, precise error positions. |
| §4.8 Notifications & Events | Replaced stringly-typed EventBus description with typed event system. Added `SubscriptionToken` lifecycle management. |
| §4.10 Document Lifecycle | Added `allowOnSubmit` immutability enforcement, cancel link integrity check, and explicit `amendedFrom` amend description. |
| §4.11 Naming System | Redesigned as a strategy registry with `NamingStrategy` protocol and concrete implementations. |
| §4.12 Hooks / Extension Points | Renamed to "Extension Points". Rewrote to describe the three-layer extensibility model. Explicitly rejected Frappe-style hooks with rationale. Removed `override_doctype_class` and `override_whitelisted_methods`. |
| §4.13 Background Tasks | Added AutomationActionRegistry description with `AutomationActionHandler` protocol. |
| §4.15 Public API Surface | Added MetaComposer, AutomationActionRegistry, and updated EventEmitter references. |
| §4.21 Realtime Updates | Updated to reference typed events instead of string EventBus. |
| §7 Directory Structure | Added new files: `DocumentVersion.swift`, `ValidationPipeline.swift`, `MetaComposer.swift`, `ResolvedMeta.swift`, `NamingStrategy.swift`, `EventEmitter.swift`, `PermissionContext.swift`, `PermissionEvaluators.swift`, `AutomationActionHandler.swift`, `AutomationActionRegistry.swift`, `BuiltInActionHandlers.swift`. Replaced `EventBus.swift` with `EventEmitter.swift`. |
| §8 ADR Table | Added ADR-020 through ADR-026. Marked ADR-012 as superseded. |

---

## Revised ADRs

| ADR | Summary of Revision |
|---|---|
| ADR-003 | Added ResolvedMeta / MetaComposer concept: base definition + custom fields + property overrides → composed metadata used by all runtime consumers. |
| ADR-011 | Replaced flat method-based description with evaluator chain pattern (`PermissionEvaluator` protocol, `PermissionDecision` enum, five named evaluators). |
| ADR-012 | Marked **Superseded by ADR-020**. Retained for historical context. |
| ADR-013 | Added `allowOnSubmit` immutability enforcement, cancel link integrity check description, explicit `amendedFrom` amend mechanics. |
| ADR-014 | Replaced strategy enumeration with `NamingStrategy` protocol registry. Named concrete implementations as `UUIDv7Strategy`, `NamingSeriesStrategy`, `FieldDerivedStrategy`, `PromptStrategy`, `FormatStrategy`. |
| ADR-015 | Renamed from "Declarative Hooks" to "Declarative Extension Points". Removed `override_doctype_class` and `override_whitelisted_methods` (require executable code). Added three-layer extensibility model description. Documented explicit rejection of Frappe-style hooks with rationale. |
| ADR-017 | Added AST-based parsing note. Noted `lookup()` cross-document function as a planned (undecided) extension. |
| ADR-019 | Added `AutomationActionRegistry` pattern with `AutomationActionHandler` protocol. Replaced implicit string-switch dispatch description. |

---

## New ADRs

| ADR | Title | Summary |
|---|---|---|
| ADR-020 | Typed Event System | Replaces stringly-typed EventBus with concrete Swift event types, type-safe subscriptions, and `SubscriptionToken` lifecycle management. Explicitly not Frappe-style hooks. |
| ADR-021 | Metadata Composition and ResolvedMeta | `MetaComposer` merges base DocType + custom fields + property setters into a cached `ResolvedMeta` used by all runtime consumers. |
| ADR-022 | Document Validation Pipeline | Ordered, staged validation on every save via `ValidationStage` protocol. Seven stages: type coercion, required fields, link validation, unique constraints, expression rules, workflow guards, permissions. |
| ADR-023 | Optimistic Concurrency via Modified Timestamp | Same-device concurrency protection via `modifiedAt` comparison at save time. Separate from cross-device sync conflicts (ADR-006). |
| ADR-024 | Document Versioning and Field-Level Diff Tracking | Field-level diffs computed on every save, stored as append-only `DocumentVersion` records. Complete change history for audit-sensitive documents. |
| ADR-025 | Automation Action Registry | Registry-based action dispatch using `AutomationActionHandler` protocol. Replaces implicit string-switch. Built-in types: set_value, set_status, send_notification, validate, assign. |
| ADR-026 | Three-Layer Extensibility Model | Formalises Layer 1 (declarative manifests), Layer 2 (typed event subscriptions), Layer 3 (compiled-in extension protocols). Explicitly rejects Frappe-style hooks with rationale table. |

---

## Superseded ADRs

| ADR | Superseded By | Reason |
|---|---|---|
| ADR-012 — EventBus for Internal Pub/Sub | ADR-020 — Typed Event System | Stringly-typed events replaced by concrete Swift event types with compile-time safety and lifecycle management. |

---

## Unresolved Follow-Up ADR Candidates

The following topics were identified during this assessment but are not yet decided. They are candidates for future ADRs:

| Topic | Description |
|---|---|
| Sharing / delegation permission mechanism | A mechanism for users to share document access with other users or roles outside the standard permission model. |
| Dynamic Link field type semantics | How `dynamic_link` fields (where the DocType is specified by another field) are resolved and validated. |
| Backlink query support | How to efficiently query "all documents that link to this document" without full-table scans. |
| Sync queue pruning strategy | When and how acknowledged sync queue entries are pruned to prevent unbounded growth. |
| FieldValue type system deepening | Explicit `date`, `dateTime`, `data`, and `array` cases in `FieldValue`; type narrowing rules. |
| Cross-document lookup in ExpressionEngine | A `lookup(docType, name, field)` function for reading a field from another document in expressions. |
| Server-side validation via CloudAdapter | Whether the CloudAdapter protocol should include a server-side validation round-trip for documents before final commit. |
