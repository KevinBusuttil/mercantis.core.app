//
//  SavedReportEngine.swift
//  mercantis core
//
//  Executes `SavedReportDefinition`s (ADR-050) against the local database and
//  returns the same `ReportResult` the built-in `ReportEngine` produces.
//
//  Safety properties enforced here:
//  - Only fields that exist in the source DocType metadata (or are well-known
//    document system columns) may be referenced — unknown fields are rejected.
//  - Filters map onto the typed `ListFilter` operator surface; there is no
//    arbitrary SQL and no Swift/script execution path.
//  - Queries go through `DocumentEngine.list`, so DocType `rowAccessExpression`
//    and role-based row filtering still apply — saved reports cannot widen
//    access beyond what the requesting user could already see.
//

import Foundation

/// Interprets `SavedReportDefinition`s into `ReportResult`s.
///
/// The engine also offers a small in-memory registry (mirroring
/// `ReportEngine`) so hosts can register saved reports, list the ones a user
/// may access, and clone built-in reports into saved configuration.
public final class SavedReportEngine {

    /// Document system columns that may be referenced by a saved report even
    /// though they aren't user-declared `FieldDefinition`s. Mirrors the columns
    /// `DocumentEngine` exposes for filtering/sorting.
    public static let systemFieldKeys: Set<String> = [
        "id", "doctype", "company", "status",
        "createdAt", "updatedAt", "syncVersion", "syncState",
        "docStatus", "amendedFrom", "parentID"
    ]

    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry

    /// Saved reports known to this engine, keyed by id.
    private var savedReports: [String: SavedReportDefinition] = [:]

    public init(documentEngine: DocumentEngine, registry: MetadataRegistry) {
        self.documentEngine = documentEngine
        self.registry = registry
    }

    // MARK: - Registry

    /// Register (or replace) a saved report.
    public func register(_ savedReport: SavedReportDefinition) {
        savedReports[savedReport.id] = savedReport
    }

    /// Remove a saved report by id.
    public func remove(_ id: String) {
        savedReports.removeValue(forKey: id)
    }

    /// Look up a registered saved report.
    public func get(_ id: String) -> SavedReportDefinition? {
        savedReports[id]
    }

    /// All registered saved reports, sorted by name for deterministic ordering.
    public func all() -> [SavedReportDefinition] {
        savedReports.values.sorted { $0.name < $1.name }
    }

