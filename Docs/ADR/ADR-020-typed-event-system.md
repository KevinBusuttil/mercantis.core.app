# ADR-020 — Typed Event System

**Status:** Accepted  
**Date:** 2026-04-14  
**Supersedes:** [ADR-012 — EventBus for Internal Pub/Sub](ADR-012-eventbus-internal-pubsub.md)

---

## Context

ADR-012 introduced an in-process `EventBus` where events are identified by strings (e.g. `document.saved`, `workflow.transition`). This approach has several problems:

- **Silent failures on misspelled names** — subscribing to `document.svaed` receives no events and no error.
- **No payload type safety** — subscribers receive a generic payload dictionary and must cast it at runtime.
- **No compile-time verification** — the set of valid event names is not machine-checkable.
- **No lifecycle management** — the original design noted memory leaks if subscriptions are not cancelled, but provided no mechanism for doing so.
- **Untraceable** — static analysis cannot determine what code runs when a given event fires.

This is not a Frappe-style hooks problem (which has all of the above, plus dynamic code loading). It is a design insufficiency even within Mercantis's single-process Swift model.

## Decision

Mercantis Core replaces the stringly-typed `EventBus` with a **typed event system**. Each event is a concrete Swift type:

```swift
protocol MercantisEvent {}

struct DocumentSavedEvent: MercantisEvent {
    let document: Document
    let docType: String
}

struct DocumentDeletedEvent: MercantisEvent {
    let documentId: String
    let docType: String
}

struct WorkflowTransitionEvent: MercantisEvent {
    let document: Document
    let fromState: String
    let toState: String
    let action: String
}

struct AppInstalledEvent: MercantisEvent {
    let appId: String
    let version: String
}
```

Subscriptions are type-parameterised:

```swift
func subscribe<E: MercantisEvent>(_ eventType: E.Type, handler: @escaping (E) -> Void) -> SubscriptionToken
func publish<E: MercantisEvent>(_ event: E)
```

`subscribe` returns a `SubscriptionToken` (an opaque cancellable). Callers retain the token; releasing it cancels the subscription. This prevents memory leaks and provides explicit lifecycle management.

**This is not Frappe-style hooks.** It is an explicit, typed, traceable observer pattern. The full set of event types is defined in Core. Handlers are compiled-in Swift closures, not dynamically loaded code. Subscriptions are type-safe and compile-time verifiable.

## Consequences

**Positive:**
- Compile-time verification of event types and payload shapes.
- No silent failures from misspelled event names.
- Explicit lifecycle management via `SubscriptionToken`.
- Fully traceable — `Find Usages` on an event type shows all subscribers.
- No breaking change to the event firing sites (just replace string publish with typed publish).

**Negative:**
- Adding a new event type requires a Core change (same constraint as before).
- Existing code using the string-based `EventBus` must be migrated.

**Neutral:**
- The `EventBus` name is retired. The new type is `EventEmitter` or equivalent. String-based API is removed.

---

*See also: [ADR-012 — EventBus for Internal Pub/Sub (Superseded)](ADR-012-eventbus-internal-pubsub.md), [ADR-015 — Declarative Extension Points for App Extension](ADR-015-declarative-hooks-app-extension.md), [ADR-026 — Three-Layer Extensibility Model](ADR-026-three-layer-extensibility-model.md)*
