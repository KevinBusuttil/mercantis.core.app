//
//  MetaComposerTests.swift
//  mercantis coreTests
//
//  Covers ADR-021: ResolvedMeta composition from base DocType + custom fields
//  + property setters, and cache invalidation via the generation counter.
//

import XCTest
@testable import mercantis_core

final class MetaComposerTests: XCTestCase {

    private var url: URL!
    private var database: MercantisDatabase!
    private var registry: MetadataRegistry!
    private var composer: MetaComposer!

    override func setUpWithError() throws {
        url = TestSupport.tempDatabaseURL()
        database = try TestSupport.makeDatabase(at: url)
        registry = MetadataRegistry(database: database)
        composer = MetaComposer(registry: registry)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: url)
    }

    // MARK: - Base composition

    func testResolveUnknownDocTypeReturnsNil() {
        XCTAssertNil(composer.resolve(docType: "DoesNotExist"))
    }

    func testResolvePreservesBaseFieldOrder() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("a"),
            TestSupport.textField("b"),
            TestSupport.textField("c")
        ])
        try registry.register(docType)

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.map(\.key), ["a", "b", "c"])
        XCTAssertTrue(resolved.fields.allSatisfy { !$0.isCustom })
    }

    // MARK: - Custom fields

    func testCustomFieldAppendedWhenInsertAfterIsNil() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("a"),
            TestSupport.textField("b")
        ])
        try registry.register(docType)

        let custom = CustomField(
            docType: "Note",
            fieldDefinition: TestSupport.textField("extra"),
            insertAfter: nil
        )
        composer.setCustomFields([custom], for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.map(\.key), ["a", "b", "extra"])
        XCTAssertTrue(resolved.fields.last!.isCustom)
    }

    func testCustomFieldInsertedAfterNamedField() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("a"),
            TestSupport.textField("b"),
            TestSupport.textField("c")
        ])
        try registry.register(docType)

        let custom = CustomField(
            docType: "Note",
            fieldDefinition: TestSupport.textField("after_a"),
            insertAfter: "a"
        )
        composer.setCustomFields([custom], for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.map(\.key), ["a", "after_a", "b", "c"])
    }

    func testCustomFieldWithUnknownInsertAfterFallsBackToAppend() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("a"),
            TestSupport.textField("b")
        ])
        try registry.register(docType)

        let custom = CustomField(
            docType: "Note",
            fieldDefinition: TestSupport.textField("extra"),
            insertAfter: "does-not-exist"
        )
        composer.setCustomFields([custom], for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.map(\.key), ["a", "b", "extra"])
    }

    // MARK: - Property setters

    func testPropertySetterOverridesLabel() throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", label: "Title"),
        ])
        try registry.register(docType)

        composer.setPropertySetters(
            [PropertySetter(docType: "Note", fieldKey: "title", property: "label", value: "Subject")],
            for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.first?.label, "Subject")
    }

    func testPropertySetterHiddenTrueSetsVisibilityFalse() throws {
        let docType = TestSupport.makeDocType(fields: [TestSupport.textField("title")])
        try registry.register(docType)

        composer.setPropertySetters(
            [PropertySetter(docType: "Note", fieldKey: "title", property: "hidden", value: "true")],
            for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.first?.visibilityExpression, "false")
    }

    func testPropertySetterReadOnlyTrueSetsReadOnlyExpression() throws {
        let docType = TestSupport.makeDocType(fields: [TestSupport.textField("title")])
        try registry.register(docType)

        composer.setPropertySetters(
            [PropertySetter(docType: "Note", fieldKey: "title", property: "read_only", value: "true")],
            for: "Note")

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.first?.readOnlyExpression, "true")
    }

    // MARK: - Cache

    func testResolveReturnsSameInstanceUntilInvalidation() throws {
        let docType = TestSupport.makeDocType(fields: [TestSupport.textField("title")])
        try registry.register(docType)

        let firstFields = try XCTUnwrap(composer.resolve(docType: "Note")).fields.map(\.key)
        XCTAssertEqual(firstFields, ["title"])

        composer.setCustomFields(
            [CustomField(docType: "Note", fieldDefinition: TestSupport.textField("extra"), insertAfter: nil)],
            for: "Note")

        // setCustomFields invalidates the per-docType cache entry, so resolve
        // now returns a recomposed ResolvedMeta.
        let secondFields = try XCTUnwrap(composer.resolve(docType: "Note")).fields.map(\.key)
        XCTAssertEqual(secondFields, ["title", "extra"])
    }

    func testInvalidateAllBumpsGeneration() throws {
        let docType = TestSupport.makeDocType(fields: [TestSupport.textField("title")])
        try registry.register(docType)

        _ = composer.resolve(docType: "Note") // prime cache

        // Invalidate globally.
        composer.invalidateAll()

        // Mutate the base registry entry by re-registering with a new field.
        let updated = TestSupport.makeDocType(fields: [
            TestSupport.textField("title"),
            TestSupport.textField("body")
        ])
        try registry.register(updated)

        let resolved = try XCTUnwrap(composer.resolve(docType: "Note"))
        XCTAssertEqual(resolved.fields.map(\.key), ["title", "body"])
    }

    // MARK: - Inline draft resolution

    func testResolveDraftDocTypeWithoutRegistryPersistence() {
        let draft = TestSupport.makeDocType(
            id: "DraftType",
            fields: [TestSupport.textField("x")]
        )
        let custom = CustomField(
            docType: "DraftType",
            fieldDefinition: TestSupport.textField("y"),
            insertAfter: "x"
        )
        let resolved = composer.resolve(docTypeDefinition: draft, customFields: [custom])
        XCTAssertEqual(resolved.fields.map(\.key), ["x", "y"])
    }
}
