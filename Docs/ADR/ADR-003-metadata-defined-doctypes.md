# ADR-003 — Metadata-Defined DocTypes

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

A traditional approach to business application development hard-codes each entity type (Customer, Invoice, Product) as a distinct model class with its own table and migration. This creates several problems:

- Adding a custom field requires a code change and schema migration.
- Permissions, workflows, and validation rules are scattered across model, controller, and UI layers.
- Domain logic bleeds into the platform layer.
- Reusing the platform for different verticals requires forking the codebase.

## Decision

**Every entity in Mercantis Core is described by a `DocType`** — a metadata definition that lives in the database and is declared in app manifests (or built-in system manifests). No Swift model class is created per entity type.

A `DocType` carries:
- **`FieldDefinition` list** — key, type (`text`, `number`, `date`, `link`, `table`, `formula`, etc.), validation rules, visibility/read-only expressions, and per-field permission rules.
- **`PermissionRule` list** — role-based read/write/create/delete/submit/amend flags.
- **`SyncPolicy`** — conflict resolution strategy and immutability flag.
- **`IndexDefinition` list** — fields to extract into indexed columns.
- **`workflowId`** — optional reference to a `WorkflowDefinition`.
- **`searchFields`** and **`titleField`** — used by the UI shell's generic list and command bar.

`SchemaValidator` validates every `DocType` before it is committed to the registry, catching empty IDs, duplicate field keys, missing linked DocTypes, and other structural errors.

`MetadataRegistry` provides an in-memory cache of registered DocTypes backed by the `doctypes` table.

At runtime, raw DocType definitions are not used directly. A `MetaComposer` composes a `ResolvedMeta` object by merging three layers:

1. **Base definition** — the `DocType` as declared in the app manifest or `doctypes` table.
2. **Custom fields** — user-added fields stored in the `custom_fields` table.
3. **Property overrides** — per-field property overrides stored in the `property_setters` table (label, hidden, read_only, default, etc.).

The resulting `ResolvedMeta` is what all runtime consumers (DocumentEngine, PermissionEngine, UIShell, ExpressionEngine) use. Raw `DocType` definitions are an internal detail of MetadataRegistry. See [ADR-021](ADR-021-metadata-composition-resolved-meta.md).

## Consequences

**Positive:**
- Custom fields, DocTypes, and modules can be added entirely through app manifests — no code changes needed.
- Permissions, validation, sync policy, and workflow are co-located in the DocType definition.
- The Document Engine can validate any document type without knowing its schema at compile time.
- The UI Shell can render any DocType generically.

**Negative:**
- The metadata registry becomes a critical dependency; startup must load DocTypes before any document operations can proceed.
- Type safety for individual field values is weaker than a hard-coded struct.
- Some queries that would benefit from fully normalised tables must use JSON extraction instead.

**Neutral:**
- System DocTypes (e.g. `AuditLog`, `SyncQueue`) are declared in Core's built-in manifest rather than in app manifests.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md), [ADR-021 — Metadata Composition and ResolvedMeta](ADR-021-metadata-composition-resolved-meta.md)*
