# ADR-030 — Link Field Search Picker

**Status:** Accepted  
**Date:** 2026-04-29

---

## Context

`FieldType.link` was rendered as a plain `TextField` in `GenericFormView`.
Users had to type document IDs exactly — including case — with no search
assistance and no visual confirmation that the referenced document exists.
This was the first friction point raised by the Hub app: the
Customer→CustomerGroup link field required users to know and type the exact
CustomerGroup ID string.

Because `GenericFormView` lives inside `MercantisCoreUI` and must stay
independent of any specific `DocumentEngine` instance, the form view itself
cannot call `engine.list(docType:whereExpression:)` directly. A protocol
injection was needed to bridge the UI layer and the engine without creating
a hard dependency from `MercantisCoreUI` to `MercantisCore`.

## Decision

A new `LinkPickerField` view is added to `MercantisCoreUI`. It renders a
search-as-you-type picker sheet for `FieldType.link` fields.

`GenericFormView` is extended with an optional closure parameter:

```swift
linkSearchProvider: ((String, String) -> [Document])?
```

- The first `String` argument is the target `docType` (taken from
  `field.options`).
- The second `String` argument is the current search query entered by the
  user.
- The closure returns the matching `[Document]` values to display.

When `linkSearchProvider` is `nil` (the default), `GenericFormView` falls
back to the original plain `TextField` for link fields, preserving full
backwards compatibility: every existing call site continues to compile and
behave identically without any changes.

When the closure is supplied, `GenericFormView` renders `LinkPickerField`
instead. The picker sheet displays matching documents and sets the selected
document's `id` as the field value on confirmation.

Hub wires the provider by wrapping `engine.list(docType:whereExpression:)`:

```swift
GenericFormView(
    document: $doc,
    docType: docType,
    linkSearchProvider: { docType, query in
        (try? engine.list(
            docType: docType,
            whereExpression: "name contains \"\(query)\""
        )) ?? []
    }
)
```

`LinkPickerField` has no import of or direct reference to `DocumentEngine`;
it receives and displays `[Document]` values passed to it through the
closure, keeping the view independently unit-testable.

## Consequences

**Positive:**

- Users can search for linked documents by name fragment instead of typing
  exact IDs. The most significant usability gap in the generic form is
  closed.
- `LinkPickerField` is fully independent of `DocumentEngine` — it can be
  unit-tested by injecting a fixed `[Document]` array without spinning up
  an engine or a database.
- The `nil`-fallback design means zero migration cost for existing
  `GenericFormView` call sites. Adoption is opt-in per form.
- The closure shape is general enough to support any search strategy Hub
  wants — full-text, prefix-only, server-backed — without changing the
  `MercantisCoreUI` API.

**Negative:**

- The Hub closure performs a synchronous `engine.list` call on the main
  actor. For large datasets, callers may need to debounce the search query
  or offload to a background task; `LinkPickerField` does not enforce a
  debounce internally.
- Injecting the closure at the `GenericFormView` call site is a per-form
  responsibility. A form that forgets to supply `linkSearchProvider` silently
  degrades to plain text entry; there is no compile-time warning.

**Neutral:**

- The picker sheet UI follows the existing `MercantisCoreUI` design language
  (sheet presentation, list rows, standard dismiss gesture). No new design
  tokens or colour assets are introduced.
- `GenericFormView`'s initialiser signature grows by one optional parameter.
  Because it is optional with a `nil` default, Xcode's autocomplete and
  existing `init` call sites are unaffected.

---

*See also:
[ADR-016 — Metadata-Driven Generic UI](ADR-016-metadata-driven-generic-ui.md),
[ADR-029 — Cross-Document `lookup()` in the Expression Engine](ADR-029-cross-document-lookup.md).*
