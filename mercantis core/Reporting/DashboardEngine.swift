//
//  DashboardEngine.swift
//  mercantis core
//
//  Phase C / §3.10 (ADR-045) — Resolves a `DashboardDefinition` into a
//  typed `DashboardResult`. The engine is rendering-agnostic: it produces
//  the data model (counts, lists, chart series, shortcut metadata) and
//  hands it to the UI layer. `MercantisCoreUI` is expected to ship a
//  `GenericDashboardView` that consumes a `DashboardResult`; that view is
//  out of scope for the engine library.
//

import Foundation

/// Resolved data for one dashboard render. Shape mirrors
/// `DashboardDefinition` 1:1 so a UI layer can iterate widgets and pick a
/// renderer per `DashboardWidgetResult` case.
public struct DashboardResult: Sendable, Equatable {
    public let dashboardId: String
    public let dashboardName: String
    public let widgets: [DashboardWidgetResult]

    public init(dashboardId: String, dashboardName: String, widgets: [DashboardWidgetResult]) {
        self.dashboardId = dashboardId
        self.dashboardName = dashboardName
        self.widgets = widgets
    }
}

/// One resolved widget. The kind tells the UI which case to read.
public enum DashboardWidgetResult: Sendable, Equatable {
    case count(title: String, value: Int, docType: String)
    case list(title: String, columns: [String], rows: [[String?]], docType: String)
    case chart(title: String, columns: [String], rows: [[String?]], reportId: String)
    case shortcut(title: String, target: String)
    /// Carries the underlying error so the UI can show "Could not load X"
    /// instead of crashing the dashboard.
    case error(title: String, reason: String)
}

/// Resolves dashboards into `DashboardResult` data models.
///
/// The engine pulls counts and lists from `DocumentEngine`, charts from
/// `ReportEngine`, and shortcuts straight from the manifest declaration.
/// Errors are captured per-widget so one bad tile doesn't blank the
/// entire dashboard.
public final class DashboardEngine: @unchecked Sendable {

    private let documentEngine: DocumentEngine
    private let reportEngine: ReportEngine?

    private let lock = NSLock()
    private var dashboards: [String: DashboardDefinition] = [:]

    public init(
        documentEngine: DocumentEngine,
        reportEngine: ReportEngine? = nil
    ) {
        self.documentEngine = documentEngine
        self.reportEngine = reportEngine
    }

    // MARK: - Registration

    public func register(_ dashboard: DashboardDefinition) {
        lock.lock(); defer { lock.unlock() }
        dashboards[dashboard.id] = dashboard
    }

    public func unregister(dashboardId: String) {
        lock.lock(); defer { lock.unlock() }
        dashboards.removeValue(forKey: dashboardId)
    }

