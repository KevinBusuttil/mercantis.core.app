//
//  UnitOfWork.swift
//  mercantis core
//
//  Phase 0 / P0.8 — a transaction-scoped seam that lets work *beyond* the core
//  document write (lifecycle audit today; posting batches in Phase 1) commit in
//  the SAME GRDB transaction as the document mutation.
//
//  Today `DocumentEngine.submit(...)` flips `docStatus`, calls `save(...)` (one
//  transaction), then appends the lifecycle audit row in a *second* transaction,
//  and Hub posting runs in a post-commit event handler in yet more transactions.
//  That is the root cause of "submitted but unposted / partially posted"
//  documents. `UnitOfWork` is the boundary that closes that gap: a closure given
//  a `UnitOfWork` runs inside the document write block, so anything it does is
//  atomic with the lifecycle change — it commits together or rolls back together.
//

import Foundation
import GRDB

/// An extra audit row to append inside a lifecycle operation's transaction
/// (e.g. the `submit` / `cancel` / `amend` row), so the audit trail can never
/// be lost to a crash between the state change and the audit write.
public struct LifecycleAudit: Sendable {
    public let action: String
    public let extraJSON: String

    public init(action: String, extraJSON: String = "{}") {
        self.action = action
        self.extraJSON = extraJSON
    }
}

/// A handle to the in-flight write transaction, plus the `ExecutionContext`
/// driving it. Passed to `DocumentEngine.save(..., inTransaction:)` so callers
/// (and, in Phase 1, posting handlers) can write additional rows that must
/// commit atomically with the document.
///
/// The underlying GRDB `Database` is exposed so Phase 1 can append ledger rows
/// without opening a nested transaction (which GRDB forbids). It is only ever
/// constructed by `DocumentEngine` from inside an active `database.write` block.
public struct UnitOfWork {

    /// The active write transaction. Valid only for the duration of the
    /// enclosing `save(...)` call — do not capture it beyond that.
    public let db: Database

    /// Who/what is performing the operation. Posting and audit rows written
    /// through this unit of work should attribute to `context.operatorId`.
    public let context: ExecutionContext

    private let auditLogWriter: AuditLogWriter

    init(db: Database, context: ExecutionContext, auditLogWriter: AuditLogWriter) {
        self.db = db
        self.context = context
        self.auditLogWriter = auditLogWriter
    }

    /// Append an audit row in this transaction, attributed to the operator.
    @discardableResult
    public func audit(
        action: String,
        documentId: String,
        docType: String,
        payloadJSON: String = "{}"
    ) throws -> AuditLogEntry {
        let entry = AuditLogEntry(
            documentId: documentId,
            docType: docType,
            userId: context.operatorId,
            action: action,
            payloadJSON: payloadJSON
        )
        try auditLogWriter.append(entry, in: db)
        return entry
    }

    /// Execute arbitrary SQL in this transaction. Phase 1 posting uses this (and
    /// later a typed ledger-append helper) to write GL / stock / subledger rows
    /// atomically with the source document's submit.
    public func execute(sql: String, arguments: StatementArguments = StatementArguments()) throws {
        try db.execute(sql: sql, arguments: arguments)
    }

    // MARK: - Posting (Phase 1)

    /// Record a posting batch in this transaction, so it commits atomically with
    /// the source document's submit. Stamps `postedBy` with the operator when not
    /// already set.
    public func recordPostingBatch(_ batch: PostingBatch) throws {
        var batch = batch
        if batch.postedBy.isEmpty {
            batch.postedBy = context.operatorId
        }
        try PostingBatchWriter.upsert(batch, in: db)
    }

    /// Whether a posting batch with `id` already exists — the idempotency guard
    /// for re-fired / replayed posting in this transaction.
    public func postingBatchExists(id: String) throws -> Bool {
        try PostingBatchWriter.exists(id: id, in: db)
    }
}
