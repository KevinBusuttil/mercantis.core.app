# ADR-032 — Typed `FieldValue` Round-Trip Persistence

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

`FieldValue` gained typed `.date`, `.dateTime`, `.data`, and `.array`
cases in P1.6, with a tagged JSON envelope so those values could travel
distinctly over the wire.

That wire contract existed at the enum level, but there was still a gap at
the document boundary:

- `DocumentEngine.save` / `fetch` needed to preserve the tagged payload all
  the way through the SQLite `documents.payload` column.
- Manifest-defined `.date` / `.datetime` fields still accepted raw
  `.string(...)` values at validation time without coercing them back into
  typed dates.
- New-document default scaffolding needed to keep `FieldDefinition.defaultValue`
  as the original typed case instead of down-casting it to a string.

Without that end-to-end guarantee, Hub could author a typed date, persist it,
and read back a legacy-looking string. That silently degraded expression
evaluation, formula inputs, and validation semantics.

## Decision

Typed `FieldValue` cases are now treated as a round-trippable persistence
contract, not just a Codable detail.

- `DocumentEngine` persists `Document.fields` via `JSONEncoder` /
  `JSONDecoder`, so `FieldValue.encode(to:)` and `FieldValue.init(from:)`
  own the payload shape written to and read from SQLite.
- `ValidationPipeline` stages can now coerce a mutable `Document` before
  validation. `TypeCoercionStage` rewrites ISO8601 strings into typed
  `.date` / `.dateTime` values for manifest-declared date fields.
- Invalid date strings now fail at the boundary with
  `DocumentValidationError` instead of being accepted as generic strings.
- New-document scaffolding continues to seed field defaults directly from
  `FieldDefinition.defaultValue`, preserving typed `.date(...)` and
  `.array(...)` defaults unchanged.

## Consequences

**Positive:**

- Typed dates, inline data, and arrays survive save → SQLite → fetch as the
  same enum case.
- Expression evaluation and any downstream code that switches on `FieldValue`
  can rely on typed dates after persistence.
- Legacy string inputs for date fields remain compatible, but only when they
  are valid ISO8601 values.

**Negative:**

- Validation is now stricter for `.date` / `.datetime` fields: an arbitrary
  string is no longer accepted just because the field type is date-like.

**Neutral:**

- The tagged-envelope wire shape introduced in P1.6 remains unchanged; this
  ADR formalises the persistence boundary around it.

---

*See also:
[ADR-009 — Single Documents Table with JSON Payload](ADR-009-single-documents-table.md),
[ADR-022 — Document Validation Pipeline](ADR-022-document-validation-pipeline.md).*
