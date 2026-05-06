//
//  AttachmentTests.swift
//  mercantis coreTests
//
//  Phase C / P3.1 (ADR-043) — File attachments via AttachmentManager.
//  Covers attach / read / list / delete and the DocumentEngine cascade.
//

import XCTest
import GRDB
@testable import mercantis_core

final class AttachmentTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var store: AttachmentStore!
    private var attachmentManager: AttachmentManager!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "alice")
        store = try AttachmentStore(beside: harness.database)
        attachmentManager = AttachmentManager(
            database: harness.database,
            store: store
        )
        try harness.registry.register(TestSupport.makeDocType())
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        attachmentManager = nil
        store = nil
        harness = nil
    }

    // MARK: - Helpers

    private func saveDoc(_ id: String) throws {
        try harness.engine.save(TestSupport.makeDocument(
            id: id,
            fields: ["title": .string(id)]
        ))
    }

    private func attach(
        _ documentId: String,
        fileName: String = "scan.pdf",
        bytes: [UInt8] = [0x25, 0x50, 0x44, 0x46]
    ) throws -> Attachment {
        try attachmentManager.attach(
            documentId: documentId,
            docType: "Note",
            fileName: fileName,
            mimeType: "application/pdf",
            data: Data(bytes),
            userId: "alice"
        )
    }

    // MARK: - Attach / read

    func testAttachWritesMetadataAndBytes() throws {
        try saveDoc("d1")
        let attachment = try attach("d1")

        XCTAssertEqual(attachment.documentId, "d1")
        XCTAssertEqual(attachment.fileName, "scan.pdf")
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(attachment.byteSize, 4)
        XCTAssertFalse(attachment.sha256.isEmpty)

        let bytes = try attachmentManager.read(attachment)
        XCTAssertEqual(bytes, Data([0x25, 0x50, 0x44, 0x46]))
    }

    func testReadByIdMatchesAttachment() throws {
        try saveDoc("d2")
        let a = try attach("d2", bytes: Array("hello".utf8))
        let bytes = try attachmentManager.read(id: a.id)
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "hello")
    }

    func testReadFailsWhenStoredBytesMismatchHash() throws {
        try saveDoc("d3")
        let a = try attach("d3", bytes: [1, 2, 3])

        // Tamper with the on-disk file.
        let tampered = store.rootURL.appendingPathComponent(a.storagePath)
        try Data([9, 9, 9]).write(to: tampered)

        XCTAssertThrowsError(try attachmentManager.read(a)) { error in
            guard case AttachmentError.integrityFailure = error else {
                return XCTFail("expected integrityFailure, got \(error)")
            }
        }
    }

    // MARK: - Listing

    func testAttachmentsForDocumentReturnedInUploadOrder() throws {
        try saveDoc("d4")
        _ = try attach("d4", fileName: "first.pdf")
        Thread.sleep(forTimeInterval: 0.02)
        _ = try attach("d4", fileName: "second.pdf")

        let list = try attachmentManager.attachments(forDocumentId: "d4")
        XCTAssertEqual(list.map(\.fileName), ["first.pdf", "second.pdf"])
    }

    func testFieldKeyIsolatesAttachments() throws {
        try saveDoc("d5")
        _ = try attachmentManager.attach(
            documentId: "d5", docType: "Note", fieldKey: "scan",
            fileName: "scan.pdf", data: Data([1, 2]), userId: "alice"
        )
        _ = try attachmentManager.attach(
            documentId: "d5", docType: "Note", fieldKey: "receipt",
            fileName: "receipt.pdf", data: Data([3, 4]), userId: "alice"
        )

        let scans = try attachmentManager.attachments(forField: "scan", on: "d5")
        XCTAssertEqual(scans.map(\.fileName), ["scan.pdf"])
    }

    // MARK: - Delete

    func testDeleteRemovesMetadataAndBytes() throws {
        try saveDoc("d6")
        let a = try attach("d6")
        XCTAssertTrue(store.exists(storagePath: a.storagePath))

        try attachmentManager.delete(id: a.id, userId: "alice")

        XCTAssertNil(try attachmentManager.metadata(id: a.id))
        XCTAssertFalse(store.exists(storagePath: a.storagePath))
    }

    func testDocumentDeleteCascadesAttachments() throws {
        // Re-create the harness with the manager wired into the engine so
        // delete() cascades.
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = try TestSupport.makeHarness(userId: "alice")
        store = try AttachmentStore(beside: harness.database)
        attachmentManager = AttachmentManager(database: harness.database, store: store)

        let cascadingEngine = DocumentEngine(
            database: harness.database,
            registry: harness.registry,
            deviceId: "test-device",
            userId: "alice",
            eventEmitter: harness.emitter,
            attachmentManager: attachmentManager
        )

        try harness.registry.register(TestSupport.makeDocType())
        try cascadingEngine.save(TestSupport.makeDocument(id: "casc",
                                                           fields: ["title": .string("Casc")]))
        let a = try attach("casc")
        XCTAssertTrue(store.exists(storagePath: a.storagePath))

        try cascadingEngine.delete(docType: "Note", id: "casc")

        XCTAssertTrue(try attachmentManager.attachments(forDocumentId: "casc").isEmpty)
        XCTAssertFalse(store.exists(storagePath: a.storagePath))
    }

    // MARK: - Audit log

    func testAttachAndDeleteWriteAuditEntries() throws {
        let auditWriter = AuditLogWriter(database: harness.database)
        let manager = AttachmentManager(
            database: harness.database, store: store, auditWriter: auditWriter
        )

        try saveDoc("d7")
        let a = try manager.attach(
            documentId: "d7", docType: "Note",
            fileName: "x.pdf", data: Data([1]), userId: "alice"
        )
        try manager.delete(id: a.id, userId: "alice")

        let entries = try auditWriter.entries(forDocumentId: "d7")
        let actions = entries.map(\.action)
        XCTAssertTrue(actions.contains("attach"))
        XCTAssertTrue(actions.contains("detach"))
    }
}
