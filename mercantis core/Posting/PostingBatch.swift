//
//  PostingBatch.swift
//  mercantis core
//
//  Phase 1 — the atomic-posting record. A PostingBatch is written in the SAME
//  transaction as a submittable document's submit (through `UnitOfWork`), so the
//  source document and its derived ledger rows commit together or not at all.
//
//  Core stays domain-neutral: it owns the batch primitive (identity, status,
//  idempotency, reversal linkage) and the transactional plumbing. Hub owns the
//  accounting rules that decide *what* ledger rows a batch contains.
//

import Foundation
import GRDB

/// Lifecycle of a posting attempt.
public nonisolated enum PostingStatus: String, Codable, Sendable {
    /// Reserved but not yet completed (rare in the atomic path; used by recovery).
    case pending
    /// Ledger rows written and committed.
    case posted
    /// Posting failed; the batch records the error for recovery / diagnostics.
    case failed
    /// A later reversal batch has reversed this one.
    case reversed
}

/// One posting attempt for a source document.
public nonisolated struct PostingBatch: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let sourceType: String
    public let sourceId: String
    public var status: PostingStatus
    public var version: Int
    public var errorCode: String?
    public var errorMessage: String?
    public var postedAt: Date?
    public var postedBy: String
    /// When this batch reverses another, the id of the batch it reverses.
    public var reversalOfBatch: String?

    public init(
        id: String,
        sourceType: String,
        sourceId: String,
        status: PostingStatus = .pending,
        version: Int = 1,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        postedAt: Date? = nil,
        postedBy: String = "",
        reversalOfBatch: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.status = status
        self.version = version
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.postedAt = postedAt
        self.postedBy = postedBy
        self.reversalOfBatch = reversalOfBatch
    }

    /// Deterministic batch id so retries are idempotent: `POST-<sourceId>-v<version>`.
    public static func makeID(sourceId: String, version: Int = 1) -> String {
        "POST-\(sourceId)-v\(version)"
    }
}

/// Low-level writer usable inside an existing GRDB transaction (e.g. a
/// `UnitOfWork`). Stateless so it can be called from the transaction-scoped seam
/// without holding a database reference.
public enum PostingBatchWriter {

    /// Insert or replace a batch row in the supplied transaction.
    public static nonisolated func upsert(_ batch: PostingBatch, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO posting_batches
                    (id, sourceType, sourceId, status, version,
                     errorCode, errorMessage, postedAt, postedBy, reversalOfBatch)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                batch.id,
                batch.sourceType,
                batch.sourceId,
                batch.status.rawValue,
                batch.version,
                batch.errorCode,
                batch.errorMessage,
                batch.postedAt.map { ISO8601DateFormatter().string(from: $0) },
                batch.postedBy,
                batch.reversalOfBatch
            ]
        )
    }

    /// Whether a batch with `id` already exists (idempotency guard), in-transaction.
    public static nonisolated func exists(id: String, in db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM posting_batches WHERE id = ? LIMIT 1",
            arguments: [id]
        ) != nil
    }

    static nonisolated func batch(from row: Row) -> PostingBatch {
        let postedAtString: String? = row["postedAt"]
        return PostingBatch(
            id: row["id"] ?? "",
            sourceType: row["sourceType"] ?? "",
            sourceId: row["sourceId"] ?? "",
            status: PostingStatus(rawValue: row["status"] ?? "") ?? .pending,
            version: row["version"] ?? 1,
            errorCode: row["errorCode"],
            errorMessage: row["errorMessage"],
            postedAt: postedAtString.flatMap { ISO8601DateFormatter().date(from: $0) },
            postedBy: row["postedBy"] ?? "",
            reversalOfBatch: row["reversalOfBatch"]
        )
    }
}

/// Read API for posting batches: idempotency checks, recovery, and the
/// diagnostics reports (failed / pending batches; per-source history).
public final class PostingBatchStore {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    public func batch(id: String) throws -> PostingBatch? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM posting_batches WHERE id = ? LIMIT 1", arguments: [id])
                .map(PostingBatchWriter.batch(from:))
        }
    }

    public func exists(id: String) throws -> Bool {
        try database.read { db in try PostingBatchWriter.exists(id: id, in: db) }
    }

    /// All batches for a source document, oldest first (by version).
    public func batches(forSourceType sourceType: String, sourceId: String) throws -> [PostingBatch] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM posting_batches
                    WHERE sourceType = ? AND sourceId = ?
                    ORDER BY version ASC
                    """,
                arguments: [sourceType, sourceId]
            ).map(PostingBatchWriter.batch(from:))
        }
    }

    /// Batches in a given status — backs the "failed postings" / "incomplete
    /// postings" diagnostic reports (Appendix C).
    public func batches(withStatus status: PostingStatus, limit: Int = 100) throws -> [PostingBatch] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM posting_batches WHERE status = ? ORDER BY sourceId LIMIT ?",
                arguments: [status.rawValue, limit]
            ).map(PostingBatchWriter.batch(from:))
        }
    }

    /// The current (highest-version) batch for a source document, if any.
    public func currentBatch(forSourceType sourceType: String, sourceId: String) throws -> PostingBatch? {
        try batches(forSourceType: sourceType, sourceId: sourceId).last
    }
}
