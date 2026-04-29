//
//  FieldValueRoundTripTests.swift
//  mercantis coreTests
//
//  W6 — End-to-end persistence tests for typed FieldValue cases.
//

import XCTest
@testable import mercantis_core

final class FieldValueRoundTripTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func installDocType(
        id: String = "Customer",
        fieldKey: String = "value",
        label: String = "Value",
        type: FieldType
    ) throws -> DocType {
        let docType = TestSupport.makeDocType(
            id: id,
            fields: [FieldDefinition(key: fieldKey, label: label, type: type, required: false)]
        )
        try harness.registry.register(docType)
        return docType
    }

    private func saveAndFetch(
        docType: DocType,
        documentId: String,
        fieldKey: String = "value",
        value: FieldValue
    ) throws -> Document {
        let document = TestSupport.makeDocument(
            id: documentId,
            docType: docType.id,
            fields: [fieldKey: value]
        )
        try harness.engine.save(document)
        return try XCTUnwrap(harness.engine.fetch(docType: docType.id, id: documentId))
    }

    private func dateOnly(_ raw: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return try XCTUnwrap(formatter.date(from: raw))
    }

    func test_date_field_value_round_trips_through_save_and_fetch() throws {
        let docType = try installDocType(fieldKey: "birthdate", label: "Birthdate", type: .date)
        let expected = Date(timeIntervalSince1970: 1_714_393_600)

        let fetched = try saveAndFetch(
            docType: docType,
            documentId: "customer-date",
            fieldKey: "birthdate",
            value: .date(expected)
        )

        guard case .date(let actual)? = fetched.fields["birthdate"] else {
            return XCTFail("expected .date, got \(String(describing: fetched.fields["birthdate"]))")
        }
        XCTAssertEqual(actual, expected)
    }

    func test_dateTime_field_value_round_trips_through_save_and_fetch() throws {
        let docType = try installDocType(fieldKey: "scheduledAt", label: "Scheduled At", type: .datetime)
        let expected = Date(timeIntervalSince1970: 1_714_393_600)

        let fetched = try saveAndFetch(
            docType: docType,
            documentId: "customer-datetime",
            fieldKey: "scheduledAt",
            value: .dateTime(expected)
        )

        guard case .dateTime(let actual)? = fetched.fields["scheduledAt"] else {
            return XCTFail("expected .dateTime, got \(String(describing: fetched.fields["scheduledAt"]))")
        }
        XCTAssertEqual(actual, expected)
    }

    func test_data_field_value_round_trips_through_save_and_fetch() throws {
        let docType = try installDocType(fieldKey: "avatar", label: "Avatar", type: .attachment)
        let expected = Data([0x00, 0x01, 0x7F, 0xFF])

        let fetched = try saveAndFetch(
            docType: docType,
            documentId: "customer-data",
            fieldKey: "avatar",
            value: .data(expected)
        )

        guard case .data(let actual)? = fetched.fields["avatar"] else {
            return XCTFail("expected .data, got \(String(describing: fetched.fields["avatar"]))")
        }
        XCTAssertEqual(actual, expected)
    }

    func test_array_field_value_round_trips_through_save_and_fetch() throws {
        let docType = try installDocType(fieldKey: "tags", label: "Tags", type: .multiselect)
        let expected: FieldValue = .array([.string("vip"), .int(7), .date(Date(timeIntervalSince1970: 1234))])

        let fetched = try saveAndFetch(
            docType: docType,
            documentId: "customer-array",
            fieldKey: "tags",
            value: expected
        )

        guard case .array(let actual)? = fetched.fields["tags"] else {
            return XCTFail("expected .array, got \(String(describing: fetched.fields["tags"]))")
        }
        XCTAssertEqual(actual, [.string("vip"), .int(7), .date(Date(timeIntervalSince1970: 1234))])
    }

    func test_string_iso8601_is_coerced_to_dot_date_when_field_type_is_date() throws {
        let docType = try installDocType(fieldKey: "birthdate", label: "Birthdate", type: .date)
        let expected = try dateOnly("2026-04-29")

        let saved = try harness.engine.save(
            TestSupport.makeDocument(
                id: "customer-coerced-date",
                docType: docType.id,
                fields: ["birthdate": .string("2026-04-29")]
            )
        )

        guard case .date(let actual)? = saved.fields["birthdate"] else {
            return XCTFail("expected save() to coerce to .date, got \(String(describing: saved.fields["birthdate"]))")
        }
        XCTAssertEqual(actual, expected)
    }

    func test_invalid_date_string_yields_validation_error() throws {
        let docType = try installDocType(fieldKey: "birthdate", label: "Birthdate", type: .date)

        XCTAssertThrowsError(
            try harness.engine.save(
                TestSupport.makeDocument(
                    id: "customer-invalid-date",
                    docType: docType.id,
                    fields: ["birthdate": .string("not-a-date")]
                )
            )
        ) { error in
            guard case DocumentEngine.DocumentEngineError.validationFailed(let errors) = error else {
                return XCTFail("expected validationFailed, got \(error)")
            }
            XCTAssertEqual(errors.count, 1)
            XCTAssertEqual(errors.first?.stage, "TypeCoercion")
            XCTAssertEqual(errors.first?.field, "birthdate")
        }
    }
}
