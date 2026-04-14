# ADR-021 — Metadata Composition and ResolvedMeta

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

ADR-003 describes `MetadataRegistry` as a cache of raw `DocType` definitions loaded from the `doctypes` table. ADR-019 (Customization Layer) describes custom fields (stored in `custom_fields`) and property setters (stored in `property_setters`) as runtime schema extensions.

Currently, consumers of the metadata registry receive a raw `DocType` and must independently apply custom field merging and property override logic. This produces:

- Duplicated merge logic across DocumentEngine, PermissionEngine, UIShell, and ExpressionEngine.
- Risk of inconsistency if one consumer applies overrides differently from another.
- No single validated representation of the "effective" DocType at runtime.

## Decision

Mercantis Core introduces a **`MetaComposer`** subsystem that produces a `ResolvedMeta` object — the authoritative runtime representation of a DocType.

`MetaComposer.resolve(docType:)` merges three layers in order:

1. **Base definition** — the `DocType` as declared in the app manifest or `doctypes` table.
2. **Custom fields** — user-added `CustomField` records from the `custom_fields` table, appended to the field list at their declared `insertAfter` position.
3. **Property overrides** — `PropertySetter` records from the `property_setters` table, applied to matching fields to override individual properties (label, hidden, read_only, default, options, etc.).

The result is a `ResolvedMeta` struct:

```swift
struct ResolvedMeta {
    let docTypeName: String
    let fields: [ResolvedFieldDefinition]
    let permissionRules: [PermissionRule]
    let syncPolicy: SyncPolicy
    let indexDefinitions: [IndexDefinition]
    let workflowId: String?
    let isSubmittable: Bool
    // …
}
```

**All runtime consumers use `ResolvedMeta`, not raw `DocType`.** `MetadataRegistry` remains the source of raw definitions; `MetaComposer` is the gateway for runtime use.

`ResolvedMeta` is cached in-memory (keyed by docType name). The cache is invalidated when:
- A `CustomField` is added, modified, or removed for that DocType.
- A `PropertySetter` is added, modified, or removed for that DocType.
- The base `DocType` definition is updated or replaced.

## Consequences

**Positive:**
- Single, consistent runtime representation of each DocType.
- All consumers (DocumentEngine, PermissionEngine, UIShell, ExpressionEngine) receive the same effective schema.
- Merge logic is tested once in `MetaComposer`, not duplicated across subsystems.
- Cache invalidation is explicit and localised.

**Negative:**
- An additional resolution step on first access per DocType.
- Cache invalidation must be triggered correctly on all write paths that touch custom fields or property setters.

**Neutral:**
- The `ResolvedMeta` cache is a new cache tier alongside the existing `MetadataRegistry` cache.

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md), [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md)*
