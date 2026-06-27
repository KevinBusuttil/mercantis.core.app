//
//  SavedReportDefinition.swift
//  mercantis core
//
//  Generic saved-report infrastructure (ADR-050). A `SavedReportDefinition`
//  is an app-neutral, user-owned customisation of a report: which columns
//  show and in what order, which filters apply (with stored defaults), and
//  how rows are sorted. It is deliberately data-only — it carries no SQL, no
//  expressions, and no script. The `SavedReportEngine` interprets it against
//  DocType metadata and the `DocumentEngine` to produce a normal
//  `ReportResult`.
//
//  This type lives in Core because the shape is reusable by any app. ERP
//  report names, DocTypes, and Hub navigation deliberately do NOT live here;
//  Hub composes saved reports on top of this foundation.
//

import Foundation

// MARK: - Visibility

/// Who may see and run a saved report.
///
/// Kept intentionally minimal (no per-role grants, no cross-company model —
/// those are out of scope for the Core foundation). `private` reports are
/// visible only to their owner; `shared` reports are visible to anyone who
/// can already reach the underlying documents.
public enum SavedReportVisibility: String, Codable, Sendable, CaseIterable {
    case `private`
    case shared
}

// MARK: - Sort

/// Direction for a saved-report sort key.
public enum SavedReportSortDirection: String, Codable, Sendable, CaseIterable {
    case ascending
    case descending
}

/// One ordered sort key in a saved report.
public struct SavedReportSort: Codable, Sendable, Equatable {
    public let fieldKey: String
    public var direction: SavedReportSortDirection

    public init(fieldKey: String, direction: SavedReportSortDirection = .ascending) {
        self.fieldKey = fieldKey
        self.direction = direction
    }
}

// MARK: - Filter

/// The comparison a saved-report filter applies. Each case maps 1:1 onto a
/// `ListFilter.Op` the `DocumentEngine` already understands — there is no
/// free-form SQL or expression surface here.
public enum SavedReportFilterOperator: String, Codable, Sendable, CaseIterable {
    case equals
    case notEquals
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    /// Substring match (`LIKE %value%`). Only meaningful for text fields.
    case contains
    case isNull
    case isNotNull

    /// Whether the operator needs a value to compare against. `isNull` /
    /// `isNotNull` are unary and ignore any stored value.
    public var requiresValue: Bool {
        switch self {
        case .isNull, .isNotNull: return false
        default: return true
        }
    }
}

/// A stored filter on a saved report.
///
/// At execution the effective value resolves as
/// `runtime override → value → defaultValue`. A `required` filter with no
/// effective value is a hard error so a report can't silently run unfiltered.
public struct SavedReportFilter: Codable, Sendable, Equatable {
    public let fieldKey: String
    public var op: SavedReportFilterOperator
    /// The value baked into the saved report (may be overridden at run time).
    public var value: FieldValue?
    /// Fallback used when neither a runtime override nor `value` is supplied.
    public var defaultValue: FieldValue?
    /// When true, execution fails unless an effective value is available.
    public var required: Bool

    public init(
        fieldKey: String,
        op: SavedReportFilterOperator = .equals,
        value: FieldValue? = nil,
        defaultValue: FieldValue? = nil,
        required: Bool = false
    ) {
        self.fieldKey = fieldKey
        self.op = op
        self.value = value
        self.defaultValue = defaultValue
        self.required = required
    }

    private enum CodingKeys: String, CodingKey {
        // `operator` is a Swift keyword; persist under the natural JSON key.
        case fieldKey
        case op = "operator"
        case value
        case defaultValue
        case required
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fieldKey = try c.decode(String.self, forKey: .fieldKey)
        op = try c.decodeIfPresent(SavedReportFilterOperator.self, forKey: .op) ?? .equals
        value = try c.decodeIfPresent(FieldValue.self, forKey: .value)
        defaultValue = try c.decodeIfPresent(FieldValue.self, forKey: .defaultValue)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
    }
}

