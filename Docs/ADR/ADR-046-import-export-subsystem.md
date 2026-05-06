# ADR-046 — Import / Export Subsystem

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

Every real ERP deployment starts with bulk import (data migration from
the legacy system, opening balances, supplier price lists, customer
master data) and grows into export (period reports, accountant
hand-offs). STATUS.md §3.9 listed the subsystem as missing.

## Decision

Subsystem under `mercantis core/ImportExport/`:

1. **`ImportExportFormat`** — `csv` and `json`, with shared error /
   outcome types (`ImportRowOutcome`, `ImportReport`,
   `ImportConflictPolicy`).
2. **`CSVCodec`** — RFC-4180-ish encoder/decoder. Handles quoted
   cells with embedded commas, newlines, and escaped quotes;
   rejects unterminated quoted cells with a typed error.
3. **`DataExporter`** — writes every document of a DocType (or a
   subset matching `[ListFilter]` predicates) to CSV (flat,
   children-omitted) or JSON (full envelope including children).
4. **`DataImporter`** — reads CSV / JSON and routes every row
   through `DocumentEngine.save(...)`. The validation pipeline,
   naming service, audit log, and per-device counter blocks all
   fire identically to interactive saves. Per-row failures are
   recorded in the report rather than aborting the batch.

Conflict policy on id collision:

- `.overwrite` (default) — re-save the row with the imported
  fields, preserving the existing `createdAt`, `syncVersion`, and
  `updatedAt` so optimistic concurrency passes.
- `.skipExisting` — keep the on-disk document, record the row as
  `skipped`.
- `.fail` — record the row as `failed`.

Field-level coercion (CSV): primitives are typed by the DocType's
`FieldDefinition.type`. Strings stay strings; numbers / booleans /
dates parse through their ISO / decimal representations; child
tables and formula fields are skipped (CSV cannot losslessly carry
them). JSON imports use `Document`'s existing `Codable` so the typed
`FieldValue` envelope (ADR-032) round-trips losslessly, including
children.

## Consequences

**Positive**

- Bulk migration paths (CSV from spreadsheet exports, JSON from
  prior backups) work without per-DocType code.
- Imports use the same write path as interactive saves, so all
  ADR-022 validation rules, ADR-039 audit entries, and ADR-038
  workflow transitions still apply. There is no "back door" that
  bypasses business logic.
- The `ImportReport` carries a per-row outcome list; admin UIs can
  show "47 inserted, 2 updated, 3 failed" with individual reasons
  without bespoke aggregation.

**Negative**

- CSV cannot losslessly express child tables. The exporter omits
  them; the importer skips child cells. JSON is the right format
  for round-trips that need to preserve full document shape.
- Imports do not currently run inside a single transaction.
  Per-row save means a partially-imported batch is durable when
  the import is interrupted. This matches ERPNext's behaviour and
  keeps memory pressure bounded for large files; the
  `ImportReport` lets the caller resume by id.
- The CSV decoder is intentionally minimal (no
  alternative-separator support, no automatic encoding detection).
  Extend per-call if needed; we won't grow the surface
  speculatively.

**Neutral**

- Legacy import-error UIs in ERPNext show line numbers from the
  CSV; we provide the row index post-decode. Mapping back to
  source lines is a UI concern.
- Round-trip JSON exports are pretty-printed with sorted keys, so
  diffs against version control are stable.
