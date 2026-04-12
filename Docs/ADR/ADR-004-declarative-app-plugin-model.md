# ADR-004 — Declarative App / Plugin Model

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Mercantis Core needs an extensibility model that allows domain-specific applications to add DocTypes, workflows, reports, automation rules, and dashboards without forking Core's codebase. Several approaches were considered:

- **Hard-coded modules** — Fast, but not extensible.
- **Swift plugins (dylib)** — Would allow arbitrary code execution; prohibited on iOS (see [ADR-008](ADR-008-no-executable-plugins-ios.md)).
- **Scripting runtime** (e.g. embedded JavaScript) — Possible but complex; introduces a large dependency and potential security surface.
- **Declarative manifests** — Apps are JSON/YAML files that declare their DocTypes, workflows, and rules. Core executes the logic through its own sandboxed engines.

## Decision

**Apps are declarative manifest files** (`AppManifest`). They declare:
- `doctypes` — DocType definitions, including fields, permissions, indexes, and sync policy.
- `workflows` — `WorkflowDefinition` objects with states and transitions.
- `permissions` — Cross-DocType permission overrides.
- `reports` — `ReportDefinition` objects with columns and filters.
- `automationRules` — `AutomationRule` objects with trigger events and sandboxed condition expressions.
- `dashboards` — `DashboardDefinition` objects with typed widgets.
- `localizations` — `LocalizationBundle` objects for multi-language support.

`AppManifest` is a `Codable` Swift struct. **It never contains executable code.** All automation logic is expressed as declarative condition expressions (`conditionExpression: String`) that are evaluated by Core's sandboxed `ExpressionEvaluator`.

`AppInstaller` validates all DocTypes in the manifest via `SchemaValidator` before committing them to the metadata tables. The installation is propagated to all devices via a `installApp` mutation in the sync queue.

## Consequences

**Positive:**
- Apps can be distributed as data files — no code review or App Store submission required.
- The extension model is the same whether you are building a built-in module or a third-party integration.
- App installation is auditable and reversible.
- App manifests can be synced to all devices via the mutation log.

**Negative:**
- Complex business logic that cannot be expressed as a declarative condition or formula requires a Core extension.
- Expression language is necessarily limited (see [ADR-008](ADR-008-no-executable-plugins-ios.md)).

**Neutral:**
- Hub (`mercantis.app`) is simply an app manifest; it uses the same plugin model as any third-party application.

---

*See also: [ADR-001 — Core / Hub Split](ADR-001-core-hub-split.md), [ADR-008 — No Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md)*
