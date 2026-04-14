# ADR-016 — Metadata-Driven Generic UI

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe's entire Desk UI (form builder, list view, report builder, workspace) is driven by DocType metadata. Forms are generated dynamically from field definitions — no per-DocType UI code is needed for standard CRUD. This is a core architectural choice that enables rapid application development.

Mercantis Core targets the same rapid-development goal for iOS/macOS. Writing a custom SwiftUI form for every DocType would be prohibitively expensive and would prevent third-party apps from getting a usable UI without custom code.

## Decision

Mercantis Core's UI Shell generates all standard views (form, list, report) dynamically from DocType metadata. `GenericFormView` reads the `FieldDefinition` array and renders appropriate SwiftUI controls per field type. `GenericListView` renders a sortable, filterable table driven by metadata.

Custom views are only needed for truly non-standard interfaces. Layout is controlled by field properties: `section`, `column`, `hidden`, `readOnly`, `collapsible`. Field types map to SwiftUI controls:

| Field type | SwiftUI control |
|------------|-----------------|
| Data | TextField |
| Check | Toggle |
| Select | Picker |
| Date | DatePicker |
| Table | Child row grid |
| Link | Search-picker |
| Currency / Float | Numeric TextField |

Apps can register a custom SwiftUI view for a specific DocType by declaring a view override. The generic view is the fallback for any DocType without a custom view.

## Consequences

**Positive:**
- New DocTypes get full CRUD UI for free, with no additional code.
- Consistent UX across all DocTypes.
- Reduces code volume by orders of magnitude compared to per-DocType views.
- Custom fields and property setters work automatically because the UI reads live metadata.

**Negative:**
- Less visual flexibility for workflows that require unique interaction patterns.
- Performance overhead for very large forms with many fields.
- SwiftUI's declarative nature makes some highly dynamic behaviours harder to implement.

**Neutral:**
- The generic view is purely a consumer of Core's public `MetadataRegistry` and `DocumentEngine` APIs.

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md), [ADR-007 — Hub Built Exclusively on Core Public APIs](ADR-007-hub-on-core-public-apis.md)*
