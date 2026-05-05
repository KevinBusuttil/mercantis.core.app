//
//  DocumentNamingRule.swift
//  mercantis core
//
//  Phase B §3.6 (ADR-040) — Conditional naming-rule selector. Picks among
//  multiple `autoname` strategies based on document field values, evaluated
//  in priority order. ERPnext's per-company / per-fiscal-year naming series
//  needs this; the flat `DocType.autoname` field can only express one
//  strategy per DocType.
//

import Foundation

/// One conditional rule that selects an `autoname` strategy when its
/// `condition` evaluates true against the document being saved.
///
/// Rules are evaluated in ascending `priority` order; the first match wins.
/// If no rule matches, `NamingService.resolve` falls through to the
/// DocType's `autoname` (or `UUIDv7Strategy` if absent).
///
/// The `condition` expression sees every entry in `document.fields`. It is
/// sandboxed by `ExpressionEvaluator` (ADR-017). A `nil` / empty condition
/// is treated as "always match" — handy as a final-priority catch-all.
public struct DocumentNamingRule: Codable, Sendable, Equatable {
    public let id: String
    /// Lower numbers run first. Ties resolve by declaration order.
    public let priority: Int
    /// Sandboxed boolean expression. `nil` / empty matches every document.
    public let condition: String?
    /// `autoname` spec to use when this rule matches. Same syntax as
    /// `DocType.autoname` (e.g. `"naming_series:SINV-.YYYY.-.####"`).
    public let autoname: String

    public init(id: String, priority: Int, condition: String?, autoname: String) {
        self.id = id
        self.priority = priority
        self.condition = condition
        self.autoname = autoname
    }
}
