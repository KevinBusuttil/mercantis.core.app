//
//  AutomationTests.swift
//  mercantis coreTests
//
//  Covers the P1.2 automation runtime: action registry, built-in handlers,
//  runner that listens to document events, and the
//  `ExtensionActionDispatcher` bridge.
//

import XCTest
@testable import mercantis_core

final class AutomationTests: XCTestCase {

    private var notifications: InMemoryNotificationLog!
    private var assignments: InMemoryAssignmentLog!

    override func setUp() {
        super.setUp()
        notifications = InMemoryNotificationLog()
        assignments = InMemoryAssignmentLog()
    }

    override func tearDown() {
        notifications = nil
        assignments = nil
        super.tearDown()
    }

    // MARK: - Registry

    func testRegistryRegistersBuiltInsByDefault() {
        let registry = AutomationActionRegistry()
        let types = registry.registeredActionTypes()
        XCTAssertEqual(
            types,
            ["set_value", "set_status", "send_notification", "validate", "assign"]
        )
    }

    func testRegistryCanOptOutOfBuiltIns() {
        let registry = AutomationActionRegistry(registerBuiltIns: false)
        XCTAssertTrue(registry.registeredActionTypes().isEmpty)
    }

    func testRegistryThrowsUnknownActionType() {
        let registry = AutomationActionRegistry()
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(try registry.execute(
            actionType: "does_not_exist",
            parameters: [:],
            on: &doc,
            context: automationContext()
        )) { error in
            XCTAssertEqual(
                error as? AutomationActionError,
                .unknownActionType("does_not_exist")
            )
        }
    }

    func testRegistryReplacesHandlerOnDuplicateRegistration() throws {
        let registry = AutomationActionRegistry()
        registry.register(ReplacementSetValueHandler())
        var doc = TestSupport.makeDocument(fields: [:])
        try registry.execute(
            actionType: "set_value",
            parameters: ["field": "x", "value": "anything"],
            on: &doc,
            context: automationContext()
        )
        XCTAssertEqual(doc.fields["x"], .string("replaced"))
    }

    // MARK: - SetValueHandler

    func testSetValueInfersIntFromDigits() throws {
        var doc = TestSupport.makeDocument(fields: [:])
        try SetValueHandler().execute(
            document: &doc,
            parameters: ["field": "qty", "value": "42"],
            context: automationContext()
        )
        XCTAssertEqual(doc.fields["qty"], .int(42))
    }

    func testSetValueInfersBoolFromKeyword() throws {
        var doc = TestSupport.makeDocument(fields: [:])
        try SetValueHandler().execute(
            document: &doc,
            parameters: ["field": "paid", "value": "true"],
            context: automationContext()
        )
        XCTAssertEqual(doc.fields["paid"], .bool(true))
    }

    func testSetValueHonoursExplicitStringType() throws {
        var doc = TestSupport.makeDocument(fields: [:])
        try SetValueHandler().execute(
            document: &doc,
            parameters: ["field": "ref", "value": "42", "type": "string"],
            context: automationContext()
        )
        XCTAssertEqual(doc.fields["ref"], .string("42"))
    }

    func testSetValueRejectsMissingField() {
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(try SetValueHandler().execute(
            document: &doc,
            parameters: ["value": "42"],
            context: automationContext()
        )) { error in
            XCTAssertEqual(
                error as? AutomationActionError,
                .missingParameter(actionType: "set_value", name: "field")
            )
        }
    }