    /// Saved reports the given user may access — every `shared` report plus the
    /// user's own `private` reports — sorted by name.
    public func accessibleSavedReports(forUserId userId: String) -> [SavedReportDefinition] {
        savedReports.values
            .filter { $0.canBeAccessed(byUserId: userId) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Conversion

    /// Clone a built-in `ReportDefinition` into a saved report and register it.
    @discardableResult
    public func convert(
        _ report: ReportDefinition,
        id: String = UUID().uuidString,
        name: String? = nil,
        ownerUserId: String,
        visibility: SavedReportVisibility = .private,
        now: Date = Date()
    ) -> SavedReportDefinition {
        let saved = SavedReportDefinition.from(
            reportDefinition: report,
            id: id,
            name: name,
            ownerUserId: ownerUserId,
            visibility: visibility,
            now: now
        )
        register(saved)
        return saved
    }

    // MARK: - Execute

    /// Execute a saved report and return its `ReportResult`.
    ///
    /// - Parameters:
    ///   - savedReport: The configuration to run.
    ///   - requestingUserId: When supplied, the saved report's ownership/visibility
    ///     gate is enforced and the id is used as the document-access subject.
    ///   - runtimeFilterValues: Per-field overrides keyed by `fieldKey`; these
    ///     take precedence over each filter's stored `value` / `defaultValue`.
    ///   - userRoles: Roles applied to DocType row-level access filtering.
    /// - Returns: A `ReportResult` whose columns are the saved report's visible
    ///   columns (in order) and whose rows are the matching documents.
    public func execute(
        savedReport: SavedReportDefinition,
        requestingUserId: String? = nil,
        runtimeFilterValues: [String: FieldValue] = [:],
        userRoles: Set<String> = []
    ) throws -> ReportResult {
        // Ownership / sharing gate.
        if let requestingUserId, !savedReport.canBeAccessed(byUserId: requestingUserId) {
            throw SavedReportError.notAuthorized(
                savedReportId: savedReport.id,
                userId: requestingUserId
            )
        }

        // The source DocType must be registered so we can validate fields
        // against real metadata rather than trusting the stored config.
        guard let docType = registry.get(savedReport.sourceDocType) else {
            throw SavedReportError.docTypeNotRegistered(savedReport.sourceDocType)
        }
        let allowedFields = Self.allowedFieldKeys(for: docType)

        let visibleColumns = savedReport.visibleColumnsInOrder
        guard !visibleColumns.isEmpty else {
            throw SavedReportError.noVisibleColumns(savedReportId: savedReport.id)
        }

        // Reject any reference to a field that isn't part of the DocType
        // metadata (or a known system column). This is the guard that keeps a
        // saved report from reaching beyond its declared surface.
        try validateFields(
            in: savedReport,
            visibleColumns: visibleColumns,
            allowedFields: allowedFields
        )

        // Build typed predicates from the stored filters.
        var predicates: [ListFilter] = []
        for filter in savedReport.filters {
            let effective = runtimeFilterValues[filter.fieldKey]
                ?? filter.value
                ?? filter.defaultValue
            if let predicate = try makePredicate(filter, effectiveValue: effective) {
                predicates.append(predicate)
            }
        }

        // Build the sort chain.
        let sortBy: [ListSort] = savedReport.sorts.map { sort in
            ListSort(
                fieldKey: sort.fieldKey,
                direction: sort.direction == .ascending ? .ascending : .descending
            )
        }

        // Query through the DocumentEngine so row-level access still applies.
        let documents = try documentEngine.list(
            docType: savedReport.sourceDocType,
            predicates: predicates.isEmpty ? nil : predicates,
            sortBy: sortBy.isEmpty ? nil : sortBy,
            userRoles: userRoles,
            listUserId: requestingUserId
        )

        let columns = visibleColumns.map(\.resolvedLabel)
        let rows: [[String?]] = documents.map { doc in
            visibleColumns.map { column in
                ReportValueFormatter.string(from: value(for: column.fieldKey, in: doc))
            }
        }

        return ReportResult(columns: columns, rows: rows)
    }

    // MARK: - Validation

    /// The set of field keys a saved report on `docType` may legally reference.
    public static func allowedFieldKeys(for docType: DocType) -> Set<String> {
        systemFieldKeys.union(docType.fields.map(\.key))
    }

    private func validateFields(
        in savedReport: SavedReportDefinition,
        visibleColumns: [SavedReportColumn],
        allowedFields: Set<String>
    ) throws {
        func check(_ key: String) throws {
            guard allowedFields.contains(key) else {
                throw SavedReportError.unknownField(
                    fieldKey: key,
                    docType: savedReport.sourceDocType
                )
            }
        }
        for column in visibleColumns { try check(column.fieldKey) }
        for filter in savedReport.filters { try check(filter.fieldKey) }
        for sort in savedReport.sorts { try check(sort.fieldKey) }
    }

    // MARK: - Predicate construction

    /// Turn a saved filter + its resolved value into a `ListFilter`, or `nil`
    /// when an optional filter has no value to apply.
    private func makePredicate(
        _ filter: SavedReportFilter,
        effectiveValue: FieldValue?
    ) throws -> ListFilter? {
        let key = filter.fieldKey
        switch filter.op {
        case .isNull:
            return ListFilter(key, .isNull)
        case .isNotNull:
            return ListFilter(key, .isNotNull)
        case .equals, .notEquals, .greaterThan, .greaterThanOrEqual,
             .lessThan, .lessThanOrEqual, .contains:
            guard let value = effectiveValue, value != .null else {
                if filter.required {
                    throw SavedReportError.missingRequiredFilter(fieldKey: key)
                }
                return nil  // optional, unset → simply skipped
            }
            return ListFilter(key, listOp(for: filter.op, value: value))
        }
    }

    /// Map a value-bearing saved operator onto a `ListFilter.Op`.
    private func listOp(for op: SavedReportFilterOperator, value: FieldValue) -> ListFilter.Op {
        switch op {
        case .equals:             return .eq(value)
        case .notEquals:          return .neq(value)
        case .greaterThan:        return .gt(value)
        case .greaterThanOrEqual: return .gte(value)
        case .lessThan:           return .lt(value)
        case .lessThanOrEqual:    return .lte(value)
        case .contains:           return .like("%\(likeFragment(from: value))%")
        // The unary operators never reach here (handled in `makePredicate`),
        // but the switch stays exhaustive.
        case .isNull:             return .isNull
        case .isNotNull:          return .isNotNull
        }
    }

    /// String form of a value for a `contains` (`LIKE`) pattern.
    private func likeFragment(from value: FieldValue) -> String {
        ReportValueFormatter.string(from: value) ?? ""
    }

    // MARK: - Value resolution

    /// Read a column value from a document. User-declared fields win; otherwise
    /// fall back to the document's system columns (matching `DocumentEngine`).
    private func value(for key: String, in document: Document) -> FieldValue? {
        if let userValue = document.fields[key] { return userValue }
        switch key {
        case "id":          return .string(document.id)
        case "doctype":     return .string(document.docType)
        case "company":     return .string(document.company)
        case "status":      return .string(document.status)
        case "createdAt":   return .dateTime(document.createdAt)
        case "updatedAt":   return .dateTime(document.updatedAt)
        case "syncVersion": return .int(Int(document.syncVersion))
        case "syncState":   return .string(document.syncState.rawValue)
        case "docStatus":   return .int(document.docStatus)
        case "amendedFrom": return document.amendedFrom.map { .string($0) }
        case "parentID":    return document.parentID.map { .string($0) }
        default:            return nil
        }
    }
}

// MARK: - Errors

public enum SavedReportError: Error, Sendable, Equatable {
    /// The saved report's `sourceDocType` isn't registered in metadata.
    case docTypeNotRegistered(String)
    /// A referenced field isn't part of the DocType metadata or system columns.
    case unknownField(fieldKey: String, docType: String)
    /// The saved report has no visible columns to render.
    case noVisibleColumns(savedReportId: String)
    /// A `required` filter resolved to no value.
    case missingRequiredFilter(fieldKey: String)
    /// The requesting user may not access this (private) saved report.
    case notAuthorized(savedReportId: String, userId: String)
}

extension SavedReportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .docTypeNotRegistered(let id):
            return "The report's source type \"\(id)\" isn't registered. Its app manifest may not have finished installing."
        case .unknownField(let fieldKey, let docType):
            return "Field \"\(fieldKey)\" doesn't exist on \"\(docType)\", so it can't be used in a saved report."
        case .noVisibleColumns:
            return "This saved report has no visible columns. Show at least one column before running it."
        case .missingRequiredFilter(let fieldKey):
            return "The required filter \"\(fieldKey)\" needs a value before this report can run."
        case .notAuthorized(_, let userId):
            return "User \"\(userId)\" isn't allowed to open this private saved report."
        }
    }
}
