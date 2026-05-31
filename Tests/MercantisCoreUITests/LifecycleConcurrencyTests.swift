//
//  LifecycleConcurrencyTests.swift
//  MercantisCoreUITests
//
//  Regression coverage for the optimistic-concurrency interaction between
//  `DocumentEngine.save` and the lifecycle transitions `submit` / `cancel`.
//
//  `save` rejects a write whose incoming `updatedAt` no longer matches the
//  stored row (optimistic concurrency). `submit`/`cancel` used to stamp a
//  fresh `Date()` onto the document *before* calling `save`, which made a
//  freshly-fetched document look stale and threw `concurrencyConflict` once a
//  second had elapsed since the last save (ISO8601 second-truncation only
//  masked it within the same wall-clock second). These tests fetch, let a
//  second pass, then transition — which must succeed.
//

import XCTest
@testable import MercantisCore

final class LifecycleConcurrencyTests: XCTestCase {

    // MARK: - Harness

    private struct Harness {
        let registry: MetadataRegistry
        let engine: DocumentEngine
        let url: URL
        func cleanUp() {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func makeHarness() throws -> Harness {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mercantis-lifecycle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("metadata.sqlite")
        let database = try MercantisDatabase(databaseURL: url)
        let registry = MetadataRegistry(database: database)
        let engine = DocumentEngine(
            database: database, registry: registry,
            deviceId: "test-device", userId: "test-user"
        )
        try registry.register(makeSubmittableDocType())
        return Harness(registry: registry, engine: engine, url: url)
    }

    private func makeSubmittableDocType() -> DocType {
        DocType(
            id: "Voucher",
            name: "Voucher",
            module: "Test",
            appId: "app.mercantis.test",
            isChildTable: false,
            isSubmittable: true,
            fields: [
                FieldDefinition(key: "title", label: "Title", type: .text, required: true)
            ],
            permissions: [
                PermissionRule(role: "System Manager", canRead: true, canWrite: true,
                               canCreate: true, canDelete: true, canSubmit: true, canAmend: true)
            ],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: ["title"],
            titleField: "title"
        )
    }

    private func makeDraft() -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString, docType: "Voucher", company: "", status: "Draft",
            createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
            docStatus: 0, fields: ["title": .string("A voucher")], children: [:]
        )
    }

    // MARK: - Tests

    func test_submit_after_delay_does_not_throw_concurrency_conflict() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let draft = makeDraft()
        try harness.engine.save(draft)

        var fetched = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))
        // Let a wall-clock second elapse so the old pre-stamping bug would fire.
        Thread.sleep(forTimeInterval: 1.2)

        XCTAssertNoThrow(try harness.engine.submit(&fetched))
        XCTAssertEqual(fetched.docStatus, 1)

        let reloaded = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))
        XCTAssertEqual(reloaded.docStatus, 1)
    }

    func test_cancel_after_delay_does_not_throw_concurrency_conflict() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        var draft = makeDraft()
        try harness.engine.save(draft)
        draft = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))
        try harness.engine.submit(&draft)

        var fetched = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))
        Thread.sleep(forTimeInterval: 1.2)

        XCTAssertNoThrow(try harness.engine.cancel(&fetched))
        XCTAssertEqual(fetched.docStatus, 2)
    }

    /// Normal edits must still be protected: saving a genuinely stale copy
    /// (one whose `updatedAt` predates a write made by someone else) throws.
    func test_normal_edit_still_detects_stale_write() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let draft = makeDraft()
        try harness.engine.save(draft)

        // Two independent fetches of the same row.
        var editorA = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))
        var editorB = try XCTUnwrap(harness.engine.fetch(docType: "Voucher", id: draft.id))

        // A saves first (a second later so its stored timestamp differs from
        // the copy B still holds); B is now stale.
        Thread.sleep(forTimeInterval: 1.2)
        editorA.fields["title"] = .string("Edited by A")
        try harness.engine.save(editorA)

        editorB.fields["title"] = .string("Edited by B")
        XCTAssertThrowsError(try harness.engine.save(editorB)) { error in
            guard case DocumentEngine.DocumentEngineError.concurrencyConflict = error else {
                return XCTFail("Expected concurrencyConflict, got \(error)")
            }
        }
    }
}
