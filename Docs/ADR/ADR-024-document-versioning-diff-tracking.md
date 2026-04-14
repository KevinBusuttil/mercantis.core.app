# ADR-024 — Document Versioning and Field-Level Diff Tracking

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

The existing `audit_log` table records that a document was saved, but does not record what changed. For audit-sensitive documents (invoices, journal entries, purchase orders), regulators and business owners need a complete field-by-field change history: which fields changed, what the old value was, and what the new value is.

Frappe provides a "Version" DocType that stores field diffs per save. Mercantis needs an equivalent that integrates with its offline-first, JSON-payload document model.

## Decision

On every `DocumentEngine.save(_:)`, before writing the new payload to the `documents` table, `DocumentEngine` computes a **field-level diff**:

1. Load the current document payload from the database.
2. Compare field by field against the incoming document.
3. Record all changed fields as `(fieldKey, oldValue, newValue)` tuples.

The diff is stored as a `DocumentVersion` record in a `document_versions` table:

```swift
struct DocumentVersion {
    let id: String           // UUID v7
    let documentId: String
    let docType: String
    let savedAt: Date
    let savedBy: String      // userId
    let fieldDiffs: [FieldDiff]
}

struct FieldDiff {
    let fieldKey: String
    let oldValue: FieldValue?
    let newValue: FieldValue?
}
```

`DocumentVersion` records are append-only. They are never modified or deleted (immutable audit trail). On document delete, versions are retained.

Child table row diffs (added, removed, or modified rows) are included in the diff as structured entries with the child row's `rowIndex` and field-level changes within that row.

`DocumentVersion` records are synced via the mutation log with an append-only conflict policy (ADR-005, ADR-006).

## Consequences

**Positive:**
- Complete field-level change history for every document save.
- Enables compliance and audit queries: "show me all changes to this invoice".
- Diffs are stored separately from the document — the main `documents` table is not affected.
- Append-only storage prevents tampering.

**Negative:**
- Storage overhead: every save writes a version record. High-frequency saves (automation-driven) accumulate versions quickly.
- Diff computation adds a read + compare step to every save path.
- No built-in version pruning strategy (planned for a future ADR — see ARCHITECTURE-CHANGELOG.md).

**Neutral:**
- The version table is queryable via standard `DocumentEngine.list()` by treating `DocumentVersion` as a DocType.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md), [ADR-013 — Submit / Cancel / Amend Document Lifecycle](ADR-013-submit-cancel-amend-lifecycle.md)*
