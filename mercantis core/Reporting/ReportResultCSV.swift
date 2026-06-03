//
//  ReportResultCSV.swift
//  mercantis core
//
//  Reusable CSV serialisation for a `ReportResult`. Lives in `MercantisCore`
//  (not the UI layer) so headless consumers — the CLI, exporters, tests —
//  can turn a report into CSV without importing SwiftUI. Presentation of the
//  result (a save panel, a share sheet) stays with the host app.
//

import Foundation

public extension ReportResult {

    /// Serialise the result as RFC-4180 CSV: a header row of column names
    /// followed by one line per row. A field is quoted when it contains a
    /// comma, double-quote, or newline, and embedded quotes are doubled.
    /// `nil` cells render as empty fields.
    ///
    /// - Parameters:
    ///   - separator: Field delimiter. Defaults to `","`.
    ///   - newline: Row delimiter. Defaults to `"\n"`.
    func csvString(separator: String = ",", newline: String = "\n") -> String {
        var lines: [String] = []
        lines.append(columns.map { Self.escapeCSVField($0, separator: separator) }.joined(separator: separator))
        for row in rows {
            lines.append(row.map { Self.escapeCSVField($0 ?? "", separator: separator) }.joined(separator: separator))
        }
        return lines.joined(separator: newline)
    }

    private static func escapeCSVField(_ field: String, separator: String) -> String {
        let needsQuoting = field.contains(separator)
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
