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
    private let expressionEvaluator: ExpressionEvaluator

    public init(
        strategies: [NamingStrategy] = NamingService.defaultStrategies(),
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()
    ) {
        var map: [String: NamingStrategy] = [:]
        for strategy in strategies {
            for token in strategy.handles {
                map[token.lowercased()] = strategy
            }
        }
        self.strategies = map
        self.expressionEvaluator = expressionEvaluator
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

    /// Resolve the document's ID according to the DocType's `namingRules`
    /// (Phase B §3.6, ADR-040), falling back to `autoname` if no rule matches.
    ///
    /// Rules run in ascending `priority` order; ties resolve by declaration
    /// order. The first rule whose `condition` evaluates `true` against the
    /// document's fields wins, and its `autoname` spec is used in place of
    /// the DocType's. A `nil` / empty / whitespace-only condition matches
    /// every document — useful as a final-priority catch-all.
    ///
    /// Conditions that fail to evaluate (parse error, type mismatch) are
    /// skipped fail-closed: the rule is treated as a non-match and the
    /// next rule (or the DocType `autoname`) is tried.
    ///
    /// A DocType with no rules and no `autoname` (or `autoname == "UUID"`)
    /// uses `UUIDv7Strategy` — the recommended offline-safe default.
    public func resolve(
        docType: DocType,
        document: Document,
        context: NamingContext
    ) throws -> String {
        let resolvedAutoname = selectAutoname(forDocType: docType, document: document)
        return try dispatch(
            autoname: resolvedAutoname,
            docType: docType,
            document: document,
            context: context
        )
    }

    /// Evaluate `docType.namingRules` and return the winning `autoname`
    /// spec, falling back to `docType.autoname` if no rule matches.
    private func selectAutoname(forDocType docType: DocType, document: Document) -> String? {
        guard !docType.namingRules.isEmpty else { return docType.autoname }
        let ordered = docType.namingRules.sorted { $0.priority < $1.priority }
        for rule in ordered {
            let trimmed = rule.condition?.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed?.isEmpty ?? true {
                return rule.autoname
            }
            let passes = (try? expressionEvaluator.evaluateBool(
                expression: trimmed!,
                context: document.fields
            )) ?? false
            if passes {
                return rule.autoname
            }
        }
        return docType.autoname
    }

    private func dispatch(
        autoname: String?,
        docType: DocType,
        document: Document,
        context: NamingContext
    ) throws -> String {
        let raw = (autoname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

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
