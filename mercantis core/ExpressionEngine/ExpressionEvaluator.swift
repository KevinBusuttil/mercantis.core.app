//
//  ExpressionEvaluator.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Sandboxed expression evaluator for automation rules, visibility conditions,
/// and formula fields. (ADR-004, ADR-008)
///
/// Expressions are evaluated in a sandbox with NO access to file system, network,
/// or arbitrary Swift APIs. (ADR-008)
///
/// JavaScriptCore or similar runtimes may ONLY be used to evaluate manifest expressions
/// and must operate with no access to I/O, globals, or system APIs. (ADR-008)
public final class ExpressionEvaluator {

    public init() {}

    /// Evaluate a boolean expression against a document's field values.
    /// Used for visibility conditions, automation rule conditions, etc.
    public func evaluateBool(expression: String, context: [String: FieldValue]) throws -> Bool {
        // TODO: Parse and evaluate expression in sandbox
        // TODO: No access to file system, network, or arbitrary Swift APIs (ADR-008)
        return false
    }

    /// Evaluate a formula expression that returns a FieldValue.
    /// Used for formula fields.
    public func evaluateFormula(expression: String, context: [String: FieldValue]) throws -> FieldValue {
        // TODO: Parse and evaluate expression in sandbox
        return .null
    }
}
