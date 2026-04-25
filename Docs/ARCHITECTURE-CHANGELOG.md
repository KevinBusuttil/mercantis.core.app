# Mercantis Core — Architecture Changelog

## Revision: 2026-04-25 (MercantisCore library product shipped — P2.6)

This revision records the productization of Core as a reusable Swift package library, completing the precondition for ADR-007's "Hub imports Core as a Swift package or embedded framework" wiring. Hub — or any third-party app — can now consume Core via a standard `.package(url: ...)` dependency.

### Code updated

| File | Summary |
|---|---|
| `Package.swift` | Added a `.library(name: "MercantisCore", targets: ["MercantisCore"])` product. New `MercantisCore` target points at `mercantis core/` with `exclude:` for the four UI / app-shell entries (`Assets.xcassets`, `mercantis_coreApp.swift`, `UIShell`, `Views`). Added GRDB (`https://github.com/groue/GRDB.swift`, `from: "6.0.0"`) as a SwiftPM dependency, threaded through the library target only. The CLI executable continues to use its `MercantisCLI/SQLite3` system-library path; consolidating the two persistence stacks remains P2.3. |

### Boundary established

- Library compile set: `AppRuntime/`, `Automation/`, `Customization/`, `DocumentEngine/`, `ExpressionEngine/`, `Metadata/`, `Naming/`, `Notifications/`, `Permissions/`, `Reporting/`, `Scheduling/`, `Storage/`, `SyncEngine/`, `Workflows/` — 51 source files.
- Excluded from the library: SwiftUI views in `UIShell/` and `Views/`, the `@main` `mercantis_coreApp.swift` entry, and `Assets.xcassets`. These continue to compile inside the Xcode app target only.
- No engine source file imports SwiftUI / AppKit / UIKit. The boundary is one-way (UI → engine).
- Access-modifier audit: every top-level engine type is `public` with `public init`s and `public func`s. Manifest / DocType value types expose `public let` / `public var` members. Two helpers in `Automation/BuiltInActionHandlers.swift` (`FieldValueDecoder`, `ParameterInterpolator`) are deliberately internal; nothing else needed visibility changes.

### Doc updates

| File | Summary |
|---|---|
| `Docs/ENHANCEMENT-PROPOSAL.md` P2.6 | Marked done. Detailed product/target shape, exclude list, GRDB wiring, audit summary, and the three known follow-ups (Xcode app target migration, SwiftPM test target wiring, P2.3 CLI consolidation). Sequencing footer updated. |

### Known follow-ups

- The Xcode app target (`mercantis core`) still compiles the engine source directly via project membership. Migrating it to consume the SwiftPM `MercantisCore` product instead is a `.pbxproj` change best made in Xcode itself; the library declaration alone is sufficient for Hub to consume Core today.
- The XCTest files under `mercantis coreTests/` use `@testable import mercantis_core` (the Xcode app module name); mirroring them as a SwiftPM `testTarget` against `MercantisCore` would require switching the import and is left as follow-up to the Xcode test-target wire-up tracked in P0.1.
- The CLI consolidating onto `MercantisCore` instead of its own raw-SQLite path remains P2.3.

---

## Revision: 2026-04-25 (Row-level permission expressions shipped — P1.7)

This revision replaces the equality-only `rowFilter` argument on `PermissionEngine.canAccessRow` with a sandboxed boolean `rowExpression` evaluated by `ExpressionEvaluator` (ADR-017) over the document's fields plus a `user.*` namespace. P1.6's typed `.date` / `.dateTime` cases land here as the comparison surface for deadline-style row predicates. No callers of the old signature existed in the codebase, so the swap was direct.

### Code updated

| File | Summary |
|---|---|
| `mercantis core/Permissions/PermissionEngine.swift` | `canAccessRow` rewritten. New signature: `canAccessRow(document:userRoles:rowExpression:userId:userAttributes:expressionEvaluator:)`. Builds the evaluator context from `document.fields` plus a `user.*` namespace (`user.id` from `userId`, `user.roles` as a sorted `.array([.string])`, plus any `userAttributes` — caller-supplied keys without a `user.` prefix are namespaced automatically). Caller entries override the standard `user.*` keys; any `user.*` key overrides a document field of the same name. `nil` / empty / whitespace-only expression grants access; an evaluator throw fails closed. |

### Code added

| File | Summary |
|---|---|
| `mercantis coreTests/PermissionEngineTests.swift` | 20 tests: nil / empty / whitespace short-circuits, equality + compound + numeric + typed-date comparisons over document fields, `owner == user.id` matching, empty-`userId` fallback, `userAttributes` namespacing for prefixed and unprefixed keys, override semantics for both `userAttributes` ⇒ standard and `user.*` ⇒ document-field, three fail-closed paths (undefined identifier returning `.null`, malformed expression with missing RHS, typeMismatch throw via unary-minus on a string). Sanity coverage for `canPerform` (matching / non-matching role) and `canAccessField` (no permission block / restricted block). |

