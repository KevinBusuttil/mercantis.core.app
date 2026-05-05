# Mercantis Core — Architecture Changelog

## Revision: 2026-05-05 (Phase A engine fixes — list operators, row access, audit log, workflow transition history)

This revision lands the four engine-level "ERP-blocking" gaps from STATUS.md
§3.1–§3.4 in a single bundle. None of the changes break existing call sites.
ADRs 036–039 cover the design.

### Code updated

| File | Summary |
|---|---|
| `mercantis core/DocumentEngine/DocumentEngine.swift` | `ListFilter` struct + `predicates: [ListFilter]?` parameter on `list(...)` (ADR-036). Operators: eq / neq / gt / gte / lt / lte / between / in / like / isNull / isNotNull. System columns and `IndexDefinition` fields push to SQL via `json_extract`; everything else evaluates in memory with mirrored semantics. New `userRoles` / `listUserId` / `userAttributes` / `applyRowAccess` parameters wire `DocType.rowAccessExpression` through `PermissionEngine.canAccessRow` for every fetched row (ADR-037). New private dependencies: `permissionEngine`, `auditLogWriter`, `workflowHistoryWriter`. Save / applyRemote / delete now append an `audit_log` row inside the same atomic write block (ADR-039). Submit / cancel / amend write a follow-on lifecycle audit row. New public readers: `auditEntries(forDocumentId:)`, `auditEntries(forDocType:limit:offset:)`, `workflowTransitions(of:)`, `workflowTransitions(forWorkflow:limit:offset:)`. |
| `mercantis core/DocumentEngine/AuditLog.swift` *(new)* | `AuditLogEntry` struct and `AuditLogWriter` (atomic-block `append(_:in:)` + convenience before/after wrapper + reader API). |
| `mercantis core/Metadata/DocType.swift` | New `rowAccessExpression: String?` field with backward-compatible `Codable` decoding (older payloads default to `nil`). |
| `mercantis core/Workflows/WorkflowEngine.swift` | Optional `historyWriter` injected at init; `transition(...)` calls `writer.append(history)` immediately after the state update when configured. Convenience init `WorkflowEngine(database:)`. Legacy "no writer = return-only" behaviour preserved. |
| `mercantis core/Workflows/WorkflowTransitionHistoryWriter.swift` *(new)* | Writer with both atomic-block (`append(_:in:)`) and standalone (`append(_:)`) entry points; reader API `transitions(of:)` and `transitions(forWorkflow:limit:offset:)`. |
| `mercantis core/Storage/MigrationRunner.swift` | Migration v8 creates `workflow_transitions` (`id`, `documentId`, `docType`, `workflowId`, `fromState`, `toState`, `action`, `userId`, `timestamp`) plus indices on `documentId` and `workflowId`. |
| `mercantis coreTests/ListFilterTests.swift` *(new)* | 13 tests covering each operator, the SQL-pushdown / in-memory-fallback split, multi-predicate AND composition, and system-column predicates. |
| `mercantis coreTests/RowAccessExpressionTests.swift` *(new)* | Auto-applied `rowAccessExpression`, explicit `listUserId`, `applyRowAccess: false` opt-out, empty expression, `user.*` namespace via `userAttributes`. |
| `mercantis coreTests/AuditLogTests.swift` *(new)* | Create/update produces two rows; delete appends; submit/cancel/amend write lifecycle rows; reader returns descending timestamps; payload carries before/after snapshots. |
| `mercantis coreTests/WorkflowTransitionPersistenceTests.swift` *(new)* | Writer-attached engine persists; writer-less engine preserves legacy return-only behaviour; multiple transitions accumulate in chronological order; reader-by-workflow-id; `DocumentEngine` reader plumb-through. |
| `mercantis coreTests/MigrationRunnerTests.swift` | Highest-applied-version assertion bumped to 8; new `testV7AddsParentIdColumn` and `testV8CreatesWorkflowTransitionsTable`. |

