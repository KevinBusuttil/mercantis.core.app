# ADR-033 — Rich Text Field Type

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

`FieldType.longText` currently renders as a plain `TextEditor`, which is fine
for raw multi-line text but too limited for customer notes, item descriptions,
quotation terms, and other long-form fields that need lightweight formatting.

Hub needs a cross-platform rich-text field that:

- persists as Markdown, not HTML,
- previews natively without a WebView,
- keeps the engine contract simple by continuing to store a string value.

## Decision

Mercantis Core adds `FieldType.richText` as a Markdown-backed field type.

- Persistence remains a plain `.string(...)` `FieldValue`; the stored payload is
  the Markdown source verbatim.
- `MercantisCoreUI` adds `RichTextField`, a SwiftUI control with an
  edit/preview toggle.
- Preview rendering uses `AttributedString(markdown:)` so the feature stays
  native and cross-platform.
- Generic UI surfaces are updated so forms render the editor and list rows show
  a single-line plain-text summary without raw Markdown markers.

## Consequences

**Positive:**

- Long-form formatted content now has a first-class field type.
- The storage model stays backwards-compatible with existing string handling.
- Preview works without HTML sanitization or platform-specific web rendering.

**Negative:**

- Markdown support is intentionally lightweight; preview fidelity is limited to
  what `AttributedString(markdown:)` can render.

**Neutral:**

- Validation does not gain a new data shape; `.richText` is treated the same as
  other string-backed field types at the engine boundary.

---

*See also:
[ADR-016 — Metadata-Driven Generic UI](ADR-016-metadata-driven-generic-ui.md),
[ADR-022 — Document Validation Pipeline](ADR-022-document-validation-pipeline.md).*
