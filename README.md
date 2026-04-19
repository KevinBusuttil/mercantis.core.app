# Mercantis Core

> The open, offline-first, metadata-driven platform layer for building business applications.

## What is Mercantis Core?

Mercantis Core is the general-purpose platform layer that provides the foundational infrastructure for any business application built on the Mercantis ecosystem. It handles documents, workflows, sync, permissions, and app installation — all without knowing anything about specific business domains.

[Mercantis Hub](https://github.com/KevinBusuttil/mercantis.app) is the first-party ERP application built entirely on top of Core's public APIs.

## Key Capabilities

- **Metadata-driven documents** — Every entity is a `DocType` defined in JSON/YAML. No schema migrations for business data.
- **Offline-first sync** — Every write produces a `MutationRecord`; a mutation log drives cloud sync automatically.
- **Declarative plugin model** — Apps are manifest files, not binaries. Business logic runs in a sandboxed expression engine.
- **Multi-level permissions** — App → DocType → field → row → workflow action, evaluated at runtime.
- **Workflow engine** — State-machine transitions with role guards and condition expressions.
- **Document lifecycle** — Submit/cancel/amend flow for submittable DocTypes, including amendment lineage.
- **Expression engine** — Sandboxed evaluator for boolean conditions and formula fields.
- **Conflict resolution** — Three policies per DocType: Last-Write-Wins, Version-Checked Merge, Append-Only.

## Project Status

⚠️ **Early development.** The platform is still evolving, but several major subsystems are now concretely implemented — including app install/uninstall mutation flow, sync push/pull/apply flow, the cloud adapter protocol boundary, submit/cancel/amend document lifecycle, and migration support for lifecycle fields such as `docStatus` and `amendedFrom`.

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full architecture document, including subsystem descriptions, design principles, and an ASCII diagram.

## Runtime UX Boundary

- The default app runtime launches into the domain-neutral `NavigationShell` (`mercantis core/UIShell/NavigationShell.swift`).
- Core navigation is platform/studio oriented (Home, Reports, Dashboards, Recents, DocTypes, Modules, Settings) and metadata-driven.
- `DocTypes` is the canonical screen for managing `DocType` records; creating DocTypes and opening Visual Builder both happen from this workflow.
- `Modules` is the canonical screen for managing `Module` records.
- `Core` remains a `Module` document instance in the data model, but is not rendered as a primary sidebar grouping.
- Child-table metadata (`DocTypeField`, `DocTypePermission`) stays embedded in the selected `DocType` workflow, not top-level navigation.
- `mercantis core/Views/DesignSystem/` contains design-lab/demo surfaces and preview fixtures. They are preserved for UI exploration, but are not the default Core product path.

## Architecture Decision Records

All architectural decisions are recorded in [`Docs/ADR/`](./Docs/ADR/). See the [ADR index](./Docs/ADR/README.md) for a summary table.

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Language  | Swift 5.9+ |
| UI        | SwiftUI |
| Local DB  | SQLite via [GRDB](https://github.com/groue/GRDB.swift) |
| Targets   | macOS 14+, iOS 17+ |

## Directory Structure

```
mercantis core/
├── AppRuntime/          # AppManifest, AppInstaller — declarative plugin model
├── DocumentEngine/      # CRUD, lifecycle, atomic mutation logging
├── ExpressionEngine/    # Sandboxed boolean + formula evaluator
├── Metadata/            # DocType registry, FieldDefinition, SchemaValidator, SyncPolicy
├── Notifications/       # Event system (transitioning from EventBus toward typed EventEmitter model)
├── Permissions/         # Multi-level permission evaluation
├── Reporting/           # ReportEngine — query and aggregate document data
├── Storage/             # MercantisDatabase (GRDB), MigrationRunner
├── SyncEngine/          # Mutation log, push/receive/apply/acknowledge, conflict resolution
├── UIShell/             # SwiftUI shell — navigation, generic form/list, command bar
└── Workflows/           # State-machine transitions, role guards, transition history
```
