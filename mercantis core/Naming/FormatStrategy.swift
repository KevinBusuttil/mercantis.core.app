//
//  FormatStrategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Format-string naming with field interpolation.
//

import Foundation

/// Format string with `{fieldKey}` placeholders. Example:
/// `autoname: "format:{customer}-{year}"` reads `document.fields["customer"]`
/// and `document.fields["year"]`, concatenated with the dash literal in between.
///
/// Unknown keys throw `NamingError.missingFieldValue`; unbalanced braces throw
/// `NamingError.malformedAutonameToken`. Dates are expanded as ISO8601 strings;
/// opaque values (`.data`, `.array`) are not stringifiable and throw
/// `NamingError.missingFieldValue`.
public struct FormatStrategy: NamingStrategy {

    public var handles: Set<String> { ["format"] }

    public init() {}

    public func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String {
        guard let pattern = argument, !pattern.isEmpty else {
            throw NamingError.malformedAutonameToken(docType.autoname ?? "")
        }

        var result = ""
        var cursor = pattern.startIndex

        while cursor < pattern.endIndex {
            let char = pattern[cursor]
            if char == "{" {
                guard let close = pattern[cursor...].firstIndex(of: "}") else {
                    throw NamingError.malformedAutonameToken("format:\(pattern)")
                }
                let keyStart = pattern.index(after: cursor)
                let key = String(pattern[keyStart..<close])
                guard !key.isEmpty else {
                    throw NamingError.malformedAutonameToken("format:\(pattern)")
                }
                guard let value = document.fields[key] else {
                    throw NamingError.missingFieldValue(fieldKey: key)
                }
                guard let stringValue = Self.stringValue(of: value) else {
                    throw NamingError.missingFieldValue(fieldKey: key)
                }
                result += stringValue
                cursor = pattern.index(after: close)
            } else {
                result.append(char)
                cursor = pattern.index(after: cursor)
            }
        }
        return result
    }

    private static func stringValue(of value: FieldValue) -> String? {
        switch value {
        case .string(let s): return s.isEmpty ? nil : s
        case .int(let n): return String(n)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .date(let d), .dateTime(let d): return ISO8601DateFormatter().string(from: d)
        case .null, .data, .array: return nil
        }
    }
}
