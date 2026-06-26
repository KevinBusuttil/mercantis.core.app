//
//  ChildTableValidationTests.swift
//  mercantis coreTests
//
//  Phase 0 / P0.5 + P0.6 — child-table rows now receive the same field-level
//  validation as parent fields (type, required, link, rule, table-scoped
//  uniqueness), are frozen after submit, and are captured in version history.
//

import XCTest
import GRDB
@testable import mercantis_core

final class ChildTableValidationTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "tester")
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    // MARK: - Fixtures

    private func registerDocTypes(
        itemUnique: Bool = false,
        itemsAllowOnSubmit: Bool = false,
        submittable: Bool = false
    ) throws {
        let orderItem = TestSupport.makeDocType(
            id: "OrderItem",
            fields: [
                TestSupport.linkField("item", targeting: "Product"),
                TestSupport.numberField("qty", required: true),
                TestSupport.numberField("rate")
            ],
            indexes: itemUnique ? [IndexDefinition(fieldKey: "item", unique: true)] : []
        )
        let product = TestSupport.makeDocType(
            id: "Product",
            fields: [TestSupport.textField("name")]
        )
        let items = FieldDefinition(
            key: "items",
            label: "Items",
            type: .table,
            required: false,
            childDocType: "OrderItem",
            allowOnSubmit: itemsAllowOnSubmit
        )
        let order = TestSupport.makeDocType(
            id: "Order",
            fields: [items],
            isSubmittable: submittable,
            syncPolicy: submittable ? TestSupport.submittableSyncPolicy() : nil
        )
        try harness.registry.register(orderItem)
        try harness.registry.register(product)
        try harness.registry.register(order)
    }

    private func makeProduct(_ id: String) throws {
        try harness.engine.save(
            TestSupport.makeDocument(id: id, docType: "Product", fields: ["name": .string(id)])
        )
    }

    private func itemRow(_ id: String, item: String?, qty: FieldValue?, rowIndex: Int = 0) -> ChildRow {
        var fields: [String: FieldValue] = [:]
        if let item { fields["item"] = .string(item) }
        if let qty { fields["qty"] = qty }
        return ChildRow(id: id, rowIndex: rowIndex, fields: fields)
    }

    private func order(id: String, rows: [ChildRow]) -> Document {
        TestSupport.makeDocument(id: id, docType: "Order", fields: [:], children: ["items": rows])
    }

    private func assertValidationFails(
        _ document: Document,
        expectField: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try harness.engine.save(document), message, file: file, line: line) { error in
            guard case DocumentEngineError.validationFailed(let errors) = error else {
                return XCTFail("expected validationFailed, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                errors.contains { $0.field == expectField },
                "expected an error on '\(expectField)'; got \(errors.map { $0.field ?? "<nil>" })",
                file: file, line: line
            )
        }
    }

    // MARK: - Validation

    func testValidChildRowSaves() throws {
        try registerDocTypes()
        try makeProduct("p1")
        XCTAssertNoThrow(
            try harness.engine.save(order(id: "o1", rows: [itemRow("r1", item: "p1", qty: .int(2))]))
        )
    }

    func testChildMissingRequiredFieldFails() throws {
        try registerDocTypes()
        try makeProduct("p1")
        assertValidationFails(
            order(id: "o2", rows: [itemRow("r1", item: "p1", qty: nil)]),
            expectField: "items[0].qty",
            "a required child field must be enforced"
        )
    }

    func testChildIncompatibleTypeFails() throws {
        try registerDocTypes()
        try makeProduct("p1")
        assertValidationFails(
            order(id: "o3", rows: [itemRow("r1", item: "p1", qty: .string("abc"))]),
            expectField: "items[0].qty",
            "a non-numeric qty in a child row must be rejected"
        )
    }

    func testChildDanglingLinkFails() throws {
        try registerDocTypes()
        // Note: no Product created, so the link target does not exist.
        assertValidationFails(
            order(id: "o4", rows: [itemRow("r1", item: "ghost", qty: .int(1))]),
            expectField: "items[0].item",
            "a child link to a non-existent document must be rejected"
        )
    }

    func testDuplicateChildRowFails() throws {
        try registerDocTypes(itemUnique: true)
        try makeProduct("p1")
        let rows = [
            itemRow("r1", item: "p1", qty: .int(1), rowIndex: 0),
            itemRow("r2", item: "p1", qty: .int(2), rowIndex: 1)
        ]
        assertValidationFails(
            order(id: "o5", rows: rows),
            expectField: "items[1].item",
            "a child DocType's unique index must be enforced within the table"
        )
    }

    // MARK: - Immutability (P0.6)

    func testChildRowsFrozenAfterSubmit() throws {
        try registerDocTypes(submittable: true)
        try makeProduct("p1")
        try harness.engine.save(order(id: "o6", rows: [itemRow("r1", item: "p1", qty: .int(1))]))
        var doc = try XCTUnwrap(harness.engine.fetch(docType: "Order", id: "o6"))
        try harness.engine.submit(&doc)

        var submitted = try XCTUnwrap(harness.engine.fetch(docType: "Order", id: "o6"))
        var rows = submitted.children["items"] ?? []
        rows[0].fields["qty"] = .int(99)
        submitted.children["items"] = rows

        XCTAssertThrowsError(try harness.engine.save(submitted)) { error in
            guard case DocumentEngineError.fieldImmutableAfterSubmit(let fieldKey, _) = error else {
                return XCTFail("expected fieldImmutableAfterSubmit, got \(error)")
            }
            XCTAssertEqual(fieldKey, "items")
        }
    }

    // MARK: - Versioning (P0.6)

    func testChildRowEditIsVersioned() throws {
        try registerDocTypes()
        try makeProduct("p1")
        try harness.engine.save(order(id: "o7", rows: [itemRow("r1", item: "p1", qty: .int(1))]))

        var doc = try XCTUnwrap(harness.engine.fetch(docType: "Order", id: "o7"))
        var rows = doc.children["items"] ?? []
        rows[0].fields["qty"] = .int(7)
        doc.children["items"] = rows
        try harness.engine.save(doc)

        let matches = try harness.database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM document_versions
                    WHERE documentId = ? AND fieldDiffs LIKE '%items[0].qty%'
                    """,
                arguments: ["o7"]
            ) ?? 0
        }
        XCTAssertGreaterThanOrEqual(matches, 1, "a child-row field change must appear in version history")
    }
}
