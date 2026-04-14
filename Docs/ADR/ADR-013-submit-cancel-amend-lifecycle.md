# ADR-013 — Submit / Cancel / Amend Document Lifecycle

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe implements a `docstatus` state machine (0=Draft, 1=Submitted, 2=Cancelled) with strict transition rules and an "Amend" workflow that creates a new document linked via `amended_from`. This lifecycle is essential for financial and regulatory documents (invoices, journal entries) that must be immutable once approved.

Mercantis Core targets ERP use cases where document immutability is a regulatory requirement — submitted invoices must not be silently modified.

## Decision

Mercantis Core adopts the same `docstatus` model:

- **Draft (0)** — Document is editable. Default state on creation.
- **Submitted (1)** — Document is immutable. Set by `DocumentEngine.submit(_:)`.
- **Cancelled (2)** — Document is immutable. Set by `DocumentEngine.cancel(_:)`.

**DocType opt-in:** DocTypes opt into this lifecycle via `isSubmittable: true` in the DocType definition. Non-submittable DocTypes remain in Draft forever.

**Immutability enforcement:** Submitted documents reject any field write at the DocumentEngine layer, except for fields explicitly marked `allowOnSubmit: true`. Attempting to write a non-`allowOnSubmit` field on a submitted document throws a validation error before the save reaches the database.

**Cancel link integrity check:** Before cancelling a submitted document, DocumentEngine checks for linked submitted documents that reference it. If any downstream submitted document holds a Link field pointing to this document, the cancel is rejected with a descriptive error listing the blocking documents. This prevents dangling references in the financial audit chain.

**Amend:** Amending a cancelled document creates a new Draft with:
- All fields copied from the cancelled document.
- `docstatus` reset to `0` (Draft).
- An `amendedFrom` Link field set to the cancelled document's name.
- A new document name (resolved by the naming strategy).

The `immutableAfterSubmit` sync policy flag (ADR-006) enforces immutability at the sync layer — the SyncEngine rejects remote mutations that attempt to modify a submitted document.

## Consequences

**Positive:**
- Full audit trail for financial documents.
- Regulatory compliance — invoices cannot be silently modified after approval.
- The amend chain provides a complete history of corrections.
- Cancel link integrity prevents orphaned downstream documents.

**Negative:**
- Users cannot directly "fix" a submitted document — they must cancel and amend, which is unintuitive for simple corrections.
- Extra complexity in DocumentEngine (submit/cancel/amend code paths).
- Child table rows also become immutable on submit, requiring the same cancel-and-amend process.
- Link integrity check on cancel requires querying all DocTypes with Link fields pointing to the cancelled document.

**Neutral:**
- Non-submittable DocTypes are unaffected — they stay in Draft forever and can always be edited.

---

*See also: [ADR-006 — Financial & Inventory Conflict Policy](ADR-006-financial-inventory-conflict-policy.md), [ADR-009 — Single Documents Table with JSON Payload](ADR-009-single-documents-table.md), [ADR-024 — Document Versioning and Field-Level Diff Tracking](ADR-024-document-versioning-diff-tracking.md)*
