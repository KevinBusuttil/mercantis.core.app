//
//  RecordListView.swift
//  mercantis core
//
//  Generic, metadata-driven list-view model for DocType workspaces.
//
//  This is the headless half of the richer list/filter UX: the UI layer
//  (`MercantisCoreUI.GenericListView`) renders these definitions, but the
//  model itself lives in `MercantisCore` so it can be authored by any
//  consumer (e.g. Hub's `HubListViews`) and unit-tested without SwiftUI.
//
//  It deliberately reuses the existing `ListFilter` / `ListSort` predicate
//  model rather than introducing a competing one, so a saved view's
//  predicates can be pushed straight into `DocumentEngine.list(...)` when a
//  consumer opts into engine-backed reloading.
//

import Foundation

/// A named, reusable list view over a DocType — the "All / Draft / Unpaid /
/// Overdue" tabs an ERP user expects. Built-in views are authored by the app
/// (Hub); user-saved views can be persisted with `isBuiltIn == false`.
public struct RecordListViewDefinition: Identifiable, Sendable {
    public let id: String
    public let label: String
    /// Optional SF Symbol name for the view chip.
    public let systemImage: String?
    /// Predicates AND-ed together to scope the view. Empty = no scoping ("All").
    public let predicates: [ListFilter]
    /// Optional default search text applied when the view is selected.
    public let searchText: String?
    /// Optional sort order applied when the view is selected.
    public let sort: [ListSort]
    /// `true` for app-provided views, `false` for user-saved ones.
    public let isBuiltIn: Bool

    public init(
        id: String,
        label: String,
        systemImage: String? = nil,
        predicates: [ListFilter] = [],
        searchText: String? = nil,
        sort: [ListSort] = [],
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.predicates = predicates
        self.searchText = searchText
        self.sort = sort
        self.isBuiltIn = isBuiltIn
    }

    /// The canonical "All records" view, prepended by the UI when a DocType
    /// declares built-in views.
    public static func all(label: String = "All", systemImage: String? = "tray.full") -> RecordListViewDefinition {
        RecordListViewDefinition(id: "all", label: label, systemImage: systemImage)
    }
}

/// A structured query a consumer can hand to `DocumentEngine.list(...)`.
/// Currently produced by the UI so engine-backed reloading can be wired in
/// without reshaping the filter state.
public struct RecordListQuery: Sendable {
    public var searchText: String
    public var predicates: [ListFilter]
    public var sort: [ListSort]
    public var limit: Int?
    public var offset: Int

    public init(
        searchText: String = "",
        predicates: [ListFilter] = [],
        sort: [ListSort] = [],
        limit: Int? = nil,
        offset: Int = 0
    ) {
        self.searchText = searchText
        self.predicates = predicates
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }
}

/// Date-range presets that translate into `ListFilter.between` predicates over
/// a date field. Ranges are inclusive on both ends.
public enum DateRangePreset: String, CaseIterable, Sendable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case thisQuarter
    case thisYear

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .thisQuarter: return "This Quarter"
        case .thisYear: return "This Year"
        }
    }

    /// Inclusive `[start, end]` range for the preset, relative to `now`.
    public func range(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? now
        switch self {
        case .today:
            return (startOfToday, endOfToday)
        case .yesterday:
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            let endOfYesterday = calendar.date(byAdding: DateComponents(second: -1), to: startOfToday) ?? startOfToday
            return (startOfYesterday, endOfYesterday)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
            return (start, endOfToday)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            return (start, endOfToday)
        case .thisQuarter:
            let start = Self.startOfQuarter(now: now, calendar: calendar)
            return (start, endOfToday)
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? startOfToday
            return (start, endOfToday)
        }
    }

    /// A `between` predicate over `fieldKey` for this preset.
    public func predicate(fieldKey: String, now: Date = Date(), calendar: Calendar = .current) -> ListFilter {
        let r = range(now: now, calendar: calendar)
        return ListFilter(fieldKey, .between(.date(r.start), .date(r.end)))
    }

    private static func startOfQuarter(now: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let month = comps.month ?? 1
        let quarterFirstMonth = ((month - 1) / 3) * 3 + 1
        var start = DateComponents()
        start.year = comps.year
        start.month = quarterFirstMonth
        start.day = 1
        return calendar.date(from: start) ?? calendar.startOfDay(for: now)
    }
}

/// In-memory evaluator for `ListFilter` / `ListSort` against `Document`s.
///
/// `DocumentEngine.list(...)` already pushes predicates to SQL where possible;
/// this evaluator is the client-side counterpart the list UI uses to filter an
/// already-loaded `[Document]` (and to keep saved-view semantics consistent
/// with the engine). Operator semantics mirror the engine's intent: comparisons
/// against a missing/`null` value fail rather than match.
public enum RecordListFilter {

