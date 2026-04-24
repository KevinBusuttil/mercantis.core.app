//
//  AutomationActionHandler.swift
//  mercantis core
//
//  P1.2 — Automation runtime. See ADR-019, ADR-025.
//

import Foundation

// MARK: - Automation Context

/// Context passed to every `AutomationActionHandler.execute(...)` call. (ADR-019)
///
/// Carries the event origin, the acting user, and the injectable side-effect
/// sinks that handlers like `send_notification` and `assign` write to. The
/// context is intentionally plain data — handlers do not receive a reference
/// to the `DocumentEngine` or the `EventEmitter`; orchestration is the
/// runner's / dispatcher's responsibility.
public struct AutomationContext: Sendable {
    /// Installed app id that owns the rule or extension-point subscription.
    /// Empty when the registry is invoked outside an app scope (e.g. a test
    /// that dispatches a handler directly).
    public let appId: String

    /// Raw trigger identifier. For document events this matches the
    /// `DocumentEventTrigger` raw value (e.g. `"on_save"`, `"on_submit"`).
    /// For legacy `AppManifest.automationRules`, this is the declared
    /// `triggerEvent` string.
    public let trigger: String

    /// The DocType id of the document the event fired for. Empty for
    /// scheduler-origin invocations that are not bound to a DocType.
    public let docType: String

    /// The id of the document the event fired for. Empty for scheduler-origin
    /// invocations.
    public let documentId: String

    /// The user on whose behalf the event was produced. `DocumentEngine`
    /// populates this from its own `userId`; scheduler-origin invocations
    /// use `""` unless the caller injects one.
    public let userId: String

    /// Wall-clock timestamp at handler-dispatch time.
    public let now: Date

    /// Sink that `SendNotificationHandler` writes to.
    public let notificationSink: NotificationLogWriter

    /// Sink that `AssignHandler` writes to.
    public let assignmentSink: AssignmentLogWriter

    /// Expression evaluator used by condition-aware handlers (currently
    /// `ValidateHandler`). Handlers that don't need it can ignore it.
    public let expressionEvaluator: ExpressionEvaluator

    public init(
        appId: String = "",
        trigger: String,
        docType: String = "",
        documentId: String = "",
        userId: String = "",
        now: Date = Date(),
        notificationSink: NotificationLogWriter = InMemoryNotificationLog(),
        assignmentSink: AssignmentLogWriter = InMemoryAssignmentLog(),
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()
    ) {
        self.appId = appId
        self.trigger = trigger
        self.docType = docType
        self.documentId = documentId
        self.userId = userId
        self.now = now
        self.notificationSink = notificationSink
        self.assignmentSink = assignmentSink
        self.expressionEvaluator = expressionEvaluator
    }
}

// MARK: - Handler Protocol

/// A handler for one built-in automation action type. (ADR-025)
///
/// Handlers mutate the document in place; it is the caller's responsibility
/// (runner or dispatcher) to persist the mutation. Handlers that produce
/// side effects — notifications, assignments — use the sinks on
/// `AutomationContext` rather than touching global state.
///
/// Throwing from `execute(...)` signals failure to the caller. When the
/// caller is `DocumentEngine` running inside the save transaction, a thrown
/// error rolls back the save (ADR-019). Post-commit callers (the runner
/// subscribed to `DocumentSavedEvent`) report the error and move on.
public protocol AutomationActionHandler: Sendable {
    /// The `actionType` string this handler is registered under
    /// (e.g. `"set_value"`, `"send_notification"`). Matching is
    /// case-sensitive.
    static var actionType: String { get }

    func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws
}

// MARK: - Errors

/// Errors thrown by `AutomationActionRegistry` and the built-in handlers.
public enum AutomationActionError: Error, Sendable, Equatable {
    /// No handler is registered for the given `actionType`. `SendNotificationHandler`
    /// et al. are registered by `BuiltInAutomationActions.registerAll(into:)`; custom
    /// actions must be registered explicitly.
    case unknownActionType(String)

    /// A required parameter was missing from the declaration.
    case missingParameter(actionType: String, name: String)

    /// A parameter was present but could not be interpreted.
    case invalidParameter(actionType: String, name: String, reason: String)

    /// `ValidateHandler` evaluated its condition and the condition returned false.
    case validationFailed(message: String)

    /// An expression handler could not evaluate its expression (e.g. syntax error
    /// or an undefined field reference). The underlying evaluator error is
    /// preserved as a string — `ExpressionEvaluator.EvaluatorError` is not
    /// `Equatable`, so we stringify to keep this enum `Equatable`.
    case expressionFailed(actionType: String, expression: String, underlying: String)
}
