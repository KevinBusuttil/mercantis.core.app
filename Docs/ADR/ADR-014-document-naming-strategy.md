# ADR-014 — Document Naming Strategy

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe supports 10+ naming strategies configurable per DocType (`naming_series`, `autoincrement`, `field:`, `format:`, UUID, hash, `prompt`, Expression, by script, `DocumentNamingRule`). Each strategy has trade-offs for uniqueness, readability, and offline compatibility.

In an offline-first multi-device environment, naming strategies that require server coordination (autoincrement, naming series counter) can produce conflicts. The naming strategy must be chosen carefully per DocType.

## Decision

Mercantis Core defaults to **UUID v7** (time-ordered) for all documents. UUID v7 ensures global uniqueness without coordination — critical for offline-first scenarios where two devices may create documents simultaneously.

Apps can override the naming strategy per DocType via the `autoname` property in the DocType definition:

- `UUID` (default) — UUID v7, time-ordered, globally unique.
- `naming_series:PATTERN` — Pattern-based sequential naming (e.g. `SINV-.YYYY.-.####`). Supports date tokens (`YY`, `YYYY`, `MM`, `DD`), field references, and hash placeholders.
- `field:FIELDNAME` — Derive the name from a field value (e.g. `field:email`).
- `autoincrement` — Integer sequence per DocType. Requires server coordination.
- `prompt` — The user enters the name manually.
- `format:TEMPLATE` — Format string with field interpolation (e.g. `format:{company_abbr}-{naming_series}`).

A `DocumentNamingRule` system allows conditional naming rules with priority ordering — different patterns can apply based on field values (e.g. different series per company).

The naming strategy is resolved at `DocumentEngine.save()` time, before the document is persisted.

## Consequences

**Positive:**
- UUID default ensures no naming conflicts across offline devices.
- Naming series provides human-readable IDs for business documents (e.g. `SINV-2026-00001`).
- Multiple strategies cover diverse requirements without changing Core infrastructure.

**Negative:**
- UUIDs are not human-friendly for business references.
- Naming series requires a counter, which is complex in multi-device sync (counter conflicts on offline creation).
- `autoincrement` requires server-side coordination and is not recommended for offline-first DocTypes.

**Neutral:**
- Naming series counters are stored in a `series` table and synced via the mutation log. Counter conflicts are resolved by reserving a range per device.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md)*