    /// Resolves the value a predicate's `fieldKey` refers to — either a
    /// `documents`-table system column or a user field.
    public static func value(for key: String, in doc: Document) -> FieldValue? {
        switch key {
        case "id":        return .string(doc.id)
        case "status":    return .string(doc.status)
        case "docStatus": return .int(doc.docStatus)
        case "company":   return .string(doc.company)
        case "createdAt": return .date(doc.createdAt)
        case "updatedAt": return .date(doc.updatedAt)
        default:          return doc.fields[key]
        }
    }

    /// Evaluates one predicate against one document.
    public static func matches(_ predicate: ListFilter, _ doc: Document) -> Bool {
        let v = value(for: predicate.fieldKey, in: doc)
        switch predicate.op {
        case .isNull:
            return isNullish(v)
        case .isNotNull:
            return !isNullish(v)
        case .eq(let target):
            return equal(v, target)
        case .neq(let target):
            return !equal(v, target)
        case .gt(let target):
            return (compare(v, target)).map { $0 > 0 } ?? false
        case .gte(let target):
            return (compare(v, target)).map { $0 >= 0 } ?? false
        case .lt(let target):
            return (compare(v, target)).map { $0 < 0 } ?? false
        case .lte(let target):
            return (compare(v, target)).map { $0 <= 0 } ?? false
        case .between(let lo, let hi):
            guard let c1 = compare(v, lo), let c2 = compare(v, hi) else { return false }
            return c1 >= 0 && c2 <= 0
        case .in(let options):
            return options.contains { equal(v, $0) }
        case .like(let pattern):
            guard let s = string(v) else { return false }
            return likeMatch(s, pattern: pattern)
        }
    }

    /// `true` when every predicate matches (AND semantics).
    public static func matchesAll(_ predicates: [ListFilter], _ doc: Document) -> Bool {
        predicates.allSatisfy { matches($0, doc) }
    }

    /// Stable ordering comparator across an ordered `[ListSort]` chain.
    public static func areInIncreasingOrder(_ a: Document, _ b: Document, by sorts: [ListSort]) -> Bool {
        for sort in sorts {
            let lhs = value(for: sort.fieldKey, in: a)
            let rhs = value(for: sort.fieldKey, in: b)
            // Equal or incomparable on this key — fall through to the next sort.
            guard let c = compare(lhs, rhs), c != 0 else { continue }
            return sort.direction == .ascending ? c < 0 : c > 0
        }
        return false
    }

    // MARK: - Primitive helpers

    private static func isNullish(_ v: FieldValue?) -> Bool {
        switch v {
        case .none, .null: return true
        case .string(let s): return s.isEmpty
        default: return false
        }
    }

    private static func string(_ v: FieldValue?) -> String? {
        switch v {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    private static func double(_ v: FieldValue?) -> Double? {
        switch v {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    private static func date(_ v: FieldValue?) -> Date? {
        switch v {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }

    /// Type-aware equality with numeric coercion (`int` vs `double`).
    private static func equal(_ a: FieldValue?, _ b: FieldValue) -> Bool {
        // Bool is compared structurally — never coerced to a number, so
        // `.bool(true)` never equals `.int(1)`.
        if case .bool(let bb) = b {
            if case .bool(let ab)? = a { return ab == bb }
            return false
        }
        if let da = double(a), let db = double(b) { return da == db }
        if let dateA = date(a), let dateB = date(b) { return dateA == dateB }
        if let sa = string(a), let sb = string(b) { return sa == sb }
        return false
    }

    /// Three-way comparison, or `nil` when the pair isn't comparable.
    private static func compare(_ a: FieldValue?, _ b: FieldValue?) -> Int? {
        if let da = double(a), let db = double(b) {
            return da < db ? -1 : (da > db ? 1 : 0)
        }
        if let dateA = date(a), let dateB = date(b) {
            return dateA < dateB ? -1 : (dateA > dateB ? 1 : 0)
        }
        if let sa = string(a), let sb = string(b) {
            let r = sa.localizedCaseInsensitiveCompare(sb)
            return r == .orderedSame ? 0 : (r == .orderedAscending ? -1 : 1)
        }
        return nil
    }

    /// Case-insensitive SQL `LIKE` matcher (`%` = any run, `_` = any char).
    private static func likeMatch(_ value: String, pattern: String) -> Bool {
        var regex = "^"
        for ch in pattern {
            switch ch {
            case "%": regex += ".*"
            case "_": regex += "."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex += "$"
        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
