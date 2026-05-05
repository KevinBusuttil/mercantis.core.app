//
//  AuditLogTests.swift
//  mercantis coreTests
//
//  Phase A §3.2 — every DocumentEngine write path appends to `audit_log`,
//  and the new reader API returns rows in deterministic order.
//

import XCTest
import GRDB
@testable import mercantis_core

final class AuditLogTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "alice")
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func registerDocType(submittable: Bool = false) throws {
        try harness.registry.register(TestSupport.makeDocType(isSubmittable: submittable))
    }

    private func auditCount() throws -> Int {
        try harness.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_log") ?? 0
        }
    }

    func testCreateThenUpdateAppendsTwoAuditRows() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(id: "n1",
                                                         fields: ["title": .string("v1")]))
        var refetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "n1"))
        refetched.fields["title"] = .string("v2")
        try harness.engine.save(refetched)

        let entries = try harness.engine.auditEntries(forDocumentId: "n1")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].action, "create")
        XCTAssertEqual(entries[1].action, "update")
        XCTAssertEqual(entries[0].userId, "alice")
    }

    func testDeleteAppendsAuditRow() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(id: "n2",
                                                         fields: ["title": .string("x")]))
        try harness.engine.delete(docType: "Note", id: "n2")

        let entries = try harness.engine.auditEntries(forDocumentId: "n2")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.action, "delete")
    }

    func testSubmitWritesLifecycleAuditRow() throws {
        try registerDocType(submittable: true)
        var doc = TestSupport.makeDocument(id: "inv-1",
                                           fields: ["title": .string("Invoice 1")])
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-1"))
        try harness.engine.submit(&doc)

        let entries = try harness.engine.auditEntries(forDocumentId: "inv-1")
        XCTAssertTrue(entries.contains(where: { $0.action == "submit" }),
                      "submit must append a lifecycle audit row")
    }

    func testCancelAndAmendWriteLifecycleAuditRows() throws {
        try registerDocType(submittable: true)
        var doc = TestSupport.makeDocument(id: "orig",
                                           fields: ["title": .string("Original")])
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        try harness.engine.submit(&doc)
        var submitted = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        try harness.engine.cancel(&submitted)
        let cancelled = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        let amended = try harness.engine.amend(cancelled)

        let origEntries = try harness.engine.auditEntries(forDocumentId: "orig")
        XCTAssertTrue(origEntries.contains(where: { $0.action == "submit" }))
        XCTAssertTrue(origEntries.contains(where: { $0.action == "cancel" }))

        let amendEntries = try harness.engine.auditEntries(forDocumentId: amended.id)
        XCTAssertTrue(amendEntries.contains(where: { $0.action == "amend" }))
    }

    func testDocTypeReaderReturnsDescendingTimestamps() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(id: "a", fields: ["title": .string("A")]))
        try harness.engine.save(TestSupport.makeDocument(id: "b", fields: ["title": .string("B")]))

        let entries = try harness.engine.auditEntries(forDocType: "Note")
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        for i in 1..<entries.count {
            XCTAssertGreaterThanOrEqual(entries[i - 1].timestamp, entries[i].timestamp)
        }
    }

    func testAuditPayloadCarriesBeforeAndAfterSnapshots() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(id: "p1",
                                                         fields: ["title": .string("v1")]))
        var refetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "p1"))
        refetched.fields["title"] = .string("v2")
        try harness.engine.save(refetched)

        let entries = try harness.engine.auditEntries(forDocumentId: "p1")
        let updateRow = try XCTUnwrap(entries.first(where: { $0.action == "update" }))

        struct Wrapper: Codable {
            let before: [String: FieldValue]?
            let after: [String: FieldValue]?
        }
        let data = try XCTUnwrap(updateRow.payloadJSON.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wrapper = try decoder.decode(Wrapper.self, from: data)
        XCTAssertEqual(wrapper.before?["title"], .string("v1"))
        XCTAssertEqual(wrapper.after?["title"], .string("v2"))
    }

    func testInitialAuditCountIsZeroBeforeAnyWrite() throws {
        XCTAssertEqual(try auditCount(), 0)
    }
}
