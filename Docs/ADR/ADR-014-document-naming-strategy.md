# ADR-014 — Document Naming Strategy

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe supports 10+ naming strategies configurable per DocType (`naming_series`, `autoincrement`, `field:`, `format:`, UUID, hash, `prompt`, Expression, by script, `DocumentNamingRule`). Each strategy has trade-offs for uniqueness, readability, and offline compatibility.

In an offline-first multi-device environment, naming strategies that require server coordination (autoincrement, naming series counter) can produce conflicts. The naming strategy must be chosen carefully per DocType.

## Decision

Mercantis Core implements naming as a **strategy registry**. Each strategy is a conformance of the `NamingStrategy` protocol:

```swift
protocol NamingStrategy {
    func resolve(docType: DocType, document: Document, context: NamingContext) throws -> String
}
```

Concrete built-in implementations:

- **`UUIDv7Strategy`** (default) — UUID v7, time-ordered, globally unique. Recommended for offline-first DocTypes.
- **`NamingSeriesStrategy`** — Pattern-based sequential naming (e.g. `SINV-.YYYY.-.####`). Supports date tokens (`YY`, `YYYY`, `MM`, `DD`), field references, and hash placeholders.
- **`FieldDerivedStrategy`** — Derives the name from a field value (e.g. `field:email`).
- **`PromptStrategy`** — The user enters the name manually. Throws if no name is provided.
- **`FormatStrategy`** — Format string with field interpolation (e.g. `format:{company_abbr}-{naming_series}`).

The `autoname` property in the DocType definition selects the strategy by its token (e.g. `UUID`, `naming_series:SINV-.YYYY.-.####`, `field:email`, `prompt`, `format:...`).

A `DocumentNamingRule` conditional selector allows priority-ordered rules that select different strategies based on document field values (e.g. different naming series per company). `NamingService` evaluates these rules at `DocumentEngine.save()` time and dispatches to the appropriate strategy.

## Consequences

**Positive:**
- UUID default ensures no naming conflicts across offline devices.
- Naming series provides human-readable IDs for business documents (e.g. `SINV-2026-00001`).
- Protocol-based strategies are independently testable and extensible via compiled-in additions.
- `DocumentNamingRule` covers conditional naming without adding control flow to Core.

**Negative:**
- UUIDs are not human-friendly for business references.
- Naming series requires a counter, which is complex in multi-device sync (counter conflicts on offline creation).
- `autoincrement` requires server-side coordination and is not supported for offline-first DocTypes.

**Neutral:**
- Naming series counters are stored in a `series` table and synced via the mutation log. Counter conflicts are resolved by reserving a range per device.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md)*