    func testSetValueRejectsInvalidExplicitType() {
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(try SetValueHandler().execute(
            document: &doc,
            parameters: ["field": "x", "value": "abc", "type": "int"],
            context: automationContext()
        )) { error in
            if case .invalidParameter(let actionType, let name, _) = error as? AutomationActionError {
                XCTAssertEqual(actionType, "set_value")
                XCTAssertEqual(name, "value")
            } else {
                XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }

    // MARK: - SetStatusHandler

    func testSetStatusChangesStatus() throws {
        var doc = TestSupport.makeDocument(fields: [:])
        doc.status = "Draft"
        try SetStatusHandler().execute(
            document: &doc,
            parameters: ["status": "Approved"],
            context: automationContext()
        )
        XCTAssertEqual(doc.status, "Approved")
    }

    func testSetStatusRejectsMissingStatus() {
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(try SetStatusHandler().execute(
            document: &doc,
            parameters: [:],
            context: automationContext()
        ))
    }

    // MARK: - SendNotificationHandler

    func testSendNotificationWritesEntryToSink() throws {
        var doc = TestSupport.makeDocument(
            id: "SI-001",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(1000)]
        )
        try SendNotificationHandler().execute(
            document: &doc,
            parameters: [
                "channel": "email",
                "recipient": "ops@example.com",
                "subject": "Invoice posted",
                "body": "Total: {grandTotal}"
            ],
            context: automationContext(appId: "app.test", docType: "SalesInvoice", documentId: "SI-001")
        )
        let entries = notifications.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.channel, "email")
        XCTAssertEqual(entries.first?.recipient, "ops@example.com")
        XCTAssertEqual(entries.first?.subject, "Invoice posted")
        XCTAssertEqual(entries.first?.body, "Total: 1000.0")
        XCTAssertEqual(entries.first?.appId, "app.test")
        XCTAssertEqual(entries.first?.documentId, "SI-001")
    }

    func testSendNotificationInterpolationLeavesUnknownPlaceholders() throws {
        var doc = TestSupport.makeDocument(fields: ["title": .string("Hi")])
        try SendNotificationHandler().execute(
            document: &doc,
            parameters: ["body": "Hello {title}, about {missing}"],
            context: automationContext()
        )
        XCTAssertEqual(notifications.entries.first?.body, "Hello Hi, about {missing}")
    }

    // MARK: - ValidateHandler

    func testValidateSucceedsWhenConditionTrue() throws {
        var doc = TestSupport.makeDocument(fields: ["amount": .double(10)])
        try ValidateHandler().execute(
            document: &doc,
            parameters: ["expression": "amount > 0", "message": "positive only"],
            context: automationContext()
        )
    }

    func testValidateThrowsWhenConditionFalse() {
        var doc = TestSupport.makeDocument(fields: ["amount": .double(-1)])
        XCTAssertThrowsError(try ValidateHandler().execute(
            document: &doc,
            parameters: ["expression": "amount > 0", "message": "positive only"],
            context: automationContext()
        )) { error in
            if case .validationFailed(let message) = error as? AutomationActionError {
                XCTAssertEqual(message, "positive only")
            } else {
                XCTFail("expected validationFailed, got \(error)")
            }
        }
    }

    func testValidateSurfacesExpressionError() {
        var doc = TestSupport.makeDocument(fields: [:])
        // Leading comparison operator with no LHS — the evaluator throws
        // `unexpectedToken`. We assert the handler wraps it.
        XCTAssertThrowsError(try ValidateHandler().execute(
            document: &doc,
            parameters: ["expression": ">5"],
            context: automationContext()
        )) { error in
            if case .expressionFailed(let actionType, _, _) = error as? AutomationActionError {
                XCTAssertEqual(actionType, "validate")
            } else {
                XCTFail("expected expressionFailed, got \(error)")
            }
        }
    }

    // MARK: - AssignHandler

    func testAssignRecordsUserTarget() throws {
        var doc = TestSupport.makeDocument(
            id: "SI-042",
            docType: "SalesInvoice",
            fields: [:]
        )
        try AssignHandler().execute(
            document: &doc,
            parameters: ["user": "alice", "note": "please review"],
            context: automationContext(
                appId: "app.test",
                docType: "SalesInvoice",
                documentId: "SI-042"
            )
        )
        XCTAssertEqual(assignments.entries.count, 1)
        XCTAssertEqual(assignments.entries.first?.target, .user("alice"))
        XCTAssertEqual(assignments.entries.first?.note, "please review")
        XCTAssertEqual(assignments.entries.first?.documentId, "SI-042")
    }

