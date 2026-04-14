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

DocTypes opt into the lifecycle via `isSubmittable: true` in the DocType definition. Submitted documents are immutable except for fields marked `allowOnSubmit: true`. Cancellation sets `docstatus = 2` but does not delete the document. Amending a cancelled document creates a new Draft with `amendedFrom` pointing to the cancelled document, providing a complete audit chain.

The `immutableAfterSubmit` sync policy flag (ADR-006) enforces this at the sync layer — the SyncEngine rejects remote mutations that attempt to modify a submitted document.

## Consequences

**Positive:**
- Full audit trail for financial documents.
- Regulatory compliance — invoices cannot be silently modified after approval.
- The amend chain provides a complete history of corrections.

**Negative:**
- Users cannot directly "fix" a submitted document — they must cancel and amend, which is unintuitive for simple corrections.
- Extra complexity in DocumentEngine (submit/cancel/amend code paths).
- Child table rows also become immutable on submit, requiring the same cancel-and-amend process.

**Neutral:**
- Non-submittable DocTypes are unaffected — they stay in Draft forever and can always be edited.

---

*See also: [ADR-006 — Financial & Inventory Conflict Policy](ADR-006-financial-inventory-conflict-policy.md), [ADR-009 — Single Documents Table with JSON Payload](ADR-009-single-documents-table.md)*
