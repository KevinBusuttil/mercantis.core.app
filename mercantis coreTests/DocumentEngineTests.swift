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

    // MARK: - Version readers (ADR-024, P0.8)

    func testVersionsReturnsEmptyForUnknownDocument() throws {
        XCTAssertTrue(try harness.engine.versions(of: "does-not-exist").isEmpty)
    }

    func testVersionsReturnsChronologicalHistoryWithCorrectDiffs() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-h",
                                                         fields: ["title": .string("v1")]))
        // ISO8601DateFormatter stores savedAt at second precision; sleep past the
        // next second boundary so the two versions are distinguishable.
        Thread.sleep(forTimeInterval: 1.1)

        var second = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-h"))
        second.fields["title"] = .string("v2")
        try harness.engine.save(second)

        let versions = try harness.engine.versions(of: "note-h")
        XCTAssertEqual(versions.count, 2)
        XCTAssertLessThanOrEqual(versions[0].savedAt, versions[1].savedAt)

        XCTAssertEqual(versions[0].fieldDiffs.first?.fieldKey, "title")
        XCTAssertNil(versions[0].fieldDiffs.first?.oldValue)
        XCTAssertEqual(versions[0].fieldDiffs.first?.newValue, .string("v1"))

        XCTAssertEqual(versions[1].fieldDiffs.first?.oldValue, .string("v1"))
        XCTAssertEqual(versions[1].fieldDiffs.first?.newValue, .string("v2"))
    }

    func testVersionAtBeforeFirstSaveReturnsNil() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let before = Date()
        Thread.sleep(forTimeInterval: 1.1)
        try harness.engine.save(TestSupport.makeDocument(id: "note-p",
                                                         fields: ["title": .string("v1")]))

        XCTAssertNil(try harness.engine.version(of: "note-p", at: before))
    }

    func testVersionAtReturnsLatestSaveAtOrBeforeTimestamp() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-pit",
                                                         fields: ["title": .string("v1")]))
        Thread.sleep(forTimeInterval: 1.1)
        let cutoff = Date()
        Thread.sleep(forTimeInterval: 1.1)

        var second = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-pit"))
        second.fields["title"] = .string("v2")
        try harness.engine.save(second)

        let snapshot = try XCTUnwrap(harness.engine.version(of: "note-pit", at: cutoff))
        XCTAssertEqual(snapshot.fieldDiffs.first?.newValue, .string("v1"),
                       "cutoff between v1 and v2 saves must resolve to the v1 version")
    }

    func testSaveWithoutFieldChangesDoesNotAppendAVersion() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(id: "note-nop",
                                                         fields: ["title": .string("v1")]))
        let countAfterFirstSave = try harness.engine.versions(of: "note-nop").count

        // Re-save with identical field values (refetch to pick up fresh updatedAt).
        let refetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "note-nop"))
        try harness.engine.save(refetched)

        XCTAssertEqual(try harness.engine.versions(of: "note-nop").count, countAfterFirstSave,
                       "a save that changes no fields must not append a version row")
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

    // MARK: - Apply Remote (P0.2 — routes sync-received writes through DocumentEngine)

    private func remoteMutation(for doc: Document, userId: String = "remote-user") throws -> MutationRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(doc),
            deviceId: "remote-device",
            userId: userId,
            localTimestamp: Date(),
            syncVersion: doc.syncVersion,
            status: .applied
        )
    }

    func testApplyRemotePersistsDocumentAndForcesSyncedState() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let doc = TestSupport.makeDocument(
            id: "r-1",
            fields: ["title": .string("From remote")],
            syncVersion: 7
        )
        let mutation = try remoteMutation(for: doc)

        try harness.engine.applyRemote(doc, from: mutation)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "r-1"))
        XCTAssertEqual(fetched.fields["title"], .string("From remote"))
        XCTAssertEqual(fetched.syncState, .synced)
        XCTAssertEqual(fetched.syncVersion, 7)
    }

    func testApplyRemoteDoesNotAppendToSyncQueue() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let doc = TestSupport.makeDocument(id: "r-2", fields: ["title": .string("x")])
        let mutation = try remoteMutation(for: doc)

        XCTAssertEqual(try syncQueueCount(), 0)
        try harness.engine.applyRemote(doc, from: mutation)
        XCTAssertEqual(try syncQueueCount(), 0,
                       "applyRemote must not append a new mutation — the received mutation is the record")
    }

    func testApplyRemoteRecordsDocumentVersion() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        // Seed a local version so the remote apply produces a diff.
        try harness.engine.save(TestSupport.makeDocument(id: "r-3",
                                                         fields: ["title": .string("v1")]))

        let remote = TestSupport.makeDocument(id: "r-3",
                                              fields: ["title": .string("v2")],
                                              syncVersion: 5)
        let mutation = try remoteMutation(for: remote)
        try harness.engine.applyRemote(remote, from: mutation)

        XCTAssertGreaterThanOrEqual(try documentVersionCount(for: "r-3"), 2,
                                    "one version from save, one from applyRemote")
    }

    func testApplyRemoteRunsValidationPipelineAndRejectsInvalidRemoteDocuments() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", required: true)
        ])
        try harness.registry.register(docType)

        // Remote document missing the required `title`.
        let doc = TestSupport.makeDocument(id: "r-bad", fields: [:])
        let mutation = try remoteMutation(for: doc)

        XCTAssertThrowsError(try harness.engine.applyRemote(doc, from: mutation)) { error in
            guard case DocumentEngine.DocumentEngineError.validationFailed = error else {
                return XCTFail("expected validationFailed, got \(error)")
            }
        }
        XCTAssertNil(try harness.engine.fetch(docType: "Note", id: "r-bad"),
                     "rejected remote writes must not touch the documents table")
    }

    func testApplyRemoteEnforcesSubmitImmutabilityOnPeerMutations() throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true, allowOnSubmit: false),
                TestSupport.textField("memo", allowOnSubmit: true)
            ],
            isSubmittable: true
        )
        try harness.registry.register(docType)

        // Save and submit locally.
        var doc = TestSupport.makeDocument(
            id: "r-imm",
            fields: ["title": .string("Final"), "memo": .string("")]
        )
        try harness.engine.save(doc)
        doc = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "r-imm"))
        try harness.engine.submit(&doc)

        // Craft a remote mutation that mutates a non-allowOnSubmit field.
        var tampered = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "r-imm"))
        tampered.fields["title"] = .string("Tampered by peer")
        let mutation = try remoteMutation(for: tampered)

        XCTAssertThrowsError(try harness.engine.applyRemote(tampered, from: mutation)) { error in
            guard case DocumentEngine.DocumentEngineError.fieldImmutableAfterSubmit = error else {
                return XCTFail("expected fieldImmutableAfterSubmit, got \(error)")
            }
        }
    }

    // MARK: - Mutation payload format (regression for UpsertPayload → full Document)

    func testSavedMutationPayloadEncodesFullDocument() throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(
            id: "payload-1",
            fields: ["title": .string("Round-trip me")]
        ))

        let payloadString = try XCTUnwrap(harness.database.read { db in
            try String.fetchOne(db,
                sql: "SELECT payload FROM sync_queue WHERE type = 'upsertDocument' ORDER BY localTimestamp DESC LIMIT 1"
            )
        })
        let data = try XCTUnwrap(payloadString.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Document.self, from: data)

        XCTAssertEqual(decoded.id, "payload-1")
        XCTAssertEqual(decoded.fields["title"], .string("Round-trip me"))
    }

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
