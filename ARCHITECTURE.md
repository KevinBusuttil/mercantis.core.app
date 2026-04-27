# Mercantis Core — Architecture

## 1. Product Context

**Mercantis Core** is the general-purpose platform layer for the Mercantis ecosystem. It provides the infrastructure every business application needs: document storage and CRUD, metadata-driven schemas, an offline-first sync engine, a declarative plugin/app model, multi-level permissions, a workflow engine, and a sandboxed expression evaluator.

Core is deliberately domain-agnostic. It knows about *documents*, *DocTypes*, *workflows*, and *apps* — not sales invoices, purchase orders, or stock ledger entries. Domain knowledge lives in app manifests, not in Core's codebase.

**Mercantis Hub** (`mercantis.app`) is the first-party ERP application that is built exclusively on top of Core's public APIs (see [ADR-001](Docs/ADR/ADR-001-core-hub-split.md) and [ADR-007](Docs/ADR/ADR-007-hub-on-core-public-apis.md)).

---

## 2. Core Architectural Principles

| Principle | Description | ADR |
|-----------|-------------|-----|
| **Offline-first** | Every write succeeds locally first. The sync engine propagates changes to the cloud when connectivity is available. | [ADR-002](Docs/ADR/ADR-002-sqlite-local-source-of-truth.md) |
| **Metadata-driven** | All entities are DocTypes described in JSON/YAML manifests. The schema registry is the single source of truth. | [ADR-003](Docs/ADR/ADR-003-metadata-defined-doctypes.md) |
| **Sync via mutation log** | Every persistent write appends an immutable `MutationRecord` to a sync queue. The log drives cloud sync; it is never modified. | [ADR-005](Docs/ADR/ADR-005-sync-via-mutation-log.md) |
| **Declarative plugins** | Apps are manifest files (JSON/YAML). They declare DocTypes, workflows, reports, and automation rules; they never ship executable code. | [ADR-004](Docs/ADR/ADR-004-declarative-app-plugin-model.md) |
| **Permissions at every level** | App → DocType → field → row → workflow action. Every operation is gated by the permission engine. | [ADR-003](Docs/ADR/ADR-003-metadata-defined-doctypes.md) |
| **No downloaded binaries** | iOS/macOS App Store rules and security policy prohibit downloaded executable plugins. All logic runs through Core's sandboxed expression engine. | [ADR-008](Docs/ADR/ADR-008-no-executable-plugins-ios.md) |
| **Pure client-side** | All logic executes within the app process. No server, no daemon. The Cloud Adapter protocol is the only external boundary. | [ADR-010](Docs/ADR/ADR-010-pure-client-side-architecture.md) |

---

## 3. Subsystem Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Mercantis Core                                 │
│                                                                             │
│   ┌───────────┐   ┌─────────────┐   ┌────────────────────┐                 │
│   │  UIShell  │   │ AppRuntime  │   │  ExpressionEngine  │                 │
│   │ (planned) │   │  (manifest  │   │  (AST-based eval)  │                 │
│   │           │   │  installer) │   │                    │                 │
│   └─────┬─────┘   └──────┬──────┘   └─────────┬──────────┘                 │
│         │                │                    │                             │
│   ┌─────▼────────────────▼────────────────────▼────────────────────────┐   │
│   │                         DocumentEngine                              │   │
│   │  save() · delete() · fetch() · list() · submit() · cancel() ·      │   │
│   │  amend() · ValidationPipeline · VersioningDiffTracker ·            │   │
│   │  optimistic concurrency · lifecycle events · mutation logging       │   │
│   └────────────────────────────┬────────────────────────────────────────┘   │
│         │           │          │           │            │                   │
│   ┌─────▼──────┐  ┌─▼──────────▼──┐  ┌────▼──────┐  ┌─▼──────────────┐   │
│   │ Permission │  │ WorkflowEngine │  │  Typed    │  │  NamingService │   │
│   │ Engine     │  │ (state machine)│  │ EventBus  │  │SchedulerService│   │
│   │ (flat API) │  └───────┬────────┘  └───────────┘  └────────────────┘   │
│   └─────┬──────┘          │                                                 │
│         │                 │                                                 │
│   ┌─────▼─────────────────▼──────────────────────────────────────────┐     │
│   │                   Storage (GRDB / SQLite)                         │     │
│   │   MercantisDatabase · MigrationRunner · CacheManager              │     │
│   └────────────────────────────┬─────────────────────────────────────┘     │
│                                │                                            │
│   ┌────────────────────────────▼─────────────────────────────────────┐     │
│   │                       SyncEngine                                  │     │
│   │   MutationRecord · push · receive · apply · acknowledge           │     │
│   │   ConflictResolver (LWW | VCM | AO) · CloudAdapter (protocol)    │     │
│   └──────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│   ┌────────────────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────┐  │
│   │  MetadataRegistry  │  │ ReportEngine │  │FileManager │  │PrintEngine│  │
│   │  + MetaComposer    │  │  (planned)   │  │            │  │(planned) │  │
│   │  → ResolvedMeta    │  └──────────────┘  └────────────┘  └──────────┘  │
│   └────────────────────┘                                                   │
│                                                                             │
│   ┌────────────────────────┐  ┌───────────────────────┐                   │
│   │  CustomizationEngine   │  │    ImportExport        │                   │
│   │  (Custom Fields, Props,│  │  (CSV/JSON import/     │                   │
│   │   Client Scripts)      │  │   export, fixtures)    │                   │
│   └────────────────────────┘  └───────────────────────┘                   │
│                                                                             │
│   ┌────────────────────────┐  ┌───────────────────────┐                   │
│   │ NamingStrategy Registry│  │  AutomationAction      │                   │
│   │ (UUIDv7 | Series |     │  │  Registry              │                   │
│   │  Field | Prompt | Fmt) │  │  (set_value | assign…) │                   │
│   └────────────────────────┘  └───────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Subsystem Descriptions

### 4.1 Metadata Engine

**Location:** `mercantis core/Metadata/`

The Metadata Engine is the schema registry. Every entity in the system — whether built-in or declared by an app manifest — is described by a `DocType`. A DocType carries:

- **Field definitions** (`FieldDefinition`) — key, type, label, validation rules, options, visibility/read-only expressions, and field-level permission rules.
- **Permission rules** (`PermissionRule`) — role-based CRUD/submit/amend flags at DocType level.
- **Sync policy** (`SyncPolicy`) — conflict resolution strategy (LWW, VCM, or AO) and immutability after submit.
- **Index definitions** (`IndexDefinition`) — fields to extract from the JSON payload into indexed columns for query performance.
- **Workflow reference** — optional `workflowId` pointing to a `WorkflowDefinition`.

