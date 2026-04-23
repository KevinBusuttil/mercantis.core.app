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
/// or arbitrary Swift APIs. Only the context dictionary (document field values)
/// is in scope. (ADR-008)
///
/// Supported syntax:
/// - Field comparisons: `field == "value"`, `field != "value"`, `field > 100`, `field < 100`
/// - Boolean operators: `&&`, `||`, `!`
/// - Parentheses for grouping
/// - Arithmetic formulas: `+`, `-`, `*`, `/` over numeric field values
public final class ExpressionEvaluator {

    public init() {}

    // MARK: - Boolean Evaluation

    /// Evaluate a boolean expression against a document's field values.
    public func evaluateBool(expression: String, context: [String: FieldValue]) throws -> Bool {
        let tokens = tokenize(expression)
        var pos = 0
        let result = try parseOr(tokens: tokens, pos: &pos, context: context)
        return result
    }

    // MARK: - Formula Evaluation

    /// Evaluate a formula expression that returns a FieldValue.
    /// Supports `+`, `-`, `*`, `/` over numeric values and field references.
    public func evaluateFormula(expression: String, context: [String: FieldValue]) throws -> FieldValue {
        let tokens = tokenize(expression)
        var pos = 0
        let result = try parseArithmetic(tokens: tokens, pos: &pos, context: context)
        return .double(result)
    }

    // MARK: - Errors

    public enum EvaluatorError: Error, Sendable {
        case unexpectedToken(String)
        case undefinedField(String)
        case typeMismatch(expected: String, got: String)
        case divisionByZero
    }

    // MARK: - Tokenizer

    private enum Token: Equatable {
        case identifier(String)
        case stringLiteral(String)
        case numberLiteral(Double)
        case boolLiteral(Bool)
        case op(String)
        case lparen
        case rparen
    }

    private func tokenize(_ expression: String) -> [Token] {
        var tokens: [Token] = []
        var idx = expression.startIndex

        while idx < expression.endIndex {
            let ch = expression[idx]

            // Skip whitespace.
            if ch.isWhitespace {
                idx = expression.index(after: idx)
                continue
            }

            // String literal.
            if ch == "\"" {
                var str = ""
                idx = expression.index(after: idx)
                while idx < expression.endIndex && expression[idx] != "\"" {
                    str.append(expression[idx])
                    idx = expression.index(after: idx)
                }
                if idx < expression.endIndex { idx = expression.index(after: idx) }
                tokens.append(.stringLiteral(str))
                continue
            }

            // Number literal. `-` is always an operator at the lexer level;
            // unary minus is handled by the parser.
            if ch.isNumber {
                var numStr = String(ch)
                idx = expression.index(after: idx)
                while idx < expression.endIndex && (expression[idx].isNumber || expression[idx] == ".") {
                    numStr.append(expression[idx])
                    idx = expression.index(after: idx)
                }
                tokens.append(.numberLiteral(Double(numStr) ?? 0))
                continue
            }

            // Parentheses.
            if ch == "(" { tokens.append(.lparen); idx = expression.index(after: idx); continue }
            if ch == ")" { tokens.append(.rparen); idx = expression.index(after: idx); continue }

            // Two-character operators: ==, !=, >=, <=, &&, ||.
            let nextIdx = expression.index(after: idx)
            if nextIdx < expression.endIndex {
                let two = String(expression[idx...nextIdx])
                if ["==", "!=", ">=", "<=", "&&", "||"].contains(two) {
                    tokens.append(.op(two))
                    idx = expression.index(idx, offsetBy: 2)
                    continue
                }
            }

            // Single-character operators.
            if [">", "<", "+", "-", "*", "/", "!"].contains(ch) {
                tokens.append(.op(String(ch)))
                idx = expression.index(after: idx)
                continue
            }

            // Identifier or keyword.
            if ch.isLetter || ch == "_" {
                var ident = String(ch)
                idx = expression.index(after: idx)
                while idx < expression.endIndex && (expression[idx].isLetter || expression[idx].isNumber || expression[idx] == "_" || expression[idx] == ".") {
                    ident.append(expression[idx])
                    idx = expression.index(after: idx)
                }
                switch ident {
                case "true":  tokens.append(.boolLiteral(true))
                case "false": tokens.append(.boolLiteral(false))
                default:      tokens.append(.identifier(ident))
                }
                continue
            }

            // Unknown character — skip.
            idx = expression.index(after: idx)
        }

        return tokens
    }

    // MARK: - Boolean Recursive Descent Parser

