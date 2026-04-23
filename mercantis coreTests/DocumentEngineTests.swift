//
//  DocumentEngineTests.swift
//  mercantis coreTests
//
//  Covers the core CRUD path (ADR-005, ADR-009), optimistic concurrency
//  (ADR-023), and the submit/cancel/amend lifecycle (ADR-013).
//

import XCTest
import GRDB
@testable import mercantis_core

final class DocumentEngineTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    // MARK: - Helpers

    private func syncQueueCount() throws -> Int {
        try harness.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue") ?? 0
        }
    }

    private func documentVersionCount(for documentId: String) throws -> Int {
        try harness.database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM document_versions WHERE documentId = ?",
                arguments: [documentId]
            ) ?? 0
        }
    }

    // MARK: - Save / fetch round-trip

    func testSaveThenFetchReturnsTheSameDocument() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let doc = TestSupport.makeDocument(id: "note-1",
                                           fields: ["title": .string("Hello")])
        try harness.engine.save(doc)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-1"))
        XCTAssertEqual(fetched.id, "note-1")
        XCTAssertEqual(fetched.fields["title"], .string("Hello"))
    }

    func testSaveAppendsExactlyOneMutationRecord() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        XCTAssertEqual(try syncQueueCount(), 0)

        try harness.engine.save(TestSupport.makeDocument(fields: ["title": .string("x")]))

        XCTAssertEqual(try syncQueueCount(), 1, "save() must append exactly one mutation row")
    }

    func testSaveBumpsUpdatedAtOnRefetch() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let original = TestSupport.makeDocument(
            id: "note-ts",
            fields: ["title": .string("x")],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try harness.engine.save(original)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-ts"))
        XCTAssertGreaterThan(fetched.updatedAt.timeIntervalSince1970, 0,
                             "updatedAt must be refreshed by save()")
    }

    // MARK: - Optimistic concurrency (ADR-023)

    func testSecondSaveWithStaleTimestampThrowsConcurrencyConflict() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let doc = TestSupport.makeDocument(id: "note-c",
                                           fields: ["title": .string("v1")])
        try harness.engine.save(doc)

        // The caller's in-memory copy still carries the original updatedAt,
        // but the stored row has been rewritten with a fresh timestamp.
        XCTAssertThrowsError(try harness.engine.save(doc)) { error in
            guard case DocumentEngine.DocumentEngineError.concurrencyConflict = error else {
                return XCTFail("expected concurrencyConflict, got \(error)")
            }
        }
    }

    func testSaveSucceedsAfterRefetch() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-r",
                                                         fields: ["title": .string("v1")]))

        var refetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-r"))
        refetched.fields["title"] = .string("v2")

        XCTAssertNoThrow(try harness.engine.save(refetched))

        let final = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-r"))
        XCTAssertEqual(final.fields["title"], .string("v2"))
    }

    // MARK: - Document versioning (ADR-024)

    func testSaveRecordsADocumentVersionWhenFieldsChange() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-v",
                                                         fields: ["title": .string("v1")]))
        var refetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-v"))
        refetched.fields["title"] = .string("v2")
        try harness.engine.save(refetched)

        XCTAssertGreaterThanOrEqual(try documentVersionCount(for: "note-v"), 1)
    }

    // MARK: - Delete

    func testDeleteRemovesRowAndAppendsMutation() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-d",
                                                         fields: ["title": .string("x")]))
        XCTAssertNotNil(try harness.engine.fetch(docType: "Note", id: "note-d"))

        try harness.engine.delete(docType: "Note", id: "note-d")

        XCTAssertNil(try harness.engine.fetch(docType: "Note", id: "note-d"))
        XCTAssertEqual(try syncQueueCount(), 2, "one save + one delete mutation")
    }

    // MARK: - Submit (ADR-013)

    func testSubmitTransitionsDocStatusToOne() throws {
        let docType = TestSupport.makeDocType(isSubmittable: true)
        try harness.registry.register(docType)

        var doc = TestSupport.makeDocument(id: "inv-1",
                                           docType: "Note",
                                           fields: ["title": .string("Invoice 1")])
        try harness.engine.save(doc)

        // Refetch so we have the up-to-date timestamp before submitting.
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-1"))
        try harness.engine.submit(&doc)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-1"))
        XCTAssertEqual(fetched.docStatus, 1)
    }

    func testSubmitRejectsNonSubmittableDocType() throws {
        let docType = TestSupport.makeDocType(isSubmittable: false)
        try harness.registry.register(docType)

        var doc = TestSupport.makeDocument(id: "note-ns",
                                           docType: "Note",
                                           fields: ["title": .string("x")])
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-ns"))

        XCTAssertThrowsError(try harness.engine.submit(&doc)) { error in
            guard case DocumentEngine.DocumentEngineError.notSubmittable = error else {
                return XCTFail("expected notSubmittable, got \(error)")
            }
        }
    }

    func testEditingNonAllowOnSubmitFieldAfterSubmitIsRejected() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true, allowOnSubmit: false),
                TestSupport.textField("memo", allowOnSubmit: true)
            ],
            isSubmittable: true
        )
        try harness.registry.register(docType)

        var doc = TestSupport.makeDocument(
            id: "inv-imm",
            fields: ["title": .string("Final"), "memo": .string("")]
        )
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-imm"))
        try harness.engine.submit(&doc)

        var afterSubmit = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-imm"))
        afterSubmit.fields["title"] = .string("Tampered") // non-allowOnSubmit

        XCTAssertThrowsError(try harness.engine.save(afterSubmit)) { error in
            guard case DocumentEngine.DocumentEngineError.fieldImmutableAfterSubmit(let key, _) = error else {
                return XCTFail("expected fieldImmutableAfterSubmit, got \(error)")
            }
            XCTAssertEqual(key, "title")
        }
    }

    func testEditingAllowOnSubmitFieldAfterSubmitSucceeds() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true, allowOnSubmit: false),
                TestSupport.textField("memo", allowOnSubmit: true)
            ],
            isSubmittable: true
        )
        try harness.registry.register(docType)

        var doc = TestSupport.makeDocument(
            id: "inv-memo",
            fields: ["title": .string("Final"), "memo": .string("")]
        )
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-memo"))
        try harness.engine.submit(&doc)

        var afterSubmit = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-memo"))
        afterSubmit.fields["memo"] = .string("post-submit note")

        XCTAssertNoThrow(try harness.engine.save(afterSubmit))

        let final = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "inv-memo"))
        XCTAssertEqual(final.fields["memo"], .string("post-submit note"))
    }

    // MARK: - Cancel (ADR-013)

    func testCancelBlockedByLinkedSubmittedDocument() throws {
        // Parent DocType and Child DocType (child has a link to parent).
        let parent = TestSupport.makeDocType(
            id: "Parent",
            fields: [TestSupport.textField("title", required: true)],
            isSubmittable: true
        )
        let child = TestSupport.makeDocType(
            id: "Child",
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.linkField("parent", targeting: "Parent")
            ],
            isSubmittable: true
        )
        try harness.registry.register(parent)
        try harness.registry.register(child)

        // Save and submit the parent.
        var parentDoc = TestSupport.makeDocument(
            id: "P-1", docType: "Parent",
            fields: ["title": .string("Parent 1")]
        )
        try harness.engine.save(parentDoc)
        parentDoc = try XCTUnwrap(harness.engine.fetch(docType: "Parent", id: "P-1"))
        try harness.engine.submit(&parentDoc)

        // Save and submit a child that links to parent.
        var childDoc = TestSupport.makeDocument(
            id: "C-1", docType: "Child",
            fields: ["title": .string("Child 1"), "parent": .string("P-1")]
        )
        try harness.engine.save(childDoc)
        childDoc = try XCTUnwrap(harness.engine.fetch(docType: "Child", id: "C-1"))
        try harness.engine.submit(&childDoc)

        // Attempting to cancel the parent must be blocked.
        var submittedParent = try XCTUnwrap(harness.engine.fetch(docType: "Parent", id: "P-1"))
        XCTAssertThrowsError(try harness.engine.cancel(&submittedParent)) { error in
            guard case DocumentEngine.DocumentEngineError.cancelBlockedByLinks(_, let ids) = error else {
                return XCTFail("expected cancelBlockedByLinks, got \(error)")
            }
            XCTAssertTrue(ids.contains("C-1"))
        }
    }

    // MARK: - Amend (ADR-013)

    func testAmendCreatesDraftWithAmendedFromReference() throws {
        let docType = TestSupport.makeDocType(
            fields: [TestSupport.textField("title", required: true)],
            isSubmittable: true
        )
        try harness.registry.register(docType)

        var doc = TestSupport.makeDocument(
            id: "orig", fields: ["title": .string("Original")]
        )
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        try harness.engine.submit(&doc)

        var submitted = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        try harness.engine.cancel(&submitted)

        let cancelled = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "orig"))
        XCTAssertEqual(cancelled.docStatus, 2)

        let amended = try harness.engine.amend(cancelled)
        XCTAssertEqual(amended.docStatus, 0)
        XCTAssertEqual(amended.amendedFrom, "orig")
        XCTAssertNotEqual(amended.id, "orig")
        XCTAssertEqual(amended.fields["title"], .string("Original"))
    }
}
