//
//  PromptStrategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Caller-supplied name (UI prompt).
//

import Foundation

/// Requires the caller to supply a name via `NamingContext.userSuppliedName`.
/// Throws `NamingError.missingUserSuppliedName` if no name is provided —
/// which is the correct behaviour: there is no sensible fallback for a
/// DocType that intentionally defers naming to the user.
public struct PromptStrategy: NamingStrategy {

    public var handles: Set<String> { ["prompt"] }

    public init() {}

    public func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String {
        guard let name = context.userSuppliedName, !name.isEmpty else {
            throw NamingError.missingUserSuppliedName
        }
        return name
    }
}
