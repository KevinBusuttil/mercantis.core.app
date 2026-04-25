//
//  ExpressionParser.swift
//  mercantis core
//
//  Recursive-descent parser that produces a typed `ExpressionNode` AST
//  from an expression source string. (ADR-017, P2.1)
//
//  Grammar — highest precedence first, so binding tightness matches the
//  ordering in `BinaryOperator`:
//
//      expression    := or
//      or            := and ('||' and)*
//      and           := equality ('&&' equality)*
//      equality      := comparison (('==' | '!=') comparison)*
//      comparison    := additive (('>' | '<' | '>=' | '<=') additive)*
//      additive      := multiplicative (('+' | '-') multiplicative)*
//      multiplicative:= unary (('*' | '/') unary)*
//      unary         := ('!' | '-' | '+') unary | call
//      call          := primary ('(' (expression (',' expression)*)? ')')?
//      primary       := number | string | bool | null | identifier
//                     | '(' expression ')'
//
//  Parse errors carry a 0-based byte offset (`ExpressionParseError`) so
//  the public evaluator can render a caret in error output.
//

import Foundation

/// Two-phase parser. Construct with the source string, then call
/// `parse()` to obtain the AST. The instance is single-use — callers
/// should not reuse a parser after `parse()` returns or throws.
struct ExpressionParser {
    let source: String
    private var tokens: [ExpressionToken] = []
    private var pos: Int = 0

    init(source: String) {
        self.source = source
    }

    // MARK: - Entry point

    mutating func parse() throws -> ExpressionNode {
        let lexer = ExpressionLexer(source: source)
        tokens = try lexer.tokenize()
        pos = 0

        // Empty source — match the legacy behaviour of "evaluates to .null,
        // which fails truthiness in `evaluateBool`". An empty range is fine.
        guard !tokens.isEmpty else {
            return .literal(.null, .zero)
        }

        let node = try parseOr()

        // Reject trailing tokens explicitly. The legacy implementation
        // silently ignored them; that masked typos like `a == b c` which
        // would parse the `a == b` half and drop `c`.
        if pos < tokens.count {
            let tok = tokens[pos]
            throw ExpressionParseError(
                message: "unexpected token after expression",
                position: tok.range.start,
                source: source
            )
        }

        return node
    }

    // MARK: - Precedence climb

    private mutating func parseOr() throws -> ExpressionNode {
        var left = try parseAnd()
        while case .op("||")? = peek() {
            consume()
            let right = try parseAnd()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(.or, left, right, r)
        }
        return left
    }

    private mutating func parseAnd() throws -> ExpressionNode {
        var left = try parseEquality()
        while case .op("&&")? = peek() {
            consume()
            let right = try parseEquality()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(.and, left, right, r)
        }
        return left
    }

    private mutating func parseEquality() throws -> ExpressionNode {
        var left = try parseComparison()
        while let kind = peek() {
            let op: BinaryOperator?
            switch kind {
            case .op("=="): op = .eq
            case .op("!="): op = .ne
            default:        op = nil
            }
            guard let bop = op else { break }
            consume()
            let right = try parseComparison()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(bop, left, right, r)
        }
        return left
    }

    private mutating func parseComparison() throws -> ExpressionNode {
        var left = try parseAdditive()
        while let kind = peek() {
            let op: BinaryOperator?
            switch kind {
            case .op(">"):  op = .gt
            case .op("<"):  op = .lt
            case .op(">="): op = .ge
            case .op("<="): op = .le
            default:        op = nil
            }
            guard let bop = op else { break }
            consume()
            let right = try parseAdditive()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(bop, left, right, r)
        }
        return left
    }

    private mutating func parseAdditive() throws -> ExpressionNode {
        var left = try parseMultiplicative()
        while let kind = peek() {
            let op: BinaryOperator?
            switch kind {
            case .op("+"): op = .add
            case .op("-"): op = .sub
            default:       op = nil
            }
            guard let bop = op else { break }
            consume()
            let right = try parseMultiplicative()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(bop, left, right, r)
        }
        return left
    }

    private mutating func parseMultiplicative() throws -> ExpressionNode {
        var left = try parseUnary()
        while let kind = peek() {
            let op: BinaryOperator?
            switch kind {
            case .op("*"): op = .mul
            case .op("/"): op = .div
            default:       op = nil
            }
            guard let bop = op else { break }
            consume()
            let right = try parseUnary()
            let r = ExpressionSourceRange(start: left.range.start, end: right.range.end)
            left = .binary(bop, left, right, r)
        }
        return left
    }

    private mutating func parseUnary() throws -> ExpressionNode {
        guard let tok = peekToken() else {
            throw ExpressionParseError(
                message: "unexpected end of input",
                position: source.utf8.count,
                source: source
            )
        }
        let unary: UnaryOperator?
        switch tok.kind {
        case .op("!"): unary = .not
        case .op("-"): unary = .minus
        case .op("+"): unary = .plus
        default:       unary = nil
        }
        if let unary {
            let opStart = tok.range.start
            consume()
            let inner = try parseUnary()
            return .unary(
                unary,
                inner,
                ExpressionSourceRange(start: opStart, end: inner.range.end)
            )
        }
        return try parseCall()
    }

