//
//  BarcodeFieldSmokeTests.swift
//  MercantisCoreUITests
//

import XCTest
import SwiftUI
import MercantisCore
import MercantisCoreUI

final class BarcodeFieldSmokeTests: XCTestCase {

    func test_barcode_field_renders_text_field_with_string_binding() {
        var storedValue = ""
        let binding = Binding<String>(
            get: { storedValue },
            set: { storedValue = $0 }
        )

        let field = BarcodeField(value: binding, isReadOnly: false)
        binding.wrappedValue = "01234567890123"

        XCTAssertNotNil(field)
        XCTAssertEqual(storedValue, "01234567890123")
    }

    func test_barcode_field_persists_string_through_save() throws {
        let harness = try BarcodeHarness.make()
        defer { harness.cleanUp() }

        let docType = BarcodeHarness.makeBarcodeDocType()
        try harness.registry.register(docType)

        let document = BarcodeHarness.makeBarcodeDocument(value: "01234567890123")
        try harness.engine.save(document)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: docType.id, id: document.id))
        XCTAssertEqual(fetched.fields["barcode"], .string("01234567890123"))
    }

    func test_barcode_field_validates_as_string() {
        let docType = BarcodeHarness.makeBarcodeDocType()
        let document = BarcodeHarness.makeBarcodeDocument(fieldValue: .int(42))
        let pipeline = ValidationPipeline(stages: [TypeCoercionStage()])

        let errors = pipeline.validate(
            document: document,
            context: ValidationContext(docType: docType)
        )

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.stage, "TypeCoercion")
        XCTAssertEqual(errors.first?.field, "barcode")
    }
}

private enum BarcodeHarness {

    struct Bundle {
        let registry: MetadataRegistry
        let engine: DocumentEngine
        let url: URL

        func cleanUp() {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func make() throws -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mercantis-barcode-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("metadata.sqlite")

        let database = try MercantisDatabase(databaseURL: url)
        let registry = MetadataRegistry(database: database)
        let engine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: "test-device",
            userId: "test-user"
        )

        return Bundle(registry: registry, engine: engine, url: url)
    }

    static func makeBarcodeDocType() -> DocType {
        DocType(
            id: "BarcodeItem",
            name: "Barcode Item",
            module: "Stock",
            appId: "app.mercantis.test",
            isChildTable: false,
            fields: [
                FieldDefinition(
                    key: "title",
                    label: "Title",
                    type: .text,
                    required: true
                ),
                FieldDefinition(
                    key: "barcode",
                    label: "Barcode",
                    type: .barcode,
                    required: false
                )
            ],
            permissions: [
                PermissionRule(
                    role: "System Manager",
                    canRead: true,
                    canWrite: true,
                    canCreate: true,
                    canDelete: true,
                    canSubmit: true,
                    canAmend: true
                )
            ],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: ["title", "barcode"],
            titleField: "title"
        )
    }

    static func makeBarcodeDocument(
        value: String = "",
        fieldValue: FieldValue? = nil
    ) -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString,
            docType: "BarcodeItem",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "title": .string("Scannable item"),
                "barcode": fieldValue ?? .string(value)
            ],
            children: [:]
        )
    }
}
