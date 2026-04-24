//
//  ExtensionPointsTests.swift
//  mercantis coreTests
//
//  Covers declarative extension-point resolution at install time. (ADR-015,
//  ADR-026, P1.3)
//

import XCTest
@testable import mercantis_core

final class ExtensionPointsTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var dispatcher: LoggingExtensionActionDispatcher!
    private var schedulerRegistrar: RecordingExtensionSchedulerRegistrar!
    private var resolver: ExtensionPointResolver!
    private var installer: AppInstaller!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        dispatcher = LoggingExtensionActionDispatcher()
        schedulerRegistrar = RecordingExtensionSchedulerRegistrar()
        resolver = ExtensionPointResolver(
            emitter: harness.emitter,
            dispatcher: dispatcher,
            schedulerRegistrar: schedulerRegistrar
        )
        installer = AppInstaller(
            database: harness.database,
            schemaValidator: SchemaValidator(),
            registry: harness.registry,
            extensionResolver: resolver
        )
    }

    override func tearDown() {
        resolver?.clearAll()
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
        dispatcher = nil
        schedulerRegistrar = nil
        resolver = nil
        installer = nil
    }

    // MARK: - Manifest decoding

    func testManifestDecodesWithoutExtensionPointsField() throws {
        // Pre-P1.3 manifests omit the `extensionPoints` key entirely.
        let json = """
        {
            "id": "app.mercantis.legacy",
            "name": "Legacy",
            "version": "0.1.0",
            "minimumCoreVersion": "1.0.0",
            "description": "",
            "doctypes": [],
            "workflows": [],
            "permissions": [],
            "reports": [],
            "automationRules": [],
            "dashboards": [],
            "localizations": []
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(AppManifest.self, from: json)
        XCTAssertEqual(manifest.extensionPoints, .empty)
    }

    func testManifestRejectsUnsupportedTrigger() {
        let json = """
        {
            "id": "app.mercantis.invalid",
            "name": "Invalid",
            "version": "0.1.0",
            "minimumCoreVersion": "1.0.0",
            "description": "",
            "doctypes": [],
            "workflows": [],
            "permissions": [],
            "reports": [],
            "automationRules": [],
            "dashboards": [],
            "localizations": [],
            "extensionPoints": {
                "documentEventSubscriptions": [{
                    "id": "s1",
                    "docTypeSelector": "*",
                    "trigger": "after_insert",
                    "actions": []
                }],
                "schedulerEvents": []
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AppManifest.self, from: json))
    }

    // MARK: - Installer wiring

    func testInstallAppliesExtensionPointsAndUninstallReleasesThem() throws {
        let manifest = Self.makeManifest(
            id: "app.test.wiring",
            docType: Self.invoiceDocType(appId: "app.test.wiring"),
            subscription: DocumentEventSubscription(
                id: "sub-1",
                docTypeSelector: "SalesInvoice",
                trigger: .onSubmit,
                actions: [ExtensionActionDeclaration(actionType: "send_notification")]
            )
        )

        try installer.install(manifest)

        XCTAssertEqual(resolver.subscriptionCount(forAppId: manifest.id), 1)
        XCTAssertTrue(resolver.boundAppIds().contains(manifest.id))

        try installer.uninstall(appId: manifest.id)

        XCTAssertEqual(resolver.subscriptionCount(forAppId: manifest.id), 0)
        XCTAssertFalse(resolver.boundAppIds().contains(manifest.id))
    }

    func testReinstallIsIdempotent() throws {
        let manifest = Self.makeManifest(
            id: "app.test.reinstall",
            docType: Self.invoiceDocType(appId: "app.test.reinstall"),
            subscription: DocumentEventSubscription(
                id: "sub-1",
                docTypeSelector: "*",
                trigger: .onSave,
                actions: [ExtensionActionDeclaration(actionType: "set_value")]
            )
        )

        try installer.install(manifest)
        try installer.install(manifest)

        XCTAssertEqual(
            resolver.subscriptionCount(forAppId: manifest.id), 1,
            "reinstall must clear prior bindings rather than accumulate"
        )
    }

    func testSchedulerDeclarationsRegisterAndReleaseWithApp() throws {
        let manifest = Self.makeManifest(
            id: "app.test.sched",
            docType: Self.invoiceDocType(appId: "app.test.sched"),
            subscription: nil,
            schedulerEvents: [
                SchedulerEventDeclaration(
                    id: "daily-reminder",
                    interval: .daily,
                    actions: [ExtensionActionDeclaration(actionType: "send_notification")]
                )
            ]
        )

        try installer.install(manifest)

        XCTAssertEqual(resolver.scheduleCount(forAppId: manifest.id), 1)
        XCTAssertEqual(
            schedulerRegistrar.entries,
            [RecordingExtensionSchedulerRegistrar.Entry(
                appId: "app.test.sched",
                declarationId: "daily-reminder"
            )]
        )

        try installer.uninstall(appId: manifest.id)

        XCTAssertEqual(resolver.scheduleCount(forAppId: manifest.id), 0)
        XCTAssertTrue(schedulerRegistrar.entries.isEmpty)
    }

    // MARK: - Event dispatch

    func testOnSubmitSubscriptionFiresOnMatchingDocType() throws {
        let docType = Self.invoiceDocType(appId: "app.test.dispatch", isSubmittable: true)
        let manifest = Self.makeManifest(
            id: "app.test.dispatch",
            docType: docType,
            subscription: DocumentEventSubscription(
                id: "sub-submit",
                docTypeSelector: "SalesInvoice",
                trigger: .onSubmit,
                actions: [
                    ExtensionActionDeclaration(
                        actionType: "send_notification",
                        parameters: ["channel": "ops"]
                    )
                ]
            )
        )

        try installer.install(manifest)

        var saved = try harness.engine.save(
            TestSupport.makeDocument(
                id: "SI-001",
                docType: "SalesInvoice",
                fields: ["grandTotal": .double(100)]
            )
        )
        try harness.engine.submit(&saved)

        let entries = dispatcher.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.actionType, "send_notification")
        XCTAssertEqual(entries.first?.appId, "app.test.dispatch")
        XCTAssertEqual(entries.first?.parameters["channel"], "ops")
    }

    func testDocTypeSelectorSkipsNonMatchingDocTypes() throws {
        try harness.registry.register(
            TestSupport.makeDocType(
                id: "Note",
                appId: "app.test.selector",
                fields: [TestSupport.textField("title", required: true)]
            )
        )

        let invoice = Self.invoiceDocType(appId: "app.test.selector")
        let manifest = Self.makeManifest(
            id: "app.test.selector",
            docType: invoice,
            subscription: DocumentEventSubscription(
                id: "sub-invoice-only",
                docTypeSelector: "SalesInvoice",
                trigger: .onSave,
                actions: [ExtensionActionDeclaration(actionType: "log")]
            )
        )

        try installer.install(manifest)

        try harness.engine.save(TestSupport.makeDocument(
            id: "note-1",
            docType: "Note",
            fields: ["title": .string("ignored")]
        ))
        XCTAssertTrue(
            dispatcher.entries.isEmpty,
            "docTypeSelector == SalesInvoice must skip Note save"
        )

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-002",
            docType: "SalesInvoice",
            fields: ["grandTotal": .double(25)]
        ))
        XCTAssertEqual(dispatcher.entries.count, 1)
    }

    func testWildcardSelectorMatchesEveryDocType() throws {
        try harness.registry.register(
            TestSupport.makeDocType(
                id: "Note",
                appId: "app.test.wild",
                fields: [TestSupport.textField("title", required: true)]
            )
        )
        let manifest = Self.makeManifest(
            id: "app.test.wild",
            docType: Self.invoiceDocType(appId: "app.test.wild"),
            subscription: DocumentEventSubscription(
                id: "sub-*",
                docTypeSelector: "*",
                trigger: .onSave,
                actions: [ExtensionActionDeclaration(actionType: "log")]
            )
        )
        try installer.install(manifest)

        try harness.engine.save(TestSupport.makeDocument(
            id: "note-1", docType: "Note", fields: ["title": .string("x")]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-003", docType: "SalesInvoice", fields: ["grandTotal": .double(1)]
        ))

        XCTAssertEqual(dispatcher.entries.count, 2)
    }

    func testUninstallStopsDispatchingEventsForThatApp() throws {
        let manifest = Self.makeManifest(
            id: "app.test.teardown",
            docType: Self.invoiceDocType(appId: "app.test.teardown"),
            subscription: DocumentEventSubscription(
                id: "sub-save",
                docTypeSelector: "*",
                trigger: .onSave,
                actions: [ExtensionActionDeclaration(actionType: "log")]
            )
        )
        try installer.install(manifest)
        try installer.uninstall(appId: manifest.id)

        // DocType is gone from the registry after uninstall; re-register so
        // the save goes through with full validation.
        try harness.registry.register(Self.invoiceDocType(appId: "app.test.teardown"))

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-004", docType: "SalesInvoice", fields: ["grandTotal": .double(5)]
        ))

        XCTAssertTrue(
            dispatcher.entries.isEmpty,
            "uninstall must release the subscription before the save fires"
        )
    }

    // MARK: - Restore

    func testRestoreReappliesBindingsForAlreadyInstalledApps() throws {
        let manifest = Self.makeManifest(
            id: "app.test.restore",
            docType: Self.invoiceDocType(appId: "app.test.restore"),
            subscription: DocumentEventSubscription(
                id: "sub-save",
                docTypeSelector: "*",
                trigger: .onSave,
                actions: [ExtensionActionDeclaration(actionType: "log")]
            )
        )
        try installer.install(manifest)

        // Simulate a process restart: discard every in-memory binding.
        resolver.clearAll()
        XCTAssertEqual(resolver.subscriptionCount(forAppId: manifest.id), 0)

        let applied = try installer.restoreExtensionPoints()
        XCTAssertEqual(applied, [manifest.id])
        XCTAssertEqual(resolver.subscriptionCount(forAppId: manifest.id), 1)

        try harness.engine.save(TestSupport.makeDocument(
            id: "SI-restore", docType: "SalesInvoice", fields: ["grandTotal": .double(1)]
        ))
        XCTAssertEqual(dispatcher.entries.count, 1)
    }

    // MARK: - Fixtures

    private static func invoiceDocType(
        appId: String,
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

    private static func makeManifest(
        id: String,
        docType: DocType,
        subscription: DocumentEventSubscription?,
        schedulerEvents: [SchedulerEventDeclaration] = []
    ) -> AppManifest {
        AppManifest(
            id: id,
            name: id,
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
                documentEventSubscriptions: subscription.map { [$0] } ?? [],
                schedulerEvents: schedulerEvents
            )
        )
    }
}
