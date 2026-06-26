//
//  UnitOfWorkTests.swift
//  mercantis coreTests
//
//  Phase 0 / P0.8 — lifecycle audit rows commit in the SAME transaction as the
//  docStatus change, and the `inTransaction` unit-of-work seam commits (or rolls
//  back) atomically with the submit. The rollback test is the Phase-1 contract:
//  a posting failure must leave no partial state and no "submitted" document.
//

import XCTest
import GRDB
@testable import mercantis_core

final class UnitOfWorkTests: XCTestCase {

    private struct InjectedFailure: Error {}

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "tester")
        try harness.registry.register(TestSupport.makeDocType(isSubmittable: true))
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func savedDraft(_ id: String) throws -> Document {
        try harness.engine.save(
            TestSupport.makeDocument(id: id, fields: ["title": .string("Doc \(id)")])
        )
        return try XCTUnwrap(harness.engine.fetch(docType: "Note", id: id))
    }

    private func actions(_ id: String) throws -> [String] {
        try harness.engine.auditEntries(forDocumentId: id).map { $0.action }
    }

    func testSubmitAppendsLifecycleAuditAtomically() throws {
        var doc = try savedDraft("a1")
        try harness.engine.submit(&doc)

        XCTAssertTrue(try actions("a1").contains("submit"), "submit must append a lifecycle audit row")
        XCTAssertEqual(try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "a1")).docStatus, 1)
    }

    func testInTransactionHookCommitsWithSubmit() throws {
        var doc = try savedDraft("a2")
        try harness.engine.submit(&doc, inTransaction: { uow in
            // Stand-in for Phase 1 posting: a row written through the unit of work.
            try uow.audit(
                action: "posted",
                documentId: "a2",
                docType: "Note",
                payloadJSON: "{\"batch\":\"B1\"}"
            )
        })

        let recorded = try actions("a2")
        XCTAssertTrue(recorded.contains("submit"))
        XCTAssertTrue(recorded.contains("posted"), "unit-of-work work must commit with the submit")
    }

    func testInTransactionFailureRollsBackEntireSubmit() throws {
        var doc = try savedDraft("a3")

        XCTAssertThrowsError(
            try harness.engine.submit(&doc, inTransaction: { _ in throw InjectedFailure() }),
            "a failing in-transaction hook must propagate"
        )

        // Nothing from the failed submit may survive: the document is still Draft
        // and no submit audit row was written.
        let persisted = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "a3"))
        XCTAssertEqual(persisted.docStatus, 0, "a failing hook must roll back the docStatus change")
        let recorded = try actions("a3")
        XCTAssertFalse(recorded.contains("submit"), "no submit audit row may survive a rolled-back submit")
        XCTAssertTrue(recorded.contains("create"), "the prior committed create remains")
    }
}
