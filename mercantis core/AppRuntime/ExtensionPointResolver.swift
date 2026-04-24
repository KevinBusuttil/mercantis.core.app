//
//  ExtensionPointResolver.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 24/04/2026.
//

import Foundation

// MARK: - Collaborators

/// Executes a single built-in action declared in a manifest. (ADR-025, P1.2)
///
/// `ExtensionPointResolver` delegates to this protocol so the automation action
/// registry (P1.2) and the resolver can ship independently. Until P1.2 lands,
/// `LoggingExtensionActionDispatcher` is the default — it logs each dispatch
/// and records it in an inspectable trail so tests can assert wiring.
public protocol ExtensionActionDispatcher: AnyObject, Sendable {
    /// Dispatch one action declared in an app manifest.
    ///
    /// Implementations look up `action.actionType` against their registry and
    /// invoke the matching handler. Throwing surfaces the error to the caller
    /// (typically the event observer closure inside the resolver); resolver
    /// callers decide whether to swallow or propagate.
    func dispatch(
        action: ExtensionActionDeclaration,
        context: ExtensionActionContext
    ) throws
}

/// Registers one scheduler declaration with the platform scheduler. (P1.4)
///
/// Until `SchedulerService` ships, `RecordingExtensionSchedulerRegistrar`
/// records the declaration so tests can assert registrations without arming
/// a timer. When P1.4 lands, `SchedulerService` will conform to this protocol.
public protocol ExtensionSchedulerRegistrar: AnyObject, Sendable {
    /// Returns a handle whose cancellation unregisters the scheduled task.
    /// The resolver keeps the handle per-app and cancels it on uninstall.
    func register(
        declaration: SchedulerEventDeclaration,
        appId: String,
        dispatch: @escaping @Sendable () -> Void
    ) -> ExtensionSchedulerHandle
}

/// Token returned by `ExtensionSchedulerRegistrar` that unregisters on cancel.
public final class ExtensionSchedulerHandle: @unchecked Sendable {
    private var cancellation: (@Sendable () -> Void)?
    public init(cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }
    public func cancel() {
        cancellation?()
        cancellation = nil
    }
    deinit { cancel() }
}

/// Context passed to each dispatched action. Today it only carries the
/// manifest's subscription origin; P1.2 will extend this with the document
/// reference when the dispatcher evolves into the automation runtime.
public struct ExtensionActionContext: Sendable {
    public let appId: String
    public let origin: Origin

    public enum Origin: Sendable {
        case documentEvent(trigger: DocumentEventTrigger, documentId: String, docType: String)
        case scheduler(declarationId: String, interval: ScheduleInterval)
    }
}

// MARK: - Default implementations

/// Default dispatcher that records each call without touching document state.
/// Replaced by the real `AutomationActionRegistry` when P1.2 lands.
public final class LoggingExtensionActionDispatcher: ExtensionActionDispatcher, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let appId: String
        public let actionType: String
        public let parameters: [String: String]
    }

    private let lock = NSLock()
    private var _entries: [Entry] = []

    public init() {}

    public var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _entries.removeAll()
    }

    public func dispatch(
        action: ExtensionActionDeclaration,
        context: ExtensionActionContext
    ) throws {
        lock.lock()
        _entries.append(Entry(
            appId: context.appId,
            actionType: action.actionType,
            parameters: action.parameters
        ))
        lock.unlock()
    }
}

/// Default registrar that records declarations without arming a timer.
/// Replaced by `SchedulerService` when P1.4 lands.
public final class RecordingExtensionSchedulerRegistrar: ExtensionSchedulerRegistrar, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let appId: String
        public let declarationId: String
    }

    private let lock = NSLock()
    private var _entries: [Entry] = []

    public init() {}

    public var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func register(
        declaration: SchedulerEventDeclaration,
        appId: String,
        dispatch: @escaping @Sendable () -> Void
    ) -> ExtensionSchedulerHandle {
        let entry = Entry(appId: appId, declarationId: declaration.id)
        lock.lock()
        _entries.append(entry)
        lock.unlock()

        return ExtensionSchedulerHandle { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self._entries.removeAll { $0 == entry }
            self.lock.unlock()
        }
    }
}

