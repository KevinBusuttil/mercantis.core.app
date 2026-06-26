//
//  PostingBatchTests.swift
//  mercantis coreTests
//
//  Phase 1 — a PostingBatch recorded through the UnitOfWork commits atomically
//  with the source document's submit, and rolls back entirely if posting fails.
//  This is the contract that makes "submitted but unposted / partially posted"
//  impossible.
//

import XCTest
import GRDB
@testable import mercantis_core

final class PostingBatchTests: XCTestCase {

    private struct InjectedFailure: Error {}

    private var harness: TestSupport.Harness!
    private var store: PostingBatchStore!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "tester")
        store = PostingBatchStore(database: harness.database)
        try harness.registry.register(TestSupport.makeDocType(isSubmittable: true))
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
        store = nil
    }

    private func savedDraft(_ id: String) throws -> Document {
        try harness.engine.save(TestSupport.makeDocument(id: id, fields: ["title": .string("Doc \(id)")]))
        return try XCTUnwrap(harness.engine.fetch(docType: "Note", id: id))
    }

    func testDeterministicBatchID() {
        XCTAssertEqual(PostingBatch.makeID(sourceId: "INV-1"), "POST-INV-1-v1")
        XCTAssertEqual(PostingBatch.makeID(sourceId: "INV-1", version: 2), "POST-INV-1-v2")
    }

    func testPostingBatchCommitsWithSubmit() throws {
        var doc = try savedDraft("a1")
        let batchId = PostingBatch.makeID(sourceId: "a1")

        try harness.engine.submit(&doc, inTransaction: { uow in
            XCTAssertFalse(try uow.postingBatchExists(id: batchId), "idempotency guard: no batch yet")
            try uow.recordPostingBatch(PostingBatch(
                id: batchId, sourceType: "Note", sourceId: "a1",
                status: .posted, postedAt: Date()
            ))
        })

        let batch = try XCTUnwrap(store.batch(id: batchId))
        XCTAssertEqual(batch.status, .posted)
        XCTAssertEqual(batch.postedBy, "tester", "postedBy is stamped from the operator context")
        XCTAssertEqual(try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "a1")).docStatus, 1)
    }

    func testPostingBatchRollsBackWhenSubmitFails() throws {
        var doc = try savedDraft("a2")
        let batchId = PostingBatch.makeID(sourceId: "a2")

        XCTAssertThrowsError(try harness.engine.submit(&doc, inTransaction: { uow in
            try uow.recordPostingBatch(PostingBatch(
                id: batchId, sourceType: "Note", sourceId: "a2", status: .posted
            ))
            throw InjectedFailure()
        }))

        XCTAssertNil(try store.batch(id: batchId), "no posting batch may survive a rolled-back submit")
        XCTAssertEqual(
            try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "a2")).docStatus, 0,
            "the document must remain Draft when posting fails"
        )
    }

    func testStoreQueriesByStatusAndSource() throws {
        var d1 = try savedDraft("b1")
        try harness.engine.submit(&d1, inTransaction: { uow in
            try uow.recordPostingBatch(PostingBatch(
                id: PostingBatch.makeID(sourceId: "b1"), sourceType: "Note", sourceId: "b1", status: .posted
            ))
        })
        var d2 = try savedDraft("b2")
        try harness.engine.submit(&d2, inTransaction: { uow in
            try uow.recordPostingBatch(PostingBatch(
                id: PostingBatch.makeID(sourceId: "b2"), sourceType: "Note", sourceId: "b2",
                status: .failed, errorCode: "UNBALANCED", errorMessage: "debits != credits"
            ))
        })

        XCTAssertEqual(try store.batches(withStatus: .posted).count, 1)
        let failed = try store.batches(withStatus: .failed)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed.first?.errorCode, "UNBALANCED")
        XCTAssertTrue(try store.exists(id: PostingBatch.makeID(sourceId: "b1")))
        XCTAssertEqual(try store.currentBatch(forSourceType: "Note", sourceId: "b2")?.status, .failed)
    }
}
