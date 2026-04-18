//
//  ReportEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

// MARK: - Report Result Types

/// A typed result set returned by the Reporting Engine.
public struct ReportResult: Sendable {
    /// The display name of each column.
    public let columns: [String]

    /// Each row is an array of optional string-formatted values, one per column.
    public let rows: [[String?]]

    /// The total number of rows in the result.
    public var rowCount: Int { rows.count }

    public init(columns: [String], rows: [[String?]]) {
        self.columns = columns
        self.rows = rows
    }
}

// MARK: - Report Engine

/// Executes `ReportDefinition` queries against the local database and returns
/// typed `ReportResult` sets. Reports are declared in app manifests and filtered
/// by user roles at runtime. (ADR-004)
public final class ReportEngine {

    private let documentEngine: DocumentEngine

    /// All available report definitions, keyed by report id.
    private var reportDefinitions: [String: ReportDefinition] = [:]

    public init(documentEngine: DocumentEngine) {
        self.documentEngine = documentEngine
    }

    // MARK: - Registration

    /// Register a report definition (typically loaded from an AppManifest).
    public func register(_ report: ReportDefinition) {
        reportDefinitions[report.id] = report
    }

    // MARK: - Available Reports

    /// Return all reports accessible to the given user roles.
    ///
    /// Currently all registered reports are returned. Role-based filtering can be
    /// layered on top of `ReportDefinition` once role annotations are added.
    public func availableReports(for userRoles: Set<String>) -> [ReportDefinition] {
        return Array(reportDefinitions.values).sorted { $0.name < $1.name }
    }

    // MARK: - Execute

    /// Execute a report with the supplied filter values and return the result.
    ///
    /// - Parameters:
    ///   - report: The `ReportDefinition` to execute.
    ///   - filters: A dictionary of filter field keys to `FieldValue` constraints.
    ///     Any filter key not matching a document field is ignored.
    /// - Returns: A `ReportResult` with the report's declared columns and matching rows.
    public func execute(report: ReportDefinition, filters: [String: FieldValue] = [:]) throws -> ReportResult {
        // Fetch all documents of the report's docType.
        let documents = try documentEngine.list(docType: report.docType, filters: filters.isEmpty ? nil : filters)

        // Build the result rows from the declared columns.
        let rows: [[String?]] = documents.map { doc in
            report.columns.map { columnKey in
                self.formatValue(doc.fields[columnKey])
            }
        }

        return ReportResult(columns: report.columns, rows: rows)
    }

    // MARK: - Helpers

    private func formatValue(_ value: FieldValue?) -> String? {
        switch value {
        case .string(let s): return s
        case .int(let i):    return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b):   return b ? "Yes" : "No"
        case .null, nil:     return nil
        }
    }
}