### Doc updates

| File | Summary |
|---|---|
| `ARCHITECTURE.md` §4.4 Permissions Engine | Updated the `canAccessRow` signature in the snippet and rewrote its bullet to describe expression evaluation, the `user.*` namespace, override semantics, and fail-closed behaviour. |
| `ARCHITECTURE.md` §4.15 Public API Surface | Refreshed the `PermissionEngine` line to list the new `canAccessRow` parameter set. |
| `Docs/ADR/ADR-011-multi-level-permission-model.md` | Status bumped (revised 2026-04-25). Snippet updated. Row-level scope rewritten to describe expression evaluation, the `user.*` namespace, override rules, and fail-closed semantics. Out-of-scope list now records "no source-of-rowExpression wiring" instead of "no expression support". Negative consequence added covering fail-closed-on-typo. |
| `Docs/IMPLEMENTATION-STATUS.md` §2.4 | Updated `canAccessRow` signature; added "Shipped (P1.7 — 2026-04-25)" row; removed the "Partial vs. original intent" entry; note added that `DocumentEngine.list` does not yet auto-apply row expressions. |
| `Docs/ENHANCEMENT-PROPOSAL.md` P1.7 | Marked done. Detailed scope, signature, evaluator contract, coverage, and known follow-ups added. P0.5 cross-reference updated. Sequencing table extended with row 7. |
| `mercantis coreTests/README.md` | Added a row for `PermissionEngineTests.swift`. Removed the "PermissionEngine — testing both shapes first is wasted effort" entry from the not-covered list. |

### Known follow-ups

- The engine accepts and evaluates an expression but does not decide *which* expression applies for a given (DocType, role, user) tuple. A `DocPerm`-style per-role row filter on metadata, plus `DocumentEngine.list` enforcement of those filters, are downstream items.
- `ValidationPipeline`'s `PermissionStage` still only calls `canPerform`. Routing row-level checks through it at write time would require threading the row expression through `ValidationContext`.
- Role membership is exposed as `.array([.string])`, but the evaluator's comparison rules treat `.array` as `.null`; `user.roles == "Admin"` is not directly expressible. A `has_role(...)` evaluator function (or per-role boolean attributes passed via `userAttributes`) is the workaround until the AST refactor in P2.1 introduces function calls.

---

## Revision: 2026-04-24 (Extension-point resolution shipped — P1.3)

This revision records the implementation of declarative extension-point resolution in `AppInstaller`. ADR-015 previously promised that installing a manifest would bind `documentEventSubscriptions` to `EventEmitter` and `schedulerEvents` to `SchedulerService`; with P1.1 complete, P1.3 became the next load-bearing piece and ships in this revision.

### Code added

| File | Summary |
|---|---|
| `mercantis core/AppRuntime/ExtensionPoints.swift` | `ExtensionPoints`, `DocumentEventSubscription`, `DocumentEventTrigger` (closed enum: `on_save`, `on_update`, `on_change`, `on_submit`, `on_cancel`, `on_amend`, `on_trash`, `on_delete`), `SchedulerEventDeclaration`, `ScheduleInterval`, `ExtensionActionDeclaration`. |
| `mercantis core/AppRuntime/ExtensionPointResolver.swift` | `ExtensionPointResolver` + `ExtensionActionDispatcher` / `ExtensionSchedulerRegistrar` protocol seams. Default `LoggingExtensionActionDispatcher` and `RecordingExtensionSchedulerRegistrar` record activity without side effects so P1.2 / P1.4 can plug in real implementations later. |
| `mercantis coreTests/ExtensionPointsTests.swift` | 10 tests covering decode backward-compat, install/uninstall lifecycle, reinstall idempotency, docType selector behaviour, wildcard matching, scheduler register/release, and process-restart re-bind. |

### Code updated

| File | Summary |
|---|---|
| `mercantis core/AppRuntime/AppManifest.swift` | Added `extensionPoints: ExtensionPoints` with `.empty` default and a `decodeIfPresent` init so pre-P1.3 manifests still decode. |
| `mercantis core/AppRuntime/AppInstaller.swift` | New optional `extensionResolver` init parameter; `install` applies it after DocType registration; `uninstall` clears bindings; new `restoreExtensionPoints()` re-binds on process restart by replaying `apps.payload`. |

### Doc updates

| File | Summary |
|---|---|
| `Docs/ADR/ADR-015-declarative-hooks-app-extension.md` | Replaced the "at install time AppInstaller resolves…" paragraph with the shipped design — `ExtensionPointResolver`, token tracking, `ExtensionActionDispatcher` / `ExtensionSchedulerRegistrar` seams, closed trigger enum. |
| `Docs/IMPLEMENTATION-STATUS.md` §2.8, §2.9, §5 | Removed the "EventBus still exists" partial note (P0.6 closed that before this revision); marked §2.9 Layer-1 resolution shipped with scope notes; updated §5's closing paragraph so the remaining gap list drops "automated events from manifests". |
| `Docs/ENHANCEMENT-PROPOSAL.md` P1.3 | Marked done. Sequencing table updated to list P1.3 in week 5 and P1.2 in week 6. |

