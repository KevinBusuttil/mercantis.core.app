# ADR-027 — DocType Creation Tooling — Phased Strategy

**Status:** Accepted

---

## Context

Frappe allows creating DocTypes entirely from the browser UI (via the DocType list → "Create New DocType" dialog → Form Builder for adding fields, permissions, and settings). In Mercantis Core, DocTypes are currently defined by hand-writing JSON inside app manifests or directly in the `doctypes` table. This is a usability gap that affects developer velocity and prevents non-developers from defining data models. The Customization Layer (§4.19 in ARCHITECTURE.md) already specifies that "Custom DocTypes — Users can create entirely new DocTypes through the UI without an app manifest" — but no concrete UI or tooling exists yet.

## Decision

DocType creation tooling is delivered in three phases:

### Phase 1 — CLI `new-doctype` command (current)

An interactive `mercantis new-doctype` CLI command scaffolds DocType definitions step by step. It prompts for the DocType name, module, type flags (submittable, single, child table), naming strategy, fields (key, label, type, options, required), and permission rules. Output is either appended to an existing app manifest or written as a standalone `.doctype.json` file. This phase targets developers building apps via manifests.

### Phase 2 — In-app DocType Builder view

A `DocTypeBuilderView` in the UIShell allows creating and editing DocTypes from within the running app. The approach is self-referential: DocType is itself treated as a document type. A system DocType called `DocType` is declared in Core's built-in manifest, with fields for name, module, flags, a child table of `FieldDefinition` rows, and a child table of `PermissionRule` rows. `GenericFormView` renders this meta-DocType automatically. On save, instead of writing to the `documents` table, the save hook calls `SchemaValidator.validate()` → `MetadataRegistry.register()` to register the new DocType. Custom DocTypes created this way are stored with `custom: true` in the `doctypes` table. This gives Frappe-level parity for non-developer users within a native iOS/macOS app.

### Phase 3 — Visual drag-and-drop Form Builder

An upgrade to Phase 2 that adds a drag-and-drop field designer. Users drag field types from a palette onto a canvas with sections and columns, configure properties in an inspector panel, and see a live preview rendered by `GenericFormView` in read-only mode. Uses SwiftUI `draggable()` / `dropDestination()` (macOS 14+ / iOS 17+). This phase targets a best-in-class no-code experience but is only justified once Phase 2 is proven in production.

## Consequences

**Positive:**
- Phase 1 unblocks developers immediately with no UI work.
- Phase 2 reuses existing GenericFormView and MetadataRegistry infrastructure — minimal new code.
- Phase 3 provides a competitive no-code UX beyond what Frappe offers natively.
- Each phase builds on the previous one; no throwaway work.

**Negative:**
- Until Phase 2 is complete, non-developers cannot create DocTypes.
- The self-referential "DocType as a DocType" pattern in Phase 2 requires careful bootstrapping (the meta-DocType must exist before any other DocType can be created through the UI).
- Phase 3's drag-and-drop is constrained by SwiftUI's current drag API maturity.

**Neutral:**
- All three phases write to the same `doctypes` table and use the same `SchemaValidator` and `MetadataRegistry` APIs. DocTypes created by any phase are interchangeable.

References: ADR-003 (Metadata-Defined DocTypes), ADR-004 (Declarative App/Plugin Model), ADR-016 (Metadata-Driven Generic UI), ARCHITECTURE.md §4.19 (Customization Layer).
