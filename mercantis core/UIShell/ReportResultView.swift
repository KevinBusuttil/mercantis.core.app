//
//  ReportResultView.swift
//  mercantis core
//
//  Feature-parity port of the Flutter `ReportResultView`
//  (`mercantis_core_ui/lib/src/widgets/report_result_view.dart`). Renders a
//  `ReportResult` (`Reporting/ReportEngine.swift`) as a scrollable table with a
//  Copy-CSV / export action.
//
//  Consolidates and supersedes the orphaned `UIShell/GenericReportView.swift`:
//  the table layout (shared-width `Grid`, alternating row fill, column
//  humanisation) is carried over, and the Copy-CSV behaviour the Flutter widget
//  ships is added here. `ReportResult` (Swift) exposes only `columns: [String]`
//  and `rows: [[String?]]` — it has no `name` or `toCsv()` — so the report name
//  is passed in by the host and CSV is generated locally.
//
//  Wiring (replace `NavigationShell.reportDetail(reportId:)`) is described in
//  `CORE_VIEWS_WIRING.md`.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// SwiftUI table over a `ReportResult` with a Copy-CSV action and optional
/// refresh. Read-only: hosts that want filter chips wrap this view and
/// re-execute the report themselves.
public struct ReportResultView: View {

    /// The report's display name, shown in the header (and used as the CSV
    /// filename hint on export).
    public let title: String
    public let result: ReportResult
    /// When `false` the header omits the title (host shows it in the nav bar)
    /// but keeps the row count and actions.
    public let showsTitle: Bool
    public let onRefresh: (() -> Void)?

    @State private var copiedConfirmation = false

    public init(
        title: String,
        result: ReportResult,
        showsTitle: Bool = true,
        onRefresh: (() -> Void)? = nil
    ) {
        self.title = title
        self.result = result
        self.showsTitle = showsTitle
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if result.rowCount == 0 {
                emptyState
            } else {
                resultsTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MercantisTheme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if showsTitle {
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            Text(rowCountLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let onRefresh {
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    .buttonStyle(MercantisSecondaryButtonStyle())
                    .labelStyle(.titleAndIcon)
            }
            Button(copiedConfirmation ? "Copied" : "Copy CSV",
                   systemImage: copiedConfirmation ? "checkmark" : "square.and.arrow.up") {
                copyCSV()
            }
            .buttonStyle(MercantisSecondaryButtonStyle())
            .disabled(result.rowCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No data for this report yet",
            systemImage: "tray",
            description: Text("No rows matched the report's filters.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table

    private var resultsTable: some View {
        // Single-axis nested scroll views pin content to the top-leading edge so
        // a short report sits directly under the header rather than centring.
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                // A shared-width `Grid` keeps every column in register across the
                // header and all rows (independent HStacks would size per-row).
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                    headerRow
                    Divider()
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { index, row in
                        bodyRow(cells: row, isAlternate: index.isMultiple(of: 2))
                        if index < result.rows.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var headerRow: some View {
        GridRow {
            ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
                Text(Self.humanise(column))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 100, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private func bodyRow(cells: [String?], isAlternate: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell ?? "—")
                    .font(.callout)
                    .foregroundStyle(cell == nil ? .secondary : .primary)
                    .frame(minWidth: 100, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .background(isAlternate ? Color.secondary.opacity(0.05) : Color.clear)
    }

    // MARK: - CSV

    private func copyCSV() {
        let csv = Self.csv(from: result)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = csv
        #endif
        copiedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copiedConfirmation = false
        }
    }

    /// RFC-4180-style CSV: header row of humanised column labels followed by one
    /// line per result row. Fields containing a comma, quote, or newline are
    /// wrapped in quotes with embedded quotes doubled. Nil cells become empty.
    static func csv(from result: ReportResult) -> String {
        func escape(_ field: String) -> String {
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }
        var lines: [String] = []
        lines.append(result.columns.map { escape(humanise($0)) }.joined(separator: ","))
        for row in result.rows {
            lines.append(row.map { escape($0 ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private var rowCountLabel: String {
        result.rowCount == 1 ? "1 row" : "\(result.rowCount) rows"
    }

    /// Default column humanisation: `total_amount` → "Total Amount".
    static func humanise(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        var spaced = ""
        for (i, ch) in key.enumerated() {
            if ch == "_" {
                spaced += " "
            } else if ch.isUppercase, i > 0 {
                spaced += " "
                spaced.append(ch)
            } else {
                spaced.append(ch)
            }
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

#if DEBUG
#Preview("Report result") {
    ReportResultView(
        title: "Open Invoices",
        result: ReportResult(
            columns: ["invoice_no", "customer", "total_amount"],
            rows: [
                ["INV-001", "Acme Co", "1,200.00"],
                ["INV-002", "Globex", nil],
            ]
        )
    )
    .frame(width: 600, height: 360)
}
#endif