`SchemaValidator` validates DocType definitions before they are committed to the registry. `MetadataRegistry` provides an in-memory cache backed by the `doctypes` table.

**MetaComposer:** At runtime, raw DocType definitions are not used directly. `MetaComposer` composes a `ResolvedMeta` object by merging three layers: the base DocType definition (from the manifest / `doctypes` table) + user custom fields (from the `custom_fields` table) + property overrides (from the `property_setters` table). The `ResolvedMeta` is the authoritative runtime schema that all consumers — DocumentEngine, PermissionEngine, UIShell, ExpressionEngine — use. The `CustomizationEngine` (§4.19) is the write path for custom fields and property setters; `MetaComposer` is the read path. `ResolvedMeta` is cached and invalidated whenever any of the three layers changes for a given DocType.

See [ADR-003](Docs/ADR/ADR-003-metadata-defined-doctypes.md) and [ADR-021](Docs/ADR/ADR-021-metadata-composition-resolved-meta.md).

---

### 4.2 Document Engine

**Location:** `mercantis core/DocumentEngine/`

The Document Engine handles all CRUD operations on `Document` instances. A `Document` is a generic container — its structure is determined entirely by its `DocType` metadata.

Key responsibilities:
- **`save(_:)`** — Run the `ValidationPipeline`, check optimistic concurrency, serialize to JSON, write to the `documents` table, compute and store a field-level diff as a `DocumentVersion`, and atomically append a `MutationRecord` to `sync_queue`. Fire a `DocumentSavedEvent` on the typed event bus.
- **`delete(docType:id:)`** — Delete from `documents`, cascade-delete child rows from `document_children`, append a `deleteDocument` mutation, fire a `DocumentDeletedEvent`.
- **`fetch(docType:id:)`** — Query `documents`, deserialize the JSON payload into a `Document`.
- **`list(docType:filters:whereExpression:sortBy:limit:offset:)`** — Query with optional equality filters, a sandboxed boolean `whereExpression` (run via `ExpressionEvaluator`), an ordered `[ListSort]` sort chain, and `limit` / `offset` paging. Filters and sort keys that match either a system column or a `DocType.IndexDefinition` are pushed to SQL via `json_extract`; the rest is finished in memory. (P2.5)

**ValidationPipeline:** Document save runs a structured, ordered validation sequence. Each stage is a `ValidationStage` protocol conformance, independently testable, executed in declared order:
1. `TypeCoercionStage` — field values match declared types.
2. `RequiredFieldStage` — required fields are non-empty.
3. `LinkValidationStage` — link field targets exist.
4. `UniqueConstraintStage` — unique fields/indexes have no collisions.
5. `ValidationRuleStage` — `ValidationRule` expressions evaluate to true.
6. `WorkflowGuardStage` — workflow transition is allowed.
7. `PermissionStage` — `PermissionEngine.canPerform` grants the operation.

Validation failures produce structured errors with stage, field, and message. See [ADR-022](Docs/ADR/ADR-022-document-validation-pipeline.md).

**Optimistic concurrency:** Documents carry a `modifiedAt` timestamp. On save, `DocumentEngine` compares the document's `modifiedAt` against the stored value. If another save occurred between load and save (even on the same device), the save fails with a `ConcurrencyConflictError`. This is separate from cross-device sync conflicts (handled by `SyncEngine`). See [ADR-023](Docs/ADR/ADR-023-optimistic-concurrency-modified-timestamp.md).

**Versioning / diff tracking:** On every save, `DocumentEngine` computes a field-level diff (which fields changed, old value → new value) and stores it as a `DocumentVersion` record. This provides a complete field-level change history for audit-sensitive documents. See [ADR-024](Docs/ADR/ADR-024-document-versioning-diff-tracking.md).

Every write goes through the Document Engine. Direct SQLite writes that bypass it are prohibited (see [ADR-005](Docs/ADR/ADR-005-sync-via-mutation-log.md)).

Child table rows are stored separately in the `document_children` table. Each `ChildRow` carries a `rowIndex` for ordering and a JSON `payload`.

---

### 4.3 Storage

**Location:** `mercantis core/Storage/`

