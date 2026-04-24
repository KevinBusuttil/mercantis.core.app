//
//  AutomationActionRegistry.swift
//  mercantis core
//
//  P1.2 — Registry that maps `actionType` strings to `AutomationActionHandler`
//  conformances. Registry-based dispatch instead of string-switch. (ADR-025)
//

import Foundation

/// Thread-safe registry of `AutomationActionHandler`s, keyed by `actionType`.
///
/// - Built-in handlers are registered via `BuiltInAutomationActions.registerAll(into:)`.
/// - Additional handlers can be added at runtime; downloaded apps cannot
///   register handlers (ADR-008).
/// - Later registrations with the same `actionType` overwrite earlier ones.
///   This is intentional so a host process can swap a built-in (e.g. replace
///   the in-memory `send_notification` handler with one that delivers email)
///   without subclassing the registry.
public final class AutomationActionRegistry: @unchecked Sendable {

    private var handlers: [String: AutomationActionHandler] = [:]
    private let lock = NSLock()

    public init(registerBuiltIns: Bool = true) {
        if registerBuiltIns {
            BuiltInAutomationActions.registerAll(into: self)
        }
    }

    // MARK: - Registration

    /// Register a handler. Replaces any previous handler with the same `actionType`.
    public func register<H: AutomationActionHandler>(_ handler: H) {
        lock.lock()
        handlers[type(of: handler).actionType] = handler
        lock.unlock()
    }

    /// Remove the handler registered for `actionType`, if any.
    public func unregister(actionType: String) {
        lock.lock()
        handlers.removeValue(forKey: actionType)
        lock.unlock()
    }

    /// The set of `actionType` strings currently registered. Inspectable at
    /// runtime (ADR-025 consequence).
    public func registeredActionTypes() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(handlers.keys)
    }

    /// Return the handler registered for `actionType`, if any.
    public func handler(for actionType: String) -> AutomationActionHandler? {
        lock.lock(); defer { lock.unlock() }
        return handlers[actionType]
    }

    // MARK: - Execution

    /// Execute one action against a document using the registered handler.
    ///
    /// Throws `AutomationActionError.unknownActionType` if no handler is
    /// registered for `actionType` — silent no-op dispatch is forbidden
    /// (ADR-025).
    ///
    /// The caller owns persistence: if the handler mutates `document`, the
    /// caller is responsible for saving the resulting value back to the
    /// document store.
    public func execute(
        actionType: String,
        parameters: [String: String],
        on document: inout Document,
        context: AutomationContext
    ) throws {
        guard let handler = handler(for: actionType) else {
            throw AutomationActionError.unknownActionType(actionType)
        }
        try handler.execute(document: &document, parameters: parameters, context: context)
    }
}
