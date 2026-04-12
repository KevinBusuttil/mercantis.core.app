//
//  WorkflowTransitionHistory.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// An immutable record of a single workflow state transition on a document.
///
/// Every call to `WorkflowEngine.transition(...)` returns one of these records.
/// The caller is responsible for persisting it (typically via `DocumentEngine` to the audit log).
public struct WorkflowTransitionHistory: Identifiable, Codable, Sendable {
    /// Unique identifier for this history record.
    public let id: String

    /// The document that was transitioned.
    public let documentId: String

    /// The DocType of the document.
    public let docType: String

    /// The workflow that was executed.
    public let workflowId: String

    /// The state the document was in before the transition.
    public let from: String

    /// The state the document moved to.
    public let to: String

    /// The action name that triggered the transition.
    public let action: String

    /// The user who initiated the transition.
    public let userId: String

    /// When the transition occurred (device clock).
    public let timestamp: Date

    public init(
        transitionId: String,
        documentId: String,
        docType: String,
        workflowId: String,
        from: String,
        to: String,
        action: String,
        userId: String,
        timestamp: Date
    ) {
        self.id = transitionId
        self.documentId = documentId
        self.docType = docType
        self.workflowId = workflowId
        self.from = from
        self.to = to
        self.action = action
        self.userId = userId
        self.timestamp = timestamp
    }
}