### Known follow-ups

- The main app (`mercantis_coreApp.swift`) does not yet construct an `AppInstaller` or call `restoreExtensionPoints()` at launch. That wiring belongs to the Hub / app-shell layer (P2.6 / P2.7).
- Subscriptions observe post-commit events. Pre-commit blocking actions (`validate` in ADR-025) require the automation runtime (P1.2) to run inside the save transaction.
- `after_insert` needs an "isNew" flag on `DocumentSavedEvent`; the trigger enum deliberately omits it and manifests using it fail at decode.

---

## Revision: 2026-04-23 (Permissions doc alignment — P0.5 option A)

This revision realigns the Permissions documentation with the shipped `PermissionEngine` code. The 2026-04-14 revision introduced an evaluator-chain design (`PermissionEvaluator` protocol, `PermissionDecision` enum, five concrete evaluators) that was never implemented; the code has always been a flat class with three public methods. `Docs/ENHANCEMENT-PROPOSAL.md` P0.5 picked option A (fix the doc) over option B (implement the chain) as the near-term resolution. The chain remains a candidate direction for a future revision alongside P1.7 (row-level expressions) and a yet-to-be-defined app-/module-level gate.

### Updated Files

| Section | Summary of Change |
|---|---|
| `ARCHITECTURE.md` §3 Architecture Diagram | Renamed the "Permission Evaluator Chain" block to "Permission Engine (flat API)". |
| `ARCHITECTURE.md` §4.2 Document Engine | `PermissionStage` now described as calling `PermissionEngine.canPerform`, not an evaluator chain. |
| `ARCHITECTURE.md` §4.4 Permissions Engine | Rewritten to describe the three shipped methods (`canPerform`, `canAccessField`, `canAccessRow`) and what is explicitly out of scope (app/module gate, workflow-level evaluator, row-level expression predicates). |
| `ARCHITECTURE.md` §4.12 Extension Points | Removed `PermissionEvaluator` from the Layer 3 list. Added a brief note that the chain is not shipped. |
| `ARCHITECTURE.md` §4.15 Public API Surface | Removed the "evaluator chain is not yet implemented" caveat on `PermissionEngine`. |
| `ARCHITECTURE.md` §7 Directory Structure | Removed the "flat; evaluator chain is planned" qualifier on `PermissionEngine.swift`. |
| `Docs/ADR/ADR-011-multi-level-permission-model.md` | Rewritten to describe the shipped flat surface. Kept the context/positioning; removed the `PermissionEvaluator` protocol / `PermissionDecision` enum / five-evaluator chain definitions. Added explicit out-of-scope notes and a forward pointer to the chain as a possible future direction. |
| `Docs/ADR/ADR-025-automation-action-registry.md` | Reframed the "consistent with `PermissionEvaluator`" line — the registry pattern is consistent with `NamingStrategy`; `PermissionEvaluator` is not shipped. |
| `Docs/ADR/ADR-026-three-layer-extensibility-model.md` | Removed `PermissionEvaluator` from the Layer 3 protocol list with a note that reintroducing it requires a chain implementation first. |
| `Docs/IMPLEMENTATION-STATUS.md` §1, §2.4, §5 | `Permissions/` row is no longer "shape doesn't match"; §2.4 now grades `PermissionEngine` against the revised doc (Shipped / Partial / out-of-scope) rather than describing a documentation gap; §5 entry updated to note P0.5 closed the drift. |
| `Docs/ENHANCEMENT-PROPOSAL.md` P0.5 | Marked done (option A). Sequencing table updated. |

### Not changed

No Swift source files were modified; this is purely a documentation change. `PermissionEngine.swift` and the `PermissionStage` integration already matched the new description.

---

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
| ~~Sync queue pruning strategy~~ | Resolved in [ADR-028](ADR/ADR-028-sync-queue-pruning.md) (2026-04-23): acknowledged `.pushed` / `.applied` rows are deleted by `SyncEngine.pruneSyncQueue` once outside a configurable retention window, throttled by a persisted `sync_state` watermark. |
| ~~FieldValue type system deepening~~ | Resolved in P1.6 (2026-04-24): `FieldValue` gained `.date`, `.dateTime`, `.data`, and `.array` with a tagged-envelope wire format that preserves backward-compatible decoding of the legacy untagged primitives. |
| Cross-document lookup in ExpressionEngine | A `lookup(docType, name, field)` function for reading a field from another document in expressions. |
| Server-side validation via CloudAdapter | Whether the CloudAdapter protocol should include a server-side validation round-trip for documents before final commit. |
