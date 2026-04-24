//
//  AutomationRunner.swift
//  mercantis core
//
//  P1.2 — Subscribes to document lifecycle events, matches rules against
//  `AutomationRule` declarations, evaluates each rule's
//  `conditionExpression`, and dispatches each action through the
//  `AutomationActionRegistry`.
//
//  See ADR-019 for the execution model and ADR-025 for the registry.
//

import Foundation

/// Document persistence gateway used by the runner to load the most recent
/// persisted document before running handlers (which may mutate it) and to
/// write the mutated document back.
///
/// `DocumentEngine` conforms to this via a thin extension below. Tests pass
/// their own conformance to assert wiring in isolation.
public protocol AutomationDocumentGateway: AnyObject {
    func loadDocument(docType: String, id: String) throws -> Document?
    func saveDocument(_ document: Document) throws -> Document
}

extension DocumentEngine: AutomationDocumentGateway {
    public func loadDocument(docType: String, id: String) throws -> Document? {
        try fetch(docType: docType, id: id)
    }

    public func saveDocument(_ document: Document) throws -> Document {
        try save(document)
    }
}

// MARK: - Runner

/// Event-driven automation runner. (ADR-019)
///
/// The runner observes post-commit `MercantisEvent`s (save / submit / cancel /
/// amend) and fires every `AutomationRule` whose `docType` and `triggerEvent`
/// match. Actions are dispatched through the shared `AutomationActionRegistry`.
/// When handlers mutate the document, the mutation is written back via
/// `AutomationDocumentGateway.saveDocument(_:)`.
///
/// ### Scope
///
/// - Post-commit only. ADR-019 calls for automation to run *inside* the save
///   transaction so a failing `validate` action rolls back the write. That
///   requires threading the runner through `DocumentEngine.save(_:)` —
///   deferred beyond P1.2 because it changes the save signature and requires
///   new coverage in `DocumentEngineTests`. Post-commit `validate` is still
///   useful: it surfaces an error to `errorReporter` and sinks an
///   `AutomationActionError.validationFailed`, so the UI layer or host
///   app can react.
/// - The runner does not interpret `triggerEvent == "onSchedule"` — that
///   belongs to P1.4's `SchedulerService`.
///
/// ### Re-entrancy
///
/// A handler that writes the document back (e.g. `set_value`) re-fires
/// `DocumentSavedEvent`, which could feed the runner into an infinite loop
/// if a rule fires on its own side effect. The runner tracks the document
/// ids currently under processing and skips nested dispatches.
public final class AutomationRunner: @unchecked Sendable {

    private let emitter: EventEmitter
    private let registry: AutomationActionRegistry
    private let gateway: AutomationDocumentGateway?
    private let notificationSink: NotificationLogWriter
    private let assignmentSink: AssignmentLogWriter
    private let expressionEvaluator: ExpressionEvaluator
    private let userId: String
    private let clock: @Sendable () -> Date
    private let errorReporter: (@Sendable (RunnerError) -> Void)?

    private let lock = NSLock()
    private var rulesByApp: [String: [AutomationRule]] = [:]
    private var tokens: [SubscriptionToken] = []
    private var inFlightDocIds: Set<String> = []

    public init(
        emitter: EventEmitter,
        registry: AutomationActionRegistry = AutomationActionRegistry(),
        gateway: AutomationDocumentGateway? = nil,
        notificationSink: NotificationLogWriter = InMemoryNotificationLog(),
        assignmentSink: AssignmentLogWriter = InMemoryAssignmentLog(),
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        userId: String = "",
        clock: @escaping @Sendable () -> Date = { Date() },
        errorReporter: (@Sendable (RunnerError) -> Void)? = nil
    ) {
        self.emitter = emitter
        self.registry = registry
        self.gateway = gateway
        self.notificationSink = notificationSink
        self.assignmentSink = assignmentSink
        self.expressionEvaluator = expressionEvaluator
        self.userId = userId
        self.clock = clock
        self.errorReporter = errorReporter
        wireSubscriptions()
    }

    deinit {
        for token in tokens { token.cancel() }
    }

    // MARK: - Rule registration

    /// Install every rule declared by a manifest. Replaces any prior rule
    /// set registered for the same `appId`. Safe to call repeatedly.
    public func register(rules: [AutomationRule], appId: String) {
        lock.lock()
        rulesByApp[appId] = rules
        lock.unlock()
    }

    /// Remove every rule registered for `appId`. Matches `AppInstaller.uninstall`.
    public func unregister(appId: String) {
        lock.lock()
        rulesByApp.removeValue(forKey: appId)
        lock.unlock()
    }

    /// Install every rule from every manifest. Used by `restore`-style paths
    /// at launch: replaces the full rule set in one call.
    public func applyManifests(_ manifests: [AppManifest]) {
        lock.lock()
        rulesByApp.removeAll(keepingCapacity: true)
        for manifest in manifests {
            rulesByApp[manifest.id] = manifest.automationRules
        }
        lock.unlock()
    }

