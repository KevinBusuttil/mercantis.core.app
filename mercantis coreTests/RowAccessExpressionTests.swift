//
//  RowAccessExpressionTests.swift
//  mercantis coreTests
//
//  Phase A §3.4 — `DocumentEngine.list(...)` auto-applies the registered
//  DocType's `rowAccessExpression` via `PermissionEngine.canAccessRow`.
//

import XCTest
@testable import mercantis_core

final class RowAccessExpressionTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "alice")
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func registerOwnerDocType(rowExpression: String? = "owner == user.id") throws {
        let docType = DocType(
            id: "Note",
            name: "Note",
            module: "Core",
            appId: "app.mercantis.test",
            isChildTable: false,
            isSubmittable: false,
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.textField("owner"),
            ],
            permissions: [TestSupport.permissionRule()],
            syncPolicy: TestSupport.defaultSyncPolicy(),
            indexes: [],
            searchFields: ["title"],
            titleField: "title",
            rowAccessExpression: rowExpression
        )
        try harness.registry.register(docType)
    }

    private func saveOwnedBy(_ id: String, owner: String) throws {
        try harness.engine.save(TestSupport.makeDocument(
            id: id,
            fields: ["title": .string(id), "owner": .string(owner)]
        ))
    }

    func testListFiltersRowsToCallerOwnedDocumentsByDefault() throws {
        try registerOwnerDocType()
        try saveOwnedBy("alice-1", owner: "alice")
        try saveOwnedBy("bob-1",   owner: "bob")
        try saveOwnedBy("alice-2", owner: "alice")

        // No explicit listUserId — engine's `userId` ("alice") is used.
        let docs = try harness.engine.list(docType: "Note")
        XCTAssertEqual(Set(docs.map(\.id)), ["alice-1", "alice-2"])
    }

    func testExplicitListUserIdOverridesEngineDefault() throws {
        try registerOwnerDocType()
        try saveOwnedBy("alice-1", owner: "alice")
        try saveOwnedBy("bob-1",   owner: "bob")

        let docs = try harness.engine.list(docType: "Note", listUserId: "bob")
        XCTAssertEqual(docs.map(\.id), ["bob-1"])
    }

    func testApplyRowAccessFalseDisablesFiltering() throws {
        try registerOwnerDocType()
        try saveOwnedBy("alice-1", owner: "alice")
        try saveOwnedBy("bob-1",   owner: "bob")

        let docs = try harness.engine.list(docType: "Note", applyRowAccess: false)
        XCTAssertEqual(Set(docs.map(\.id)), ["alice-1", "bob-1"])
    }

    func testEmptyRowAccessExpressionGrantsAll() throws {
        try registerOwnerDocType(rowExpression: "")
        try saveOwnedBy("a", owner: "alice")
        try saveOwnedBy("b", owner: "bob")

        let docs = try harness.engine.list(docType: "Note")
        XCTAssertEqual(Set(docs.map(\.id)), ["a", "b"])
    }

    func testWarehouseScopedExpressionUsesUserAttributes() throws {
        let docType = DocType(
            id: "Note",
            name: "Note",
            module: "Core",
            appId: "app.mercantis.test",
            isChildTable: false,
            isSubmittable: false,
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.textField("warehouse"),
            ],
            permissions: [TestSupport.permissionRule()],
            syncPolicy: TestSupport.defaultSyncPolicy(),
            indexes: [],
            searchFields: ["title"],
            titleField: "title",
            rowAccessExpression: "warehouse == user.warehouse"
        )
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(
            id: "a",
            fields: ["title": .string("A"), "warehouse": .string("WH-01")]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "b",
            fields: ["title": .string("B"), "warehouse": .string("WH-02")]
        ))

        let docs = try harness.engine.list(
            docType: "Note",
            userAttributes: ["warehouse": .string("WH-01")]
        )
        XCTAssertEqual(docs.map(\.id), ["a"])
    }
}