### Behaviour changes

- `DocumentEngine.list(...)` with no `applyRowAccess` argument now silently filters out rows the registered DocType's `rowAccessExpression` rejects. DocTypes that ship today with `rowAccessExpression == nil` (the default) are unaffected.
- `DocumentEngine.delete(...)` and the rest of the write paths now write an `audit_log` row per call. Existing `sync_queue` count assertions in tests remain correct because the audit table is separate.
- `WorkflowEngine.transition(...)` constructed via the legacy `WorkflowEngine()` (no writer) initializer behaves exactly as before. The new `WorkflowEngine(database:)` / `WorkflowEngine(historyWriter:)` paths persist automatically.

### Doc updates

| File | Summary |
|---|---|
| `Docs/ADR/ADR-036-list-filter-operator-surface.md` *(new)* | Typed `ListFilter` predicate + SQL pushdown contract. |
| `Docs/ADR/ADR-037-doctype-row-access-expression.md` *(new)* | DocType-level row-access expression auto-filter. |
| `Docs/ADR/ADR-038-workflow-transition-history-persistence.md` *(new)* | `workflow_transitions` table + writer/reader API. |
| `Docs/ADR/ADR-039-audit-log-writer.md` *(new)* | `AuditLogWriter` wired into the atomic write block; reader API. |
| `Docs/ADR/README.md` | Index extended with ADR-036 to ADR-039. |
| `Docs/STATUS.md` | Headline grade bumped to ~75%. §2 scorecard updated for DocumentEngine / Storage / WorkflowEngine / PermissionEngine / Audit log. §3.1–§3.4 rewritten as "shipped" entries. §4 Phase A marked complete. |

### Known follow-ups

- Phase B is unblocked: SchedulerService ↔ AutomationRunner wiring (§3.8), `DocumentNamingRule` (§3.6), counter range reservation (§3.7).
- The `audit_log` payload format is `{before, after}` JSON. If Hub's audit UI grows, we may extract a `summary` column or a structured-diff format in a follow-up.
- The lifecycle audit follow-on rows for submit/cancel/amend commit in a separate transaction from the underlying save. The save's atomicity is preserved; full atomicity across the two writes is a follow-up if required.

---

## Revision: 2026-04-27 (MercantisCoreUI library product shipped — P2.7)

This revision promotes `mercantis core/UIShell/` to its own SwiftPM library product (`MercantisCoreUI`) so downstream apps that `import MercantisCore` can also `import MercantisCoreUI` and reach `GenericFormView` / `GenericListView` directly, instead of hand-rolling a SwiftUI form per DocType.

### Code updated

| File | Summary |
|---|---|
| `Package.swift` | Added `.library(name: "MercantisCoreUI", targets: ["MercantisCoreUI"])` product. New `MercantisCoreUI` target points at `mercantis core/UIShell/` and depends on `MercantisCore` + GRDB. `MercantisCore`'s `exclude:` list still carries `"UIShell"` — the exclude is now load-bearing for the target partition (SwiftPM rejects overlapping source paths), not for "UI is out of scope". CLI executable target remains on `MercantisCore` only, so SwiftUI stays out of the CLI's transitive graph. New `MercantisCoreUITests` SwiftPM test target. |
| `Tests/MercantisCoreUITests/GenericFormViewSmokeTests.swift` *(new)* | Smoke tests that build an in-memory `DocumentEngine`, register a `Customer` DocType, and instantiate `GenericFormView` / `GenericListView` against it. Catches bit-rot when engine-side public types drift. |

### Boundary established

