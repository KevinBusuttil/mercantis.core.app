//
//  FieldDerivedStrategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Use a field's value as the document ID.
//

import Foundation

/// Uses the value of a named field as the document ID. Example: `autoname: "field:email"`
/// — an unambiguous natural key for a user or contact DocType.
///
/// Throws if the referenced field is absent, null, or a non-convertible `FieldValue`
/// case. The caller is responsible for ensuring the field is `required: true` on
/// the DocType if they do not want `save` to fail late.
public struct FieldDerivedStrategy: NamingStrategy {

    public var handles: Set<String> { ["field"] }

    public init() {}

    public func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String {
        guard let fieldKey = argument, !fieldKey.isEmpty else {
            throw NamingError.malformedAutonameToken(docType.autoname ?? "")
        }
        guard let value = document.fields[fieldKey] else {
            throw NamingError.missingFieldValue(fieldKey: fieldKey)
        }
        switch value {
        case .string(let s):
            guard !s.isEmpty else { throw NamingError.missingFieldValue(fieldKey: fieldKey) }
            return s
        case .int(let n):
            return String(n)
        case .double(let d):
            return String(d)
        case .date(let d), .dateTime(let d):
            return ISO8601DateFormatter().string(from: d)
        case .bool, .null, .data, .array:
            throw NamingError.missingFieldValue(fieldKey: fieldKey)
        }
    }
}