    public func registeredDashboardIds() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(dashboards.keys).sorted()
    }

    // MARK: - Resolve

    /// Resolve a dashboard by id. Throws only when no dashboard with the
    /// given id is registered; per-widget failures fold into
    /// `DashboardWidgetResult.error`.
    public func resolve(
        dashboardId: String,
        userRoles: Set<String> = []
    ) throws -> DashboardResult {
        lock.lock()
        let dashboard = dashboards[dashboardId]
        lock.unlock()

        guard let dashboard else {
            throw DashboardEngineError.unknownDashboard(dashboardId)
        }
        let widgets = dashboard.widgets.map { widget in
            resolveWidget(widget, userRoles: userRoles)
        }
        return DashboardResult(
            dashboardId: dashboard.id,
            dashboardName: dashboard.name,
            widgets: widgets
        )
    }

    // MARK: - Widget resolution

    private func resolveWidget(
        _ widget: DashboardWidget,
        userRoles: Set<String>
    ) -> DashboardWidgetResult {
        switch widget.type.lowercased() {
        case "count":   return resolveCount(widget)
        case "list":    return resolveList(widget)
        case "chart":   return resolveChart(widget, userRoles: userRoles)
        case "shortcut": return resolveShortcut(widget)
        default:
            return .error(
                title: widget.title,
                reason: "Unknown widget type '\(widget.type)'"
            )
        }
    }

    private func resolveCount(_ widget: DashboardWidget) -> DashboardWidgetResult {
        guard let docType = widget.docType, !docType.isEmpty else {
            return .error(title: widget.title, reason: "count widget requires `docType`")
        }
        do {
            let predicates = ParamFilters.predicates(from: widget.parameters)
            let documents = try documentEngine.list(
                docType: docType,
                predicates: predicates.isEmpty ? nil : predicates,
                applyRowAccess: false
            )
            return .count(title: widget.title, value: documents.count, docType: docType)
        } catch {
            return .error(title: widget.title, reason: "\(error)")
        }
    }

    private func resolveList(_ widget: DashboardWidget) -> DashboardWidgetResult {
        guard let docType = widget.docType, !docType.isEmpty else {
            return .error(title: widget.title, reason: "list widget requires `docType`")
        }
        let columns = widget.parameters["columns"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        let limit = widget.parameters["limit"].flatMap { Int($0) } ?? 10

        do {
            let predicates = ParamFilters.predicates(from: widget.parameters)
            let documents = try documentEngine.list(
                docType: docType,
                predicates: predicates.isEmpty ? nil : predicates,
                limit: limit,
                applyRowAccess: false
            )
            // If no columns are declared, fall back to id + first user field.
            let resolvedColumns: [String]
            if columns.isEmpty {
                resolvedColumns = ["id"] + (documents.first?.fields.keys.sorted().prefix(2) ?? [])
            } else {
                resolvedColumns = columns
            }
            let rows: [[String?]] = documents.map { doc in
                resolvedColumns.map { col in
                    let value = PrintTemplate.lookup(key: col, in: doc)
                    return value.map(PrintTemplate.format)
                }
            }
            return .list(
                title: widget.title,
                columns: resolvedColumns,
                rows: rows,
                docType: docType
            )
        } catch {
            return .error(title: widget.title, reason: "\(error)")
        }
    }

    private func resolveChart(_ widget: DashboardWidget, userRoles: Set<String>) -> DashboardWidgetResult {
        guard let reportId = widget.reportId, !reportId.isEmpty else {
            return .error(title: widget.title, reason: "chart widget requires `reportId`")
        }
        guard let reportEngine else {
            return .error(title: widget.title, reason: "chart widget needs a configured ReportEngine")
        }
        let report = reportEngine.availableReports(for: userRoles)
            .first { $0.id == reportId }
        guard let report else {
            return .error(title: widget.title, reason: "report '\(reportId)' not registered")
        }
        do {
            let result = try reportEngine.execute(report: report)
            return .chart(
                title: widget.title,
                columns: result.columns,
                rows: result.rows,
                reportId: reportId
            )
        } catch {
            return .error(title: widget.title, reason: "\(error)")
        }
    }

    private func resolveShortcut(_ widget: DashboardWidget) -> DashboardWidgetResult {
        let target = widget.parameters["target"]
            ?? widget.docType
            ?? widget.reportId
            ?? ""
        return .shortcut(title: widget.title, target: target)
    }

    public enum DashboardEngineError: Error, Sendable, Equatable {
        case unknownDashboard(String)
    }
}

// MARK: - Parameter parsing helpers

private enum ParamFilters {
    /// Translate widget `parameters` into `ListFilter` predicates.
    /// Supported syntax:
    ///   - `where.<field>=<value>` ⇒ eq predicate
    ///   - `where.<field>__gt=<n>` ⇒ gt predicate (and gte/lt/lte/like)
    ///   - `status=Open` ⇒ shorthand eq (kept for ergonomics)
    static func predicates(from parameters: [String: String]) -> [ListFilter] {
        var out: [ListFilter] = []
        for (key, raw) in parameters {
            if key.hasPrefix("where.") {
                let body = String(key.dropFirst("where.".count))
                let parts = body.split(separator: "_", omittingEmptySubsequences: false)
                if parts.count >= 3,
                   let opIndex = (parts.count - 2 >= 0 ? Optional(parts.count - 2) : nil),
                   parts[opIndex].isEmpty {
                    // pattern: <field>__<op>
                    let op = String(parts.last ?? "eq")
                    let field = parts.dropLast(2).joined(separator: "_")
                    if let predicate = predicate(field: field, op: op, value: raw) {
                        out.append(predicate)
                    }
                } else {
                    out.append(ListFilter(body, .eq(coerce(raw))))
                }
            } else if !["columns", "limit", "target"].contains(key),
                      key.first?.isLetter == true {
                out.append(ListFilter(key, .eq(coerce(raw))))
            }
        }
        return out
    }

    private static func predicate(field: String, op: String, value: String) -> ListFilter? {
        let coerced = coerce(value)
        switch op {
        case "eq":   return ListFilter(field, .eq(coerced))
        case "neq":  return ListFilter(field, .neq(coerced))
        case "gt":   return ListFilter(field, .gt(coerced))
        case "gte":  return ListFilter(field, .gte(coerced))
        case "lt":   return ListFilter(field, .lt(coerced))
        case "lte":  return ListFilter(field, .lte(coerced))
        case "like": return ListFilter(field, .like(value))
        case "isnull":  return ListFilter(field, .isNull)
        case "notnull": return ListFilter(field, .isNotNull)
        default:     return nil
        }
    }

    private static func coerce(_ raw: String) -> FieldValue {
        if let i = Int(raw)    { return .int(i) }
        if let d = Double(raw) { return .double(d) }
        if raw.lowercased() == "true"  { return .bool(true) }
        if raw.lowercased() == "false" { return .bool(false) }
        return .string(raw)
    }
}
