//
//  SchemaValidatorTests.swift
//  mercantis coreTests
//
//  Covers the static expression-reference checks added by P2.1.
//  `SchemaValidator.validate(_:)` parses each field's
//  `visibilityExpression` / `readOnlyExpression` / `formulaExpression`
//  and rejects DocTypes that reference fields the DocType does not
//  declare. Other validator behaviours (duplicate field key, missing
//  linked DocType, etc.) are exercised by the install paths in
//  `AutomationTests` and `MetaComposerTests`.
//

import XCTest
@testable import mercantis_core

final class SchemaValidatorTests: XCTestCase {

    // MARK: - visibilityExpression

    func testVisibilityExpressionReferencingDeclaredFieldPasses() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("status"),
                FieldDefinition(
                    key: "secondaryNote",
                    label: "Secondary Note",
                    type: .longText,
                    required: false,
                    visibilityExpression: "status == \"Submitted\""
                )
            ],
            titleField: "status"
        )
        try SchemaValidator().validate(docType)
    }

    func testVisibilityExpressionReferencingUndeclaredFieldThrows() {
        let docType = TestSupport.makeDocType(
            fields: [
                FieldDefinition(
                    key: "secondaryNote",
                    label: "Secondary Note",
                    type: .longText,
                    required: false,
                    visibilityExpression: "status == \"Submitted\""
                )
            ],
            titleField: "secondaryNote"
        )
        XCTAssertThrowsError(try SchemaValidator().validate(docType)) { error in
            guard case SchemaValidator.ValidationError.unknownFieldInExpression(_, let fieldKey, let kind, let referenced) = error else {
                return XCTFail("expected unknownFieldInExpression, got \(error)")
            }
            XCTAssertEqual(fieldKey, "secondaryNote")
            XCTAssertEqual(kind, "visibilityExpression")
            XCTAssertEqual(referenced, "status")
        }
    }

    // MARK: - readOnlyExpression

    func testReadOnlyExpressionReferencingDeclaredFieldPasses() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("approvalState"),
                FieldDefinition(
                    key: "amount",
                    label: "Amount",
                    type: .decimal,
                    required: false,
                    readOnlyExpression: "approvalState == \"Locked\""
                )
            ],
            titleField: "approvalState"
        )
        try SchemaValidator().validate(docType)
    }

    func testReadOnlyExpressionReferencingUndeclaredFieldThrows() {
        let docType = TestSupport.makeDocType(
            fields: [
                FieldDefinition(
                    key: "amount",
                    label: "Amount",
                    type: .decimal,
                    required: false,
                    readOnlyExpression: "approvalState == \"Locked\""
                )
            ],
            titleField: "amount"
        )
        XCTAssertThrowsError(try SchemaValidator().validate(docType)) { error in
            guard case SchemaValidator.ValidationError.unknownFieldInExpression(_, _, let kind, let referenced) = error else {
                return XCTFail("expected unknownFieldInExpression, got \(error)")
            }
            XCTAssertEqual(kind, "readOnlyExpression")
            XCTAssertEqual(referenced, "approvalState")
        }
    }

    // MARK: - formulaExpression

    func testFormulaExpressionReferencingDeclaredFieldPasses() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.numberField("qty"),
                TestSupport.numberField("rate"),
                FieldDefinition(
                    key: "amount",
                    label: "Amount",
                    type: .formula,
                    required: false,
                    formulaExpression: "qty * rate"
                )
            ],
            titleField: "qty"
        )
        try SchemaValidator().validate(docType)
    }

    func testFormulaExpressionReferencingUndeclaredFieldThrows() {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.numberField("qty"),
                FieldDefinition(
                    key: "amount",
                    label: "Amount",
                    type: .formula,
                    required: false,
                    formulaExpression: "qty * rate"
                )
            ],
            titleField: "qty"
        )
        XCTAssertThrowsError(try SchemaValidator().validate(docType)) { error in
            guard case SchemaValidator.ValidationError.unknownFieldInExpression(_, _, let kind, let referenced) = error else {
                return XCTFail("expected unknownFieldInExpression, got \(error)")
            }
            XCTAssertEqual(kind, "formulaExpression")
            XCTAssertEqual(referenced, "rate")
        }
    }

    // MARK: - Parse-time rejection

    func testMalformedExpressionRaisesExpressionParseFailed() {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("status"),
                FieldDefinition(
                    key: "note",
                    label: "Note",
                    type: .longText,
                    required: false,
                    visibilityExpression: "status == "
                )
            ],
            titleField: "status"
        )
        XCTAssertThrowsError(try SchemaValidator().validate(docType)) { error in
            guard case SchemaValidator.ValidationError.expressionParseFailed(_, let fieldKey, let kind, _, _) = error else {
                return XCTFail("expected expressionParseFailed, got \(error)")
            }
            XCTAssertEqual(fieldKey, "note")
            XCTAssertEqual(kind, "visibilityExpression")
        }
    }

    // MARK: - Opt-out

    func testValidatesExpressionsFlagSkipsCheckWhenFalse() throws {
        // Some downstream tooling (DocType builder previewing a draft)
        // wants structural validation without the expression-reference
        // pass — `validatesExpressions = false` opts out.
        let docType = TestSupport.makeDocType(
            fields: [
                FieldDefinition(
                    key: "amount",
                    label: "Amount",
                    type: .decimal,
                    required: false,
                    visibilityExpression: "approvalState == \"Locked\""
                )
            ],
            titleField: "amount"
        )
        var validator = SchemaValidator()
        validator.validatesExpressions = false
        try validator.validate(docType)
    }

    // MARK: - Dotted identifiers

    func testDottedIdentifiersAreNotEnforcedAgainstDeclaredFields() throws {
        // `user.id`, `user.roles`, etc. are populated by the permission
        // engine at evaluation time — they are never declared as
        // DocType fields. Treating them as field references would
        // make every row-level expression fail validation.
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("owner"),
                FieldDefinition(
                    key: "summary",
                    label: "Summary",
                    type: .longText,
                    required: false,
                    visibilityExpression: "owner == user.id"
                )
            ],
            titleField: "owner"
        )
        try SchemaValidator().validate(docType)
    }
}
