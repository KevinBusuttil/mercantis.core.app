//
//  ExecutionContextTests.swift
//  mercantis coreTests
//
//  Phase 0 / P0.1 — a per-operation ExecutionContext attributes audit rows,
//  document versions, and mutation provenance to the *live* operator, and the
//  absence of a context preserves pre-P0.1 behaviour (the engine's instance
//  identity is used).
//

import XCTest
import GRDB
@testable import mercantis_core

final class ExecutionContextTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        // The engine's constructor identity is deliberately distinct from any
        // operator below so a test failing to thread context is obvious.
        harness = try TestSupport.makeHarness(userId: "device-default")
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func context(_ operatorId: String, roles: Set<String> = []) -> ExecutionContext {
        ExecutionContext(
            operatorId: operatorId,
            companyId: "ACME",
            roles: roles,
            deviceId: "device-1",
            sessionId: "session-1"
        )
    }

    func testSaveAttributesAuditToContextOperator() throws {
        try harness.registry.register(TestSupport.makeDocType())
        try harness.engine.save(
            TestSupport.makeDocument(id: "n1", fields: ["title": .string("v1")]),
            context: context("bob")
        )

        let entries = try harness.engine.auditEntries(forDocumentId: "n1")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries[0].userId, "bob",
            "audit must record the live operator, not the engine's instance identity"
        )
    }

    func testLifecycleAttributesEachActionToItsOperator() throws {
        try harness.registry.register(TestSupport.makeDocType(isSubmittable: true))
        var doc = TestSupport.makeDocument(id: "inv-1", fields: ["title": .string("Invoice 1")])
        try harness.engine.save(doc, context: context("clerk"))
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-1"))
        try harness.engine.submit(&doc, context: context("manager"))

        let entries = try harness.engine.auditEntries(forDocumentId: "inv-1")
        let create = try XCTUnwrap(entries.first(where: { $0.action == "create" }))
        let submit = try XCTUnwrap(entries.first(where: { $0.action == "submit" }))
        XCTAssertEqual(create.userId, "clerk", "the creating operator must be recorded")
        XCTAssertEqual(
            submit.userId, "manager",
            "the submitting operator must be recorded on the submit lifecycle row"
        )
    }

    func testNoContextFallsBackToInstanceIdentity() throws {
        try harness.registry.register(TestSupport.makeDocType())
        // No context supplied: behaviour must be unchanged from pre-P0.1.
        try harness.engine.save(TestSupport.makeDocument(id: "n2", fields: ["title": .string("x")]))

        let entries = try harness.engine.auditEntries(forDocumentId: "n2")
        XCTAssertEqual(
            entries[0].userId, "device-default",
            "absent a context, the engine's instance identity is used"
        )
    }

    func testMutationRecordsContextOperatorAndDevice() throws {
        try harness.registry.register(TestSupport.makeDocType())
        try harness.engine.save(
            TestSupport.makeDocument(id: "n3", fields: ["title": .string("v")]),
            context: context("dana")
        )

        let provenance = try harness.database.read { db -> (userId: String, deviceId: String) in
            let row = try XCTUnwrap(
                Row.fetchOne(
                    db,
                    sql: """
                        SELECT userId, deviceId FROM sync_queue
                        WHERE type = 'upsertDocument'
                        ORDER BY localTimestamp DESC LIMIT 1
                        """
                )
            )
            return (row["userId"] ?? "", row["deviceId"] ?? "")
        }
        XCTAssertEqual(provenance.userId, "dana", "mutation provenance must carry the operator")
        XCTAssertEqual(provenance.deviceId, "device-1", "mutation provenance must carry the device")
    }

    func testLegacyAndSystemFactoriesCarryExpectedFlags() {
        let legacy = ExecutionContext.legacy(userId: "u", deviceId: "d")
        XCTAssertEqual(legacy.operatorId, "u")
        XCTAssertEqual(legacy.deviceId, "d")
        XCTAssertFalse(legacy.isSystemOperation)

        let system = ExecutionContext.system(deviceId: "d", companyId: "ACME")
        XCTAssertEqual(system.operatorId, "system")
        XCTAssertTrue(system.isSystemOperation, "system context must flag the bypass for audit")
    }
}
