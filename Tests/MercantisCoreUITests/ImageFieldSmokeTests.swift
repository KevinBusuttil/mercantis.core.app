//
//  ImageFieldSmokeTests.swift
//  MercantisCoreUITests
//

import XCTest
import SwiftUI
import MercantisCore
import MercantisCoreUI

final class ImageFieldSmokeTests: XCTestCase {

    private let singlePixelPNG = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x04, 0x00, 0x00, 0x00, 0xB5, 0x1C, 0x0C,
        0x02, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
        0x54, 0x78, 0xDA, 0x63, 0xFC, 0xFF, 0x1F, 0x00,
        0x03, 0x03, 0x02, 0x00, 0xEF, 0xDF, 0xC7, 0x2F,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82
    ])

    func test_image_field_round_trips_data_blob_through_save() throws {
        let harness = try ImageHarness.make()
        defer { harness.cleanUp() }

        let docType = ImageHarness.makeImageDocType()
        try harness.registry.register(docType)

        let document = ImageHarness.makeImageDocument(fieldValue: .data(singlePixelPNG))
        try harness.engine.save(document)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: docType.id, id: document.id))
        guard case .data(let actual)? = fetched.fields["photo"] else {
            return XCTFail("expected .data, got \(String(describing: fetched.fields["photo"]))")
        }
        XCTAssertEqual(actual, singlePixelPNG)
    }

    func test_image_field_clear_writes_null_value() {
        var document = ImageHarness.makeImageDocument(fieldValue: .data(singlePixelPNG))
        let binding = Binding<Data?>(
            get: {
                if case .data(let data) = document.fields["photo"] { return data }
                return nil
            },
            set: { newValue in
                document.fields["photo"] = newValue.map(FieldValue.data) ?? .null
            }
        )

        binding.wrappedValue = nil

        XCTAssertEqual(document.fields["photo"], .null)
    }

    func test_image_field_validates_data_payload() {
        let docType = ImageHarness.makeImageDocType()
        let pipeline = ValidationPipeline(stages: [TypeCoercionStage()])

        let valid = pipeline.validate(
            document: ImageHarness.makeImageDocument(fieldValue: .data(singlePixelPNG)),
            context: ValidationContext(docType: docType)
        )
        XCTAssertTrue(valid.isEmpty)

        let invalid = pipeline.validate(
            document: ImageHarness.makeImageDocument(fieldValue: .int(42)),
            context: ValidationContext(docType: docType)
        )
        XCTAssertEqual(invalid.count, 1)
        XCTAssertEqual(invalid.first?.stage, "TypeCoercion")
        XCTAssertEqual(invalid.first?.field, "photo")
    }

    func test_image_field_renders_ImageField() throws {
        let harness = try ImageHarness.make()
        defer { harness.cleanUp() }

        let docType = ImageHarness.makeImageDocType()
        try harness.registry.register(docType)

        var document = ImageHarness.makeImageDocument(fieldValue: .data(singlePixelPNG))
        try harness.engine.save(document)

        let binding = Binding<Document>(get: { document }, set: { document = $0 })
        let form = GenericFormView(docType: docType, document: binding)

        XCTAssertNotNil(form)
    }
}

private enum ImageHarness {

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
            .appendingPathComponent("mercantis-image-tests-\(UUID().uuidString)", isDirectory: true)
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

    static func makeImageDocType() -> DocType {
        DocType(
            id: "CatalogItem",
            name: "Catalog Item",
            module: "Catalog",
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
                    key: "photo",
                    label: "Photo",
                    type: .image,
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
            searchFields: ["title"],
            titleField: "title"
        )
    }

    static func makeImageDocument(fieldValue: FieldValue = .null) -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString,
            docType: "CatalogItem",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "title": .string("Widget"),
                "photo": fieldValue
            ],
            children: [:]
        )
    }
}
