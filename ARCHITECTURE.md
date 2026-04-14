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
│   │ (planned) │   │  (manifest  │   │  (sandboxed eval)  │                 │
│   │           │   │  installer) │   │                    │                 │
│   └─────┬─────┘   └──────┬──────┘   └─────────┬──────────┘                 │
│         │                │                    │                             │
│   ┌─────▼────────────────▼────────────────────▼────────────────────────┐   │
│   │                         DocumentEngine                              │   │
│   │  save() · delete() · fetch() · list() · submit() · cancel() ·      │   │
│   │  amend() · SchemaValidator · lifecycle events · mutation logging    │   │
│   └────────────────────────────┬────────────────────────────────────────┘   │
│         │           │          │           │            │                   │
│   ┌─────▼──────┐  ┌─▼──────────▼──┐  ┌────▼──────┐  ┌─▼──────────────┐   │
│   │ Permissions│  │ WorkflowEngine │  │ EventBus  │  │  NamingService │   │
│   │  Engine    │  │ (state machine)│  │(Notif'ns) │  │SchedulerService│   │
│   └─────┬──────┘  └───────┬────────┘  └───────────┘  └────────────────┘   │
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
│   │  (DocType registry)│  │  (planned)   │  │            │  │(planned) │  │
│   └────────────────────┘  └──────────────┘  └────────────┘  └──────────┘  │
│                                                                             │
│   ┌────────────────────────┐  ┌───────────────────────┐                   │
│   │  CustomizationEngine   │  │    ImportExport        │                   │
│   │  (Custom Fields, Props,│  │  (CSV/JSON import/     │                   │
│   │   Client Scripts)      │  │   export, fixtures)    │                   │
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

See [ADR-003](Docs/ADR/ADR-003-metadata-defined-doctypes.md).

---

### 4.2 Document Engine

**Location:** `mercantis core/DocumentEngine/`

The Document Engine handles all CRUD operations on `Document` instances. A `Document` is a generic container — its structure is determined entirely by its `DocType` metadata.

Key responsibilities:
- **`save(_:)`** — Validate against the DocType via `SchemaValidator`, serialize to JSON, write to the `documents` table, and atomically append a `MutationRecord` to `sync_queue`. Fire a `document.saved` event on the `EventBus`.
- **`delete(docType:id:)`** — Delete from `documents`, cascade-delete child rows from `document_children`, append a `deleteDocument` mutation, fire a `document.deleted` event.
- **`fetch(docType:id:)`** — Query `documents`, deserialize the JSON payload into a `Document`.
- **`list(docType:filters:)`** — Query with optional WHERE clauses, return a list of `Document` objects.

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

The Permissions Engine evaluates multi-level access rules before any document operation proceeds.

Permission levels (evaluated in order):
1. **App-level** — Is the user's role allowed to use this module/app at all?
2. **DocType-level** — `PermissionRule` per role: read, write, create, delete, submit, amend.
3. **Field-level** — `FieldPermission.readRoles` / `writeRoles` per field.
4. **Row-level** — Arbitrary condition filter (e.g. user can only see documents for their warehouse).
5. **Workflow action level** — `WorkflowTransition.allowedRoles` guards each transition.

Key methods:
- `canPerform(operation:on:userRoles:)` — DocType-level check.
- `canAccessField(fieldKey:on:userRoles:operation:)` — Field-level check.
- `canAccessRow(document:userRoles:rowFilter:)` — Row-level check.

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

The evaluator operates with **no access to the file system, network, or arbitrary Swift APIs**.

---

### 4.8 Notifications & Events

**Location:** `mercantis core/Notifications/`

`EventBus` is a simple in-process publish/subscribe bus. Subsystems publish named events; interested components subscribe to them.

Standard event names:
- `document.saved` — fired by `DocumentEngine.save(_:)`
- `document.deleted` — fired by `DocumentEngine.delete(docType:id:)`
- `workflow.transition` — fired by `WorkflowEngine.transition(...)`
- `app.installed` — fired by `AppInstaller.install(_:)`

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

DocTypes opt into this lifecycle via `isSubmittable: true` in the DocType definition. Fields marked `allowOnSubmit: true` can be edited after submission. Amending a cancelled document creates a new Draft linked via `amendedFrom`, providing a complete correction history. The `immutableAfterSubmit` sync policy flag (from [ADR-006](Docs/ADR/ADR-006-financial-inventory-conflict-policy.md)) enforces immutability at the sync layer.

Key methods: `DocumentEngine.submit(_:)`, `DocumentEngine.cancel(_:)`, `DocumentEngine.amend(_:)`.

See [ADR-009](Docs/ADR/ADR-009-single-documents-table.md) and [ADR-013](Docs/ADR/ADR-013-submit-cancel-amend-lifecycle.md).

---

### 4.11 Naming System

**Location:** `mercantis core/Naming/`

The Naming System determines the `id` / `name` of each document at save time. The naming strategy is declared per DocType via the `autoname` property.

Supported strategies:

- **UUID (default)** — UUID v7, time-ordered, globally unique. Recommended for offline-first DocTypes.
- **Naming Series** — Pattern-based sequential naming (e.g. `SINV-.YYYY.-.####`). Supports date tokens (`YY`, `YYYY`, `MM`, `DD`), field references, and hash placeholders.
- **Field-based** — Derive the name from a field value (e.g. `field:email`).
- **Autoincrement** — Integer sequence per DocType. Requires server coordination; not recommended for offline-first.
- **Prompt** — The user enters the name manually.
- **Expression** — Format string with field interpolation (e.g. `format:{company_abbr}-{naming_series}`).

A `DocumentNamingRule` system allows conditional naming rules with priority ordering — different patterns can apply based on document field values.

See [ADR-014](Docs/ADR/ADR-014-document-naming-strategy.md).

---

### 4.12 Hooks / Extension Points

**Location:** `mercantis core/AppRuntime/`

The Hooks subsystem provides a declarative mechanism for apps to wire into Core lifecycle events without modifying Core code.

Apps declare hooks in their manifest under the `hooks` section. Supported hook types:

- `doc_events` — Subscribe to document lifecycle events (`on_update`, `after_insert`, `on_submit`, `on_cancel`, `on_trash`, `on_change`) per DocType or globally (`*`).
- `scheduler_events` — Register functions for periodic execution (`all`, `daily`, `hourly`, `weekly`, `monthly`, `cron`).
- `override_doctype_class` — Extend or replace the controller for a DocType.
- `override_whitelisted_methods` — Redirect API calls to custom implementations.

Hooks are resolved at install time by `AppInstaller`, which collects hook declarations from all installed app manifests and registers them as `EventBus` subscriptions or `SchedulerService` entries. Since no executable code is downloaded, hook handlers are limited to built-in action types.

The `EventBus` (§4.8) fires events; hooks are the declarative mechanism for apps to subscribe to them.

See [ADR-015](Docs/ADR/ADR-015-declarative-hooks-app-extension.md).

---

### 4.13 Background Tasks & Scheduling

**Location:** `mercantis core/Scheduling/`

Because Mercantis Core is a pure client-side library (no server process), background tasks execute within the app process using Swift Concurrency (`Task`, `TaskGroup`).

- **Scheduled tasks** — A `SchedulerService` checks for due tasks on app launch and periodically while the app is active. Tasks are declared in app manifests under `scheduler_events`.
- **Task types:** `all` (every 5 min), `hourly`, `daily`, `weekly`, `monthly`, `cron` (custom cron expression).
- **Queue categories:** `short` (< 5 s, UI-blocking permitted), `default` (< 60 s), `long` (> 60 s, runs as a background task).
- Failed tasks are retried with exponential backoff. Failures are logged to `audit_log`.
- Sync operations (push/receive) are themselves scheduled background tasks.

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

- `DocumentEngine` — `save(_:)`, `delete(docType:id:)`, `fetch(docType:id:)`, `list(docType:filters:sortBy:limit:)`, `submit(_:)`, `cancel(_:)`, `amend(_:)`
- `MetadataRegistry` — `register(_:)`, `get(docType:)`, `all()`, `unregister(docType:)`
- `PermissionEngine` — `canPerform(operation:on:userRoles:)`, `canAccessField(...)`, `canAccessRow(...)`
- `WorkflowEngine` — `availableTransitions(...)`, `transition(...)`
- `SyncEngine` — `push()`, `receive()`, `applyRemote(_:)`
- `ExpressionEvaluator` — `evaluateBool(_:context:)`, `evaluateFormula(_:context:)`
- `EventBus` — `subscribe(event:handler:)`, `publish(event:payload:)`
- `AppInstaller` — `install(_:)`, `uninstall(appId:)`

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

- **Local observation** — SwiftUI views observe the `EventBus` for `document.saved` and `document.deleted` events to refresh automatically without polling.
- **Sync-triggered updates** — When `SyncEngine.receive()` applies remote mutations, it fires the same `EventBus` events, causing UI refreshes as if changes were local.
- **Planned: WebSocket adapter** — For multi-device scenarios, a `RealtimeAdapter` protocol will allow push notifications from the cloud when remote changes occur. Core defines the protocol; the host app provides the implementation.

---

### 5.1 UI Shell

**Location:** `mercantis core/UIShell/` *(in progress)*

The UI Shell provides a generic, metadata-driven SwiftUI interface:

- **`NavigationShell`** — Top-level navigation: `NavigationSplitView` on macOS/iPad, tab bar on iPhone. Sections: Home, Inbox, Search, Modules, Reports, Settings.
- **`GenericFormView`** — Dynamically renders a form from a `DocType` and a `Document`: text fields, toggles, date pickers, select dropdowns, child tables, etc.
- **`GenericListView`** — Sortable, filterable list/table of documents driven by `DocType` metadata.
- **`CommandBarView`** — Spotlight-like search overlay for navigating across DocTypes and documents.

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

```
mercantis core/
├── AppRuntime/
│   ├── AppInstaller.swift        # Installs/uninstalls app manifests
│   ├── AppManifest.swift         # Codable manifest struct
│   └── AppRuntimeTypes.swift     # WorkflowDefinition, ReportDefinition, AutomationRule, …
├── Cache/
│   └── CacheManager.swift        # Generation-counter cache; metadata, document, and query caches
├── Customization/
│   ├── ClientScript.swift        # Expression-based form scripts
│   ├── CustomField.swift         # Runtime field additions to existing DocTypes
│   └── PropertySetter.swift      # Per-field property overrides
├── DocumentEngine/
│   ├── Document.swift            # Document, ChildRow, SyncState
│   └── DocumentEngine.swift      # save, delete, fetch, list, submit, cancel, amend
├── ExpressionEngine/
│   └── ExpressionEvaluator.swift # evaluateBool, evaluateFormula
├── Files/
│   ├── File.swift                # File DocType metadata record
│   └── FileManager.swift         # Sandboxed file storage; public/private paths
├── ImportExport/
│   ├── DataExporter.swift        # CSV/JSON export with field selection
│   └── DataImporter.swift        # CSV/JSON import with schema validation
├── Metadata/
│   ├── DocType.swift             # DocType struct
│   ├── FieldDefinition.swift     # FieldDefinition, FieldType, FieldValue, FieldPermission
│   ├── IndexDefinition.swift     # IndexDefinition
│   ├── MetadataRegistry.swift    # In-memory DocType cache
│   ├── PermissionRule.swift      # PermissionRule
│   ├── SchemaValidator.swift     # Validates DocType definitions
│   └── SyncPolicy.swift          # SyncPolicy, ConflictResolution
├── Naming/
│   ├── DocumentNamingRule.swift  # Conditional naming rules with priority ordering
│   ├── NamingSeries.swift        # Pattern-based sequential naming (SINV-.YYYY.-.####)
│   └── NamingService.swift       # Resolves autoname strategy at save time
├── Notifications/
│   └── EventBus.swift            # In-process publish/subscribe
├── Permissions/
│   └── PermissionEngine.swift    # canPerform, canAccessField, canAccessRow
├── Printing/
│   ├── LetterHead.swift          # Company header/footer templates
│   ├── PDFGenerator.swift        # Protocol-based PDF renderer adapter
│   └── PrintFormat.swift         # Per-DocType print format definition
├── Reporting/
│   └── ReportEngine.swift        # ReportEngine, ReportResult
├── Scheduling/
│   ├── ScheduledTask.swift       # Task declaration: type, handler, retry policy
│   └── SchedulerService.swift    # Evaluates due tasks; exponential-backoff retry
├── Storage/
│   ├── MercantisDatabase.swift   # GRDB DatabasePool wrapper
│   └── MigrationRunner.swift     # Versioned schema migrations
├── SyncEngine/
│   ├── ConflictResolver.swift    # LWW / VCM / AO resolution
│   ├── MutationRecord.swift      # MutationRecord, MutationType, MutationStatus
│   └── SyncEngine.swift          # push, applyRemote, resolveConflict
├── UIShell/
│   ├── CommandBarView.swift      # Spotlight-like search overlay
│   ├── GenericFormView.swift     # Dynamic form renderer
│   ├── GenericListView.swift     # Sortable/filterable list renderer
│   └── NavigationShell.swift     # Top-level navigation shell
└── Workflows/
    ├── WorkflowEngine.swift          # availableTransitions, transition
    └── WorkflowTransitionHistory.swift # Audit record of state changes
```

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
| [ADR-012](Docs/ADR/ADR-012-eventbus-internal-pubsub.md) | EventBus for Internal Pub/Sub |
| [ADR-013](Docs/ADR/ADR-013-submit-cancel-amend-lifecycle.md) | Submit / Cancel / Amend Document Lifecycle |
| [ADR-014](Docs/ADR/ADR-014-document-naming-strategy.md) | Document Naming Strategy |
| [ADR-015](Docs/ADR/ADR-015-declarative-hooks-app-extension.md) | Declarative Hooks for App Extension |
| [ADR-016](Docs/ADR/ADR-016-metadata-driven-generic-ui.md) | Metadata-Driven Generic UI |
| [ADR-017](Docs/ADR/ADR-017-expression-engine-scope-sandboxing.md) | Expression Engine Scope and Sandboxing |
| [ADR-018](Docs/ADR/ADR-018-cloud-adapter-protocol-boundary.md) | Cloud Adapter as Protocol Boundary |
| [ADR-019](Docs/ADR/ADR-019-automation-execution-model.md) | Automation Execution Model |
