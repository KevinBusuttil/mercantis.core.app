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
        operation: DocumentOperation = .write,
        documentExists: @escaping @Sendable (String, String) -> Bool = { _, _ in true },
        uniqueConflict: @escaping @Sendable (String, String, FieldValue, String) -> Bool = { _, _, _, _ in false },
        workflowProvider: @escaping @Sendable (String) -> WorkflowDefinition? = { _ in nil },
        previousStatus: @escaping @Sendable (String, String) -> String? = { _, _ in nil }
    ) -> ValidationContext {
        ValidationContext(
            docType: docType,
            userId: "tester",
            userRoles: userRoles,
            operation: operation,
            expressionEvaluator: ExpressionEvaluator(),
            documentExists: documentExists,
            uniqueConflictExists: uniqueConflict,
            workflowProvider: workflowProvider,
            previousStatus: previousStatus
        )
    }

    // MARK: - Workflow fixture

    private func draftToSubmittedWorkflow(
        conditionExpression: String? = nil,
        allowedRoles: [String] = ["Approver"]
    ) -> WorkflowDefinition {
        WorkflowDefinition(
            id: "NoteWorkflow",
            name: "Note Workflow",
            docType: "Note",
            states: [
                WorkflowState(name: "Draft", isDefault: true, allowEdit: true),
                WorkflowState(name: "Submitted", isDefault: false, allowEdit: false)
            ],
            transitions: [
                WorkflowTransition(
                    from: "Draft",
                    to: "Submitted",
                    action: "submit",
                    allowedRoles: allowedRoles,
                    conditionExpression: conditionExpression
                )
            ]
        )
    }

    private func noteDocType(withWorkflowId id: String? = "NoteWorkflow") -> DocType {
        DocType(
            id: "Note",
            name: "Note",
            module: "Core",
            appId: "app.mercantis.test",
            isChildTable: false,
            isSubmittable: false,
            fields: [TestSupport.textField("title"), TestSupport.numberField("total")],
            permissions: [],
            workflowId: id,
            autoname: nil,
            syncPolicy: TestSupport.defaultSyncPolicy(),
            indexes: [],
            searchFields: ["title"],
            titleField: "title"
        )
    }

    private func workflowDocument(
        id: String = "doc-1",
        status: String,
        total: Double = 0
    ) -> Document {
        var doc = TestSupport.makeDocument(id: id, fields: ["title": .string("N"), "total": .double(total)])
        doc.status = status
        return doc
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

    func testPermissionStagePassesWhenDocTypeDeclaresNoPermissionRules() {
        // An unconstrained DocType — no rules — is considered open to any authenticated caller.
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title")],
            permissions: []
        )
        let doc = TestSupport.makeDocument()
        let pipeline = ValidationPipeline(stages: [PermissionStage()])

        let ctx = context(for: docType, userRoles: ["Editor"])
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testPermissionStagePassesWhenUserRolesEmpty() {
        // System / import contexts do not enforce role-based permission checks.
        let rule = PermissionRule(
            role: "Editor",
            canRead: false, canWrite: false, canCreate: false,
            canDelete: false, canSubmit: false, canAmend: false
        )
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title")],
            permissions: [rule]
        )
        let doc = TestSupport.makeDocument()
        let pipeline = ValidationPipeline(stages: [PermissionStage()])

        let ctx = context(for: docType, userRoles: [])
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testPermissionStageHonoursCreateOperationDistinctFromWrite() {
        // A role that can create but cannot write: create must pass, write must fail.
        let rule = PermissionRule(
            role: "Author",
            canRead: true, canWrite: false, canCreate: true,
            canDelete: false, canSubmit: false, canAmend: false
        )
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title")],
            permissions: [rule]
        )
        let doc = TestSupport.makeDocument()
        let pipeline = ValidationPipeline(stages: [PermissionStage()])

        let createCtx = context(for: docType, userRoles: ["Author"], operation: .create)
        XCTAssertTrue(pipeline.validate(document: doc, context: createCtx).isEmpty)

        let writeCtx = context(for: docType, userRoles: ["Author"], operation: .write)
        let writeErrors = pipeline.validate(document: doc, context: writeCtx)
        XCTAssertEqual(writeErrors.first?.stage, "Permission")
    }

    // MARK: - Workflow guard

    func testWorkflowGuardPassesWhenNoWorkflowAttached() {
        let docType = noteDocType(withWorkflowId: nil)
        let doc = workflowDocument(status: "Submitted")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardPassesWhenWorkflowUnresolvable() {
        // DocType declares a workflowId but the provider cannot find it — treated as no workflow.
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in nil },
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardPassesOnNewDocumentCreation() {
        // No previously-persisted status => creation, not a transition.
        let docType = noteDocType()
        let doc = workflowDocument(status: "Draft")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow()
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in nil }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardPassesWhenStatusUnchanged() {
        let docType = noteDocType()
        let doc = workflowDocument(status: "Draft")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow()
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardRejectsUndeclaredTransition() {
        // Draft -> Closed is not in the workflow.
        let docType = noteDocType()
        let doc = workflowDocument(status: "Closed")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow()
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "WorkflowGuard")
        XCTAssertTrue(errors.first?.message.contains("does not declare a transition") ?? false)
    }

    func testWorkflowGuardRejectsUnauthorisedTransition() {
        // User has no role matching allowedRoles.
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow(allowedRoles: ["Approver"])
        let ctx = context(
            for: docType,
            userRoles: ["Reader"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "WorkflowGuard")
        XCTAssertTrue(errors.first?.message.contains("not authorised") ?? false)
    }

    func testWorkflowGuardAllowsDeclaredTransitionWithRole() {
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow()
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardRejectsTransitionWhenConditionFalse() {
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted", total: -1)
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow(conditionExpression: "total > 0")
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "WorkflowGuard")
        XCTAssertTrue(errors.first?.message.contains("blocked by its condition") ?? false)
    }

    func testWorkflowGuardAllowsTransitionWhenConditionTrue() {
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted", total: 10)
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow(conditionExpression: "total > 0")
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardSkipsRoleCheckForSystemContext() {
        // When userRoles is empty (import / seed / system), role enforcement is skipped.
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted")
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        let workflow = draftToSubmittedWorkflow(allowedRoles: ["Approver"])
        let ctx = context(
            for: docType,
            userRoles: [],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        XCTAssertTrue(pipeline.validate(document: doc, context: ctx).isEmpty)
    }

    func testWorkflowGuardReportsEvaluationErrorForMalformedCondition() {
        let docType = noteDocType()
        let doc = workflowDocument(status: "Submitted", total: 1)
        let pipeline = ValidationPipeline(stages: [WorkflowGuardStage()])

        // Reference an undefined field so ExpressionEvaluator throws.
        let workflow = draftToSubmittedWorkflow(conditionExpression: "missingField > 0")
        let ctx = context(
            for: docType,
            userRoles: ["Approver"],
            workflowProvider: { _ in workflow },
            previousStatus: { _, _ in "Draft" }
        )
        let errors = pipeline.validate(document: doc, context: ctx)
        XCTAssertEqual(errors.first?.stage, "WorkflowGuard")
        XCTAssertTrue(errors.first?.message.contains("failed to evaluate") ?? false)
    }
}
