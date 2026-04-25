//
//  ExpressionAST.swift
//  mercantis core
//
//  Typed AST and lexer for the sandboxed expression engine. (ADR-017, P2.1)
//
//  Splitting the evaluator into a parser (string → AST) and an interpreter
//  (AST → value) unlocks three things called out in the proposal:
//  - static analysis of field references (`ExpressionEvaluator.referencedFields`)
//  - parse-once / evaluate-many caching for expressions on metadata that
//    runs against many documents (visibilityExpression, readOnlyExpression,
//    automation conditionExpression, list whereExpression)
//  - parse errors that carry a source position so we can render a caret.
//

import Foundation

// MARK: - Source positions

/// Half-open `[start, end)` byte offset range into the original expression
/// source. Stored on every AST node so error messages can point back to the
/// relevant span and IDE-style tooling can highlight regions later.
public struct ExpressionSourceRange: Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public static let zero = ExpressionSourceRange(start: 0, end: 0)
}

// MARK: - AST

/// A node in the parsed expression tree. The internal representation of
/// every expression after a successful `ExpressionParser.parse` call.
public indirect enum ExpressionNode: Sendable, Equatable {
    /// `"hello"`, `42`, `true`, `null`.
    case literal(LiteralValue, ExpressionSourceRange)

    /// `fieldKey` — looked up in the evaluation context.
    case fieldRef(String, ExpressionSourceRange)

    /// `!x`, `-x`, `+x`.
    case unary(UnaryOperator, ExpressionNode, ExpressionSourceRange)

    /// `a + b`, `a == b`, `a && b`, …
    case binary(BinaryOperator, ExpressionNode, ExpressionNode, ExpressionSourceRange)

    /// `lookup("Item", code, "rate")` — reserved for future extension
    /// (P2.2). The parser doesn't currently emit `.call`; the evaluator
    /// rejects it. Keeping the case in the AST avoids a breaking change
    /// when `lookup()` lands.
    case call(name: String, args: [ExpressionNode], ExpressionSourceRange)

    public var range: ExpressionSourceRange {
        switch self {
        case .literal(_, let r),
             .fieldRef(_, let r),
             .unary(_, _, let r),
             .binary(_, _, _, let r),
             .call(_, _, let r):
            return r
        }
    }
}

/// Constant values producible by the parser. The runtime `ExpressionValue`
/// (in `ExpressionInterpreter.swift`) reuses these cases plus a few extra
/// (`.number`-derived dates, etc.) — keeping this enum literal-only keeps
/// `ExpressionNode.literal` provably Equatable.
public enum LiteralValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

public enum UnaryOperator: String, Sendable, Equatable {
    case not = "!"
    case minus = "-"
    case plus = "+"
}

public enum BinaryOperator: String, Sendable, Equatable {
    // Logical
    case or  = "||"
    case and = "&&"
    // Comparison
    case eq = "=="
    case ne = "!="
    case gt = ">"
    case lt = "<"
    case ge = ">="
    case le = "<="
    // Arithmetic
    case add = "+"
    case sub = "-"
    case mul = "*"
    case div = "/"
}

// MARK: - Lexer

/// A token produced by the lexer. Each token carries its source range so
/// the parser can attach positions to the AST nodes it builds.
struct ExpressionToken: Equatable {
    enum Kind: Equatable {
        case identifier(String)
        case stringLiteral(String)
        case numberLiteral(Double)
        case boolLiteral(Bool)
        case nullLiteral
        case op(String)
        case lparen
        case rparen
        case comma
    }

    let kind: Kind
    let range: ExpressionSourceRange
}

/// Errors the lexer / parser can raise. Distinct from
/// `ExpressionEvaluator.EvaluatorError` so the parser layer is not
/// coupled to the public error surface — the evaluator wraps these into
/// `EvaluatorError.parseError` for callers.
public struct ExpressionParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    /// 0-based byte offset into the original expression source where the
    /// error was detected. Falls inside the source string except for
    /// "unexpected end of input" errors, which point at `source.count`.
    public let position: Int
    public let source: String

    public init(message: String, position: Int, source: String) {
        self.message = message
        self.position = position
        self.source = source
    }

    /// Multi-line rendering with a caret pointing at `position`. Suitable
    /// for log output; UI surfaces will typically use just `message` plus
    /// `position` to render their own highlight.
    public var description: String {
        let safePos = max(0, min(position, source.utf8.count))
        // Convert utf8 offset → String view positions; clamp at end.
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: safePos)
        let stringIdx = String.Index(utf8Index, within: source) ?? source.endIndex
        let prefix = source[..<stringIdx]
        let column = prefix.count
        let caretPad = String(repeating: " ", count: column)
        return "\(message) at column \(column + 1)\n\(source)\n\(caretPad)^"
    }
}

