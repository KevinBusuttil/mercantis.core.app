//
//  NamingService.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Strategy registry and dispatch.
//

import Foundation

/// Resolves `Document.id` from `DocType.autoname` by dispatching to the
/// appropriate `NamingStrategy`. Built-in tokens:
///
/// | `autoname` value                      | Strategy              |
/// |---------------------------------------|-----------------------|
/// | `nil` / `""` / `"UUID"`                | `UUIDv7Strategy`      |
/// | `"naming_series:SINV-.YYYY.-.####"`   | `NamingSeriesStrategy`|
/// | `"field:email"`                       | `FieldDerivedStrategy`|
/// | `"prompt"`                            | `PromptStrategy`      |
/// | `"format:{customer}-{year}"`          | `FormatStrategy`      |
///
/// Additional strategies can be contributed by calling `register(_:)`.
public final class NamingService {

    private var strategies: [String: NamingStrategy]

    public init(strategies: [NamingStrategy] = NamingService.defaultStrategies()) {
        var map: [String: NamingStrategy] = [:]
        for strategy in strategies {
            for token in strategy.handles {
                map[token.lowercased()] = strategy
            }
        }
        self.strategies = map
    }

    public static func defaultStrategies() -> [NamingStrategy] {
        [
            UUIDv7Strategy(),
            NamingSeriesStrategy(),
            FieldDerivedStrategy(),
            PromptStrategy(),
            FormatStrategy()
        ]
    }

    /// Register (or replace) a strategy. Later registrations override earlier
    /// ones for the same token.
    public func register(_ strategy: NamingStrategy) {
        for token in strategy.handles {
            strategies[token.lowercased()] = strategy
        }
    }

    /// Resolve the document's ID according to the DocType's `autoname`.
    ///
    /// A DocType with no `autoname` (or `autoname == "UUID"`) uses
    /// `UUIDv7Strategy` — this is the recommended offline-safe default.
    public func resolve(
        docType: DocType,
        document: Document,
        context: NamingContext
    ) throws -> String {
        let raw = (docType.autoname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.isEmpty {
            return try dispatchUUID(docType: docType, document: document, context: context)
        }

        let (token, argument) = parse(raw)

        // Bare "UUID" (any case) without a colon is the default strategy.
        if argument == nil && token.lowercased() == "uuid" {
            return try dispatchUUID(docType: docType, document: document, context: context)
        }

        guard let strategy = strategies[token.lowercased()] else {
            throw NamingError.unknownStrategy(token)
        }
        return try strategy.resolve(
            docType: docType,
            document: document,
            argument: argument,
            context: context
        )
    }

    private func dispatchUUID(
        docType: DocType,
        document: Document,
        context: NamingContext
    ) throws -> String {
        guard let uuid = strategies["uuid"] else {
            // Only possible if a caller registered a strategy list that omits UUIDv7.
            throw NamingError.unknownStrategy("UUID")
        }
        return try uuid.resolve(
            docType: docType,
            document: document,
            argument: nil,
            context: context
        )
    }

    /// Split `"naming_series:SINV-.YYYY.-.####"` into (`"naming_series"`,
    /// `"SINV-.YYYY.-.####"`). A bare `"prompt"` returns (`"prompt"`, `nil`).
    private func parse(_ spec: String) -> (token: String, argument: String?) {
        if let colon = spec.firstIndex(of: ":") {
            let token = String(spec[..<colon])
            let argument = String(spec[spec.index(after: colon)...])
            return (token, argument)
        }
        return (spec, nil)
    }
}
