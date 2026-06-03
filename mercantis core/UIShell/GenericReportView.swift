//
//  GenericReportView.swift
//  mercantis core
//
//  Phase D / item 14 (ADR-049) — Metadata-driven report renderer. Pairs
//  with `ReportEngine.execute(report:)` and `ReportResult` to display
//  any registered report without per-report SwiftUI code. Hub Wall 9 in
//  HUB-STATUS.md is satisfied by this view.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// SwiftUI table view over a `ReportResult`. The table renders the
/// report's declared columns as headers and one row per result row.
///
/// Callers that want filter chips or sortable columns can wrap this
/// view in their own form and re-execute the report when the user
/// changes filters; this view is intentionally read-only.
public struct GenericReportView: View {

    public let title: String
    public let result: ReportResult
    /// When `false`, the header omits the title text but keeps the row count
    /// and action buttons. Hosts that already show the report name elsewhere
    /// (e.g. a navigation bar) use this to avoid a duplicate title.
    public let showsTitle: Bool
    public let onRefresh: (() -> Void)?
    public let onExportCSV: (() -> Void)?

    public init(
        title: String,
        result: ReportResult,
        showsTitle: Bool = true,
        onRefresh: (() -> Void)? = nil,
        onExportCSV: (() -> Void)? = nil
    ) {
        self.title = title
        self.result = result
        self.showsTitle = showsTitle
        self.onRefresh = onRefresh
        self.onExportCSV = onExportCSV
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if result.rowCount == 0 {
                emptyState
            } else {
                resultsTable
            }
        }
        // Fill the available space and keep content pinned to the top so the
        // table sits directly under the header rather than floating in the
        // vertical centre when there are only a few rows.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sub-views

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
                    .labelStyle(.iconOnly)
            }
            if let onExportCSV {
                Button("Export CSV", systemImage: "square.and.arrow.up", action: onExportCSV)
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No matching rows")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var resultsTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                tableHeaderRow
                Divider()
                ForEach(Array(result.rows.enumerated()), id: \.offset) { (index, row) in
                    tableBodyRow(cells: row, isAlternate: index.isMultiple(of: 2))
                    if index < result.rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 16) {
            ForEach(Array(result.columns.enumerated()), id: \.offset) { (_, column) in
                Text(humanise(column))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 100, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    private func tableBodyRow(cells: [String?], isAlternate: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(Array(cells.enumerated()), id: \.offset) { (_, cell) in
                Text(cell ?? "—")
                    .font(.callout)
                    .foregroundStyle(cell == nil ? .secondary : .primary)
                    .frame(minWidth: 100, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .background(
            isAlternate
                ? Color.secondary.opacity(0.05)
                : Color.clear
        )
    }

    // MARK: - Helpers

    private var rowCountLabel: String {
        result.rowCount == 1 ? "1 row" : "\(result.rowCount) rows"
    }

    /// Default column humanisation: `total_amount` → "Total Amount".
    /// Hosts that want custom labels should pre-process the result.
    private func humanise(_ key: String) -> String {
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
