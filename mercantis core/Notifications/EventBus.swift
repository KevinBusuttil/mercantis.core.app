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

    private var handlers: [String: [Handler]] = [:]
    private let lock = NSLock()

    public init() {}

    public func subscribe(to eventName: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[eventName, default: []].append(handler)
    }

    public func publish(_ event: Event) {
        lock.lock()
        let eventHandlers = handlers[event.name] ?? []
        lock.unlock()
        for handler in eventHandlers {
            handler(event)
        }
    }
}
