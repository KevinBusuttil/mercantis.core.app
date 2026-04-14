# ADR-015 — Declarative Extension Points for App Extension

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe's `hooks.py` is a Python file that apps use to wire into the framework: `doc_events`, `scheduler_events`, `override_whitelisted_methods`, `override_doctype_class`, etc. This relies on Python's dynamic import system to load and execute arbitrary code at runtime. Mercantis cannot use dynamic code loading on iOS (ADR-008), and apps must not ship executable code (ADR-004).

The term "hooks" carries specific Frappe connotations — stringly-typed, dynamically resolved, with silent failures on misspelled event names and no ordering guarantees. Mercantis rejects this model entirely (see rationale below).

A mechanism is still needed to allow apps to respond to document lifecycle events and register periodic tasks — without executable code.

## Decision

Mercantis Core uses a **three-layer extensibility model** (fully described in ADR-026). Apps interact primarily through Layer 1 and Layer 2:

**Layer 1 — Declarative manifests (primary extension surface):**
Apps declare extension points in their manifest (JSON/YAML) under an `extensionPoints` section:

- `documentEventSubscriptions` — Per-DocType (or global `*`) lifecycle event subscriptions: `on_update`, `after_insert`, `on_submit`, `on_cancel`, `on_trash`, `on_change`. Each subscription declares a list of built-in action types to execute.
- `schedulerEvents` — Periodic task registration: `all`, `daily`, `hourly`, `weekly`, `monthly`, `cron`.

**Frappe hook types explicitly rejected:**
- ~~`override_doctype_class`~~ — Requires executable code. Not supported.
- ~~`override_whitelisted_methods`~~ — Requires executable code. Not supported.

**Layer 2 — Typed event subscriptions:**
First-party code compiled into Core or Hub can subscribe to typed events via `EventBus.subscribe(_:handler:)` using concrete Swift event types (ADR-020). This is not available to downloaded apps.

**Layer 3 — Compiled-in extension protocols:**
First-party code can provide custom `NamingStrategy`, `AutomationActionHandler`, or `ConflictResolutionPolicy` conformances compiled directly into Core or Hub. Not available to downloaded apps.

**Why Frappe-style hooks are rejected:**
- Hooks are stringly-typed — a misspelled event name silently receives no events.
- No ordering guarantees — hook execution order depends on installation order and Python import resolution.
- No type safety — hook handlers receive generic dicts; field access errors are runtime failures.
- Untraceable execution — no static analysis can determine what code runs on a given event.
- Circular dependency risk — hooks from different apps can form undeclared dependency cycles.

At install time, `AppInstaller` resolves each `documentEventSubscription` and `schedulerEvent` declaration into a typed `EventBus` subscription or a `SchedulerService` registration. Since no executable code is downloaded, subscription "handlers" are limited to built-in action types (ADR-025).

## Consequences

**Positive:**
- Apps extend Core without shipping or downloading executable code.
- Extension points are serialised in the manifest — they are inspectable and auditable.
- Compatible with iOS App Store rules.
- Typed event subscriptions eliminate silent failures from misspelled event names.

**Negative:**
- Less flexible than Frappe's arbitrary Python hooks. Complex business logic that would be a single Python function in Frappe must be decomposed into chains of built-in actions and expressions.
- No dynamic dispatch — adding a new built-in action type requires a Core update.

**Neutral:**
- The resolution system is identical for first-party (Hub) and third-party apps, ensuring a level playing field for declarative extensions.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md), [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md), [ADR-020 — Typed Event System](ADR-020-typed-event-system.md), [ADR-026 — Three-Layer Extensibility Model](ADR-026-three-layer-extensibility-model.md)*
