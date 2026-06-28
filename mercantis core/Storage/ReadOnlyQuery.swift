//
//  ReadOnlyQuery.swift
//  mercantis core
//
//  A guarded, read-only SQL runner for the Developer ▸ Data Browser. Executes a
//  single SELECT-style statement on a read-only connection and returns the
//  result as plain columns + string-rendered rows. Writes are impossible here:
//  the statement runs through `DatabasePool.read`, which SQLite enforces as a
//  read-only connection, and a syntactic guard rejects non-SELECT or
//  multi-statement input up front for a clear error.
//

import Foundation
import GRDB

/// A tabular result of a read-only query: column headers plus rows of
/// already-rendered string cells (null → "", blobs → "<N bytes>").
public struct ReadOnlyQueryResult: Sendable {
    public let columns: [String]
    public let rows: [[String]]
    /// True when the engine stopped collecting at `rowLimit`, so the UI can say
    /// the result was truncated rather than implying it's complete.
    public let truncated: Bool

    public init(columns: [String], rows: [[String]], truncated: Bool) {
        self.columns = columns
        self.rows = rows
        self.truncated = truncated
    }
}

public enum ReadOnlyQueryError: LocalizedError {
    case empty
    case multipleStatements
    case notReadOnly(firstWord: String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a query to run."
        case .multipleStatements:
            return "Only a single statement can be run at a time. Remove the extra “;”."
        case .notReadOnly(let word):
            return "Only read-only queries are allowed here (SELECT / WITH / EXPLAIN / PRAGMA). “\(word.uppercased())” is not permitted."
        }
    }
}

/// Up-front syntactic guard. The read-only connection is the real safety net;
/// this just turns "attempt to write a readonly database" into a friendly,
/// specific message and blocks multi-statement input.
enum ReadOnlyQueryGuard {
    private static let allowedLeadingKeywords: Set<String> = ["select", "with", "explain", "pragma"]

    static func validate(_ sql: String) throws {
        var trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow a single trailing semicolon; reject any interior one (which would
        // mean a second statement).
        while trimmed.hasSuffix(";") { trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmed.isEmpty else { throw ReadOnlyQueryError.empty }
        if trimmed.contains(";") { throw ReadOnlyQueryError.multipleStatements }

        let firstWord = trimmed
            .lowercased()
            .prefix { $0.isLetter }
        guard allowedLeadingKeywords.contains(String(firstWord)) else {
            throw ReadOnlyQueryError.notReadOnly(firstWord: String(firstWord))
        }
    }
}

public extension MercantisDatabase {

    /// Run a single read-only statement and return its rows. `rowLimit` caps how
    /// many rows are materialised for the UI; the result flags when it was hit.
    func runReadOnlyQuery(_ sql: String, rowLimit: Int = 5_000) throws -> ReadOnlyQueryResult {
        try ReadOnlyQueryGuard.validate(sql)
        return try read { db in try Self.buildResult(db, sql: sql, rowLimit: rowLimit) }
    }

    /// Async variant: runs the query off the main thread so the Data Browser UI
    /// stays responsive while a slow query executes.
    func runReadOnlyQueryAsync(_ sql: String, rowLimit: Int = 5_000) async throws -> ReadOnlyQueryResult {
        try ReadOnlyQueryGuard.validate(sql)
        return try await readAsync { db in try Self.buildResult(db, sql: sql, rowLimit: rowLimit) }
    }

    private static func buildResult(_ db: Database, sql: String, rowLimit: Int) throws -> ReadOnlyQueryResult {
        let cursor = try Row.fetchCursor(db, sql: sql)
        var columns: [String] = []
        var rows: [[String]] = []
        var truncated = false
        while let row = try cursor.next() {
            if columns.isEmpty { columns = row.map { $0.0 } }
            if rows.count >= rowLimit { truncated = true; break }
            rows.append(row.map { render($0.1) })
        }
        return ReadOnlyQueryResult(columns: columns, rows: rows, truncated: truncated)
    }

    private static func render(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null:            return ""
        case .int64(let i):    return String(i)
        case .double(let d):   return String(d)
        case .string(let s):   return s
        case .blob(let data):  return "<\(data.count) bytes>"
        }
    }
}