// MARK: - Resolver

/// Binds `AppManifest.extensionPoints` to the running `EventEmitter` and
/// `SchedulerService` at install time, and tears bindings back down on
/// uninstall. (ADR-015, ADR-026, P1.3)
///
/// The resolver keeps two per-app handle arrays:
/// - `SubscriptionToken`s returned by `EventEmitter.subscribe`
/// - `ExtensionSchedulerHandle`s returned by the scheduler registrar
///
/// `clear(appId:)` cancels every handle in both arrays and drops the entry.
/// Both operations are idempotent.
///
/// ## Known follow-ups
/// - `after_insert` is not in `DocumentEventTrigger`: `DocumentSavedEvent` does
///   not yet carry an "isNew" flag, and silently binding to every save would
///   surprise authors. Manifests using `"after_insert"` fail at decode time.
/// - `documentEventSubscriptions` observe events published *after* commit, so
///   they cannot block a save. When P1.2's automation runtime lands it will
///   own pre-commit blocking actions; this resolver remains the post-commit
///   pathway.
public final class ExtensionPointResolver: @unchecked Sendable {

    private let emitter: EventEmitter
    private let dispatcher: ExtensionActionDispatcher
    private let schedulerRegistrar: ExtensionSchedulerRegistrar
    private let errorReporter: (@Sendable (ResolverError) -> Void)?

    private let lock = NSLock()
    private var tokensByApp: [String: [SubscriptionToken]] = [:]
    private var scheduleHandlesByApp: [String: [ExtensionSchedulerHandle]] = [:]

    public init(
        emitter: EventEmitter,
        dispatcher: ExtensionActionDispatcher = LoggingExtensionActionDispatcher(),
        schedulerRegistrar: ExtensionSchedulerRegistrar = RecordingExtensionSchedulerRegistrar(),
        errorReporter: (@Sendable (ResolverError) -> Void)? = nil
    ) {
        self.emitter = emitter
        self.dispatcher = dispatcher
        self.schedulerRegistrar = schedulerRegistrar
        self.errorReporter = errorReporter
    }

    // MARK: - Apply / clear

    /// Bind the manifest's declared extension points to the event emitter and
    /// scheduler. Clears any prior bindings for the same app id first, so
    /// reinstall/upgrade is idempotent.
    ///
    /// Unknown trigger strings fail earlier, at `AppManifest` decoding time —
    /// `DocumentEventTrigger` is a closed enum and its `Codable` synthesis
    /// rejects unlisted raw values (e.g. `"after_insert"`).
    public func apply(manifest: AppManifest) {
        let points = manifest.extensionPoints

        clear(appId: manifest.id)

        var newTokens: [SubscriptionToken] = []
        newTokens.reserveCapacity(points.documentEventSubscriptions.count)

        for sub in points.documentEventSubscriptions {
            let token = bind(subscription: sub, appId: manifest.id)
            newTokens.append(token)
        }

        var newHandles: [ExtensionSchedulerHandle] = []
        newHandles.reserveCapacity(points.schedulerEvents.count)

        for decl in points.schedulerEvents {
            let handle = schedulerRegistrar.register(
                declaration: decl,
                appId: manifest.id,
                dispatch: { [dispatcher, errorReporter] in
                    let ctx = ExtensionActionContext(
                        appId: manifest.id,
                        origin: .scheduler(declarationId: decl.id, interval: decl.interval)
                    )
                    for action in decl.actions {
                        do {
                            try dispatcher.dispatch(action: action, context: ctx)
                        } catch {
                            errorReporter?(.dispatchFailed(
                                appId: manifest.id,
                                actionType: action.actionType,
                                underlying: error
                            ))
                        }
                    }
                }
            )
            newHandles.append(handle)
        }

        lock.lock()
        tokensByApp[manifest.id] = newTokens
        scheduleHandlesByApp[manifest.id] = newHandles
        lock.unlock()
    }

