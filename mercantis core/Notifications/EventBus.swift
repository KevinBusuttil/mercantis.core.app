//
//  EventBus.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A simple in-process event bus for Core notifications. (ADR-004)
public final class EventBus: @unchecked Sendable {

    public typealias Handler = @Sendable (Event) -> Void

    public struct Event: Sendable {
        public let name: String
        public let docType: String?
        public let documentId: String?
        public let payload: [String: String]
    }

    /// Token returned by `subscribe` to allow unsubscribing.
    public final class SubscriptionToken: Sendable {
        private let _lock = NSLock()
        private var _isActive = true
        var isActive: Bool {
            get { _lock.lock(); defer { _lock.unlock() }; return _isActive }
            set { _lock.lock(); defer { _lock.unlock() }; _isActive = newValue }
        }
        let id: UUID
        init() { self.id = UUID() }
    }

    private struct Entry {
        let id: UUID
        let handler: Handler
        weak var token: SubscriptionToken?
    }

    private var handlers: [String: [Entry]] = [:]
    private let lock = NSLock()

    public init() {}

    /// Subscribe to an event. Keep the returned token alive; when it is
    /// deallocated or you call `unsubscribe`, the handler is removed.
    @discardableResult
    public func subscribe(to eventName: String, handler: @escaping Handler) -> SubscriptionToken {
        let token = SubscriptionToken()
        lock.lock()
        defer { lock.unlock() }
        handlers[eventName, default: []].append(Entry(id: token.id, handler: handler, token: token))
        return token
    }

    /// Remove a subscription by its token.
    public func unsubscribe(_ token: SubscriptionToken) {
        token.isActive = false
        lock.lock()
        defer { lock.unlock() }
        for key in handlers.keys {
            handlers[key]?.removeAll(where: { $0.id == token.id })
        }
    }

    public func publish(_ event: Event) {
        lock.lock()
        // Prune entries whose token has been released.
        handlers[event.name]?.removeAll(where: { $0.token == nil || !($0.token?.isActive ?? false) })
        let eventHandlers = handlers[event.name] ?? []
        lock.unlock()
        for entry in eventHandlers {
            entry.handler(event)
        }
    }
}