    private func parseOr(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Bool {
        var left = try parseAnd(tokens: tokens, pos: &pos, context: context)
        while pos < tokens.count, case .op("||") = tokens[pos] {
            pos += 1
            let right = try parseAnd(tokens: tokens, pos: &pos, context: context)
            left = left || right
        }
        return left
    }

    private func parseAnd(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Bool {
        var left = try parseNot(tokens: tokens, pos: &pos, context: context)
        while pos < tokens.count, case .op("&&") = tokens[pos] {
            pos += 1
            let right = try parseNot(tokens: tokens, pos: &pos, context: context)
            left = left && right
        }
        return left
    }

    private func parseNot(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Bool {
        if pos < tokens.count, case .op("!") = tokens[pos] {
            pos += 1
            return !(try parseNot(tokens: tokens, pos: &pos, context: context))
        }
        return try parseComparison(tokens: tokens, pos: &pos, context: context)
    }

    private func parseComparison(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Bool {
        // Parenthesised boolean sub-expression.
        if pos < tokens.count, case .lparen = tokens[pos] {
            pos += 1
            let result = try parseOr(tokens: tokens, pos: &pos, context: context)
            if pos < tokens.count, case .rparen = tokens[pos] { pos += 1 }
            return result
        }

        // Boolean literal.
        if pos < tokens.count, case .boolLiteral(let b) = tokens[pos] {
            pos += 1
            return b
        }

        // LHS value.
        let lhs = try parseValue(tokens: tokens, pos: &pos, context: context)

        guard pos < tokens.count, case .op(let opStr) = tokens[pos],
              ["==", "!=", ">", "<", ">=", "<="].contains(opStr) else {
            // No operator — treat as truthy check on the LHS.
            return isTruthy(lhs)
        }
        pos += 1

        let rhs = try parseValue(tokens: tokens, pos: &pos, context: context)

        return try compareValues(lhs: lhs, op: opStr, rhs: rhs)
    }

    // MARK: - Arithmetic Recursive Descent Parser

    private func parseArithmetic(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Double {
        var result = try parseTerm(tokens: tokens, pos: &pos, context: context)
        while pos < tokens.count {
            if case .op("+") = tokens[pos] {
                pos += 1
                result += try parseTerm(tokens: tokens, pos: &pos, context: context)
            } else if case .op("-") = tokens[pos] {
                pos += 1
                result -= try parseTerm(tokens: tokens, pos: &pos, context: context)
            } else {
                break
            }
        }
        return result
    }

    private func parseTerm(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Double {
        var result = try parseFactor(tokens: tokens, pos: &pos, context: context)
        while pos < tokens.count {
            if case .op("*") = tokens[pos] {
                pos += 1
                result *= try parseFactor(tokens: tokens, pos: &pos, context: context)
            } else if case .op("/") = tokens[pos] {
                pos += 1
                let divisor = try parseFactor(tokens: tokens, pos: &pos, context: context)
                guard divisor != 0 else { throw EvaluatorError.divisionByZero }
                result /= divisor
            } else {
                break
            }
        }
        return result
    }

    private func parseFactor(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> Double {
        guard pos < tokens.count else { return 0 }

        // Unary +/- prefix: `-5`, `--x`, `+3`.
        if case .op("-") = tokens[pos] {
            pos += 1
            return -(try parseFactor(tokens: tokens, pos: &pos, context: context))
        }
        if case .op("+") = tokens[pos] {
            pos += 1
            return try parseFactor(tokens: tokens, pos: &pos, context: context)
        }

        if case .lparen = tokens[pos] {
            pos += 1
            let result = try parseArithmetic(tokens: tokens, pos: &pos, context: context)
            if pos < tokens.count, case .rparen = tokens[pos] { pos += 1 }
            return result
        }

        if case .numberLiteral(let n) = tokens[pos] {
            pos += 1
            return n
        }

        if case .identifier(let name) = tokens[pos] {
            pos += 1
            guard let fieldValue = context[name] else {
                throw EvaluatorError.undefinedField(name)
            }
            return numericValue(fieldValue)
        }

        return 0
    }

    // MARK: - Value Parsing

    private enum ExprValue {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
    }

    private func parseValue(tokens: [Token], pos: inout Int, context: [String: FieldValue]) throws -> ExprValue {
        guard pos < tokens.count else { return .null }

        switch tokens[pos] {
        case .stringLiteral(let s):
            pos += 1
            return .string(s)
        case .numberLiteral(let n):
            pos += 1
            return .number(n)
        case .boolLiteral(let b):
            pos += 1
            return .bool(b)
        case .identifier(let name):
            pos += 1
            guard let fieldValue = context[name] else {
                return .null
            }
            return fieldValueToExprValue(fieldValue)
        case .op("-"):
            pos += 1
            let inner = try parseValue(tokens: tokens, pos: &pos, context: context)
            guard case .number(let n) = inner else {
                throw EvaluatorError.typeMismatch(expected: "number", got: "\(inner)")
            }
            return .number(-n)
        case .op("+"):
            pos += 1
            return try parseValue(tokens: tokens, pos: &pos, context: context)
        default:
            throw EvaluatorError.unexpectedToken("\(tokens[pos])")
        }
    }

    // MARK: - Comparison

    private func compareValues(lhs: ExprValue, op: String, rhs: ExprValue) throws -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)):
            switch op {
            case "==": return l == r
            case "!=": return l != r
            case ">":  return l > r
            case "<":  return l < r
            case ">=": return l >= r
            case "<=": return l <= r
            default:   return false
            }
        case (.number(let l), .number(let r)):
            switch op {
            case "==": return l == r
            case "!=": return l != r
            case ">":  return l > r
            case "<":  return l < r
            case ">=": return l >= r
            case "<=": return l <= r
            default:   return false
            }
        case (.bool(let l), .bool(let r)):
            switch op {
            case "==": return l == r
            case "!=": return l != r
            default:   return false
            }
        case (.null, .null):
            return op == "=="
        default:
            return op == "!="
        }
    }

    // MARK: - Helpers

    private func isTruthy(_ value: ExprValue) -> Bool {
        switch value {
        case .bool(let b): return b
        case .string(let s): return !s.isEmpty
        case .number(let n): return n != 0
        case .null: return false
        }
    }

    private func numericValue(_ value: FieldValue) -> Double {
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s) ?? 0
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        }
    }

    private func fieldValueToExprValue(_ value: FieldValue) -> ExprValue {
        switch value {
        case .string(let s): return .string(s)
        case .int(let i): return .number(Double(i))
        case .double(let d): return .number(d)
        case .bool(let b): return .bool(b)
        case .null: return .null
        }
    }
}
