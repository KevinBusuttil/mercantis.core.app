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

    // MARK: - W4: link field smoke tests

    /// GenericFormView with a link field and no provider compiles and
    /// instantiates — existing callers that haven't wired a provider yet
    /// are unaffected.
    func testLinkFieldRendersWithNilProvider() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        let docType = TestHarness.makeDocTypeWithLinkField()
        try harness.registry.register(docType)

        var document = TestHarness.makeDocumentWithLinkField()
        try harness.engine.save(document)

        let binding = Binding<Document>(get: { document }, set: { document = $0 })

        let form = GenericFormView(
            docType: docType,
            document: binding,
            linkSearchProvider: nil
        )
        XCTAssertNotNil(form)
    }

    /// GenericFormView with a link field and a wired provider compiles and
    /// instantiates. The provider closure is the same shape Hub will use:
    /// `engine.list(docType:)` wrapped in a try?.
    func testLinkFieldRendersWithWiredProvider() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        // Register the target DocType (CustomerGroup) so the provider can list it.
        let groupDocType = TestHarness.makeCustomerGroupDocType()
        try harness.registry.register(groupDocType)
        let groupDoc = TestHarness.makeCustomerGroupDocument(id: "CG-001")
        try harness.engine.save(groupDoc)

        let docType = TestHarness.makeDocTypeWithLinkField()
        try harness.registry.register(docType)

        var document = TestHarness.makeDocumentWithLinkField(linkedId: "CG-001")
        try harness.engine.save(document)

        let binding = Binding<Document>(get: { document }, set: { document = $0 })

        let form = GenericFormView(
            docType: docType,
            document: binding,
            linkSearchProvider: { targetDocType, _ in
                (try? harness.engine.list(docType: targetDocType)) ?? []
            }
        )
        XCTAssertNotNil(form)
    }

    /// The save-time link validation rejects a reference to a non-existent document.
    func testLinkValidationRejectsUnknownTarget() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        let docType = TestHarness.makeDocTypeWithLinkField()
        try harness.registry.register(docType)

        let document = TestHarness.makeDocumentWithLinkField(linkedId: "DOES-NOT-EXIST")
        XCTAssertThrowsError(try harness.engine.save(document)) { error in
            guard case DocumentEngine.DocumentEngineError.validationFailed(let errors) = error else {
                XCTFail("Expected validationFailed, got \(error)"); return
            }
            XCTAssertTrue(errors.contains { $0.stage == "LinkValidation" })
        }
    }

    /// The save-time link validation passes when the referenced document exists.
    func testLinkValidationPassesWithKnownTarget() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanUp() }

        let groupDocType = TestHarness.makeCustomerGroupDocType()
        try harness.registry.register(groupDocType)
        let groupDoc = TestHarness.makeCustomerGroupDocument(id: "CG-002")
        try harness.engine.save(groupDoc)

        let docType = TestHarness.makeDocTypeWithLinkField()
        try harness.registry.register(docType)

        let document = TestHarness.makeDocumentWithLinkField(linkedId: "CG-002")
        XCTAssertNoThrow(try harness.engine.save(document))
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

    // MARK: - W4 fixtures

    /// A DocType that contains a `customer_group` link field targeting "CustomerGroup".
    static func makeDocTypeWithLinkField() -> DocType {
        DocType(
            id: "Contact",
            name: "Contact",
            module: "CRM",
            appId: "app.mercantis.test",
            isChildTable: false,
            fields: [
                FieldDefinition(
                    key: "full_name",
                    label: "Full Name",
                    type: .text,
                    required: true
                ),
                FieldDefinition(
                    key: "customer_group",
                    label: "Customer Group",
                    type: .link,
                    required: false,
                    linkedDocType: "CustomerGroup"
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
            searchFields: ["full_name"],
            titleField: "full_name"
        )
    }

    static func makeDocumentWithLinkField(linkedId: String = "") -> Document {
        let now = Date()
        var fields: [String: FieldValue] = ["full_name": .string("Jane Smith")]
        if !linkedId.isEmpty {
            fields["customer_group"] = .string(linkedId)
        }
        return Document(
            id: UUID().uuidString,
            docType: "Contact",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
    }

    static func makeCustomerGroupDocType() -> DocType {
        DocType(
            id: "CustomerGroup",
            name: "Customer Group",
            module: "Setup",
            appId: "app.mercantis.test",
            isChildTable: false,
            fields: [
                FieldDefinition(
                    key: "group_name",
                    label: "Group Name",
                    type: .text,
                    required: true
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
            searchFields: ["group_name"],
            titleField: "group_name"
        )
    }

    static func makeCustomerGroupDocument(id: String) -> Document {
        let now = Date()
        return Document(
            id: id,
            docType: "CustomerGroup",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: ["group_name": .string("Commercial")],
            children: [:]
        )
    }
}