Storage wraps SQLite via [GRDB](https://github.com/groue/GRDB.swift) and owns all schema migrations.

- **`MercantisDatabase`** — Central database manager. Opens a GRDB `DatabasePool` at a given URL and runs `MigrationRunner.migrate()` on startup. Exposes `read(_:)` and `write(_:)` closures for typed, thread-safe access.
- **`MigrationRunner`** — Tracks the current schema version in a `schema_version` table and runs pending migrations in transactions.

The initial migration (v1) creates:

| Table | Purpose |
|-------|---------|
| `schema_version` | Migration tracking |
| `doctypes` | Registered DocType definitions (JSON payload) |
| `fields` | Flattened field definitions per DocType |
| `documents` | Core document store: id, doctype, company, status, createdAt, updatedAt, syncVersion, syncState, payload (JSON) |
| `document_children` | Child table rows: id, parentId, parentDocType, tableName, rowIndex, payload (JSON) |
| `sync_queue` | Mutation log: id, type, payload, deviceId, userId, localTimestamp, syncVersion, status |
| `audit_log` | Immutable audit trail of all document mutations |
| `apps` | Installed app manifest registry |
| `workflows` | Workflow definitions (JSON payload) |

See [ADR-002](Docs/ADR/ADR-002-sqlite-local-source-of-truth.md).

---

### 4.4 Permissions Engine

**Location:** `mercantis core/Permissions/`

`PermissionEngine` is a small, flat class with three public methods — one per permission scope. Callers (DocumentEngine, WorkflowEngine, UI shell, the `PermissionStage` of the `ValidationPipeline`) invoke the method that matches the check they need.

```swift
public final class PermissionEngine {
    public init()

    func canPerform(operation: DocumentOperation, on: DocType,
                    userRoles: Set<String>) -> Bool
    func canAccessField(fieldKey: String, on: DocType,
                        userRoles: Set<String>, operation: FieldOperation) -> Bool
    func canAccessRow(document: Document, userRoles: Set<String>,
                      rowExpression: String?, userId: String = "",
                      userAttributes: [String: FieldValue] = [:],
                      expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()) -> Bool
}
```

- **DocType-level** (`canPerform`) — walks `DocType.permissions` (`[PermissionRule]`), keeps rules whose role is in `userRoles`, and returns `true` on the first rule that grants the requested `DocumentOperation` (`.read` / `.write` / `.create` / `.delete` / `.submit` / `.amend`).
- **Field-level** (`canAccessField`) — consults `FieldDefinition.permissions` (`FieldPermission?`). A field with no `permissions` block is reachable by anyone who already passed the DocType check. If the block is present, membership of `readRoles` or `writeRoles` (per `FieldOperation`) decides.
- **Row-level** (`canAccessRow`) — `rowExpression` is a sandboxed boolean expression evaluated by `ExpressionEvaluator` (ADR-017) over the document's fields plus a `user.*` namespace populated from `userId`, `userRoles`, and any extra `userAttributes`. Standard entries are `user.id` (string) and `user.roles` (`.array([.string])`); `userAttributes` keys without a `user.` prefix are namespaced automatically and override the standard entries. Common expressions: `"owner == user.id"`, `"warehouse == user.warehouse"`. A `nil`, empty, or whitespace-only expression grants access; an expression that fails to evaluate (parse error, undefined identifier, type mismatch) fails closed. Wired in for P1.7.

**Out of scope for `PermissionEngine` today:**
- App / module gating — nothing in Core asks "is this role allowed to use this module at all?" A future evaluator (tracked as a P1 enhancement) may be added.
- Workflow transition role gates — these are enforced inside `WorkflowEngine.availableTransitions` via `WorkflowTransition.allowedRoles`, not through `PermissionEngine`.

ADR-011 previously described an evaluator-chain design (a `PermissionEvaluator` protocol with concrete `AppLevel` / `DocTypeLevel` / `FieldLevel` / `RowLevel` / `WorkflowLevel` evaluators, short-circuiting on the first `.denied`). That design is a future candidate, not the shipped engine. See the revised ADR-011 for why the flat surface is the current contract.

See [ADR-011](Docs/ADR/ADR-011-multi-level-permission-model.md).

---

### 4.5 Workflow Engine

**Location:** `mercantis core/Workflows/`

The Workflow Engine implements state-machine transitions for documents.

A `WorkflowDefinition` (declared in an app manifest) defines:
- **States** — name, `isDefault`, `allowEdit`.
- **Transitions** — from/to states, action name, allowed roles, optional condition expression.

Key methods:
- `availableTransitions(workflow:currentState:userRoles:document:expressionEvaluator:)` — Returns transitions the current user can execute from the current state.
- `transition(document:workflow:action:userRoles:expressionEvaluator:)` — Validates the transition is allowed (role + condition), updates `document.status`, appends a `WorkflowTransitionHistory` record, and fires a `workflow.transition` event on the `EventBus`.

`WorkflowTransitionHistory` records the full audit trail of every state change: transitionId, documentId, from, to, action, userId, timestamp.

---

### 4.6 Sync Engine

**Location:** `mercantis core/SyncEngine/`

The Sync Engine orchestrates the push/receive/apply/acknowledge flow between the local database and a cloud adapter (see [ADR-005](Docs/ADR/ADR-005-sync-via-mutation-log.md)).

**Push flow:**
1. Read `pending` mutations from `sync_queue` ordered by `localTimestamp`.
2. Send batch to cloud adapter.
3. Mark mutations as `pushed` on success.

**Receive/apply flow:**
1. Receive remote mutations from cloud adapter.
2. For each mutation, look up the DocType's `SyncPolicy`.
3. Apply the appropriate conflict resolution strategy via `ConflictResolver`.
4. Update document `syncState` accordingly.

**Conflict resolution** (`ConflictResolver`) — Three policies:
- **Last-Write-Wins (LWW)** — Descriptive, non-financial fields. Higher server sequence wins. Loser is recorded in the audit log.
- **Version-Checked Merge (VCM)** — Financial/inventory documents. Concurrent edits are rejected; human resolution is required.
- **Append-Only (AO)** — Immutable-once-created records (ledger entries, audit log). Always accepted.

See [ADR-006](Docs/ADR/ADR-006-financial-inventory-conflict-policy.md).

---

### 4.7 Expression Engine

**Location:** `mercantis core/ExpressionEngine/`

The Expression Engine is a sandboxed evaluator for boolean conditions and formula fields (see [ADR-008](Docs/ADR/ADR-008-no-executable-plugins-ios.md)).

It is used by:
- Automation rule `conditionExpression` — e.g. `status == "Submitted" && grandTotal > 10000`
- Field `visibilityExpression` and `readOnlyExpression`
- Workflow transition `conditionExpression`
- Formula field values

Supported syntax:
- Field comparisons: `field == "value"`, `field != "value"`, `field > 100`, `field < 100`
- Boolean operators: `&&`, `||`, `!`
- Parentheses for grouping
- Arithmetic formulas: `+`, `-`, `*`, `/`

The evaluator parses expressions into a **typed AST** (`ExpressionNode`) before evaluation — not string-walking. Benefits unlocked by the AST (P2.1):

- **Static field-reference analysis** — `ExpressionEvaluator.referencedFields(in:)` returns the identifiers an expression touches without evaluating it. `SchemaValidator.validate(_:)` calls this at install time and rejects DocTypes whose `visibilityExpression` / `readOnlyExpression` / `formulaExpression` references a field key the DocType does not declare.
- **Parse-once / evaluate-many** — `parse(_:)` returns a reusable `ExpressionNode` that callers (e.g. `DocumentEngine.list` running a `whereExpression` over many rows, or an automation rule's per-save `conditionExpression`) hand to `evaluateBool(parsed:context:)` to skip the parse phase. A bounded LRU on the evaluator caches recently-seen source strings so naive callers also benefit transparently.
- **Constant folding** — pure-literal subtrees collapse at parse time. `2 + 3 * 4` becomes a single `.literal(.number(14))`. Subtrees that throw (e.g. `10 / 0`) are deliberately left unfolded so the runtime error contract is preserved.
- **Source-position errors** — every AST node carries a `[start, end)` UTF-8 range; parse errors lift through `EvaluatorError.parseError(ExpressionParseError)` whose `description` renders the source line and a `^` caret pointing at the offending byte.

**Cross-document `lookup()` (ADR-029, P2.2)** — when the evaluator is constructed with a `DocumentLookupResolver`, expressions can call `lookup("DocType", id, "field")` to read a single field from a different document. Wrong arity / non-string args throw; missing documents / fields resolve to `null`; resolver throws are caught and surfaced as `null` so transient I/O does not crash a form's expression evaluation. A per-evaluation `lookupBudget` (default 32) caps cross-document reads per top-level evaluation. `DocumentEngine` is the reference resolver and exposes a pre-wired, per-save-invalidating `CachingDocumentLookupResolver` so list `whereExpression`s and automation rules that join through the same parent only fetch each parent once. Without an injected resolver, every `lookup(...)` call throws — opt-in, not silent.

The evaluator operates with **no access to the file system, network, or arbitrary Swift APIs** beyond the optional `DocumentLookupResolver` described above.

See [ADR-017](Docs/ADR/ADR-017-expression-engine-scope-sandboxing.md), [ADR-029](Docs/ADR/ADR-029-cross-document-lookup.md).

---

### 4.8 Notifications & Events

**Location:** `mercantis core/Notifications/`

The event system uses **typed events** — each event is a concrete Swift type, not a string key. Subscriptions are type-parameterised and compile-time verified. Callers receive a `SubscriptionToken`; releasing it cancels the subscription, preventing memory leaks.

Standard event types:
- `DocumentSavedEvent` — fired by `DocumentEngine.save(_:)`
- `DocumentDeletedEvent` — fired by `DocumentEngine.delete(docType:id:)`
- `WorkflowTransitionEvent` — fired by `WorkflowEngine.transition(...)`
- `AppInstalledEvent` — fired by `AppInstaller.install(_:)`

This supersedes the stringly-typed `EventBus` (ADR-012). See [ADR-020](Docs/ADR/ADR-020-typed-event-system.md).

An in-app inbox for user-visible notifications is planned.

---

### 4.9 App Runtime

**Location:** `mercantis core/AppRuntime/`

The App Runtime implements the declarative plugin model (see [ADR-004](Docs/ADR/ADR-004-declarative-app-plugin-model.md) and [ADR-008](Docs/ADR/ADR-008-no-executable-plugins-ios.md)).

- **`AppManifest`** — A Codable struct representing a manifest file. It declares DocTypes, workflows, permissions, reports, automation rules, and dashboards. It never contains executable code.
- **`AppInstaller`** — Validates all DocTypes in the manifest via `SchemaValidator`, writes DocTypes/workflows/permissions to metadata tables, and appends an `installApp` mutation to `sync_queue` so the installation is distributed to all devices.

Apps are identified by a reverse-DNS `id` (e.g. `app.mercantis.hub`) and carry a semver `version` and `minimumCoreVersion` constraint.

---

### 4.10 Document Lifecycle (Submit / Cancel / Amend)

**Location:** `mercantis core/DocumentEngine/`

The Document Lifecycle subsystem manages the `docstatus` state machine for submittable DocTypes.

- **Draft (0)** — Default state on creation. The document is freely editable.
- **Submitted (1)** — The document is immutable. Set by `DocumentEngine.submit(_:)`.
- **Cancelled (2)** — The document is immutable. Set by `DocumentEngine.cancel(_:)`. The document is retained for audit purposes.

Valid transitions: Draft → Draft (save), Draft → Submitted (submit), Submitted → Cancelled (cancel). No other transitions are permitted.

DocTypes opt into this lifecycle via `isSubmittable: true` in the DocType definition. Fields marked `allowOnSubmit: true` can be edited after submission — all other fields are immutable and any write attempt is rejected at the DocumentEngine layer. Cancellation checks for linked submitted documents: if any downstream submitted document references the document being cancelled, the cancel is rejected to prevent dangling references. Amending a cancelled document creates a new Draft with `amendedFrom` pointing to the cancelled document and `docstatus` reset to 0, providing a complete correction history. The `immutableAfterSubmit` sync policy flag (from [ADR-006](Docs/ADR/ADR-006-financial-inventory-conflict-policy.md)) enforces immutability at the sync layer.

Key methods: `DocumentEngine.submit(_:)`, `DocumentEngine.cancel(_:)`, `DocumentEngine.amend(_:)`.

See [ADR-009](Docs/ADR/ADR-009-single-documents-table.md) and [ADR-013](Docs/ADR/ADR-013-submit-cancel-amend-lifecycle.md).

---

### 4.11 Naming System

**Location:** `mercantis core/Naming/`

The Naming System determines the `id` / `name` of each document at save time. It is implemented as a **strategy registry** — each naming strategy is a `NamingStrategy` protocol conformance:

```swift
protocol NamingStrategy {
    func resolve(docType: DocType, document: Document, context: NamingContext) throws -> String
}
```

Built-in strategies:

- **`UUIDv7Strategy`** (default) — UUID v7, time-ordered, globally unique. Recommended for offline-first DocTypes.
- **`NamingSeriesStrategy`** — Pattern-based sequential naming (e.g. `SINV-.YYYY.-.####`). Supports date tokens (`YY`, `YYYY`, `MM`, `DD`), field references, and hash placeholders.
- **`FieldDerivedStrategy`** — Derive the name from a field value (e.g. `field:email`).
- **`PromptStrategy`** — The user enters the name manually.
- **`FormatStrategy`** — Format string with field interpolation (e.g. `format:{company_abbr}-{naming_series}`).

A `DocumentNamingRule` conditional selector picks the strategy based on document field values (e.g. different naming series per company), with priority ordering. `NamingService` evaluates these rules at `DocumentEngine.save()` time and dispatches to the appropriate strategy.

See [ADR-014](Docs/ADR/ADR-014-document-naming-strategy.md).

---

### 4.12 Extension Points

**Location:** `mercantis core/AppRuntime/`

Mercantis Core uses a **three-layer extensibility model** (see [ADR-026](Docs/ADR/ADR-026-three-layer-extensibility-model.md)) instead of Frappe-style hooks. Frappe hooks are explicitly rejected: they are stringly-typed, have no ordering guarantees, produce silent failures on misspelled event names, and require executable code that violates iOS App Store rules.

**Layer 1 — Declarative manifests (primary extension surface):**
Apps declare extension points in their manifest under `extensionPoints`:
- `documentEventSubscriptions` — Per-DocType or global lifecycle subscriptions (`on_update`, `after_insert`, `on_submit`, `on_cancel`, `on_trash`, `on_change`). Handlers are built-in action types only.
- `schedulerEvents` — Periodic task registration (`all`, `daily`, `hourly`, `weekly`, `monthly`, `cron`).

**Layer 2 — Typed event subscriptions:**
Compiled-in code subscribes to typed events via the `EventEmitter`. Type-safe, lifecycle-managed via `SubscriptionToken`. Not available to downloaded apps.

**Layer 3 — Compiled-in extension protocols:**
First-party code provides custom `NamingStrategy` or `AutomationActionHandler` conformances compiled into Core. Not available to downloaded apps. (A `PermissionEvaluator` protocol was proposed in earlier revisions of ADR-011 but is not shipped; the current `PermissionEngine` exposes three flat methods rather than a pluggable protocol.)

At install time, `AppInstaller` resolves Layer 1 declarations into typed event subscriptions or `SchedulerService` registrations.

See [ADR-015](Docs/ADR/ADR-015-declarative-hooks-app-extension.md) and [ADR-026](Docs/ADR/ADR-026-three-layer-extensibility-model.md).

---

### 4.13 Background Tasks & Scheduling

**Location:** `mercantis core/Scheduling/`

Because Mercantis Core is a pure client-side library (no server process), background tasks execute within the app process using Swift Concurrency (`Task`).

- **Scheduled tasks** — `SchedulerService` checks for due tasks on app launch and periodically while the app is active. Tasks are declared in app manifests under `schedulerEvents` and registered via `ExtensionPointResolver` → `ExtensionSchedulerRegistrar`. (P1.4 — 2026-04-24)
- **Task types:** `all` (every tick), `hourly`, `daily`, `weekly`, `monthly`, `cron` (custom expression).
- **Cron support:** dependency-free five-field parser (minute, hour, day-of-month, month, day-of-week). Supports `*`, integer, comma-separated lists, inclusive ranges, and `*/step`. Day-of-week accepts `0`–`7` with both `0` and `7` binding to Sunday. When both day fields are explicit, the matcher uses Vixie union semantics. `@yearly` / `@daily` aliases are not supported.
- **Persistence:** the v6 `scheduler_state(taskKey, lastRunAt)` table records the last-run timestamp per task. Task keys are `"<appId>::<declarationId>"`. Reinstall preserves cadence (the resolver only forgets the in-memory binding); full uninstall calls `SchedulerService.unregister(appId:)` which wipes every row whose key starts with `"<appId>::"`.
- **Tick loop:** `start()` opts into a `Task` loop running every `tickInterval` (default 60 s). The first tick fires immediately so a task that came due while the app was closed catches up on launch instead of waiting a full interval. Tests and CLI hosts can drive the scheduler manually via `tick()` without `start()`.
- **Queue categories** (`short` / `default` / `long`) and `audit_log` writes for failed scheduled runs are not yet implemented; the current loop is a single in-process tick.
- Sync operations (push/receive) are themselves scheduled background tasks.

**AutomationActionRegistry:** Automation action dispatch uses a registry of `AutomationActionHandler` protocol conformances keyed by `actionType` string. Built-in action types: `set_value`, `set_status`, `send_notification`, `validate`, `assign`. New action types are added by registering a conformance compiled into Core. See [ADR-025](Docs/ADR/ADR-025-automation-action-registry.md).

See [ADR-010](Docs/ADR/ADR-010-pure-client-side-architecture.md).

---

### 4.14 Caching Layer

**Location:** `mercantis core/Cache/`

The Caching Layer minimises repeated database reads for hot data.

- **MetadataRegistry cache** — All DocType definitions are cached in-memory on first access. The cache is invalidated when a DocType is installed, updated, or uninstalled via `AppInstaller`.
- **Document cache** — Frequently accessed single-instance documents (e.g. system settings) can be cached using `getOrCache(docType:id:)`. The cache is invalidated on any write to that document.
- **Query result cache** — List queries are not cached by default (SQLite is fast enough for on-device data volumes). Apps can opt in to result caching for expensive computed reports.
- **Cache invalidation** — All caches use a generation counter. Any schema change increments the generation, forcing a full reload.

---

### 4.15 Public API Surface

**Location:** `mercantis core/` (top-level public interfaces)

The Public API Surface defines the Swift types and methods that app-layer code (including Hub) consumes. All public API methods are annotated with `public` access control. Internal subsystems are `internal`. Direct database access is never exposed.

Key API points:

- `DocumentEngine` — `save(_:)`, `delete(docType:id:)`, `fetch(docType:id:)`, `list(docType:filters:whereExpression:sortBy:limit:offset:)`, `submit(_:)`, `cancel(_:)`, `amend(_:)`, `lookup(docType:name:field:)` (P2.2), `lookupCache`, `listExpressionEvaluator`
- `MetadataRegistry` — `register(_:)`, `get(docType:)`, `all()`, `unregister(docType:)`
- `MetaComposer` — `resolve(docType:)` → `ResolvedMeta`
- `PermissionEngine` — `canPerform(operation:on:userRoles:)`, `canAccessField(fieldKey:on:userRoles:operation:)`, `canAccessRow(document:userRoles:rowExpression:userId:userAttributes:expressionEvaluator:)`
- `WorkflowEngine` — `availableTransitions(...)`, `transition(...)`
- `SyncEngine` — `pushPendingMutations()`, `pullAndApplyRemoteMutations()`, `applyRemoteMutations(_:)`, `resolveConflict(docType:documentId:chosenVersion:resolvedBy:)`
- `ExpressionEvaluator` — `evaluateBool(expression:context:)`, `evaluateFormula(expression:context:)`, `parse(_:) -> ExpressionNode`, `evaluateBool(parsed:context:)`, `evaluateFormula(parsed:context:)`, `referencedFields(in:)` (P2.1); optional `lookupResolver` + `lookupBudget` for cross-document `lookup(...)` (P2.2 / ADR-029)
- `DocumentLookupResolver` — `lookup(docType:name:field:)` protocol; `CachingDocumentLookupResolver` is the read-through cache with per-save invalidation. (P2.2 / ADR-029)
- `EventEmitter` — `subscribe(_:handler:)` → `SubscriptionToken`, `publish(_:)`
- `AppInstaller` — `install(_:)`, `install(manifestData:)`, `validate(manifestData:)`, `uninstall(appId:)`, `decodeManifest(from:)` (P2.3)
- *`AutomationActionRegistry` is planned (ADR-025) — not yet implemented.*

See [ADR-007](Docs/ADR/ADR-007-hub-on-core-public-apis.md).

---

### 4.16 Notification & Communication System

**Location:** `mercantis core/Notifications/` *(in progress)*

The Notification subsystem delivers user-visible alerts and integrates with external communication channels.

- **In-app notifications** — A `NotificationLog` DocType stores user-visible notifications. Types: Alert, Mention, Assignment, Share, Energy Point.
- **Email integration** — Planned. Will use a protocol-based `EmailAdapter` (analogous to `CloudAdapter`) so Core defines the interface and the host app provides the SMTP/API implementation.
- **Channels:** System Notification (in-app), Email, SMS, Slack/Webhook — declared per `Notification` rule.
- **Notification rules** — Declared in app manifests. Trigger on document events (New, Save, Submit, Cancel, Value Change) or custom method calls.

---

### 4.17 Print & PDF System

**Location:** `mercantis core/Printing/` *(planned)*

The Print & PDF subsystem supports document rendering for physical or digital output.

- **Print Formats** — Declared per DocType, supporting Jinja-like templates with field interpolation.
- **PDF generation** — Protocol-based `PDFGenerator` adapter. The host app provides the rendering implementation (e.g. UIKit PDF renderer on iOS, AppKit on macOS).
- **Letterheads** — Company-specific header/footer templates applied to print formats.
- **Print Settings** — Font, page size, margins, and draft/cancelled watermarks.

---

### 4.18 File & Attachment System

**Location:** `mercantis core/Files/`

The File subsystem manages metadata and storage for file attachments.

- **`File` DocType** — Metadata record for each file: name, URL, size, MIME type, `isPrivate`, `attachedToDocType`, `attachedToName`, `attachedToField`.
- **Storage** — Files are stored in the app's sandboxed file system under `{site}/public/files/` (public) or `{site}/private/files/` (private).
- **Attachment limits** — DocTypes can declare `maxAttachments` and `makeAttachmentsPublic` in their definition.
- **Sync** — File metadata is synced via the mutation log. File content sync is deferred to the Cloud Adapter.

---

### 4.19 Customization Layer

**Location:** `mercantis core/Customization/`

The Customization Layer allows runtime schema and behaviour changes without modifying app manifests.

- **Custom Fields** — Users can add fields to existing DocTypes at runtime. Custom fields are stored separately and merged with standard fields at metadata resolution time.
- **Property Setters** — Override individual properties of existing fields (label, default, hidden, read_only) without modifying the DocType definition.
- **Client Scripts** — Lightweight expression-based scripts that run in the `ExpressionEngine` to customise form behaviour (show/hide fields, set values, validate).
- **Custom DocTypes** — Users can create entirely new DocTypes through the UI without an app manifest. These are stored in the `doctypes` table with `custom: true`.

---

### 4.20 Data Import / Export

**Location:** `mercantis core/ImportExport/`

The Data Import / Export subsystem handles bulk data operations.

- **Import** — CSV/JSON import with column-to-field mapping, validation against the DocType schema, and batch insert via `DocumentEngine`. Each imported row creates a proper `MutationRecord` for sync.
- **Export** — CSV/JSON export of document lists with field selection and filter support.
- **Fixtures** — App manifests can declare `fixtures` — lists of documents to be created on app install (e.g. default roles, default print formats).

---

### 4.21 Realtime Updates

**Location:** `mercantis core/Notifications/`

The Realtime Updates subsystem keeps the UI consistent with the underlying document state.

- **Local observation** — SwiftUI views subscribe to typed events (`DocumentSavedEvent`, `DocumentDeletedEvent`) to refresh automatically without polling.
- **Sync-triggered updates** — When `SyncEngine.receive()` applies remote mutations, it publishes the same typed events, causing UI refreshes as if changes were local.
- **Planned: WebSocket adapter** — For multi-device scenarios, a `RealtimeAdapter` protocol will allow push notifications from the cloud when remote changes occur. Core defines the protocol; the host app provides the implementation.

---

### 5.1 UI Shell

**Location:** `mercantis core/UIShell/` *(in progress)*

The UI Shell provides a generic, metadata-driven SwiftUI interface:

- **`NavigationShell`** — Default runtime shell. Top-level navigation uses `NavigationSplitView` on macOS/iPad and a tab shell on iPhone. Core sections are domain-neutral (Home, Reports, Dashboards, Recents, DocTypes, Modules, Settings). `DocTypes` is the canonical `DocType`-management destination and `Modules` is the canonical `Module`-management destination. Module records (for example, `Core`) remain valid data-model instances but are not exposed as primary sidebar groupings. Child-table metadata (`DocTypeField`, `DocTypePermission`) is managed inside the selected `DocType` workflow.
- **`FormBuilderView` (DocTypes → Visual Builder)** — Native macOS three-pane studio (`HSplitView`): controls palette (searchable grouped controls), metadata canvas (sections/groups projected from `ResolvedMeta` via `ResolvedMetaCanvasAdapter`), and inspector/activity panel (field properties + status history + timeline). `DocTypes` remains the canonical entry point; `Open Visual Builder` now opens a dedicated non-modal macOS window (via `WindowGroup` + `openWindow`) scoped to the selected DocType ID, rather than presenting a sheet. Canvas grouping currently derives from resolved field `section` and `column` hints. Drag/drop insertion is supported for palette-to-canvas fields, while richer layout authoring (explicit section/group entities and persistent ordering rules beyond field hints) remains a follow-up.
- **`GenericFormView`** — Dynamically renders a form from a `DocType` and a `Document`: text fields, toggles, date pickers, select dropdowns, child tables, etc.
- **`GenericListView`** — Sortable, filterable list/table of documents driven by `DocType` metadata.
- **`CommandBarView`** — Spotlight-like search overlay for navigating across DocTypes and documents.
- **Design system demos** — `mercantis core/Views/DesignSystem/` contains design-lab/demo surfaces and preview fixtures. These assets are intentionally non-default and do not define Core runtime behavior.

### 5.2 Reporting Engine

**Location:** `mercantis core/Reporting/` *(in progress)*

The Reporting Engine executes `ReportDefinition` queries against the local database and returns typed result sets. Reports are declared in app manifests and scoped by user roles.

### 5.3 Cloud Adapter

*(Planned)* A protocol-based adapter layer that connects the Sync Engine to a cloud backend. The adapter implementation is separate from Core; Core defines the interface.

---

## 6. Technology Choices

| Technology | Rationale |
|-----------|----------|
| **Swift** | Type safety, value semantics (`struct`/`enum`), strong concurrency model. |
| **SwiftUI** | Declarative UI that maps cleanly onto metadata-driven document rendering. |
| **SQLite / GRDB** | Reliable, zero-configuration, offline-capable relational store. GRDB provides a type-safe Swift API. See [ADR-002](Docs/ADR/ADR-002-sqlite-local-source-of-truth.md). |
| **macOS 14+ / iOS 17+** | Modern SwiftUI APIs (`NavigationSplitView`, `@Observable`, etc.). |

---

## 7. Directory Structure

The tree below reflects what is actually on disk today. Subsystems described in §§4.11–4.20 that are not yet implemented are listed in the "Planned, not on disk" block that follows. For a full doc-vs-code reconciliation see [`Docs/IMPLEMENTATION-STATUS.md`](Docs/IMPLEMENTATION-STATUS.md).

```
mercantis core/
├── mercantis_coreApp.swift       # @main SwiftUI entry point
├── AppRuntime/
│   ├── AppInstaller.swift        # Installs/uninstalls app manifests; wires ExtensionPointResolver + AutomationRunner
│   ├── AppManifest.swift         # Codable manifest struct
│   ├── AppRuntimeTypes.swift     # WorkflowDefinition, ReportDefinition, AutomationRule, DashboardDefinition, LocalizationBundle, …
│   ├── ExtensionPoints.swift     # DocumentEventSubscription, SchedulerEventDeclaration, ExtensionActionDeclaration
│   └── ExtensionPointResolver.swift # Binds manifest extension points to EventEmitter + scheduler
├── Automation/
│   ├── AutomationActionHandler.swift       # AutomationActionHandler protocol + AutomationContext + AutomationActionError
│   ├── AutomationActionRegistry.swift      # Registry keyed by actionType (ADR-025)
│   ├── BuiltInActionHandlers.swift         # set_value / set_status / send_notification / validate / assign
│   ├── AutomationSinks.swift               # NotificationLogWriter / AssignmentLogWriter + in-memory defaults
│   ├── AutomationRunner.swift              # Subscribes to document events, matches AppManifest.automationRules
│   └── AutomationActionDispatcher.swift    # Bridges registry → ExtensionActionDispatcher seam for P1.3
├── Customization/
│   ├── CustomField.swift         # Runtime field additions to existing DocTypes
│   └── PropertySetter.swift      # Per-field property overrides
├── DocumentEngine/
│   ├── Document.swift            # Document, ChildRow, SyncState
│   ├── DocumentEngine.swift      # save, delete, fetch, list, submit, cancel, amend
│   ├── DocumentVersion.swift     # DocumentVersion, FieldDiff (versioning/diff tracking)
│   └── ValidationPipeline.swift  # ValidationStage protocol, pipeline, DocumentValidationError
├── ExpressionEngine/
│   ├── ExpressionAST.swift            # ExpressionNode, LiteralValue, UnaryOperator, BinaryOperator, ExpressionSourceRange, lexer
│   ├── ExpressionParser.swift         # Recursive-descent parser → ExpressionNode AST; referencedFields, isConstant
│   ├── ExpressionEvaluator.swift      # Public façade: parse, evaluateBool/Formula (string + parsed), referencedFields, parse cache, constant folding, optional lookup resolver
│   └── DocumentLookupResolver.swift   # DocumentLookupResolver protocol + CachingDocumentLookupResolver (per-save invalidation, ADR-029)
├── Metadata/
│   ├── BuiltInDocTypes.swift     # Registers system DocTypes (Module, DocTypeField, DocTypePermission, …)
│   ├── DocType.swift             # DocType struct
│   ├── FieldDefinition.swift     # FieldDefinition, FieldType, FieldValue, FieldPermission
│   ├── IndexDefinition.swift     # IndexDefinition
│   ├── MetaComposer.swift        # Composes ResolvedMeta from base + custom fields + property setters
│   ├── MetadataRegistry.swift    # In-memory DocType cache (raw definitions)
│   ├── PermissionRule.swift      # PermissionRule
│   ├── ResolvedMeta.swift        # ResolvedMeta, ResolvedFieldDefinition
│   ├── SchemaValidator.swift     # Validates DocType definitions
│   └── SyncPolicy.swift          # SyncPolicy, ConflictResolution
├── Notifications/
│   └── EventEmitter.swift        # Typed event bus: subscribe<E>(_:handler:) → SubscriptionToken
├── Permissions/
│   └── PermissionEngine.swift    # canPerform / canAccessField / canAccessRow
├── Reporting/
│   └── ReportEngine.swift        # ReportEngine, ReportResult
├── Scheduling/
│   ├── ScheduledTask.swift          # key + appId + interval + dispatch + RetryPolicy
│   ├── CronExpression.swift         # 5-field cron parser + matcher
│   ├── SchedulerPersistence.swift   # scheduler_state read/write/clear
│   └── SchedulerService.swift       # ExtensionSchedulerRegistrar + tick loop
├── Storage/
│   ├── MercantisDatabase.swift   # GRDB DatabasePool wrapper
│   └── MigrationRunner.swift     # Versioned schema migrations (v1–v6)
├── SyncEngine/
│   ├── CloudAdapter.swift        # Protocol boundary + NoOpCloudAdapter (ADR-018)
│   ├── ConflictResolver.swift    # LWW / VCM / AO resolution
│   ├── MutationRecord.swift      # MutationRecord, MutationType, MutationStatus
│   └── SyncEngine.swift          # push, pull, applyRemote, resolveConflict
├── UIShell/
│   ├── CommandBarView.swift          # Spotlight-like search overlay
│   ├── DocTypeBuilderView.swift      # In-app DocType creation/editing (ADR-027, Phase 2)
│   ├── DocTypeListView.swift         # DocTypes management screen
│   ├── FormBuilderView.swift         # Three-pane macOS visual builder
│   ├── GenericFormView.swift         # Dynamic form renderer
│   ├── GenericListView.swift         # Sortable/filterable list renderer
│   ├── MercantisTheme.swift          # Design tokens
│   ├── NavigationShell.swift         # Top-level navigation shell
│   ├── RecordCollectionHostView.swift# List/form mode container
│   ├── RecordViewMode.swift          # list / form / detail modes
│   ├── RecordWorkspaceChrome.swift   # Top bar + sidebar + content scaffold
│   └── ResolvedMetaCanvasAdapter.swift# Projects ResolvedMeta onto the builder canvas
├── Views/
│   └── DesignSystem/             # Design-lab/demo surfaces and preview fixtures — not part of runtime Core (see §5.1)
└── Workflows/
    ├── WorkflowEngine.swift          # availableTransitions, transition
    └── WorkflowTransitionHistory.swift # Audit record of state changes
```

**Planned, not on disk.** The following subsystems are described elsewhere in this document but are not yet implemented. Track them via the linked ADRs and the corresponding `Docs/ENHANCEMENT-PROPOSAL.md` items:

| Subsystem | §s | ADRs | Proposal |
|---|---|---|---|
| `Cache/` — cross-subsystem `CacheManager` | §4.14 | — | P3.4 |
| `Files/` — attachments + sandboxed storage | §4.18 | — | P3.1 |
| `ImportExport/` — CSV/JSON importer + exporter + fixtures | §4.20 | — | P3.3 |
| `Printing/` — `PrintFormat`, `PDFGenerator`, `LetterHead` | §4.17 | — | P3.2 |

**SwiftPM module boundary.** `Package.swift` exposes two library products so Hub and third-party apps can pick the surface they need (ADR-007, P2.6, P2.7):

- `MercantisCore` — the headless engine. The target points at `mercantis core/` with `exclude: ["Assets.xcassets", "mercantis_coreApp.swift", "UIShell", "Views"]` — every engine subsystem above is part of the public package, with no SwiftUI / AppKit / UIKit imports anywhere in its transitive graph. CLI and server-side consumers depend on this product only.
- `MercantisCoreUI` — the metadata-driven SwiftUI shell (`GenericFormView`, `GenericListView`, `NavigationShell`, `DocTypeBuilderView`, `FormBuilderView`, `CommandBarView`, `RecordCollectionHostView`, …). Sources live in `mercantis core/UIShell/`. Depends on `MercantisCore`. Apps that want the out-of-the-box renderer add this product on the app target; apps that don't need SwiftUI keep using `MercantisCore` alone (P2.7).

GRDB is declared as a SwiftPM dependency on both library targets (`UIShell/DocTypeBuilderView.swift` queries `apps.payload` via GRDB to project installed `AppManifest`s into the builder context). The `mercantis` CLI executable depends on `MercantisCore` for its `install-app` / `list-apps` / `new-app` / `new-doctype` commands so both install surfaces share one schema and one `AppInstaller` pipeline (P2.3); the `SQLite3` system-library link is still wired for the patch commands (`migrate`, `create-patch`, `run-patch`), which operate on raw SQL patch files. A `MercantisCoreUITests` SwiftPM test target instantiates `GenericFormView` / `GenericListView` against an in-memory `DocumentEngine` so the new product can't bit-rot silently.

---

## 8. Architecture Decision Records

| ADR | Decision |
|-----|---------|
| [ADR-001](Docs/ADR/ADR-001-core-hub-split.md) | Core / Hub Split |
| [ADR-002](Docs/ADR/ADR-002-sqlite-local-source-of-truth.md) | SQLite as Local Source of Truth |
| [ADR-003](Docs/ADR/ADR-003-metadata-defined-doctypes.md) | Metadata-Defined DocTypes |
| [ADR-004](Docs/ADR/ADR-004-declarative-app-plugin-model.md) | Declarative App / Plugin Model |
| [ADR-005](Docs/ADR/ADR-005-sync-via-mutation-log.md) | Sync via Mutation Log |
| [ADR-006](Docs/ADR/ADR-006-financial-inventory-conflict-policy.md) | Financial & Inventory Conflict Policy |
| [ADR-007](Docs/ADR/ADR-007-hub-on-core-public-apis.md) | Hub Built Exclusively on Core Public APIs |
| [ADR-008](Docs/ADR/ADR-008-no-executable-plugins-ios.md) | No Arbitrary Downloaded Executable Plugins on iOS |
| [ADR-009](Docs/ADR/ADR-009-single-documents-table.md) | Single Documents Table with JSON Payload |
| [ADR-010](Docs/ADR/ADR-010-pure-client-side-architecture.md) | Pure Client-Side Architecture (No Server Component) |
| [ADR-011](Docs/ADR/ADR-011-multi-level-permission-model.md) | Multi-Level Permission Evaluation Model |
| [ADR-012](Docs/ADR/ADR-012-eventbus-internal-pubsub.md) | EventBus for Internal Pub/Sub *(Superseded by ADR-020)* |
| [ADR-013](Docs/ADR/ADR-013-submit-cancel-amend-lifecycle.md) | Submit / Cancel / Amend Document Lifecycle |
| [ADR-014](Docs/ADR/ADR-014-document-naming-strategy.md) | Document Naming Strategy |
| [ADR-015](Docs/ADR/ADR-015-declarative-hooks-app-extension.md) | Declarative Extension Points for App Extension |
| [ADR-016](Docs/ADR/ADR-016-metadata-driven-generic-ui.md) | Metadata-Driven Generic UI |
| [ADR-017](Docs/ADR/ADR-017-expression-engine-scope-sandboxing.md) | Expression Engine Scope and Sandboxing |
| [ADR-018](Docs/ADR/ADR-018-cloud-adapter-protocol-boundary.md) | Cloud Adapter as Protocol Boundary |
| [ADR-019](Docs/ADR/ADR-019-automation-execution-model.md) | Automation Execution Model |
| [ADR-020](Docs/ADR/ADR-020-typed-event-system.md) | Typed Event System |
| [ADR-021](Docs/ADR/ADR-021-metadata-composition-resolved-meta.md) | Metadata Composition and ResolvedMeta |
| [ADR-022](Docs/ADR/ADR-022-document-validation-pipeline.md) | Document Validation Pipeline |
| [ADR-023](Docs/ADR/ADR-023-optimistic-concurrency-modified-timestamp.md) | Optimistic Concurrency via Modified Timestamp |
| [ADR-024](Docs/ADR/ADR-024-document-versioning-diff-tracking.md) | Document Versioning and Field-Level Diff Tracking |
| [ADR-025](Docs/ADR/ADR-025-automation-action-registry.md) | Automation Action Registry |
| [ADR-026](Docs/ADR/ADR-026-three-layer-extensibility-model.md) | Three-Layer Extensibility Model |
| [ADR-027](Docs/ADR/ADR-027-doctype-creation-strategy.md) | DocType Creation Tooling — Phased Strategy |
| [ADR-028](Docs/ADR/ADR-028-sync-queue-pruning.md) | Sync Queue Pruning Strategy |
| [ADR-029](Docs/ADR/ADR-029-cross-document-lookup.md) | Cross-Document `lookup()` in the Expression Engine |
