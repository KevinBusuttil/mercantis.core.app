//
//  ExpressionEvaluatorTests.swift
//  mercantis coreTests
//
//  Covers the sandboxed expression evaluator described in ADR-017.
//

import XCTest
@testable import mercantis_core

final class ExpressionEvaluatorTests: XCTestCase {

    private let evaluator = ExpressionEvaluator()

    // MARK: - Boolean literals & identifiers

    func testBooleanLiterals() throws {
        XCTAssertTrue(try evaluator.evaluateBool(expression: "true", context: [:]))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "false", context: [:]))
    }

    func testIdentifierTruthiness() throws {
        XCTAssertTrue(try evaluator.evaluateBool(expression: "flag", context: ["flag": .bool(true)]))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "flag", context: ["flag": .bool(false)]))
        XCTAssertTrue(try evaluator.evaluateBool(expression: "name", context: ["name": .string("x")]))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "name", context: ["name": .string("")]))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "missing", context: [:]))
    }

    // MARK: - Comparisons

    func testStringEquality() throws {
        let ctx: [String: FieldValue] = ["status": .string("Submitted")]
        XCTAssertTrue(try evaluator.evaluateBool(expression: "status == \"Submitted\"", context: ctx))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "status != \"Submitted\"", context: ctx))
    }

    func testNumericComparisons() throws {
        let ctx: [String: FieldValue] = ["total": .double(250.0)]
        XCTAssertTrue(try evaluator.evaluateBool(expression: "total > 100", context: ctx))
        XCTAssertTrue(try evaluator.evaluateBool(expression: "total >= 250", context: ctx))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "total < 100", context: ctx))
        XCTAssertTrue(try evaluator.evaluateBool(expression: "total <= 250", context: ctx))
    }

    // MARK: - Boolean operators

    func testBooleanOperators() throws {
        let ctx: [String: FieldValue] = [
            "status": .string("Submitted"),
            "total":  .double(15_000)
        ]
        XCTAssertTrue(try evaluator.evaluateBool(
            expression: "status == \"Submitted\" && total > 10000",
            context: ctx))
        XCTAssertTrue(try evaluator.evaluateBool(
            expression: "status == \"Draft\" || total > 10000",
            context: ctx))
        XCTAssertFalse(try evaluator.evaluateBool(
            expression: "!(total > 10000)",
            context: ctx))
    }

    func testParenthesesChangePrecedence() throws {
        let ctx: [String: FieldValue] = ["a": .bool(true), "b": .bool(false), "c": .bool(true)]
        XCTAssertTrue(try evaluator.evaluateBool(expression: "a && (b || c)", context: ctx))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "(a && b) || (!c)", context: ctx))
    }

    // MARK: - Arithmetic formulas

    func testArithmeticBasics() throws {
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "2 + 3", context: [:]), .double(5))
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "10 - 4", context: [:]), .double(6))
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "6 * 7", context: [:]), .double(42))
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "20 / 4", context: [:]), .double(5))
    }

    func testArithmeticPrecedence() throws {
        XCTAssertEqual(
            try evaluator.evaluateFormula(expression: "2 + 3 * 4", context: [:]),
            .double(14))
        XCTAssertEqual(
            try evaluator.evaluateFormula(expression: "(2 + 3) * 4", context: [:]),
            .double(20))
    }

    func testArithmeticReferencesNumericField() throws {
        let ctx: [String: FieldValue] = ["qty": .int(4), "rate": .double(12.5)]
        XCTAssertEqual(
            try evaluator.evaluateFormula(expression: "qty * rate", context: ctx),
            .double(50))
    }

    // MARK: - Unary minus (regression for P0.9)

    func testUnaryMinusOnLiteralInArithmetic() throws {
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "-5", context: [:]), .double(-5))
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "1 + -2", context: [:]), .double(-1))
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "3 * -2", context: [:]), .double(-6))
    }

    func testDoubleUnaryMinus() throws {
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "--5", context: [:]), .double(5))
    }

    func testUnaryMinusOnParenthesisedExpression() throws {
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "-(2 + 3)", context: [:]), .double(-5))
    }

    func testUnaryMinusOnFieldRef() throws {
        let ctx: [String: FieldValue] = ["price": .double(5)]
        XCTAssertEqual(try evaluator.evaluateFormula(expression: "-price", context: ctx), .double(-5))
    }

    func testUnaryMinusInBooleanComparison() throws {
        let ctx: [String: FieldValue] = ["price": .double(-5)]
        XCTAssertTrue(try evaluator.evaluateBool(expression: "-5 == price", context: ctx))
        XCTAssertFalse(try evaluator.evaluateBool(expression: "-5 != price", context: ctx))
    }

    // MARK: - Error cases

    func testDivisionByZeroThrows() {
        XCTAssertThrowsError(try evaluator.evaluateFormula(expression: "10 / 0", context: [:])) { error in
            guard case ExpressionEvaluator.EvaluatorError.divisionByZero = error else {
                return XCTFail("expected divisionByZero, got \(error)")
            }
        }
    }

    func testUndefinedFieldInFormulaThrows() {
        XCTAssertThrowsError(try evaluator.evaluateFormula(expression: "qty * 2", context: [:])) { error in
            guard case ExpressionEvaluator.EvaluatorError.undefinedField(let name) = error else {
                return XCTFail("expected undefinedField, got \(error)")
            }
            XCTAssertEqual(name, "qty")
        }
    }

    func testEmptyExpressionEvaluatesToFalse() throws {
        // An empty expression has no tokens; `parseValue` returns .null and
        // a truthiness fallback gives false.
        XCTAssertFalse(try evaluator.evaluateBool(expression: "", context: [:]))
    }

    // MARK: - AST / static analysis (P2.1)

    func testParseProducesReusableASTNode() throws {
        let node = try evaluator.parse("status == \"Submitted\"")
        let ctx: [String: FieldValue] = ["status": .string("Submitted")]
        XCTAssertTrue(try evaluator.evaluateBool(parsed: node, context: ctx))
    }

    func testParseCachesSoSecondCallReturnsSameAST() throws {
        let a = try evaluator.parse("a + b")
        let b = try evaluator.parse("a + b")
        // Equatable AST round-trip — same source ⇒ structurally identical
        // tree. The cache also avoids re-parsing on the second call.
        XCTAssertEqual(a, b)
    }

    func testReferencedFieldsExtractsEveryIdentifier() throws {
        let referenced = try evaluator.referencedFields(
            in: "amount > 100 && warehouse == \"Main\" && !discontinued"
        )
        XCTAssertEqual(referenced, ["amount", "warehouse", "discontinued"])
    }

    func testReferencedFieldsIgnoresLiteralsAndOperators() throws {
        XCTAssertEqual(try evaluator.referencedFields(in: "true || false"), [])
        XCTAssertEqual(try evaluator.referencedFields(in: "2 + 3 * 4"), [])
    }

    func testReferencedFieldsTreatsDottedIdentifierAsSingleKey() throws {
        // The `user.*` namespace travels as a flat key — pre-flattened
        // by `PermissionEngine` into the evaluation context.
        let referenced = try evaluator.referencedFields(in: "owner == user.id")
        XCTAssertEqual(referenced, ["owner", "user.id"])
    }

    func testReferencedFieldsOnEmptyExpressionReturnsEmptySet() throws {
        XCTAssertEqual(try evaluator.referencedFields(in: ""), [])
        XCTAssertEqual(try evaluator.referencedFields(in: "    "), [])
    }

    // MARK: - Constant folding (P2.1)

    func testConstantFoldingCollapsesPureArithmetic() throws {
        // After folding, `2 + 3 * 4` is a single literal — exercising
        // the AST shape directly via `parse`.
        guard case .literal(.number(let n), _) = try evaluator.parse("2 + 3 * 4") else {
            return XCTFail("expected pure-arithmetic expression to fold to a literal")
        }
        XCTAssertEqual(n, 14)
    }

    func testConstantFoldingDoesNotEliminateFieldReferences() throws {
        // `qty * 2` references a field — must not collapse.
        let node = try evaluator.parse("qty * 2")
        guard case .binary = node else {
            return XCTFail("expression with a field reference must not fold to a literal")
        }
    }

    func testConstantFoldingPreservesDivisionByZeroAsRuntimeError() {
        // Folding division-by-zero would change the error contract: the
        // existing `testDivisionByZeroThrows` regression must keep
        // throwing at evaluation time, not parse time.
        XCTAssertThrowsError(try evaluator.evaluateFormula(expression: "10 / 0", context: [:])) { error in
            guard case ExpressionEvaluator.EvaluatorError.divisionByZero = error else {
                return XCTFail("expected divisionByZero, got \(error)")
            }
        }
    }

    // MARK: - Source-position-aware errors (P2.1)

    func testUnknownCharacterReportsPosition() {
        // The legacy evaluator silently dropped unknown characters; the
        // AST-based parser surfaces them with their source offset so
        // callers can render a caret.
        XCTAssertThrowsError(try evaluator.evaluateBool(expression: "a $ b", context: [:])) { error in
            switch error {
            case ExpressionEvaluator.EvaluatorError.unexpectedToken,
                 ExpressionEvaluator.EvaluatorError.parseError:
                break
            default:
                XCTFail("expected parse error for unknown character, got \(error)")
            }
        }
    }

    func testUnterminatedStringLiteralReportsParseError() {
        XCTAssertThrowsError(try evaluator.evaluateBool(expression: "name == \"oops", context: [:])) { error in
            guard case ExpressionEvaluator.EvaluatorError.parseError(let parseError) = error else {
                return XCTFail("expected parseError, got \(error)")
            }
            XCTAssertTrue(parseError.message.contains("unterminated"))
            XCTAssertGreaterThanOrEqual(parseError.position, 0)
            XCTAssertTrue(parseError.description.contains("^"))
        }
    }

    func testTrailingTokensAfterExpressionThrow() {
        // Legacy behaviour silently dropped trailing tokens like the
        // `c` in `a == b c`. The AST parser rejects them so typos
        // surface at parse time instead of being half-evaluated.
        XCTAssertThrowsError(try evaluator.evaluateBool(expression: "a == b c", context: [:]))
    }

    func testCacheBypassedWhenLimitIsZero() throws {
        let uncached = ExpressionEvaluator(parseCacheLimit: 0)
        // Just exercise the no-cache path — semantics must not differ.
        XCTAssertTrue(try uncached.evaluateBool(
            expression: "x > 0",
            context: ["x": .double(5)]
        ))
        XCTAssertFalse(try uncached.evaluateBool(
            expression: "x > 0",
            context: ["x": .double(-1)]
        ))
    }
}