    /// The number of rules currently registered for `appId`. For tests and
    /// diagnostics.
    public func ruleCount(forAppId appId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return rulesByApp[appId]?.count ?? 0
    }

    // MARK: - Event wiring

    private func wireSubscriptions() {
        let saved = emitter.subscribe(DocumentSavedEvent.self) { [weak self] event in
            self?.handle(trigger: "onSave", document: event.document, docType: event.docType)
        }
        let submitted = emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handle(trigger: "onSubmit", document: event.document, docType: event.docType)
        }
        let cancelled = emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handle(trigger: "onCancel", document: event.document, docType: event.docType)
        }

        lock.lock()
        tokens.append(saved)
        tokens.append(submitted)
        tokens.append(cancelled)
        lock.unlock()
    }

    // MARK: - Dispatch

    private func handle(trigger: String, document: Document, docType: String) {
        // Snapshot the matching rules under the lock; release before dispatch
        // so handlers can re-enter without deadlocking.
        let matches: [(appId: String, rule: AutomationRule)] = {
            lock.lock(); defer { lock.unlock() }
            var out: [(String, AutomationRule)] = []
            for (appId, rules) in rulesByApp {
                for rule in rules where rule.docType == docType
                    && triggerMatches(declaredTrigger: rule.triggerEvent, eventTrigger: trigger) {
                    out.append((appId, rule))
                }
            }
            return out
        }()
        guard !matches.isEmpty else { return }

        // Re-entrancy guard.
        lock.lock()
        if inFlightDocIds.contains(document.id) {
            lock.unlock()
            return
        }
        inFlightDocIds.insert(document.id)
        lock.unlock()

        defer {
            lock.lock()
            inFlightDocIds.remove(document.id)
            lock.unlock()
        }

        for (appId, rule) in matches {
            do {
                try runRule(rule, appId: appId, trigger: trigger, initialDocument: document)
            } catch {
                errorReporter?(.ruleFailed(
                    appId: appId,
                    ruleId: rule.id,
                    underlying: error
                ))
            }
        }
    }

    private func runRule(
        _ rule: AutomationRule,
        appId: String,
        trigger: String,
        initialDocument: Document
    ) throws {
        // Load the latest persisted state if a gateway is available. This
        // protects against stale payloads when multiple saves fire in quick
        // succession. Without a gateway the event-delivered document is
        // treated as authoritative.
        var document: Document = {
            guard let gateway,
                  let loaded = try? gateway.loadDocument(
                    docType: initialDocument.docType,
                    id: initialDocument.id
                  ) else {
                return initialDocument
            }
            return loaded
        }()
        let originalFields = document.fields
        let originalStatus = document.status

        // Evaluate the rule's condition against the current document state.
        // A missing / empty condition is treated as `true`. Evaluation errors
        // are reported and the rule is skipped — a broken condition is not
        // the same as a false one, so we don't silently run actions.
        if !rule.conditionExpression.isEmpty {
            let passes: Bool
            do {
                passes = try expressionEvaluator.evaluateBool(
                    expression: rule.conditionExpression,
                    context: document.fields
                )
            } catch {
                throw RunnerError.conditionFailed(
                    appId: appId,
                    ruleId: rule.id,
                    expression: rule.conditionExpression,
                    underlying: error
                )
            }
            guard passes else { return }
        }

        let context = AutomationContext(
            appId: appId,
            trigger: trigger,
            docType: document.docType,
            documentId: document.id,
            userId: userId,
            now: clock(),
            notificationSink: notificationSink,
            assignmentSink: assignmentSink,
            expressionEvaluator: expressionEvaluator
        )

        for action in rule.actions {
            try registry.execute(
                actionType: action.type,
                parameters: action.parameters,
                on: &document,
                context: context
            )
        }

        let mutated = document.fields != originalFields || document.status != originalStatus
        if mutated, let gateway {
            _ = try gateway.saveDocument(document)
        }
    }

    // MARK: - Trigger matching

    /// Match the manifest-declared `triggerEvent` against the runner's event trigger.
    ///
    /// Accepts the Mercantis camelCase form (`onSave`, `onSubmit`, `onCancel`)
    /// and the Frappe-style snake_case aliases (`on_save`, `on_submit`,
    /// `on_update`, `on_change`, `on_cancel`). Case-insensitive.
    private func triggerMatches(declaredTrigger declared: String, eventTrigger event: String) -> Bool {
        let d = declared.lowercased()
        let e = event.lowercased()
        if d == e { return true }
        switch e {
        case "onsave":
            return ["on_save", "on_update", "on_change", "onupdate", "onchange"].contains(d)
        case "onsubmit":
            return d == "on_submit"
        case "oncancel":
            return d == "on_cancel"
        default:
            return false
        }
    }

    // MARK: - Errors

    public enum RunnerError: Error, Sendable {
        /// The condition expression couldn't be evaluated. The rule was not run.
        case conditionFailed(appId: String, ruleId: String, expression: String, underlying: Error)

        /// A registered handler threw during execution.
        case ruleFailed(appId: String, ruleId: String, underlying: Error)
    }
}