- `MercantisCore` — engine library, no SwiftUI / AppKit / UIKit anywhere in its transitive graph. CLI / server-side / headless consumers depend on this only.
- `MercantisCoreUI` — SwiftUI shell library. Sources: `mercantis core/UIShell/` (`GenericFormView`, `GenericListView`, `NavigationShell`, `DocTypeBuilderView`, `FormBuilderView`, `CommandBarView`, `RecordCollectionHostView`, `RecordWorkspaceToolbarContent`, `SelectedRecordHeader`, `DocTypeListView`, `RecordViewMode`, `RecordCollectionViewConfiguration`, plus internal theme / modifier scaffolding).
- `GenericFormView` / `GenericListView` were already `public struct` with `public init`s — only the SwiftPM target geometry needed to change.

### Doc updates

| File | Summary |
|---|---|
| `Docs/ENHANCEMENT-PROPOSAL.md` | New P2.7 entry (UIShell promotion, marked shipped). The previous P2.7 (Hub-on-Core readiness gap analysis) renamed to P2.7a; cross-references updated. Sequencing footer updated. |
| `Docs/IMPLEMENTATION-STATUS.md` §4 | "SwiftPM products" expanded to three products (added `MercantisCoreUI` row). UIShell row in §1 directory table cross-references the new product. |
| `ARCHITECTURE.md` §7 | "SwiftPM module boundary" rewritten to describe both library products and the CLI's `MercantisCore`-only dependency. |
| `README.md` | New "SwiftPM products" section with a one-line `GenericFormView` usage snippet under `import MercantisCoreUI`. |

### Known follow-ups

- The Xcode app target still compiles `UIShell/` via project membership rather than via the `MercantisCoreUI` SwiftPM product. Same situation as the engine target — shipping the library declaration is sufficient for Hub today; the `.pbxproj` migration is a separate item.
- Hub's `mercantis hub/UI/CustomerFormView.swift` already has a `#if canImport(MercantisCoreUI)` block; activating it is now a Hub-side package-graph change plus matching `GenericFormView`'s actual init signature (`docType: DocType, document: Binding<Document>`, not `(docType: String, engine: DocumentEngine)`).
- `DocTypeBuilderView`'s `fatalError`-on-DB-open-failure is a pre-existing footgun (§2.17 of `IMPLEMENTATION-STATUS.md`), not introduced by this change.

---

## Revision: 2026-04-25 (ExpressionEvaluator AST shipped — P2.1)

This revision records the long-promised lift of `ExpressionEngine/` from a string-walking evaluator to a typed-AST parser + interpreter, plus the install-time static-analysis wiring it unlocks.

### Code updated

| File | Summary |
|---|---|
| `mercantis core/ExpressionEngine/ExpressionAST.swift` *(new)* | `ExpressionNode` (`.literal`, `.fieldRef`, `.unary`, `.binary`, `.call`), `LiteralValue`, `UnaryOperator`, `BinaryOperator`, `ExpressionSourceRange`, `ExpressionParseError`, `ExpressionLexer`. Every node carries a UTF-8 byte range over the original source. |
| `mercantis core/ExpressionEngine/ExpressionParser.swift` *(new)* | Recursive-descent parser. Grammar `or → and → equality → comparison → additive → multiplicative → unary → call → primary` — strictly more powerful than the legacy split (`parseValue` for booleans, `parseFactor` for arithmetic). Comparison RHS now accepts arithmetic; trailing tokens / unknown characters raise parse errors. Static analysis: `ExpressionNode.referencedFields()` and `isConstant`. |
| `mercantis core/ExpressionEngine/ExpressionEvaluator.swift` | Rewritten as a public façade around the parser + an AST interpreter. Existing API (`evaluateBool(expression:context:)`, `evaluateFormula(expression:context:)`, the four `EvaluatorError` cases) is preserved verbatim; a fifth `EvaluatorError.parseError(ExpressionParseError)` case carries source positions. New API: `parse(_:)`, `evaluateBool(parsed:context:)`, `evaluateFormula(parsed:context:)`, `referencedFields(in:)`. Bounded LRU parse cache (`parseCacheLimit`, default 256). Pure-literal subtrees collapse at parse time (constant folding); fold-time exceptions (e.g. `10 / 0`) are deliberately deferred to runtime. |
| `mercantis core/Metadata/SchemaValidator.swift` | New `validatesExpressions: Bool = true` toggle. `validate(_:)` now parses each field's `visibilityExpression` / `readOnlyExpression` / `formulaExpression` and rejects DocTypes whose expressions reference an undeclared field key (`unknownFieldInExpression`) or fail to parse (`expressionParseFailed`). Dotted identifiers (`user.id`, `user.roles`) are exempt because the permission engine pre-flattens them into the evaluation context. |
| `mercantis core/UIShell/DocTypeBuilderView.swift` | `errorMessage(for:)` switch updated to surface the two new `SchemaValidator.ValidationError` cases. |
| `mercantis coreTests/ExpressionEvaluatorTests.swift` | New tests for `parse`, `referencedFields`, parse-cache equality, constant folding (collapse + division-by-zero deferral), source-position parse errors (unknown char, unterminated string, trailing tokens), `parseCacheLimit: 0` opt-out. Every legacy test preserved. |
| `mercantis coreTests/SchemaValidatorTests.swift` *(new)* | Declared-field happy-path / undeclared-field rejection for each of the three field-level expression slots, malformed-expression rejection, dotted-identifier exemption, `validatesExpressions = false` opt-out. |

