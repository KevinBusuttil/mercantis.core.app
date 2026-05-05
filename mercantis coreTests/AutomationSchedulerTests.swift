//
//  AutomationSchedulerTests.swift
//  mercantis coreTests
//
//  Phase B §3.8 (ADR-041) — `AutomationRunner` registers an `onSchedule`
//  rule with the scheduler. On tick, it iterates documents of the rule's
//  DocType, evaluates the condition per-document, and runs the actions.
//

import XCTest
import GRDB
@testable import mercantis_core

final class AutomationSchedulerTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var scheduler: SchedulerService!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        scheduler = SchedulerService(
            persistence: SchedulerPersistence(database: harness.database),
            tickInterval: 60,
            clock: { Date() }
        )
    }

    override func tearDown() {
        scheduler.stop()
        scheduler = nil
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    // MARK: - Helpers

    private func registerNote() throws {
        try harness.registry.register(TestSupport.makeDocType(
            id: "Note",
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("priority"),
                TestSupport.textField("status"),
            ]
        ))
    }

    private func makeRunner() -> AutomationRunner {
        AutomationRunner(
            emitter: harness.emitter,
            registry: AutomationActionRegistry(),
            gateway: harness.engine,
            scheduler: scheduler
        )
    }

    private func saveNote(_ id: String, priority: Int, status: String = "Open") throws {
        var doc = TestSupport.makeDocument(
            id: id,
            fields: [
                "title":    .string(id),
                "priority": .int(priority),
                "status":   .string(status),
            ]
        )
        doc.status = status
        try harness.engine.save(doc)
    }

    // MARK: - Scheduler registration

    func testOnScheduleRuleIsRegisteredWithScheduler() throws {
        let runner = makeRunner()
        let rule = AutomationRule(
            id: "rule-1", name: "Daily refresh", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [], schedule: .daily
        )
        runner.register(rules: [rule], appId: "app.test")

        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.test"), 1)
        XCTAssertTrue(scheduler.registeredTaskKeys()
            .contains(where: { $0.contains("automation::rule-1") }))
    }

    func testNonScheduleRulesAreNotRegisteredWithScheduler() throws {
        let runner = makeRunner()
        let rule = AutomationRule(
            id: "rule-onsave", name: "Save handler", docType: "Note",
            triggerEvent: "onSave", conditionExpression: "", actions: []
        )
        runner.register(rules: [rule], appId: "app.test")

        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.test"), 0)
    }

    func testOnScheduleRuleWithoutScheduleIsNotRegistered() throws {
        let runner = makeRunner()
        let rule = AutomationRule(
            id: "rule-no-schedule", name: "Bad rule", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [], schedule: nil
        )
        runner.register(rules: [rule], appId: "app.test")

        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.test"), 0)
    }

    func testUnregisterCancelsScheduledHandles() throws {
        let runner = makeRunner()
        let rule = AutomationRule(
            id: "r", name: "", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [], schedule: .hourly
        )
        runner.register(rules: [rule], appId: "app.test")
        XCTAssertEqual(scheduler.taskCount(forAppId: "app.test"), 1)

        runner.unregister(appId: "app.test")
        XCTAssertEqual(scheduler.taskCount(forAppId: "app.test"), 0)
        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.test"), 0)
    }

    func testReRegisterReplacesPriorScheduledHandles() throws {
        let runner = makeRunner()
        let firstRule = AutomationRule(
            id: "r1", name: "", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [], schedule: .daily
        )
        runner.register(rules: [firstRule], appId: "app.test")
        XCTAssertEqual(scheduler.taskCount(forAppId: "app.test"), 1)

        // Replace with a different rule set — old handle should drop.
        let secondRule = AutomationRule(
            id: "r2", name: "", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [], schedule: .hourly
        )
        runner.register(rules: [secondRule], appId: "app.test")
        XCTAssertEqual(scheduler.taskCount(forAppId: "app.test"), 1)
        XCTAssertTrue(scheduler.registeredTaskKeys()
            .contains(where: { $0.contains("automation::r2") }))
        XCTAssertFalse(scheduler.registeredTaskKeys()
            .contains(where: { $0.contains("automation::r1") }))
    }

    // MARK: - Tick semantics

    func testSchedulerTickFiresActionAcrossEveryDocumentOfDocType() throws {
        try registerNote()
        try saveNote("a", priority: 1)
        try saveNote("b", priority: 2)
        try saveNote("c", priority: 3)

        let registry = AutomationActionRegistry()
        let runner = AutomationRunner(
            emitter: harness.emitter,
            registry: registry,
            gateway: harness.engine,
            scheduler: scheduler
        )

        let rule = AutomationRule(
            id: "set-status", name: "Mark reviewed", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "",
            actions: [
                AutomationAction(
                    type: "set_value",
                    parameters: ["field": "status", "value": "Reviewed"]
                )
            ],
            schedule: .all
        )
        runner.register(rules: [rule], appId: "app.test")

        // Drive a tick directly; the runner closure dispatches into the gateway.
        _ = scheduler.tick()

        for id in ["a", "b", "c"] {
            let updated = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: id))
            XCTAssertEqual(updated.fields["status"], .string("Reviewed"),
                           "Scheduled rule must fan out to every document of \(id)'s docType")
        }
    }

    func testSchedulerTickRespectsConditionExpressionPerDocument() throws {
        try registerNote()
        try saveNote("low",  priority: 1)
        try saveNote("high", priority: 9)

        let runner = AutomationRunner(
            emitter: harness.emitter,
            registry: AutomationActionRegistry(),
            gateway: harness.engine,
            scheduler: scheduler
        )

        let rule = AutomationRule(
            id: "elevate", name: "", docType: "Note",
            triggerEvent: "onSchedule", conditionExpression: "priority > 5",
            actions: [
                AutomationAction(
                    type: "set_value",
                    parameters: ["field": "status", "value": "Escalated"]
                )
            ],
            schedule: .all
        )
        runner.register(rules: [rule], appId: "app.test")
        _ = scheduler.tick()

        let low = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "low"))
        let high = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "high"))
        XCTAssertNotEqual(low.fields["status"], .string("Escalated"))
        XCTAssertEqual(high.fields["status"], .string("Escalated"))
    }

    // MARK: - applyManifests integration

    func testApplyManifestsRegistersScheduledRulesFromEveryManifest() throws {
        let runner = makeRunner()
        let manifestA = AppManifest(
            id: "app.a", name: "A", version: "0.1.0",
            minimumCoreVersion: "0.1.0", description: "A",
            doctypes: [], workflows: [], permissions: [], reports: [],
            automationRules: [
                AutomationRule(id: "r-a", name: "", docType: "Note",
                               triggerEvent: "onSchedule", conditionExpression: "",
                               actions: [], schedule: .daily)
            ],
            dashboards: [], localizations: []
        )
        let manifestB = AppManifest(
            id: "app.b", name: "B", version: "0.1.0",
            minimumCoreVersion: "0.1.0", description: "B",
            doctypes: [], workflows: [], permissions: [], reports: [],
            automationRules: [
                AutomationRule(id: "r-b", name: "", docType: "Note",
                               triggerEvent: "onSchedule", conditionExpression: "",
                               actions: [], schedule: .hourly)
            ],
            dashboards: [], localizations: []
        )
        runner.applyManifests([manifestA, manifestB])

        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.a"), 1)
        XCTAssertEqual(runner.scheduledRuleCount(forAppId: "app.b"), 1)
    }
}