// MARK: - Aggregation

/// How a column's values are combined for group subtotals / a grand total, and
/// how a chart reduces the values in each category.
public enum SavedReportAggregate: String, Codable, Sendable, CaseIterable {
    case none
    case sum
    case average
    case count
    case min
    case max

    public var label: String {
        switch self {
        case .none:    return "None"
        case .sum:     return "Sum"
        case .average: return "Average"
        case .count:   return "Count"
        case .min:     return "Min"
        case .max:     return "Max"
        }
    }
}

// MARK: - Chart

/// The visual a report can render in addition to its table.
public enum SavedReportChartKind: String, Codable, Sendable, CaseIterable {
    case bar
    case line
    case pie

    public var label: String {
        switch self {
        case .bar:  return "Bar"
        case .line: return "Line"
        case .pie:  return "Pie"
        }
    }
}

/// Declarative chart config: reduce `valueFieldKey` by `valueAggregate` within
/// each `categoryFieldKey` bucket and plot it as `kind`.
public struct SavedReportChart: Codable, Sendable, Equatable {
    public var kind: SavedReportChartKind
    public var categoryFieldKey: String
    public var valueFieldKey: String
    public var valueAggregate: SavedReportAggregate

    public init(
        kind: SavedReportChartKind = .bar,
        categoryFieldKey: String,
        valueFieldKey: String,
        valueAggregate: SavedReportAggregate = .sum
    ) {
        self.kind = kind
        self.categoryFieldKey = categoryFieldKey
        self.valueFieldKey = valueFieldKey
        self.valueAggregate = valueAggregate
    }
}

// MARK: - Column

/// A column in a saved report. `order` drives left-to-right placement;
/// `visible == false` hides the column without losing its configuration.
public struct SavedReportColumn: Codable, Identifiable, Sendable, Equatable {
    public var id: String { fieldKey }

    public let fieldKey: String
    /// Header text to show instead of the raw field key, when set.
    public var labelOverride: String?
    public var visible: Bool
    public var order: Int
    /// Optional preferred render width (points). Advisory only — the engine
    /// ignores it; UI hosts may honour it.
    public var width: Double?
    /// How this column is aggregated in group subtotals and the grand total.
    /// `.none` (the default) contributes no total for this column.
    public var aggregate: SavedReportAggregate

    public init(
        fieldKey: String,
        labelOverride: String? = nil,
        visible: Bool = true,
        order: Int,
        width: Double? = nil,
        aggregate: SavedReportAggregate = .none
    ) {
        self.fieldKey = fieldKey
        self.labelOverride = labelOverride
        self.visible = visible
        self.order = order
        self.width = width
        self.aggregate = aggregate
    }

    private enum CodingKeys: String, CodingKey {
        case fieldKey, labelOverride, visible, order, width, aggregate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fieldKey = try c.decode(String.self, forKey: .fieldKey)
        labelOverride = try c.decodeIfPresent(String.self, forKey: .labelOverride)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        order = try c.decode(Int.self, forKey: .order)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        aggregate = try c.decodeIfPresent(SavedReportAggregate.self, forKey: .aggregate) ?? .none
    }

    /// The header label this column contributes to a `ReportResult` —
    /// the override when present, otherwise the raw field key (matching the
    /// built-in `ReportEngine`, which leaves humanisation to the view).
    public var resolvedLabel: String {
        labelOverride ?? fieldKey
    }
}

// MARK: - Saved report