### Behaviour changes

- Comparison RHS now accepts arithmetic expressions (`total > 100 + 50` evaluates the addition); the legacy parser silently dropped the `+ 50` half. Strict improvement, but flagged for any manifest that was relying on the drop.
- Trailing tokens (`a == b c`) and unknown characters (`a $ b`) now raise parse errors. The legacy parser silently ignored them.
- Undefined-field semantics preserved exactly: arithmetic context throws `undefinedField`; comparison and truthiness context behaves like `null` / `false`. Implemented via an internal `RuntimeValue.undefined(name)` carrier inside the interpreter.

### Doc updates

| File | Summary |
|---|---|
| `Docs/ENHANCEMENT-PROPOSAL.md` P2.1 | Marked done. Detailed three-file split, immediate-wins list, behaviour-change call-outs, coverage matrix, and the three known follow-ups (workflow / automation install-time validation, SQL push-down via the new AST, short-circuit folding). Sequencing footer updated. |
| `Docs/IMPLEMENTATION-STATUS.md` §2.7 | Replaced "Partial — no AST" entry with the P2.1 shipped breakdown. P0.9 unary-minus partial removed (subsumed by the new AST grammar). |
| `ARCHITECTURE.md` §4.7 | Reframed the "typed AST" claim as fact rather than aspiration; expanded the four AST-enabled benefits (static analysis, parse-once / evaluate-many, constant folding, source-position errors). |
| `ARCHITECTURE.md` §4.15 | `ExpressionEvaluator` public-API line expanded to list `parse`, `evaluateBool(parsed:context:)`, `evaluateFormula(parsed:context:)`, `referencedFields(in:)`. |
| `ARCHITECTURE.md` §7 | Directory tree shows the three files now in `ExpressionEngine/`. |
| `mercantis coreTests/README.md` | Coverage row for `ExpressionEvaluatorTests.swift` extended with the P2.1 additions; new row for `SchemaValidatorTests.swift`. |

### Known follow-ups

- Workflow `transition.conditionExpression` and `AutomationRule.conditionExpression` are not yet validated at install time. The right hook is `AppInstaller.install`, not `SchemaValidator` (the rules don't live on the DocType). Tracked.
- The AST → SQL emitter that would push `whereExpression` filters down to SQLite is the second half of P2.5's known follow-up. The parser side is now in place; the emitter is not yet written.
- Constant folding is conservative — it does not short-circuit `||` / `&&` when only one side is constant. Adding short-circuit folding is a safe future tweak.
- The `.call` AST node is parsed but rejected by the interpreter, so the AST shape is forward-compatible with `lookup()` (P2.2) when it lands.

---

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