/// Splits an expression source string into tokens. The lexer is
/// deliberately permissive — it only fails on unterminated string
/// literals; everything else is the parser's job.
struct ExpressionLexer {
    let source: String

    func tokenize() throws -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []
        let scalars = Array(source)
        var i = 0
        let n = scalars.count

        // Map char indices ↔ utf8 offsets so token ranges agree with the
        // parse-error byte offsets.
        var utf8Offset = 0
        var utf8Offsets: [Int] = []
        utf8Offsets.reserveCapacity(n + 1)
        utf8Offsets.append(0)
        for ch in scalars {
            utf8Offset += String(ch).utf8.count
            utf8Offsets.append(utf8Offset)
        }

        func range(_ start: Int, _ end: Int) -> ExpressionSourceRange {
            ExpressionSourceRange(start: utf8Offsets[start], end: utf8Offsets[end])
        }

        while i < n {
            let ch = scalars[i]

            // Whitespace.
            if ch.isWhitespace { i += 1; continue }

            let start = i

            // String literal — supports `\"` and `\\` escapes; everything
            // else passes through.
            if ch == "\"" {
                i += 1
                var str = ""
                while i < n && scalars[i] != "\"" {
                    if scalars[i] == "\\" && i + 1 < n {
                        let next = scalars[i + 1]
                        switch next {
                        case "\"": str.append("\"")
                        case "\\": str.append("\\")
                        case "n":  str.append("\n")
                        case "t":  str.append("\t")
                        default:   str.append(next)
                        }
                        i += 2
                    } else {
                        str.append(scalars[i])
                        i += 1
                    }
                }
                guard i < n, scalars[i] == "\"" else {
                    throw ExpressionParseError(
                        message: "unterminated string literal",
                        position: utf8Offsets[start],
                        source: source
                    )
                }
                i += 1   // consume closing quote
                tokens.append(.init(kind: .stringLiteral(str), range: range(start, i)))
                continue
            }

            // Number literal. Unary minus is handled by the parser, not the
            // lexer — `-5` tokenizes to two tokens `-` and `5`.
            if ch.isNumber {
                while i < n && (scalars[i].isNumber || scalars[i] == ".") { i += 1 }
                let text = String(scalars[start..<i])
                let value = Double(text) ?? 0
                tokens.append(.init(kind: .numberLiteral(value), range: range(start, i)))
                continue
            }

            // Parens / comma.
            if ch == "(" { tokens.append(.init(kind: .lparen, range: range(i, i + 1))); i += 1; continue }
            if ch == ")" { tokens.append(.init(kind: .rparen, range: range(i, i + 1))); i += 1; continue }
            if ch == "," { tokens.append(.init(kind: .comma,  range: range(i, i + 1))); i += 1; continue }

            // Two-character operators.
            if i + 1 < n {
                let two = String(scalars[i...i + 1])
                if ["==", "!=", ">=", "<=", "&&", "||"].contains(two) {
                    tokens.append(.init(kind: .op(two), range: range(i, i + 2)))
                    i += 2
                    continue
                }
            }

            // Single-character operators.
            if "+-*/<>!".contains(ch) {
                tokens.append(.init(kind: .op(String(ch)), range: range(i, i + 1)))
                i += 1
                continue
            }

            // Identifier / keyword.
            if ch.isLetter || ch == "_" {
                while i < n,
                      scalars[i].isLetter || scalars[i].isNumber
                        || scalars[i] == "_" || scalars[i] == "."
                { i += 1 }
                let ident = String(scalars[start..<i])
                let r = range(start, i)
                switch ident {
                case "true":  tokens.append(.init(kind: .boolLiteral(true),  range: r))
                case "false": tokens.append(.init(kind: .boolLiteral(false), range: r))
                case "null":  tokens.append(.init(kind: .nullLiteral,        range: r))
                default:      tokens.append(.init(kind: .identifier(ident),  range: r))
                }
                continue
            }

            // Anything else is an unknown character — surface it instead of
            // silently skipping. The old evaluator quietly dropped these,
            // which made `a $ b` look like `a b` with no warning.
            throw ExpressionParseError(
                message: "unexpected character '\(ch)'",
                position: utf8Offsets[start],
                source: source
            )
        }

        return tokens
    }
}
