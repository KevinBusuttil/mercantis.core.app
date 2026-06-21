//
//  DashboardResultGrid.swift
//  mercantis core
//
//  Feature-parity port of the Flutter `DashboardResultGrid`
//  (`mercantis_core_ui/lib/src/widgets/dashboard_result_grid.dart`). Renders a
//  resolved `DashboardResult` (`Reporting/DashboardEngine.swift`) as a
//  responsive grid of widget cards — count KPIs, lists, shortcuts, and mini
//  chart tables — with per-widget error isolation.
//
//  Unlike the current `NavigationShell.dashboardDetail(dashboardId:)`, which
//  re-counts documents inline, this grid renders the engine's typed
//  `DashboardResult`. It can either resolve the dashboard itself (pass a
//  `DashboardEngine` + id) or render a result the host already resolved.
//
//  The Swift `DashboardWidgetResult` enum has no `.sum` case (the Flutter model
//  does) — the engine emits `.count`, `.list`, `.chart`, `.shortcut`, `.error`,
//  so only those are rendered here. Per-widget failures arrive as
//  `.error(title:reason:)` and render as a red-tinted card rather than blanking
//  the grid. Wiring is described in `CORE_VIEWS_WIRING.md`.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct DashboardResultGrid: View {

    /// Resolved dashboard data. Either supplied directly or produced once on
    /// appear by resolving `resolver` for `dashboardId`.
    @State private var result: DashboardResult?
    @State private var resolveError: String?
    @State private var hasResolved = false

    private let dashboardId: String
    private let resolver: DashboardEngine?
    private let userRoles: Set<String>
    /// Called when the user taps a shortcut card. The string is the resolved
    /// target (a docType id, report id, or explicit `target` parameter).
    private let onShortcut: ((String) -> Void)?

    /// Resolve-on-appear initializer. The grid calls
    /// `engine.resolve(dashboardId:userRoles:)` which folds per-widget failures
    /// into `.error` widgets (only an unknown dashboard id throws).
    public init(
        engine: DashboardEngine,
        dashboardId: String,
        userRoles: Set<String> = [],
        onShortcut: ((String) -> Void)? = nil
    ) {
        self.resolver = engine
        self.dashboardId = dashboardId
        self.userRoles = userRoles
        self.onShortcut = onShortcut
        _result = State(initialValue: nil)
    }

    /// Pre-resolved initializer for hosts that already hold a `DashboardResult`.
    public init(
        result: DashboardResult,
        onShortcut: ((String) -> Void)? = nil
    ) {
        self.resolver = nil
        self.dashboardId = result.dashboardId
        self.userRoles = []
        self.onShortcut = onShortcut
        _result = State(initialValue: result)
        _hasResolved = State(initialValue: true)
    }

    public var body: some View {
        Group {
            if let resolveError {
                ContentUnavailableView {
                    Label("Dashboard unavailable", systemImage: "rectangle.3.group")
                } description: {
                    Text(resolveError)
                }
            } else if let result {
                grid(for: result)
                    .navigationTitle(result.dashboardName)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MercantisTheme.background)
        .onAppear {
            guard !hasResolved else { return }
            hasResolved = true
            resolve()
        }
    }

    private func resolve() {
        guard let resolver else { return }
        do {
            result = try resolver.resolve(dashboardId: dashboardId, userRoles: userRoles)
            resolveError = nil
        } catch {
            resolveError = error.localizedDescription
        }
    }

    private func grid(for result: DashboardResult) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(Array(result.widgets.enumerated()), id: \.offset) { _, widget in
                    DashboardWidgetCard(widget: widget, onShortcut: onShortcut)
                }
            }
            .padding()
        }
    }
}

/// Renders a single `DashboardWidgetResult`. Each case maps to a card style; an
/// `.error` widget renders a red-tinted "could not load" card so one bad tile
/// never blanks the grid.
private struct DashboardWidgetCard: View {
    let widget: DashboardWidgetResult
    let onShortcut: ((String) -> Void)?

    var body: some View {
        switch widget {
        case let .count(title, value, docType):
            kpiCard(title: title, value: "\(value)", footnote: docType)

        case let .list(title, columns, rows, _):
            listCard(title: title, columns: columns, rows: rows)

        case let .chart(title, columns, rows, _):
            chartCard(title: title, columns: columns, rows: rows)

        case let .shortcut(title, target):
            shortcutCard(title: title, target: target)

        case let .error(title, reason):
            errorCard(title: title, reason: reason)
        }
    }

    // MARK: - Card styles

    private func kpiCard(title: String, value: String, footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .mercantisCard()
    }

    private func listCard(title: String, columns: [String], rows: [[String?]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text("No records")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let values = row.compactMap { $0 }.filter { !$0.isEmpty }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(values.first ?? "—")
                            .font(.callout)
                            .lineLimit(1)
                        if values.count > 1 {
                            Text(values.dropFirst().joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .mercantisCard()
    }

    private func chartCard(title: String, columns: [String], rows: [[String?]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text("No data")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // Mini table mirroring the Flutter `_miniTable` (first 5 rows).
                ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { _, row in
                    Text(row.map { $0 ?? "" }.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if rows.count > 5 {
                    Text("+\(rows.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .mercantisCard()
    }

    private func shortcutCard(title: String, target: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Button("Open") {
                if !target.isEmpty { onShortcut?(target) }
            }
            .buttonStyle(MercantisSecondaryButtonStyle())
            .disabled(target.isEmpty || onShortcut == nil)
        }
        .mercantisCard()
    }

    private func errorCard(title: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(MercantisTheme.danger)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .mercantisCard()
        .overlay(
            RoundedRectangle(cornerRadius: MercantisSpacing.cardCornerRadius, style: .continuous)
                .stroke(MercantisTheme.danger.opacity(0.28), lineWidth: 1)
        )
    }
}
