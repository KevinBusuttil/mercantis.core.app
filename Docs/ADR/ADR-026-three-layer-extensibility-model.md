# ADR-026 — Three-Layer Extensibility Model

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe's extensibility model relies on `hooks.py` — Python files that apps register to intercept document events, override methods, and inject behaviour at arbitrary points in the framework. This model is powerful but has fundamental problems:

- **Untraceable execution** — no static analysis can determine what code runs on a given event.
- **No ordering guarantees** — hook execution order depends on app installation order and Python import resolution.
- **No type safety** — hooks receive generic dicts; field access errors are silent runtime failures.
- **Silent failures** — misspelled event names receive no events and produce no error.
- **Circular dependency risk** — hooks from different apps can form undeclared dependency cycles.
- **Security** — arbitrary Python execution is incompatible with iOS App Store rules and Mercantis's no-downloaded-code policy (ADR-008).

Mercantis Core needs an extensibility model that preserves safety, traceability, and App Store compliance while enabling meaningful customisation.

## Decision

Mercantis Core uses a **three-layer extensibility model**. Each layer has different scope and audience:

---

### Layer 1 — Declarative Manifests (primary extension surface)

The primary and only extension surface for downloaded apps. Apps declare DocTypes, workflows, reports, automation rules, custom fields, property overrides, document event subscriptions, and scheduled tasks in JSON/YAML manifests.

No executable code. No dynamic dispatch. All declarations are statically analysable.

Available to: all installed apps (third-party and first-party).

---

### Layer 2 — Typed Event Subscriptions

First-party code compiled into Core or Hub can subscribe to typed events via the `EventEmitter` (ADR-020). Subscriptions use concrete Swift event types — no strings, no dynamic dispatch.

This layer is **not** available to downloaded apps. It is for Core-internal wiring (e.g. `WorkflowEngine` subscribing to `DocumentSavedEvent`) and Hub-level observers.

Available to: compiled-in code only.

---

### Layer 3 — Compiled-In Extension Protocols

The deepest layer. First-party code compiled into Core can provide custom conformances of Core extension protocols:

- `NamingStrategy` — Custom document naming logic (ADR-014).
- `AutomationActionHandler` — Custom automation action types (ADR-025).
- `ConflictResolutionPolicy` — Custom sync conflict resolution strategies (ADR-006).
- `PermissionEvaluator` — Additional permission levels (ADR-011).

These conformances are registered at startup and are indistinguishable from built-in implementations at runtime. They are not available to downloaded apps.

Available to: compiled-in code only.

---

### Why Frappe-style hooks are explicitly rejected

| Property | Frappe hooks | Mercantis Layer 1–3 |
|---|---|---|
| Type safety | None (generic dicts) | Full (typed protocols/events) |
| Ordering | Installation-order dependent | Declared explicit order |
| Traceability | None | Find Usages on event/protocol |
| Misspelling safety | Silent no-op | Compile error or explicit error |
| Circular dependency risk | High | None (no dynamic dispatch) |
| App Store compliance | N/A (server-side) | Compliant |
| Downloaded code | Required | Prohibited |

## Consequences

**Positive:**
- All extension points are type-safe and statically traceable.
- Layer 1 is inspectable and auditable — manifest declarations are data, not code.
- Layers 2 and 3 are compile-time verified.
- No silent failures from misspelled names or missing handlers.
- App Store compliant by design.

**Negative:**
- Less flexible than Frappe's arbitrary Python hooks for complex logic.
- Adding new Layer 3 protocols requires a Core release.
- Third-party apps are limited to Layer 1 — complex business logic must be expressible in declarative rules and expressions.

**Neutral:**
- The three-layer model explicitly documents the boundary between what apps can do and what only Core code can do. This is a deliberate design constraint, not a limitation.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md), [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md), [ADR-015 — Declarative Extension Points for App Extension](ADR-015-declarative-hooks-app-extension.md), [ADR-020 — Typed Event System](ADR-020-typed-event-system.md)*
