//
//  EventEmitter.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

// MARK: - Event Protocol

/// Marker protocol for all typed events in Mercantis Core. (ADR-020)
///
/// Each event is a concrete Swift type — no stringly-typed event names.
/// Subscriptions are type-parameterised and compile-time verified.
public protocol MercantisEvent: Sendable {}

// MARK: - Concrete Event Types

/// Fired by `DocumentEngine.save(_:)` after a document is persisted.
public struct DocumentSavedEvent: MercantisEvent {
    public let document: Document
    public let docType: String

    public init(document: Document, docType: String) {
        self.document = document
        self.docType = docType
    }
}

/// Fired by `DocumentEngine.delete(docType:id:)` after a document is removed.
public struct DocumentDeletedEvent: MercantisEvent {
    public let documentId: String
    public let docType: String

    public init(documentId: String, docType: String) {
        self.documentId = documentId
        self.docType = docType
    }
}

/// Fired by `DocumentEngine.submit(_:)` after a document is submitted.
public struct DocumentSubmittedEvent: MercantisEvent {
    public let document: Document
    public let docType: String

    public init(document: Document, docType: String) {
        self.document = document
        self.docType = docType
    }
}

/// Fired by `DocumentEngine.cancel(_:)` after a document is cancelled.
public struct DocumentCancelledEvent: MercantisEvent {
    public let document: Document
    public let docType: String

    public init(document: Document, docType: String) {
        self.document = document
        self.docType = docType
    }
}

/// Fired by `DocumentEngine.amend(_:)` after a new amended document is created.
public struct DocumentAmendedEvent: MercantisEvent {
    public let newDocumentId: String
    public let amendedFrom: String
    public let docType: String

    public init(newDocumentId: String, amendedFrom: String, docType: String) {
        self.newDocumentId = newDocumentId
        self.amendedFrom = amendedFrom
        self.docType = docType
    }
}

/// Fired by `WorkflowEngine.transition(...)` after a workflow state change.
public struct WorkflowTransitionEvent: MercantisEvent {
    public let document: Document
    public let fromState: String
    public let toState: String
    public let action: String
    public let workflowId: String

    public init(document: Document, fromState: String, toState: String, action: String, workflowId: String) {
        self.document = document
        self.fromState = fromState
        self.toState = toState
        self.action = action
        self.workflowId = workflowId
    }
}

/// Fired by `AppInstaller.install(_:)` after an app manifest is installed.
public struct AppInstalledEvent: MercantisEvent {
    public let appId: String
    public let version: String

    public init(appId: String, version: String) {
        self.appId = appId
        self.version = version
    }
}

// MARK: - Subscription Token

/// An opaque cancellable token returned by `EventEmitter.subscribe(...)`. (ADR-020)
///
/// Callers retain the token; releasing it cancels the subscription.
/// This prevents memory leaks and provides explicit lifecycle management.
public final class SubscriptionToken: Sendable {
    nonisolated(unsafe) fileprivate var isActive: Bool = true
    fileprivate let id: UUID
    private let cancellation: @Sendable () -> Void

    fileprivate init(id: UUID, cancellation: @escaping @Sendable () -> Void) {
        self.id = id
        self.cancellation = cancellation
    }

    /// Explicitly cancel this subscription.
    public func cancel() {
        isActive = false
        cancellation()
    }

    deinit {
        cancel()
    }
}

// MARK: - Event Emitter

/// Typed event bus for Mercantis Core. (ADR-020)
///
/// Replaces the stringly-typed `EventBus` with compile-time verified,
/// type-parameterised subscriptions. Each event is a concrete Swift type
/// conforming to `MercantisEvent`.
///
/// This also maintains backward compatibility with the legacy `EventBus`
/// interface by bridging typed events to the existing string-based bus
/// during the migration period.
public final class EventEmitter: @unchecked Sendable {

    private struct AnySubscription {
        let id: UUID
        let handler: (Any) -> Void
        weak var token: SubscriptionToken?
    }

