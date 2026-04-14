# ADR-015 — Declarative Hooks for App Extension

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe's `hooks.py` is a Python file that apps use to wire into the framework: `doc_events`, `scheduler_events`, `override_whitelisted_methods`, `override_doctype_class`, etc. This relies on Python's dynamic import system to load and execute arbitrary code at runtime. Mercantis cannot use dynamic code loading on iOS (ADR-008), and apps must not ship executable code (ADR-004).

A mechanism is still needed to allow apps to respond to document lifecycle events, register periodic tasks, and extend built-in behaviour — without executable code.

## Decision

Mercantis Core implements hooks as declarative entries in the app manifest (JSON/YAML). Apps declare hooks under a `hooks` section:

- `doc_events` — Per-DocType (or global `*`) lifecycle subscriptions: `on_update`, `after_insert`, `on_submit`, `on_cancel`, `on_trash`, `on_change`.
- `scheduler_events` — Periodic task registration: `all`, `daily`, `hourly`, `weekly`, `monthly`, `cron`.
- `override_api` — Redirect public API calls to alternative built-in implementations.
- `extend_doctype` — Add mixin behaviour to a DocType controller.

At install time, `AppInstaller` resolves each hook declaration into an `EventBus` subscription or a `SchedulerService` registration. Since no executable code is downloaded, hook "handlers" are limited to built-in action types: set field value, change workflow state, send notification, evaluate expression, trigger workflow action.

## Consequences

**Positive:**
- Apps extend Core without shipping or downloading executable code.
- Hooks are serialised in the manifest — they are inspectable and auditable.
- Compatible with iOS App Store rules.
- The same resolution system applies to first-party (Hub) and third-party apps.

**Negative:**
- Less flexible than Frappe's arbitrary Python hooks. Complex business logic that would be a single Python function in Frappe must be decomposed into chains of built-in actions and expressions.
- No dynamic dispatch — adding a new built-in action type requires a Core update.

**Neutral:**
- The hook resolution system is identical for first-party (Hub) and third-party apps, ensuring a level playing field.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md), [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md), [ADR-012 — EventBus for Internal Pub/Sub](ADR-012-eventbus-internal-pubsub.md)*
