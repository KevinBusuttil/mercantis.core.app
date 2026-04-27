//
//  GenericFormViewSmokeTests.swift
//  MercantisCoreUITests
//
//  Smoke coverage for the SwiftPM `MercantisCoreUI` library product
//  introduced by P2.7 (issue #81). These tests exist to catch
//  bit-rot — accidentally breaking the public surface of the
//  metadata-driven form/list renderers, or breaking the package
//  graph that lets Hub `import MercantisCoreUI`.
//

import XCTest
import SwiftUI
import MercantisCore
import MercantisCoreUI

final class GenericFormViewSmokeTests: XCTestCase {

    func testGenericFormViewInstantiatesAgainstInMemoryDocumentEngine() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        let docType = TestHarness.makeCustomerDocType()
        try harness.registry.register(docType)

        var document = TestHarness.makeCustomerDocument()
        try harness.engine.save(document)

        let binding = Binding<Document>(
            get: { document },
            set: { document = $0 }
        )

        let form = GenericFormView(
            docType: docType,
            document: binding,
            userRoles: ["System Manager"],
            expressionEvaluator: harness.engine.listExpressionEvaluator
        )

        // Smoke: instantiating the view forces the SwiftPM dependency
        // graph to compile and the public init to resolve against the
        // engine's public types. We don't render — that would need a
        // host environment we can't assume in a headless test target.
        XCTAssertNotNil(form)
    }

    func testGenericListViewInstantiatesAgainstInMemoryDocumentEngine() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        let docType = TestHarness.makeCustomerDocType()
        try harness.registry.register(docType)

        let document = TestHarness.makeCustomerDocument()
        try harness.engine.save(document)
        let documents = try harness.engine.list(docType: docType.id)

        let list = GenericListView(
            docType: docType,
            documents: documents,
            onSelect: { _ in },
            onCreate: { }
        )

        XCTAssertNotNil(list)
        XCTAssertEqual(documents.count, 1)
    }
}

// MARK: - Local harness

/// Mirror of the in-memory engine fixture in `mercantis coreTests/`. Kept
/// local so this test target doesn't take a `@testable` dependency on the
/// Xcode app's `mercantis_core` module — it builds against the SwiftPM
/// `MercantisCore` library directly.
private enum TestHarness {

    struct Bundle {
        let database: MercantisDatabase
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
            .appendingPathComponent("mercantis-coreui-tests-\(UUID().uuidString)", isDirectory: true)
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
        return Bundle(database: database, registry: registry, engine: engine, url: url)
    }

    static func makeCustomerDocType() -> DocType {
        DocType(
            id: "Customer",
            name: "Customer",
            module: "CRM",
            appId: "app.mercantis.test",
            isChildTable: false,
            fields: [
                FieldDefinition(
                    key: "customer_name",
                    label: "Customer Name",
                    type: .text,
                    required: true
                ),
                FieldDefinition(
                    key: "email",
                    label: "Email",
                    type: .email,
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
            syncPolicy: SyncPolicy(
                conflictResolution: .lastWriteWins,
                immutableAfterSubmit: false
            ),
            indexes: [],
            searchFields: ["customer_name"],
            titleField: "customer_name"
        )
    }

    static func makeCustomerDocument() -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString,
            docType: "Customer",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "customer_name": .string("Acme Co"),
                "email": .string("info@acme.example")
            ],
            children: [:]
        )
    }
}
