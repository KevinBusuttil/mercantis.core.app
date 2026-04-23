//
//  ValidationPipelineTests.swift
//  mercantis coreTests
//
//  Covers ADR-022: structured, ordered validation stages.
//

import XCTest
@testable import mercantis_core

final class ValidationPipelineTests: XCTestCase {

    // MARK: - Helpers

    private func context(
        for docType: DocType,
        userRoles: Set<String> = [],
        documentExists: @escaping @Sendable (String, String) -> Bool = { _, _ in true },
        uniqueConflict: @escaping @Sendable (String, String, FieldValue, String) -> Bool = { _, _, _, _ in false }
    ) -> ValidationContext {
        ValidationContext(
            docType: docType,
            userId: "tester",
            userRoles: userRoles,
            expressionEvaluator: ExpressionEvaluator(),
            documentExists: documentExists,
            uniqueConflictExists: uniqueConflict
        )
    }

    // MARK: - Required

    func testRequiredStageFailsOnMissingValue() {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", required: true)
        ])
        let doc = TestSupport.makeDocument(fields: [:])
        let pipeline = ValidationPipeline(stages: [RequiredFieldStage()])

        let errors = pipeline.validate(document: doc, context: context(for: docType))
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.stage, "RequiredField")
        XCTAssertEqual(errors.first?.field, "title")
    }

    func testRequiredStageFailsOnWhitespaceOnlyString() {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", required: true)
        ])
        let doc = TestSupport.makeDocument(fields: ["title": .string("   ")])
        let pipeline = ValidationPipeline(stages: [RequiredFieldStage()])

        let errors = pipeline.validate(document: doc, context: context(for: docType))
        XCTAssertEqual(errors.count, 1)
    }

    func testRequiredStagePassesForPopulatedField() {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", required: true)
        ])
        let doc = TestSupport.makeDocument(fields: ["title": .string("Hello")])
        let pipeline = ValidationPipeline(stages: [RequiredFieldStage()])

        XCTAssertTrue(pipeline.validate(document: doc, context: context(for: docType)).isEmpty)
    }

    // MARK: - Type coercion

    func testTypeCoercionRejectsBoolInTextField() {
        let docType = TestSupport.makeDocType(fields: [TestSupport.textField("title")])
        let doc = TestSupport.makeDocument(fields: ["title": .bool(true)])
        let pipeline = ValidationPipeline(stages: [TypeCoercionStage()])

        let errors = pipeline.validate(document: doc, context: context(for: docType))
        XCTAssertEqual(errors.first?.stage, "TypeCoercion")
    }

    func testTypeCoercionAcceptsNumericStringForNumberField() {
        let docType = TestSupport.makeDocType(fields: [TestSupport.numberField("qty")])
        let doc = TestSupport.makeDocument(fields: ["qty": .string("42")])
        let pipeline = ValidationPipeline(stages: [TypeCoercionStage()])

        XCTAssertTrue(pipeline.validate(document: doc, context: context(for: docType)).isEmpty)
    }

    // MARK: - Link validation

    func testLinkValidationFailsWhenTargetDoesNotExist() {
        let docType = TestSupport.makeDocType(fields: [TestSupport.linkField("customer", targeting: "Customer")])
        let doc = TestSupport.makeDocument(fields: ["customer": .string("missing-id")])
        let pipeline = ValidationPipeline(stages: [LinkValidationStage()])

        let ctx = context(for: docType, documentExists: { _, _ in false })
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "LinkValidation")
        XCTAssertEqual(errors.first?.field, "customer")
    }

    func testLinkValidationPassesWhenTargetExists() {
        let docType = TestSupport.makeDocType(fields: [TestSupport.linkField("customer", targeting: "Customer")])
        let doc = TestSupport.makeDocument(fields: ["customer": .string("CUST-1")])
        let pipeline = ValidationPipeline(stages: [LinkValidationStage()])

        let ctx = context(for: docType, documentExists: { _, _ in true })
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    // MARK: - Unique constraint

    func testUniqueConstraintFailsOnDuplicateValue() {
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("slug")],
            indexes: [IndexDefinition(fieldKey: "slug", unique: true)]
        )
        let doc = TestSupport.makeDocument(fields: ["slug": .string("hello")])
        let pipeline = ValidationPipeline(stages: [UniqueConstraintStage()])

        let ctx = context(for: docType, uniqueConflict: { _, _, _, _ in true })
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "UniqueConstraint")
    }

    func testUniqueConstraintPassesWhenNoConflict() {
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("slug")],
            indexes: [IndexDefinition(fieldKey: "slug", unique: true)]
        )
        let doc = TestSupport.makeDocument(fields: ["slug": .string("hello")])
        let pipeline = ValidationPipeline(stages: [UniqueConstraintStage()])

        let ctx = context(for: docType, uniqueConflict: { _, _, _, _ in false })
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    // MARK: - Validation rule expressions

    func testValidationRuleFailsOnFalseExpression() {
        let field = FieldDefinition(
            key: "total",
            label: "Total",
            type: .number,
            required: false,
            validationRules: [ValidationRule(ruleType: "range", expression: "total > 0", message: "Must be positive")]
        )
        let docType = TestSupport.makeDocType(fields: [field])
        let doc = TestSupport.makeDocument(fields: ["total": .double(-5)])
        let pipeline = ValidationPipeline(stages: [ValidationRuleStage()])

        let errors = pipeline.validate(document: doc, context: context(for: docType))
        XCTAssertEqual(errors.first?.stage, "ValidationRule")
        XCTAssertEqual(errors.first?.message, "Must be positive")
    }

    func testValidationRulePassesOnTrueExpression() {
        let field = FieldDefinition(
            key: "total",
            label: "Total",
            type: .number,
            required: false,
            validationRules: [ValidationRule(ruleType: "range", expression: "total > 0", message: "Must be positive")]
        )
        let docType = TestSupport.makeDocType(fields: [field])
        let doc = TestSupport.makeDocument(fields: ["total": .double(10)])
        let pipeline = ValidationPipeline(stages: [ValidationRuleStage()])

        XCTAssertTrue(pipeline.validate(document: doc, context: context(for: docType)).isEmpty)
    }

    // MARK: - Pipeline ordering / short-circuit

    func testPipelineShortCircuitsAfterFirstFailingStage() {
        // RequiredField must fail first and prevent ValidationRule from running;
        // the rule references `total` which, if run, would throw `undefinedField`
        // and add a second error.
        let field = FieldDefinition(
            key: "total",
            label: "Total",
            type: .number,
            required: true,
            validationRules: [ValidationRule(ruleType: "range", expression: "total > 0", message: "positive")]
        )
        let docType = TestSupport.makeDocType(fields: [field])
        let doc = TestSupport.makeDocument(fields: [:])
        let pipeline = ValidationPipeline(stages: [
            RequiredFieldStage(),
            ValidationRuleStage()
        ])

        let errors = pipeline.validate(document: doc, context: context(for: docType))
        XCTAssertEqual(errors.count, 1, "pipeline must stop at the first failing stage")
        XCTAssertEqual(errors.first?.stage, "RequiredField")
    }

    // MARK: - Permission stage

    func testPermissionStagePassesWhenRoleHasWriteAccess() {
        let rule = PermissionRule(
            role: "Editor",
            canRead: true, canWrite: true, canCreate: true,
            canDelete: false, canSubmit: false, canAmend: false
        )
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title")],
            permissions: [rule]
        )
        let doc = TestSupport.makeDocument()
        let pipeline = ValidationPipeline(stages: [PermissionStage()])

        let ctx = context(for: docType, userRoles: ["Editor"])
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testPermissionStageFailsWhenRoleLacksWriteAccess() {
        let rule = PermissionRule(
            role: "Reader",
            canRead: true, canWrite: false, canCreate: false,
            canDelete: false, canSubmit: false, canAmend: false
        )
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title")],
            permissions: [rule]
        )
        let doc = TestSupport.makeDocument()
        let pipeline = ValidationPipeline(stages: [PermissionStage()])

        let ctx = context(for: docType, userRoles: ["Reader"])
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "Permission")
    }
}
