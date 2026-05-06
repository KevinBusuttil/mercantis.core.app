//
//  ImportExportFormat.swift
//  mercantis core
//
//  Phase C / P3.3 (ADR-046) — Common shapes for the bulk import / export
//  subsystem.
//

import Foundation

/// Wire format for bulk transfer.
public enum ImportExportFormat: String, Sendable, Codable {
    case csv
    case json
}

/// Per-row outcome from an import run. Aggregated into `ImportReport`.
public enum ImportRowOutcome: Sendable, Equatable {
    case inserted(documentId: String)
    case updated(documentId: String)
    case skipped(documentId: String, reason: String)
    case failed(rowIndex: Int, reason: String)
}

/// Aggregated outcome of an `import(...)` call. Imports never partially
/// abort: every row is attempted, and per-row failures are recorded
/// without rolling back successful rows.
public struct ImportReport: Sendable, Equatable {
    public let docType: String
    public let rowsRead: Int
    public let outcomes: [ImportRowOutcome]

    public init(docType: String, rowsRead: Int, outcomes: [ImportRowOutcome]) {
        self.docType = docType
        self.rowsRead = rowsRead
        self.outcomes = outcomes
    }

    public var insertedCount: Int { outcomes.reduce(0) { $0 + (isInserted($1) ? 1 : 0) } }
    public var updatedCount: Int  { outcomes.reduce(0) { $0 + (isUpdated($1)  ? 1 : 0) } }
    public var skippedCount: Int  { outcomes.reduce(0) { $0 + (isSkipped($1)  ? 1 : 0) } }
    public var failedCount: Int   { outcomes.reduce(0) { $0 + (isFailed($1)   ? 1 : 0) } }

    private func isInserted(_ o: ImportRowOutcome) -> Bool { if case .inserted = o { return true }; return false }
    private func isUpdated(_ o: ImportRowOutcome) -> Bool { if case .updated = o { return true }; return false }
    private func isSkipped(_ o: ImportRowOutcome) -> Bool { if case .skipped = o { return true }; return false }
    private func isFailed(_ o: ImportRowOutcome) -> Bool { if case .failed = o { return true }; return false }
}

/// What to do when an imported row's `id` matches an existing document.
public enum ImportConflictPolicy: String, Sendable, Codable {
    /// Default — overwrite the existing document with the imported fields.
    case overwrite
    /// Keep the existing document; record the row as `skipped`.
    case skipExisting
    /// Treat the conflict as a per-row failure.
    case fail
}

public enum ImportExportError: Error, Sendable, Equatable {
    case malformedCSV(line: Int, reason: String)
    case malformedJSON(reason: String)
    case docTypeNotRegistered(String)
}
