//
//  ReportValueFormatter.swift
//  mercantis core
//
//  Shared, side-effect-free formatting of a `FieldValue` into the
//  optional string a `ReportResult` cell carries. Both the built-in
//  `ReportEngine` and the `SavedReportEngine` (ADR-050) render cells
//  through this single helper so column values look identical no matter
//  which path produced them.
//

import Foundation

/// Formats a `FieldValue` into the display string used for a report cell.
///
/// The mapping is intentionally lossless-enough for tabular display but not
/// a round-trippable encoding: doubles are fixed to two decimals, booleans
/// read as "Yes"/"No", and the opaque `.data` / `.array` cases collapse to a
/// short summary. `nil` and `.null` both render as a missing cell (`nil`),
/// which `GenericReportView` shows as an em dash.
public enum ReportValueFormatter {

    /// Render a single optional `FieldValue` as a report cell string.
    public static func string(from value: FieldValue?) -> String? {
        switch value {
        case .string(let s):   return s
        case .int(let i):      return "\(i)"
        case .double(let d):   return String(format: "%.2f", d)
        case .bool(let b):     return b ? "Yes" : "No"
        case .date(let d):     return dateFormatter.string(from: d)
        case .dateTime(let d): return dateTimeFormatter.string(from: d)
        case .data(let d):     return "<\(d.count) bytes>"
        case .array(let xs):   return "[\(xs.count) items]"
        case .null, nil:       return nil
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