    private mutating func parseCall() throws -> ExpressionNode {
        let primary = try parsePrimary()

        // Function-call shape: `identifier ( … )`. Reserved for future
        // `lookup()` (P2.2). The interpreter rejects every call name today.
        if case .fieldRef(let name, let nameRange) = primary,
           case .lparen? = peek() {
            consume()   // '('
            var args: [ExpressionNode] = []
            if !match(.rparen) {
                while true {
                    args.append(try parseOr())
                    if match(.comma) { continue }
                    break
                }
                guard let close = peekToken(), case .rparen = close.kind else {
                    let p = peekToken()?.range.start ?? source.utf8.count
                    throw ExpressionParseError(
                        message: "expected ')'",
                        position: p,
                        source: source
                    )
                }
                consume()
            }
            // Range from identifier start through closing paren.
            let endTok = tokens[pos - 1]
            return .call(
                name: name,
                args: args,
                ExpressionSourceRange(start: nameRange.start, end: endTok.range.end)
            )
        }

        return primary
    }

    private mutating func parsePrimary() throws -> ExpressionNode {
        guard let tok = peekToken() else {
            throw ExpressionParseError(
                message: "unexpected end of input",
                position: source.utf8.count,
                source: source
            )
        }
        switch tok.kind {
        case .numberLiteral(let n):
            consume()
            return .literal(.number(n), tok.range)
        case .stringLiteral(let s):
            consume()
            return .literal(.string(s), tok.range)
        case .boolLiteral(let b):
            consume()
            return .literal(.bool(b), tok.range)
        case .nullLiteral:
            consume()
            return .literal(.null, tok.range)
        case .identifier(let name):
            consume()
            return .fieldRef(name, tok.range)
        case .lparen:
            consume()
            let inner = try parseOr()
            guard let close = peekToken(), case .rparen = close.kind else {
                let p = peekToken()?.range.start ?? source.utf8.count
                throw ExpressionParseError(
                    message: "expected ')'",
                    position: p,
                    source: source
                )
            }
            consume()
            return inner
        case .rparen, .comma, .op:
            throw ExpressionParseError(
                message: "unexpected token '\(describe(tok.kind))'",
                position: tok.range.start,
                source: source
            )
        }
    }

    // MARK: - Token helpers

    private func peek() -> ExpressionToken.Kind? {
        pos < tokens.count ? tokens[pos].kind : nil
    }

    private func peekToken() -> ExpressionToken? {
        pos < tokens.count ? tokens[pos] : nil
    }

    private mutating func consume() {
        pos += 1
    }

    private mutating func match(_ kind: ExpressionToken.Kind) -> Bool {
        guard pos < tokens.count, tokens[pos].kind == kind else { return false }
        pos += 1
        return true
    }

    private func describe(_ kind: ExpressionToken.Kind) -> String {
        switch kind {
        case .identifier(let s):     return s
        case .stringLiteral(let s):  return "\"\(s)\""
        case .numberLiteral(let n):  return "\(n)"
        case .boolLiteral(let b):    return "\(b)"
        case .nullLiteral:           return "null"
        case .op(let s):             return s
        case .lparen:                return "("
        case .rparen:                return ")"
        case .comma:                 return ","
        }
    }
}

// MARK: - Static analysis

extension ExpressionNode {
    /// Every distinct field name referenced anywhere in the subtree.
    /// Used by `SchemaValidator` (P2.1 install-time check) to fail an app
    /// install if a `visibilityExpression` / `readOnlyExpression` /
    /// `formulaExpression` / automation `conditionExpression` references
    /// a field the DocType does not declare.
    public func referencedFields() -> Set<String> {
        var result: Set<String> = []
        collectFieldRefs(into: &result)
        return result
    }

    private func collectFieldRefs(into result: inout Set<String>) {
        switch self {
        case .literal:
            return
        case .fieldRef(let name, _):
            result.insert(name)
        case .unary(_, let inner, _):
            inner.collectFieldRefs(into: &result)
        case .binary(_, let l, let r, _):
            l.collectFieldRefs(into: &result)
            r.collectFieldRefs(into: &result)
        case .call(_, let args, _):
            for a in args { a.collectFieldRefs(into: &result) }
        }
    }

    /// True if this subtree contains no field references and no calls —
    /// i.e. the value depends only on literals. Used by the constant
    /// folder to decide whether to evaluate a subtree at parse time.
    var isConstant: Bool {
        switch self {
        case .literal:
            return true
        case .fieldRef:
            return false
        case .unary(_, let inner, _):
            return inner.isConstant
        case .binary(_, let l, let r, _):
            return l.isConstant && r.isConstant
        case .call:
            // `call` is reserved for future side-effecting forms (e.g.
            // lookup); never fold it.
            return false
        }
    }
}
