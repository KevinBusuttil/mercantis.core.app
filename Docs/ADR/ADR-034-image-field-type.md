# ADR-034 — Image Field Type

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

`FieldType.attachment` currently treats image references as a generic blob or
string, which is too weak for common Hub workflows like item photos and
customer logos.

Hub needs a first-class image field that:

- explicitly declares image intent in metadata,
- round-trips inline binary payloads safely through `FieldValue.data`, and
- renders a native inline preview with a platform chooser.

## Decision

Mercantis Core adds `FieldType.image` as a new metadata field type.

- Persistence uses the existing typed `FieldValue.data(...)` envelope introduced
  by ADR-032.
- Validation accepts both `.data(...)` and legacy `.string(...)` values so
  older URL-based rows remain readable.
- `MercantisCoreUI` adds `ImageField`, which renders a thumbnail preview and a
  native chooser (`PhotosPicker` on iOS, `NSOpenPanel` on macOS).
- Generic list rendering shows inline image payloads as `<image>` instead of a
  raw byte count.

## Consequences

**Positive:**

- Image-bearing fields now have an explicit metadata contract.
- Inline previews improve usability for image-centric records.
- Existing string-backed image references remain compatible during migration.

**Negative:**

- Binary image payloads can increase document size versus URL-only references.
- Platform-specific picker code is required in the UI shell.

**Neutral:**

- Engine storage does not need a new wire format because `.data(...)` already
  exists.

---

*See also:
[ADR-016 — Metadata-Driven Generic UI](ADR-016-metadata-driven-generic-ui.md),
[ADR-022 — Document Validation Pipeline](ADR-022-document-validation-pipeline.md),
[ADR-032 — Typed `FieldValue` Round-Trip Persistence](ADR-032-typed-fieldvalue-roundtrip.md).*
