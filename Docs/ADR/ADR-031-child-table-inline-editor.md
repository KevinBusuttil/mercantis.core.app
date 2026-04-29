# ADR-031 — Child-Table Inline Editor

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

`FieldType.table` was rendered in `GenericFormView` as a static read-only
label showing the row count of `Document.children` for that field. There
was no way for users to add, edit, or remove child rows from within the
generic form UI.

Hub's first concrete need was an editable order-line grid (Sales Order →
order_items) and a BOM-row editor (Bill of Materials → bom_items). Both
require an inline grid keyed off the child DocType's field schema
(`childDocType.fields`) so that column headers and cell renderers are
derived from metadata rather than hardcoded.

As with the link-picker problem (ADR-030), `GenericFormView` must remain
independent of any specific `DocumentEngine` instance. The child DocType
schema needed to be resolved at the call site and injected, not looked up
internally.

## Decision

A new `ChildTableField` view is added to `MercantisCoreUI`. It renders an
inline grid for `FieldType.table` fields, with one row per child entry and
one column per field declared in the child DocType's schema.

`GenericFormView` is extended with an optional closure parameter:

```swift
childDocTypeProvider: ((String) -> DocType?)?
```

- The `String` argument is the child `docType` name (taken from
  `field.options`).
- The closure returns the resolved `DocType?`, or `nil` if the schema
  cannot be found.

When `childDocTypeProvider` is `nil` (the default), `GenericFormView`
falls back to the original static row-count label for table fields,
preserving full backwards compatibility: every existing call site continues
to compile and behave identically without any changes.

When the closure is supplied and returns a non-`nil` `DocType`,
`GenericFormView` renders `ChildTableField` instead. The inline grid:

- Derives column headers from `docType.fields` (in declaration order,
  filtered to non-hidden fields).
- Renders each `ChildRow` from `Document.children[field.fieldname]` as an
  editable row.
- Supports add-row and delete-row actions; changes are written back into
  the binding document's `children` dictionary in place.

Children persist atomically through the existing `Document.children` /
`ChildRow` plumbing that was already part of `DocumentEngine.save`. No
engine-layer changes are required.

Hub wires the provider by wrapping `engine.docType(named:)` (or an
equivalent registry lookup):

```swift
GenericFormView(
    document: $doc,
    docType: docType,
    childDocTypeProvider: { childName in
        engine.resolvedMeta(for: childName)?.docType
    }
)
```

`ChildTableField` has no import of or direct reference to `DocumentEngine`;
it receives a `DocType` value and a binding into `Document.children`,
making it independently unit-testable.

## Consequences

**Positive:**

- Hub can expose fully editable order-line and BOM-row grids without
  writing any custom SwiftUI view code — the inline editor is driven
  entirely by the child DocType's metadata.
- `ChildTableField` is fully independent of `DocumentEngine`. Tests can
  construct a `DocType` value directly and assert grid behaviour without
  a database.
- The `nil`-fallback design means zero migration cost for existing
  `GenericFormView` call sites. Adoption is opt-in per form.
- Child persistence is atomic: `DocumentEngine.save` already serialises
  `Document.children` as part of the document payload. No new write path
  is introduced.

**Negative:**

- Very wide child schemas (many fields) will overflow the horizontal
  viewport on small screens. `ChildTableField` uses a `ScrollView` in the
  horizontal axis, but very wide grids may be awkward on iPhone-sized
  devices without a custom column-visibility configuration.
- The closure resolves the schema once per render pass. Call sites that
  cache `DocType` values will have lower overhead than those that call a
  live metadata fetch on every invocation.

**Neutral:**

- Column ordering follows `DocType.fields` declaration order. If Hub
  needs a different column order, it can supply a modified `DocType` copy
  with fields reordered.
- The grid's cell renderer reuses the same field-renderer logic as
  `GenericFormView`'s flat-field path, so new field types added to the
  renderer automatically appear in child table cells.

---

*See also:
[ADR-016 — Metadata-Driven Generic UI](ADR-016-metadata-driven-generic-ui.md),
[ADR-030 — Link Field Search Picker](ADR-030-link-field-search-picker.md).*
