//
//  CustomFieldStoreTests.swift
//  mercantis coreTests
//
//  Covers persistence of end-user CustomField rows: insert / list /
//  update / remove + uniqueness of (docType, fieldKey).
//

import XCTest
@testable import mercantis_core

final class CustomFieldStoreTests: XCTestCase {

    private var url: URL!
    private var database: MercantisDatabase!
    private var store: CustomFieldStore!

    override func setUpWithError() throws {
        url = TestSupport.tempDatabaseURL()
        database = try TestSupport.makeDatabase(at: url)
        store = CustomFieldStore(database: database)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: url)
    }

    // MARK: - List

    func testListReturnsEmptyForUnknownDocType() throws {
        XCTAssertTrue(try store.list(forDocType: "Customer").isEmpty)
    }

    func testListReturnsRowsInCreationOrder() throws {
        try store.add(makeField(docType: "Customer", key: "vat_number"))
        try store.add(makeField(docType: "Customer", key: "loyalty_tier"))

        let fields = try store.list(forDocType: "Customer")
        XCTAssertEqual(fields.map(\.fieldDefinition.key), ["vat_number", "loyalty_tier"])
    }

    func testListScopesByDocType() throws {
        try store.add(makeField(docType: "Customer", key: "vat_number"))
        try store.add(makeField(docType: "Supplier", key: "vat_number"))

        XCTAssertEqual(try store.list(forDocType: "Customer").count, 1)
        XCTAssertEqual(try store.list(forDocType: "Supplier").count, 1)
    }

    // MARK: - loadAll

    func testLoadAllGroupsByDocType() throws {
        try store.add(makeField(docType: "Customer", key: "vat_number"))
        try store.add(makeField(docType: "Customer", key: "loyalty_tier"))
        try store.add(makeField(docType: "Supplier", key: "vat_number"))

        let grouped = try store.loadAll()
        XCTAssertEqual(Set(grouped.keys), ["Customer", "Supplier"])
        XCTAssertEqual(grouped["Customer"]?.count, 2)
        XCTAssertEqual(grouped["Supplier"]?.count, 1)
    }

    // MARK: - Add

    func testDuplicateKeyOnSameDocTypeIsRejected() throws {
        try store.add(makeField(docType: "Customer", key: "vat_number"))
        XCTAssertThrowsError(try store.add(makeField(docType: "Customer", key: "vat_number")))
    }

    func testInsertAfterIsPersistedAndNullifiedWhenEmpty() throws {
        try store.add(makeField(docType: "Customer", key: "a", insertAfter: "phone"))
        try store.add(makeField(docType: "Customer", key: "b", insertAfter: ""))

        let fields = try store.list(forDocType: "Customer")
        XCTAssertEqual(fields[0].insertAfter, "phone")
        XCTAssertNil(fields[1].insertAfter, "Empty insert_after should round-trip as nil.")
    }

    // MARK: - Update

    func testUpdateReplacesDefinitionAndInsertAfter() throws {
        var field = makeField(docType: "Customer", key: "vat_number", label: "VAT", insertAfter: nil)
        try store.add(field)

        field = CustomField(
            id: field.id,
            docType: field.docType,
            fieldDefinition: FieldDefinition(
                key: "vat_number",
                label: "VAT Number",
                type: .text,
                required: true
            ),
            insertAfter: "email"
        )
        try store.update(field)

        let reloaded = try XCTUnwrap(try store.list(forDocType: "Customer").first)
        XCTAssertEqual(reloaded.fieldDefinition.label, "VAT Number")
        XCTAssertTrue(reloaded.fieldDefinition.required)
        XCTAssertEqual(reloaded.insertAfter, "email")
    }

    // MARK: - Remove

    func testRemoveDropsTheRow() throws {
        let field = makeField(docType: "Customer", key: "vat_number")
        try store.add(field)
        try store.remove(id: field.id)
        XCTAssertTrue(try store.list(forDocType: "Customer").isEmpty)
    }

    // MARK: - Helpers

    private func makeField(
        docType: String,
        key: String,
        label: String? = nil,
        insertAfter: String? = nil
    ) -> CustomField {
        CustomField(
            docType: docType,
            fieldDefinition: FieldDefinition(
                key: key,
                label: label ?? key,
                type: .text,
                required: false
            ),
            insertAfter: insertAfter
        )
    }
}