    /// Release every subscription and scheduler handle owned by `appId`.
    /// Safe to call with an unknown app id.
    public func clear(appId: String) {
        lock.lock()
        let tokens = tokensByApp.removeValue(forKey: appId) ?? []
        let handles = scheduleHandlesByApp.removeValue(forKey: appId) ?? []
        lock.unlock()

        for token in tokens { token.cancel() }
        for handle in handles { handle.cancel() }
    }

    /// Release every subscription and scheduler handle the resolver owns.
    public func clearAll() {
        lock.lock()
        let apps = Array(tokensByApp.keys) + Array(scheduleHandlesByApp.keys)
        lock.unlock()
        for appId in Set(apps) {
            clear(appId: appId)
        }
    }

    // MARK: - Inspection (test / diagnostics)

    public func boundAppIds() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(tokensByApp.keys).union(scheduleHandlesByApp.keys)
    }

    public func subscriptionCount(forAppId appId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return tokensByApp[appId]?.count ?? 0
    }

    public func scheduleCount(forAppId appId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return scheduleHandlesByApp[appId]?.count ?? 0
    }

    // MARK: - Binding

    private func bind(subscription: DocumentEventSubscription, appId: String) -> SubscriptionToken {
        // Each trigger binds to exactly one event type. The handler filters by
        // `docTypeSelector` and dispatches each action in declared order.
        switch subscription.trigger {
        case .onSave, .onUpdate, .onChange:
            return emitter.subscribe(DocumentSavedEvent.self) { [weak self] event in
                guard let self, subscription.matches(docType: event.docType) else { return }
                self.run(
                    actions: subscription.actions,
                    origin: .documentEvent(
                        trigger: subscription.trigger,
                        documentId: event.document.id,
                        docType: event.docType
                    ),
                    appId: appId
                )
            }
        case .onSubmit:
            return emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
                guard let self, subscription.matches(docType: event.docType) else { return }
                self.run(
                    actions: subscription.actions,
                    origin: .documentEvent(
                        trigger: .onSubmit,
                        documentId: event.document.id,
                        docType: event.docType
                    ),
                    appId: appId
                )
            }
        case .onCancel:
            return emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
                guard let self, subscription.matches(docType: event.docType) else { return }
                self.run(
                    actions: subscription.actions,
                    origin: .documentEvent(
                        trigger: .onCancel,
                        documentId: event.document.id,
                        docType: event.docType
                    ),
                    appId: appId
                )
            }
        case .onAmend:
            return emitter.subscribe(DocumentAmendedEvent.self) { [weak self] event in
                guard let self, subscription.matches(docType: event.docType) else { return }
                self.run(
                    actions: subscription.actions,
                    origin: .documentEvent(
                        trigger: .onAmend,
                        documentId: event.newDocumentId,
                        docType: event.docType
                    ),
                    appId: appId
                )
            }
        case .onTrash, .onDelete:
            return emitter.subscribe(DocumentDeletedEvent.self) { [weak self] event in
                guard let self, subscription.matches(docType: event.docType) else { return }
                self.run(
                    actions: subscription.actions,
                    origin: .documentEvent(
                        trigger: subscription.trigger,
                        documentId: event.documentId,
                        docType: event.docType
                    ),
                    appId: appId
                )
            }
        }
    }

    private func run(
        actions: [ExtensionActionDeclaration],
        origin: ExtensionActionContext.Origin,
        appId: String
    ) {
        let ctx = ExtensionActionContext(appId: appId, origin: origin)
        for action in actions {
            do {
                try dispatcher.dispatch(action: action, context: ctx)
            } catch {
                errorReporter?(.dispatchFailed(
                    appId: appId,
                    actionType: action.actionType,
                    underlying: error
                ))
            }
        }
    }

    // MARK: - Errors

    public enum ResolverError: Error, Sendable {
        case dispatchFailed(appId: String, actionType: String, underlying: Error)
    }
}