    func testAssignRecordsRoleTarget() throws {
        var doc = TestSupport.makeDocument(fields: [:])
        try AssignHandler().execute(
            document: &doc,
            parameters: ["role": "Auditor"],
            context: automationContext()
        )
        XCTAssertEqual(assignments.entries.first?.target, .role("Auditor"))
    }

    func testAssignRejectsMissingTarget() {
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(try AssignHandler().execute(
            document: &doc,
            parameters: ["note": "nobody?"],
            context: automationContext()
        ))
    }

    // MARK: - Runner

    func testRunnerFiresMatchingRuleOnSaveAndPersistsMutation() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "rule-1",
                    name: "Auto-post flag",
                    docType: "SalesInvoice",
                    triggerEvent: "onSave",
                    conditionExpression: "grandTotal > 100",
                    actions: [
                        AutomationAction(
                            type: "set_value",
                            parameters: ["field": "autoposted", "value": "true"]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-001",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(500)]
        ))

        let reloaded = try XCTUnwrap(harness.engine.fetch(docType: "SalesInvoice", id: "SI-001"))
        XCTAssertEqual(reloaded.fields["autoposted"], .bool(true))
    }

    func testRunnerSkipsRuleWhenConditionFalse() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "rule-1",
                    name: "Big-order notifier",
                    docType: "SalesInvoice",
                    triggerEvent: "onSave",
                    conditionExpression: "grandTotal > 1000",
                    actions: [
                        AutomationAction(
                            type: "send_notification",
                            parameters: ["subject": "Big order"]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-002",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(25)]
        ))

        XCTAssertTrue(notifications.entries.isEmpty)
    }

    func testRunnerMatchesFrappeStyleAliases() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "rule-1",
                    name: "On update notifier",
                    docType: "SalesInvoice",
                    triggerEvent: "on_update",
                    conditionExpression: "",
                    actions: [
                        AutomationAction(
                            type: "send_notification",
                            parameters: [:]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-003",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(1)]
        ))
        XCTAssertEqual(notifications.entries.count, 1)
    }

    func testRunnerFiresOnSubmitButNotOnSaveWhenTriggerIsOnSubmit() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType(isSubmittable: true))

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "rule-submit",
                    name: "On-submit only",
                    docType: "SalesInvoice",
                    triggerEvent: "onSubmit",
                    conditionExpression: "",
                    actions: [
                        AutomationAction(
                            type: "send_notification",
                            parameters: ["subject": "submitted"]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-004",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(10)]
        ))
        XCTAssertTrue(
            notifications.entries.isEmpty,
            "save should not trigger an onSubmit rule"
        )

        // Refetch to pick up the persisted `updatedAt` before submit.
        var doc = try XCTUnwrap(harness.engine.fetch(docType: "SalesInvoice", id: "SI-004"))
        try harness.engine.submit(&doc)
        XCTAssertEqual(notifications.entries.count, 1)
    }

    func testRunnerReentrancyGuardBreaksFeedbackLoops() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        // This rule mutates the document on save, which would fire another
        // DocumentSavedEvent. Without the re-entrancy guard this would loop
        // until stack overflow.
        runner.register(
            rules: [
                AutomationRule(
                    id: "feedback",
                    name: "Feedback",
                    docType: "SalesInvoice",
                    triggerEvent: "onSave",
                    conditionExpression: "",
                    actions: [
                        AutomationAction(
                            type: "set_value",
                            parameters: ["field": "counter", "value": "1"]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-loop",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(1)]
        ))

        let reloaded = try XCTUnwrap(harness.engine.fetch(docType: "SalesInvoice", id: "SI-loop"))
        XCTAssertEqual(reloaded.fields["counter"], .int(1))
    }

    func testRunnerReportsRuleFailure() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let reportedErrors = ErrorCollector()

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments,
            errorReporter: { reportedErrors.append($0) }
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "bad-rule",
                    name: "Bad",
                    docType: "SalesInvoice",
                    triggerEvent: "onSave",
                    conditionExpression: "",
                    actions: [
                        AutomationAction(
                            type: "set_value",
                            parameters: ["value": "missing field"]
                        )
                    ]
                )
            ],
            appId: "app.test"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-err",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(1)]
        ))

        XCTAssertEqual(reportedErrors.count, 1)
    }

    func testRunnerUnregisterRemovesRulesForApp() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        runner.register(
            rules: [
                AutomationRule(
                    id: "r",
                    name: "R",
                    docType: "SalesInvoice",
                    triggerEvent: "onSave",
                    conditionExpression: "",
                    actions: [AutomationAction(
                        type: "send_notification",
                        parameters: [:]
                    )]
                )
            ],
            appId: "app.test"
        )
        XCTAssertEqual(runner.ruleCount(forAppId: "app.test"), 1)

        runner.unregister(appId: "app.test")
        XCTAssertEqual(runner.ruleCount(forAppId: "app.test"), 0)

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-u", docType: "SalesInvoice", fields: ["grandTotal": .double(1)]
        ))
        XCTAssertTrue(notifications.entries.isEmpty)
    }

    // MARK: - AutomationActionDispatcher bridge

    func testDispatcherInvokesRegistryForDocumentEvent() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let dispatcher = AutomationActionDispatcher(
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-dispatch",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(5)]
        ))

        try dispatcher.dispatch(
            action: ExtensionActionDeclaration(
                actionType: "send_notification",
                parameters: ["subject": "From dispatcher"]
            ),
            context: ExtensionActionContext(
                appId: "app.bridge",
                origin: .documentEvent(
                    trigger: .onSave,
                    documentId: "SI-dispatch",
                    docType: "SalesInvoice"
                )
            )
        )

        XCTAssertEqual(notifications.entries.count, 1)
        XCTAssertEqual(notifications.entries.first?.subject, "From dispatcher")
        XCTAssertEqual(notifications.entries.first?.appId, "app.bridge")
    }

    func testDispatcherPersistsDocumentMutationThroughGateway() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(invoiceDocType())

        let dispatcher = AutomationActionDispatcher(
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-mutate",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(5)]
        ))

        try dispatcher.dispatch(
            action: ExtensionActionDeclaration(
                actionType: "set_value",
                parameters: ["field": "approved", "value": "true"]
            ),
            context: ExtensionActionContext(
                appId: "app.bridge",
                origin: .documentEvent(
                    trigger: .onSave,
                    documentId: "SI-mutate",
                    docType: "SalesInvoice"
                )
            )
        )

        let reloaded = try XCTUnwrap(harness.engine.fetch(docType: "SalesInvoice", id: "SI-mutate"))
        XCTAssertEqual(reloaded.fields["approved"], .bool(true))
    }

    func testDispatcherEndToEndThroughExtensionPointResolver() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let dispatcher = AutomationActionDispatcher(
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        let resolver = ExtensionPointResolver(
            emitter: harness.emitter,
            dispatcher: dispatcher
        )
        let installer = AppInstaller(
            database: harness.database,
            schemaValidator: SchemaValidator(),
            registry: harness.registry,
            extensionResolver: resolver
        )

        let docType = invoiceDocType(appId: "app.e2e", isSubmittable: true)
        let manifest = AppManifest(
            id: "app.e2e",
            name: "e2e",
            version: "0.1.0",
            minimumCoreVersion: "1.0.0",
            description: "",
            doctypes: [docType],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: [],
            extensionPoints: ExtensionPoints(
                documentEventSubscriptions: [
                    DocumentEventSubscription(
                        id: "sub",
                        docTypeSelector: "SalesInvoice",
                        trigger: .onSubmit,
                        actions: [
                            ExtensionActionDeclaration(
                                actionType: "send_notification",
                                parameters: ["subject": "submitted"]
                            )
                        ]
                    )
                ]
            )
        )

        try installer.install(manifest)

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-e2e",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(10)]
        ))
        // Refetch so the submit's optimistic-concurrency check matches the DB.
        var doc = try XCTUnwrap(harness.engine.fetch(docType: "SalesInvoice", id: "SI-e2e"))
        try harness.engine.submit(&doc)

        XCTAssertEqual(notifications.entries.count, 1)
        XCTAssertEqual(notifications.entries.first?.subject, "submitted")
        XCTAssertEqual(notifications.entries.first?.appId, "app.e2e")
    }

    // MARK: - AppInstaller → Runner wiring

    func testAppInstallerRegistersAndUnregistersAutomationRulesWithRunner() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let runner = AutomationRunner(
            emitter: harness.emitter,
            gateway: harness.engine,
            notificationSink: notifications,
            assignmentSink: assignments
        )
        let installer = AppInstaller(
            database: harness.database,
            schemaValidator: SchemaValidator(),
            registry: harness.registry,
            automationRunner: runner
        )

        let rule = AutomationRule(
            id: "rule-1",
            name: "Notify",
            docType: "SalesInvoice",
            triggerEvent: "onSave",
            conditionExpression: "",
            actions: [AutomationAction(
                type: "send_notification",
                parameters: ["subject": "hi"]
            )]
        )

        let manifest = AppManifest(
            id: "app.install",
            name: "install",
            version: "0.1.0",
            minimumCoreVersion: "1.0.0",
            description: "",
            doctypes: [invoiceDocType(appId: "app.install")],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [rule],
            dashboards: [],
            localizations: []
        )

        try installer.install(manifest)
        XCTAssertEqual(runner.ruleCount(forAppId: "app.install"), 1)

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-install",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(1)]
        ))
        XCTAssertEqual(notifications.entries.count, 1)

        try installer.uninstall(appId: "app.install")
        XCTAssertEqual(runner.ruleCount(forAppId: "app.install"), 0)
    }

    func testDispatcherSchedulerOriginRunsHandlerAgainstPlaceholder() throws {
        let dispatcher = AutomationActionDispatcher(
            notificationSink: notifications,
            assignmentSink: assignments
        )

        try dispatcher.dispatch(
            action: ExtensionActionDeclaration(
                actionType: "send_notification",
                parameters: ["subject": "daily"]
            ),
            context: ExtensionActionContext(
                appId: "app.sched",
                origin: .scheduler(declarationId: "daily-1", interval: .daily)
            )
        )
        XCTAssertEqual(notifications.entries.first?.subject, "daily")
        XCTAssertEqual(notifications.entries.first?.appId, "app.sched")
    }

    // MARK: - Fixtures

    private func automationContext(
        appId: String = "app.test",
        docType: String = "",
        documentId: String = ""
    ) -> AutomationContext {
        AutomationContext(
            appId: appId,
            trigger: "onSave",
            docType: docType,
            documentId: documentId,
            userId: "tester",
            now: Date(),
            notificationSink: notifications,
            assignmentSink: assignments
        )
    }

    private func invoiceDocType(
        appId: String = "app.test",
        isSubmittable: Bool = false
    ) -> DocType {
        TestSupport.makeDocType(
            id: "SalesInvoice",
            appId: appId,
            fields: [
                TestSupport.numberField("grandTotal")
            ],
            isSubmittable: isSubmittable,
            syncPolicy: isSubmittable
                ? TestSupport.submittableSyncPolicy()
                : TestSupport.defaultSyncPolicy(),
            titleField: "grandTotal"
        )
    }
}

// MARK: - Test Doubles

private struct ReplacementSetValueHandler: AutomationActionHandler {
    static let actionType = "set_value"
    func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        let field = parameters["field"] ?? "x"
        document.fields[field] = .string("replaced")
    }
}

private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Error] = []

    func append(_ error: Error) {
        lock.lock()
        items.append(error)
        lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }
}
