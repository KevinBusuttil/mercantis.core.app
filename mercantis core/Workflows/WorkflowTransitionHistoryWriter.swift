//
//  WorkflowTransitionHistoryWriter.swift
//  mercantis core
//
//  Phase A §3.3 — auto-persist workflow transition history. Previously
//  `WorkflowEngine.transition(...)` returned a `WorkflowTransitionHistory`
//  record but never wrote it anywhere; callers had to remember to persist it
//  themselves. This writer plus the new v8 `workflow_transitions` table
//  guarantee an audit trail.
//

import Foundation
import GRDB

/// Persists `WorkflowTransitionHistory` rows to the `workflow_transitions`
/// table and exposes a read API for compliance / audit views.
public final class WorkflowTransitionHistoryWriter {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    /// Write inside an existing GRDB transaction. Use this when the caller
    /// wants the transition row to commit atomically with another write.
    public func append(_ history: WorkflowTransitionHistory, in db: Database) throws {
        try Self.insert(history, db: db)
    }

    /// Write in a fresh short transaction. Used by `WorkflowEngine.transition`
    /// so callers don't need to manage a write block.
    public func append(_ history: WorkflowTransitionHistory) throws {
        try database.write { db in
            try Self.insert(history, db: db)
        }
    }

    private static func insert(_ history: WorkflowTransitionHistory, db: Database) throws {
        let tsString = ISO8601DateFormatter().string(from: history.timestamp)
        try db.execute(
            sql: """
                INSERT INTO workflow_transitions
                    (id, documentId, docType, workflowId, fromState, toState, action, userId, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                history.id,
                history.documentId,
                history.docType,
                history.workflowId,
                history.from,
                history.to,
                history.action,
                history.userId,
                tsString
            ]
        )
    }

    // MARK: - Reader API

    /// Return the full transition history for a document, oldest first.
    public func transitions(of documentId: String) throws -> [WorkflowTransitionHistory] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, workflowId, fromState, toState,
                           action, userId, timestamp
                    FROM workflow_transitions
                    WHERE documentId = ?
                    ORDER BY timestamp ASC, id ASC
                    """,
                arguments: [documentId]
            )
            return try rows.map { try Self.historyFromRow($0) }
        }
    }

    /// Return all transitions for a workflow id across documents, newest first.
    public func transitions(forWorkflow workflowId: String, limit: Int = 100, offset: Int = 0) throws -> [WorkflowTransitionHistory] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, workflowId, fromState, toState,
                           action, userId, timestamp
                    FROM workflow_transitions
                    WHERE workflowId = ?
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [workflowId, limit, max(offset, 0)]
            )
            return try rows.map { try Self.historyFromRow($0) }
        }
    }

    private static func historyFromRow(_ row: Row) throws -> WorkflowTransitionHistory {
        let id: String = row["id"] ?? ""
        let documentId: String = row["documentId"] ?? ""
        let docType: String = row["docType"] ?? ""
        let workflowId: String = row["workflowId"] ?? ""
        let from: String = row["fromState"] ?? ""
        let to: String = row["toState"] ?? ""
        let action: String = row["action"] ?? ""
        let userId: String = row["userId"] ?? ""
        let tsString: String = row["timestamp"] ?? ""
        let ts = ISO8601DateFormatter().date(from: tsString) ?? Date(timeIntervalSince1970: 0)
        return WorkflowTransitionHistory(
            transitionId: id,
            documentId: documentId,
            docType: docType,
            workflowId: workflowId,
            from: from,
            to: to,
            action: action,
            userId: userId,
            timestamp: ts
        )
    }
}
