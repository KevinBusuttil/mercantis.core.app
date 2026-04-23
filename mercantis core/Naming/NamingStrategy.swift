//
//  NamingStrategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Document naming subsystem.
//

import Foundation

/// A strategy that resolves a document's ID from a DocType's `autoname` spec.
///
/// Each strategy declares one or more tokens it handles (e.g. `"uuid"`,
/// `"naming_series"`, `"field"`, `"prompt"`, `"format"`). `NamingService`
/// dispatches based on the leading token of `DocType.autoname`. Strategies are
/// stateless and `Sendable`; any per-call state arrives via `NamingContext`.
public protocol NamingStrategy: Sendable {

    /// Tokens this strategy handles. Case-insensitive — `NamingService` lower-cases
    /// both sides during lookup.
    var handles: Set<String> { get }

    /// Resolve the document's ID.
    ///
    /// - Parameters:
    ///   - docType: The DocType the document belongs to.
    ///   - document: The in-memory document being saved. Its `id` is expected
    ///     to be empty on entry; all other fields are populated.
    ///   - argument: The substring of `DocType.autoname` following the colon
    ///     (e.g. for `"naming_series:SINV-.YYYY.-.####"` this is
    ///     `"SINV-.YYYY.-.####"`). `nil` for bare tokens like `"UUID"`.
    ///   - context: Ambient parameters the strategy may need (see `NamingContext`).
    func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String
}

/// Ambient inputs that some strategies need but are not part of the document itself.
///
/// - `userSuppliedName` is the optional caller-provided name used by
///   `PromptStrategy`. `DocumentEngine.save` does not accept a name today, so
///   UI callers that use `prompt` naming must pre-populate `document.id`
///   themselves (in which case naming is skipped entirely) or route through a
///   future `save(_:userName:)` overload.
/// - `now` makes date-token expansion deterministic under test.
/// - `counterProvider` reserves and returns the next counter value for a given
///   series key. The closure is responsible for its own atomicity; see
///   `DocumentEngine+Naming` for the SQLite-backed default.
public struct NamingContext: Sendable {
    public let userSuppliedName: String?
    public let now: Date
    public let counterProvider: @Sendable (_ seriesKey: String) throws -> Int

    public init(
        userSuppliedName: String? = nil,
        now: Date = Date(),
        counterProvider: @escaping @Sendable (_ seriesKey: String) throws -> Int = { _ in
            throw NamingError.noCounterProvider
        }
    ) {
        self.userSuppliedName = userSuppliedName
        self.now = now
        self.counterProvider = counterProvider
    }
}

public enum NamingError: Error, Equatable, Sendable {
    case unknownStrategy(String)
    case malformedAutonameToken(String)
    case invalidNamingSeries(pattern: String, reason: String)
    case missingFieldValue(fieldKey: String)
    case missingUserSuppliedName
    case noCounterProvider
}
