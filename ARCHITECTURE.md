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

---

## 3. Subsystem Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mercantis Core                           │
│                                                                 │
│   ┌───────────┐   ┌─────────────┐   ┌────────────────────────┐ │
│   │  UIShell  │   │ AppRuntime  │   │   ExpressionEngine     │ │
│   │ (planned) │   │  (manifest  │   │  (sandboxed eval)      │ │
│   │           │   │  installer) │   │                        │ │
│   └─────┬─────┘   └──────┬──────┘   └───────────┬────────────┘ │
│         │                │                       │              │
│   ┌─────▼────────────────▼───────────────────────▼────────────┐ │
│   │                  DocumentEngine                            │ │
│   │   save() · delete() · fetch() · list()                     │ │
│   │   SchemaValidator · lifecycle events · mutation logging    │ │
│   └─────────────────────────┬──────────────────────────────────┘ │
│         │                   │                   │              │
│   ┌─────▼──────┐   ┌────────▼───────┐  ┌───────▼───────────┐ │
│   │ Permissions│   │ WorkflowEngine │  │   Notifications   │ │
│   │  Engine    │   │ (state machine)│  │    EventBus       │ │
│   └─────┬──────┘   └────────┬───────┘  └───────────────────┘ │
│         │                   │                                  │
│   ┌─────▼───────────────────▼──────────────────────────────┐  │
│   │                  Storage (GRDB / SQLite)                │  │
│   │   MercantisDatabase · MigrationRunner                   │  │
│   └─────────────────────────┬──────────────────────────────┘  │
│                             │                                   │
│   ┌─────────────────────────▼──────────────────────────────┐   │
│   │                    SyncEngine                           │   │
│   │   MutationRecord · push · receive · apply · acknowledge │   │
│   │   ConflictResolver (LWW | VCM | AO)                    │   │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   ┌──────────────────────┐   ┌──────────────────────────────┐  │
│   │   Metadata Registry  │   │      ReportEngine            │  │
│   │  (DocType registry)  │   │       (planned)              │  │
│   └──────────────────────┘   └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
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

## 5. Planned Subsystems

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
├── DocumentEngine/
│   ├── Document.swift            # Document, ChildRow, SyncState
│   └── DocumentEngine.swift      # save, delete, fetch, list
├── ExpressionEngine/
│   └── ExpressionEvaluator.swift # evaluateBool, evaluateFormula
├── Metadata/
│   ├── DocType.swift             # DocType struct
│   ├── FieldDefinition.swift     # FieldDefinition, FieldType, FieldValue, FieldPermission
│   ├── IndexDefinition.swift     # IndexDefinition
│   ├── MetadataRegistry.swift    # In-memory DocType cache
│   ├── PermissionRule.swift      # PermissionRule
│   ├── SchemaValidator.swift     # Validates DocType definitions
│   └── SyncPolicy.swift          # SyncPolicy, ConflictResolution
├── Notifications/
│   └── EventBus.swift            # In-process publish/subscribe
├── Permissions/
│   └── PermissionEngine.swift    # canPerform, canAccessField, canAccessRow
├── Reporting/
│   └── ReportEngine.swift        # ReportEngine, ReportResult
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
