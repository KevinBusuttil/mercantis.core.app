//
//  AutomationActionDispatcher.swift
//  mercantis core
//
//  P1.2 — Bridges `AutomationActionRegistry` to the
//  `ExtensionActionDispatcher` seam exposed by P1.3's
//  `ExtensionPointResolver`. Satisfies the "P1.2 fills the
//  ExtensionActionDispatcher seam" item in the sequencing plan.
//

import Foundation

/// `ExtensionActionDispatcher` conformance that routes declarative
/// `ExtensionActionDeclaration`s through the shared
/// `AutomationActionRegistry`.
///
/// ### Responsibilities
///
/// 1. Translate `ExtensionActionContext.Origin` into the corresponding
///    `AutomationContext` (appId, trigger, docType, documentId).
/// 2. For document-origin invocations: load the document via the injected
///    `AutomationDocumentGateway`, run the handler in-place, and persist
///    mutations. When no gateway is configured the handler runs against a
///    placeholder document — fine for `send_notification` / `assign`, a
///    no-op for `set_value` / `set_status` because the mutated value has
///    nowhere to go.
/// 3. For scheduler-origin invocations: run the handler against an empty
///    placeholder document. Scheduler triggers are document-less by design;
///    a handler that needs fields should not be wired to a scheduler rule.
///
/// ### Re-entrancy
///
/// The dispatcher tracks the document ids currently being processed in the
/// same way as `AutomationRunner`. A handler that writes the document back
/// re-fires `DocumentSavedEvent`, which could hit another manifest
/// subscription and loop — the per-document guard breaks the cycle.
public final class AutomationActionDispatcher: ExtensionActionDispatcher, @unchecked Sendable {

    private let registry: AutomationActionRegistry
    private let gateway: AutomationDocumentGateway?
    private let notificationSink: NotificationLogWriter
    private let assignmentSink: AssignmentLogWriter
    private let expressionEvaluator: ExpressionEvaluator
    private let userId: String
    private let clock: @Sendable () -> Date

    private let lock = NSLock()
    private var inFlightDocIds: Set<String> = []

    public init(
        registry: AutomationActionRegistry = AutomationActionRegistry(),
        gateway: AutomationDocumentGateway? = nil,
        notificationSink: NotificationLogWriter = InMemoryNotificationLog(),
        assignmentSink: AssignmentLogWriter = InMemoryAssignmentLog(),
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        userId: String = "",
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.gateway = gateway
        self.notificationSink = notificationSink
        self.assignmentSink = assignmentSink
        self.expressionEvaluator = expressionEvaluator
        self.userId = userId
        self.clock = clock
    }

    // MARK: - ExtensionActionDispatcher

    public func dispatch(
        action: ExtensionActionDeclaration,
        context: ExtensionActionContext
    ) throws {
        switch context.origin {
        case let .documentEvent(trigger, documentId, docType):
            try dispatchDocumentAction(
                action: action,
                appId: context.appId,
                trigger: trigger.rawValue,
                documentId: documentId,
                docType: docType
            )
        case let .scheduler(declarationId, _):
            try dispatchSchedulerAction(
                action: action,
                appId: context.appId,
                declarationId: declarationId
            )
        }
    }

    // MARK: - Private

    private func dispatchDocumentAction(
        action: ExtensionActionDeclaration,
        appId: String,
        trigger: String,
        documentId: String,
        docType: String
    ) throws {
        // Re-entrancy guard. Handlers that mutate the document and write it
        // back will fire DocumentSavedEvent, which could route through the
        // resolver and land here again for the same doc id.
        lock.lock()
        if inFlightDocIds.contains(documentId) {
            lock.unlock()
            return
        }
        inFlightDocIds.insert(documentId)
        lock.unlock()
        defer {
            lock.lock()
            inFlightDocIds.remove(documentId)
            lock.unlock()
        }

        var document = (try gateway?.loadDocument(docType: docType, id: documentId))
            ?? Self.placeholder(documentId: documentId, docType: docType)
        let originalFields = document.fields
        let originalStatus = document.status

        let autoCtx = AutomationContext(
            appId: appId,
            trigger: trigger,
            docType: docType,
            documentId: documentId,
            userId: userId,
            now: clock(),
            notificationSink: notificationSink,
            assignmentSink: assignmentSink,
            expressionEvaluator: expressionEvaluator
        )

        try registry.execute(
            actionType: action.actionType,
            parameters: action.parameters,
            on: &document,
            context: autoCtx
        )

        let mutated = document.fields != originalFields || document.status != originalStatus
        if mutated, let gateway {
            _ = try gateway.saveDocument(document)
        }
    }

    private func dispatchSchedulerAction(
        action: ExtensionActionDeclaration,
        appId: String,
        declarationId: String
    ) throws {
        var placeholder = Self.placeholder(
            documentId: "scheduler:\(declarationId)",
            docType: ""
        )
        let autoCtx = AutomationContext(
            appId: appId,
            trigger: "onSchedule",
            docType: "",
            documentId: "",
            userId: userId,
            now: clock(),
            notificationSink: notificationSink,
            assignmentSink: assignmentSink,
            expressionEvaluator: expressionEvaluator
        )
        try registry.execute(
            actionType: action.actionType,
            parameters: action.parameters,
            on: &placeholder,
            context: autoCtx
        )
    }

    private static func placeholder(documentId: String, docType: String) -> Document {
        Document(
            id: documentId,
            docType: docType,
            company: "",
            status: "",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            docStatus: 0,
            amendedFrom: nil,
            fields: [:],
            children: [:]
        )
    }
}