    /// Subscriptions keyed by the event type's `ObjectIdentifier`.
    private var subscriptions: [ObjectIdentifier: [AnySubscription]] = [:]
    private let lock = NSLock()

    /// Optional legacy EventBus bridge for backward compatibility.
    private let legacyBus: EventBus?

    public init(legacyBus: EventBus? = nil) {
        self.legacyBus = legacyBus
    }

    // MARK: - Subscribe

    /// Subscribe to a typed event. Returns a `SubscriptionToken` whose
    /// lifecycle controls the subscription.
    ///
    /// ```swift
    /// let token = emitter.subscribe(DocumentSavedEvent.self) { event in
    ///     print("Saved: \(event.document.id)")
    /// }
    /// // Releasing `token` cancels the subscription.
    /// ```
    @discardableResult
    public func subscribe<E: MercantisEvent>(
        _ eventType: E.Type,
        handler: @escaping @Sendable (E) -> Void
    ) -> SubscriptionToken {
        let subId = UUID()
        let key = ObjectIdentifier(eventType)

        let token = SubscriptionToken(id: subId) { [weak self] in
            self?.removeSubscription(id: subId, for: key)
        }

        let entry = AnySubscription(
            id: subId,
            handler: { event in
                if let typed = event as? E {
                    handler(typed)
                }
            },
            token: token
        )

        lock.lock()
        subscriptions[key, default: []].append(entry)
        lock.unlock()

        return token
    }

    // MARK: - Publish

    /// Publish a typed event to all subscribers of that event type.
    public func publish<E: MercantisEvent>(_ event: E) {
        let key = ObjectIdentifier(E.self)

        lock.lock()
        // Prune entries whose token has been released.
        subscriptions[key]?.removeAll { $0.token == nil || !($0.token?.isActive ?? false) }
        let handlers = subscriptions[key] ?? []
        lock.unlock()

        for sub in handlers {
            sub.handler(event)
        }

        // Bridge to legacy EventBus if present.
        bridgeToLegacyBus(event)
    }

    // MARK: - Private

    private func removeSubscription(id: UUID, for key: ObjectIdentifier) {
        lock.lock()
        subscriptions[key]?.removeAll { $0.id == id }
        lock.unlock()
    }

    /// Bridge typed events to the legacy `EventBus` for backward compatibility.
    private func bridgeToLegacyBus<E: MercantisEvent>(_ event: E) {
        guard let bus = legacyBus else { return }

        switch event {
        case let e as DocumentSavedEvent:
            bus.publish(EventBus.Event(name: "document.saved", docType: e.docType, documentId: e.document.id, payload: [:]))
        case let e as DocumentDeletedEvent:
            bus.publish(EventBus.Event(name: "document.deleted", docType: e.docType, documentId: e.documentId, payload: [:]))
        case let e as DocumentSubmittedEvent:
            bus.publish(EventBus.Event(name: "document.submitted", docType: e.docType, documentId: e.document.id, payload: [:]))
        case let e as DocumentCancelledEvent:
            bus.publish(EventBus.Event(name: "document.cancelled", docType: e.docType, documentId: e.document.id, payload: [:]))
        case let e as DocumentAmendedEvent:
            bus.publish(EventBus.Event(name: "document.amended", docType: e.docType, documentId: e.newDocumentId, payload: ["amendedFrom": e.amendedFrom]))
        case let e as WorkflowTransitionEvent:
            bus.publish(EventBus.Event(name: "workflow.transition", docType: nil, documentId: e.document.id, payload: [
                "workflowId": e.workflowId, "action": e.action, "from": e.fromState, "to": e.toState
            ]))
        case let e as AppInstalledEvent:
            bus.publish(EventBus.Event(name: "app.installed", docType: nil, documentId: nil, payload: ["appId": e.appId, "version": e.version]))
        default:
            break
        }
    }
}