/// A generic, app-neutral saved/customised report. (ADR-050)
public struct SavedReportDefinition: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    /// The built-in `ReportDefinition.id` this was derived from, if any.
    public var baseReportId: String?
    /// The DocType whose documents the report queries.
    public let sourceDocType: String
    /// The user who owns (and, when `private`, exclusively sees) this report.
    public var ownerUserId: String
    public var visibility: SavedReportVisibility
    public var columns: [SavedReportColumn]
    public var filters: [SavedReportFilter]
    public var sorts: [SavedReportSort]
    /// When set, rows are grouped by this field; each group shows its column
    /// aggregates as a subtotal, plus a grand total across all groups.
    public var groupByFieldKey: String?
    /// Optional chart rendered alongside the table.
    public var chart: SavedReportChart?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseReportId: String? = nil,
        sourceDocType: String,
        ownerUserId: String,
        visibility: SavedReportVisibility = .private,
        columns: [SavedReportColumn] = [],
        filters: [SavedReportFilter] = [],
        sorts: [SavedReportSort] = [],
        groupByFieldKey: String? = nil,
        chart: SavedReportChart? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseReportId = baseReportId
        self.sourceDocType = sourceDocType
        self.ownerUserId = ownerUserId
        self.visibility = visibility
        self.columns = columns
        self.filters = filters
        self.sorts = sorts
        self.groupByFieldKey = groupByFieldKey
        self.chart = chart
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseReportId, sourceDocType, ownerUserId, visibility
        case columns, filters, sorts, groupByFieldKey, chart, createdAt, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseReportId = try c.decodeIfPresent(String.self, forKey: .baseReportId)
        sourceDocType = try c.decode(String.self, forKey: .sourceDocType)
        ownerUserId = try c.decode(String.self, forKey: .ownerUserId)
        visibility = try c.decodeIfPresent(SavedReportVisibility.self, forKey: .visibility) ?? .private
        columns = try c.decodeIfPresent([SavedReportColumn].self, forKey: .columns) ?? []
        filters = try c.decodeIfPresent([SavedReportFilter].self, forKey: .filters) ?? []
        sorts = try c.decodeIfPresent([SavedReportSort].self, forKey: .sorts) ?? []
        groupByFieldKey = try c.decodeIfPresent(String.self, forKey: .groupByFieldKey)
        chart = try c.decodeIfPresent(SavedReportChart.self, forKey: .chart)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    // MARK: - Derived views

    /// Visible columns in `order`, ties broken by their original array index so
    /// ordering is deterministic. These define the `ReportResult` column set.
    public var visibleColumnsInOrder: [SavedReportColumn] {
        columns.enumerated()
            .filter { $0.element.visible }
            .sorted { lhs, rhs in
                lhs.element.order != rhs.element.order
                    ? lhs.element.order < rhs.element.order
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Ownership/visibility gate. `private` reports are reachable only by their
    /// owner; `shared` reports are reachable by anyone (document-level access is
    /// still enforced separately when the report runs).
    public func canBeAccessed(byUserId userId: String) -> Bool {
        switch visibility {
        case .shared:   return true
        case .private:  return userId == ownerUserId
        }
    }

    // MARK: - Conversion from a built-in report

    /// Clone a built-in `ReportDefinition` into editable saved-report
    /// configuration. Every declared column becomes a visible column in
    /// declaration order; every declared filter becomes an (optional) saved
    /// filter seeded with the built-in's default value. Sorts start empty —
    /// built-in reports don't declare a sort order.
    public static func from(
        reportDefinition report: ReportDefinition,
        id: String = UUID().uuidString,
        name: String? = nil,
        ownerUserId: String,
        visibility: SavedReportVisibility = .private,
        now: Date = Date()
    ) -> SavedReportDefinition {
        let columns = report.columns.enumerated().map { index, key in
            SavedReportColumn(fieldKey: key, visible: true, order: index)
        }
        let filters = report.filters.map { filter in
            SavedReportFilter(
                fieldKey: filter.fieldKey,
                op: .equals,
                value: nil,
                defaultValue: filter.defaultValue,
                required: false
            )
        }
        return SavedReportDefinition(
            id: id,
            name: name ?? report.name,
            baseReportId: report.id,
            sourceDocType: report.docType,
            ownerUserId: ownerUserId,
            visibility: visibility,
            columns: columns,
            filters: filters,
            sorts: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
