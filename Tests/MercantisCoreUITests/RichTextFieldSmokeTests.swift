//
//  RichTextFieldSmokeTests.swift
//  MercantisCoreUITests
//

import XCTest
import SwiftUI
import MercantisCore
import MercantisCoreUI

final class RichTextFieldSmokeTests: XCTestCase {

    func test_richText_field_renders_RichTextField() throws {
        let harness = try RichTextHarness.make()
        defer { harness.cleanUp() }

        let docType = RichTextHarness.makeRichTextDocType()
        try harness.registry.register(docType)

        var document = RichTextHarness.makeRichTextDocument()
        try harness.engine.save(document)

        let binding = Binding<Document>(get: { document }, set: { document = $0 })
        let form = GenericFormView(docType: docType, document: binding)

        XCTAssertNotNil(form)
    }

    func test_richText_field_persists_markdown_string_through_save() throws {
        let harness = try RichTextHarness.make()
        defer { harness.cleanUp() }

        let docType = RichTextHarness.makeRichTextDocType()
        try harness.registry.register(docType)

        let markdown = "# Hello\n**world**"
        let document = RichTextHarness.makeRichTextDocument(value: markdown)
        try harness.engine.save(document)

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: docType.id, id: document.id))
        XCTAssertEqual(fetched.fields["notes"], .string(markdown))
    }

    func test_richText_field_validates_as_string() {
        let docType = RichTextHarness.makeRichTextDocType()
        let document = RichTextHarness.makeRichTextDocument(fieldValue: .int(42))
        let pipeline = ValidationPipeline(stages: [TypeCoercionStage()])

        let errors = pipeline.validate(
            document: document,
            context: ValidationContext(docType: docType)
        )

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.stage, "TypeCoercion")
        XCTAssertEqual(errors.first?.field, "notes")
    }
}

private enum RichTextHarness {

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
            .appendingPathComponent("mercantis-richtext-tests-\(UUID().uuidString)", isDirectory: true)
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

    static func makeRichTextDocType() -> DocType {
        DocType(
            id: "RichTextNote",
            name: "Rich Text Note",
            module: "CRM",
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
                    key: "notes",
                    label: "Notes",
                    type: .richText,
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
            searchFields: ["title", "notes"],
            titleField: "title"
        )
    }

    static func makeRichTextDocument(
        value: String = "",
        fieldValue: FieldValue? = nil
    ) -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString,
            docType: "RichTextNote",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "title": .string("Rich text"),
                "notes": fieldValue ?? .string(value)
            ],
            children: [:]
        )
    }
}
