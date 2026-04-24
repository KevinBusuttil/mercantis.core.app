//
//  FieldValueTests.swift
//  mercantis coreTests
//
//  P1.6 — Covers the expanded FieldValue enum: .date, .dateTime, .data,
//  .array. Verifies tagged-envelope encoding, backward-compatible decoding of
//  legacy untagged payloads, recursive equality, and the downstream behaviour
//  that ValidationPipeline / ExpressionEvaluator / Reporting / Naming /
//  Automation expose for the new cases.
//

import XCTest
@testable import mercantis_core

final class FieldValueTests: XCTestCase {

    // MARK: - Codable round-trip

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func roundTrip(_ value: FieldValue, file: StaticString = #file, line: UInt = #line) throws {
        // Round-trip inside `[String: FieldValue]` to match the production
        // shape — FieldValue always travels inside Document.fields or a sync
        // queue payload, never as a top-level JSON fragment.
        let data = try encoder().encode(["k": value])
        let decoded = try decoder().decode([String: FieldValue].self, from: data)
        XCTAssertEqual(decoded["k"], value, file: file, line: line)
    }

    func testLegacyPrimitiveCasesRoundTrip() throws {
        try roundTrip(.string("hello"))
        try roundTrip(.string(""))
        try roundTrip(.int(42))
        try roundTrip(.int(-7))
        try roundTrip(.double(3.14))
        try roundTrip(.bool(true))
        try roundTrip(.bool(false))
        try roundTrip(.null)
    }

    func testLegacyPrimitivesEncodeAsUntaggedJSON() throws {
        // Backward-compat: existing DB rows and sync-queue payloads predate the
        // tagged envelope. New encodes of the legacy cases must match the old
        // wire shape so a mixed-version reader doesn't break. Production always
        // encodes inside `[String: FieldValue]`, so assert on that shape.
        let enc = encoder()
        enc.outputFormatting = [.sortedKeys]

        XCTAssertEqual(try String(decoding: enc.encode(["k": FieldValue.string("x")]), as: UTF8.self), "{\"k\":\"x\"}")
        XCTAssertEqual(try String(decoding: enc.encode(["k": FieldValue.int(7)]), as: UTF8.self), "{\"k\":7}")
        XCTAssertEqual(try String(decoding: enc.encode(["k": FieldValue.bool(true)]), as: UTF8.self), "{\"k\":true}")
        XCTAssertEqual(try String(decoding: enc.encode(["k": FieldValue.null]), as: UTF8.self), "{\"k\":null}")
    }

    func testDateCaseRoundTrips() throws {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        try roundTrip(.date(d))
        try roundTrip(.dateTime(d))
    }

    func testDataCaseRoundTrips() throws {
        try roundTrip(.data(Data([0x00, 0x01, 0xFF])))
        try roundTrip(.data(Data()))
    }

    func testArrayCaseRoundTripsRecursively() throws {
        try roundTrip(.array([]))
        try roundTrip(.array([.string("a"), .int(1), .null]))
        // Nested arrays — recursion.
        try roundTrip(.array([.array([.bool(true), .double(2.5)]), .string("ok")]))
    }

    func testTaggedEnvelopeShapeIsStable() throws {
        // The wire format is part of the sync contract; keep it explicit so
        // a refactor that changes tag names trips this test. Encoded inside a
        // dict to mirror the production `[String: FieldValue]` call site.
        let enc = encoder()
        enc.outputFormatting = [.sortedKeys]
        let json = try String(decoding: enc.encode(["k": FieldValue.data(Data([0x41]))]), as: UTF8.self)
        XCTAssertTrue(json.contains("\"$type\":\"data\""), "got: \(json)")
        XCTAssertTrue(json.contains("\"$value\":\"QQ==\""), "got: \(json)")
    }

    func testDecoderRejectsUnknownTypeTag() {
        let bad = Data(#"{"k":{"$type":"unknown","$value":1}}"#.utf8)
        XCTAssertThrowsError(try decoder().decode([String: FieldValue].self, from: bad))
    }

    func testDecoderFallsBackToUntaggedPrimitives() throws {
        // Exact shape a v1 payload would have written (inside a [String: FieldValue]
        // dict, which is the production storage and sync-queue format).
        func decodeOne(_ raw: String) throws -> FieldValue {
            let data = Data("{\"k\":\(raw)}".utf8)
            let dict = try decoder().decode([String: FieldValue].self, from: data)
            return dict["k"] ?? .null
        }
        XCTAssertEqual(try decodeOne("\"abc\""), .string("abc"))
        XCTAssertEqual(try decodeOne("42"), .int(42))
        XCTAssertEqual(try decodeOne("3.5"), .double(3.5))
        XCTAssertEqual(try decodeOne("true"), .bool(true))
        XCTAssertEqual(try decodeOne("null"), .null)
    }

    // MARK: - Equality

    func testEqualityForNewCases() {
        let d = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(FieldValue.date(d), .date(d))
        XCTAssertNotEqual(FieldValue.date(d), .dateTime(d))           // distinct cases
        XCTAssertEqual(FieldValue.dateTime(d), .dateTime(d))
        XCTAssertEqual(FieldValue.data(Data([1, 2])), .data(Data([1, 2])))
        XCTAssertNotEqual(FieldValue.data(Data([1])), .data(Data([2])))
        XCTAssertEqual(FieldValue.array([.int(1), .string("a")]),
                       .array([.int(1), .string("a")]))
        XCTAssertNotEqual(FieldValue.array([.int(1)]), .array([.int(2)]))
    }

    // MARK: - Validation: type coercion

    func testTypeCoercionAcceptsTypedDateForDateField() {
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "due", label: "Due", type: .date, required: false)
        ])
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["due": .date(Date())]
        )
        let errors = TypeCoercionStage().validate(
            document: doc,
            context: ValidationContext(docType: docType)
        )
        XCTAssertTrue(errors.isEmpty)
    }

    func testTypeCoercionAcceptsTypedDateTimeForDatetimeField() {
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "at", label: "At", type: .datetime, required: false)
        ])
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["at": .dateTime(Date())]
        )
        let errors = TypeCoercionStage().validate(
            document: doc,
            context: ValidationContext(docType: docType)
        )
        XCTAssertTrue(errors.isEmpty)
    }

    func testTypeCoercionStillAcceptsLegacyStringDate() {
        // Backward-compat for rows written before P1.6.
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "due", label: "Due", type: .date, required: false)
        ])
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["due": .string("2026-04-24T00:00:00Z")]
        )
        let errors = TypeCoercionStage().validate(
            document: doc,
            context: ValidationContext(docType: docType)
        )
        XCTAssertTrue(errors.isEmpty)
    }

    func testTypeCoercionRejectsBoolForDateField() {
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "due", label: "Due", type: .date, required: false)
        ])
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["due": .bool(true)]
        )
        let errors = TypeCoercionStage().validate(
            document: doc,
            context: ValidationContext(docType: docType)
        )
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.field, "due")
    }

    func testTypeCoercionAcceptsInlineDataForAttachment() {
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "avatar", label: "Avatar", type: .attachment, required: false)
        ])
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["avatar": .data(Data([0xFF]))]
        )
        let errors = TypeCoercionStage().validate(
            document: doc,
            context: ValidationContext(docType: docType)
        )
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Validation: required

    func testRequiredEmptinessForNewCases() {
        // Required-empty rules:
        // - typed dates are never empty (they always carry a Date).
        // - .data is empty only when the underlying Data has 0 bytes.
        // - .array is empty only when there are 0 elements.
        let docType = TestSupport.makeDocType(fields: [
            FieldDefinition(key: "when", label: "When", type: .date, required: true),
            FieldDefinition(key: "blob", label: "Blob", type: .attachment, required: true),
            FieldDefinition(key: "tags", label: "Tags", type: .multiselect, required: true)
        ])

        let populated = TestSupport.makeDocument(
            docType: docType.id,
            fields: [
                "when": .date(Date()),
                "blob": .data(Data([0x01])),
                "tags": .array([.string("a")])
            ]
        )
        XCTAssertTrue(
            RequiredFieldStage().validate(
                document: populated,
                context: ValidationContext(docType: docType)
            ).isEmpty
        )

        let empty = TestSupport.makeDocument(
            docType: docType.id,
            fields: [
                "when": .date(Date()),      // still populated
                "blob": .data(Data()),      // 0 bytes → empty
                "tags": .array([])          // 0 items → empty
            ]
        )
        let errors = RequiredFieldStage().validate(
            document: empty,
            context: ValidationContext(docType: docType)
        )
        XCTAssertEqual(Set(errors.map { $0.field }), ["blob", "tags"])
    }

    // MARK: - ExpressionEvaluator

    func testExpressionEvaluatorComparesDatesAsEpochSeconds() throws {
        let early = Date(timeIntervalSince1970: 1_000_000)
        let late  = Date(timeIntervalSince1970: 2_000_000)
        let ctx: [String: FieldValue] = ["start": .date(early), "end": .dateTime(late)]
        let eval = ExpressionEvaluator()
        XCTAssertTrue(try eval.evaluateBool(expression: "start < end", context: ctx))
        XCTAssertFalse(try eval.evaluateBool(expression: "start > end", context: ctx))
    }

    func testExpressionEvaluatorTreatsOpaqueValuesAsNullForComparison() throws {
        let ctx: [String: FieldValue] = ["blob": .data(Data([0x01]))]
        let eval = ExpressionEvaluator()
        // Opaque values compare as .null — the only way equality to a number
        // can succeed is the `!=` leg that matches any non-null literal.
        XCTAssertTrue(try eval.evaluateBool(expression: "blob != 1", context: ctx))
    }

    // MARK: - Naming: FormatStrategy & FieldDerivedStrategy

    func testFormatStrategyStringifiesDates() throws {
        let docType = TestSupport.makeDocType(
            id: "Invoice",
            fields: [FieldDefinition(key: "issued", label: "Issued", type: .date, required: false)],
            autoname: "format:INV-{issued}"
        )
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["issued": .date(Date(timeIntervalSince1970: 0))]
        )
        let service = NamingService()
        let resolved = try service.resolve(
            docType: docType,
            document: doc,
            context: NamingContext(now: Date())
        )
        XCTAssertTrue(resolved.hasPrefix("INV-1970-01-01"), "got: \(resolved)")
    }

    func testFormatStrategyRejectsDataAndArray() {
        let docType = TestSupport.makeDocType(
            id: "Thing",
            fields: [FieldDefinition(key: "payload", label: "Payload", type: .attachment, required: false)],
            autoname: "format:THG-{payload}"
        )
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["payload": .data(Data([0xAA]))]
        )
        let service = NamingService()
        XCTAssertThrowsError(
            try service.resolve(
                docType: docType,
                document: doc,
                context: NamingContext(now: Date())
            )
        ) { error in
            guard case NamingError.missingFieldValue(let key) = error else {
                return XCTFail("expected missingFieldValue, got \(error)")
            }
            XCTAssertEqual(key, "payload")
        }
    }

    func testFieldDerivedStrategyAcceptsDateValues() throws {
        let docType = TestSupport.makeDocType(
            id: "Stamp",
            fields: [FieldDefinition(key: "at", label: "At", type: .datetime, required: false)],
            autoname: "field:at"
        )
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["at": .dateTime(Date(timeIntervalSince1970: 0))]
        )
        let service = NamingService()
        let resolved = try service.resolve(
            docType: docType,
            document: doc,
            context: NamingContext(now: Date())
        )
        XCTAssertTrue(resolved.hasPrefix("1970-01-01"), "got: \(resolved)")
    }

    func testFieldDerivedStrategyRejectsOpaqueValues() {
        let docType = TestSupport.makeDocType(
            id: "Stamp",
            fields: [FieldDefinition(key: "blob", label: "Blob", type: .attachment, required: false)],
            autoname: "field:blob"
        )
        let doc = TestSupport.makeDocument(
            docType: docType.id,
            fields: ["blob": .data(Data([0xAA]))]
        )
        let service = NamingService()
        XCTAssertThrowsError(
            try service.resolve(
                docType: docType,
                document: doc,
                context: NamingContext(now: Date())
            )
        )
    }

    // MARK: - Automation: FieldValueDecoder

    func testFieldValueDecoderParsesTypedDate() throws {
        // `set_value` handler parameters are untyped strings; the decoder
        // needs an explicit "date" tag to produce a typed FieldValue.date.
        let iso = "2026-04-24T10:00:00Z"
        let registry = AutomationActionRegistry()
        var doc = TestSupport.makeDocument(fields: [:])
        try registry.execute(
            actionType: "set_value",
            parameters: ["field": "due", "value": iso, "type": "date"],
            on: &doc,
            context: AutomationContext(trigger: "on_save")
        )
        guard case .date(let d) = doc.fields["due"] else {
            return XCTFail("expected .date, got \(String(describing: doc.fields["due"]))")
        }
        XCTAssertEqual(
            ISO8601DateFormatter().string(from: d),
            iso
        )
    }

    func testFieldValueDecoderParsesBase64Data() throws {
        let registry = AutomationActionRegistry()
        var doc = TestSupport.makeDocument(fields: [:])
        try registry.execute(
            actionType: "set_value",
            parameters: ["field": "blob", "value": "QUI=", "type": "data"],
            on: &doc,
            context: AutomationContext(trigger: "on_save")
        )
        guard case .data(let d) = doc.fields["blob"] else {
            return XCTFail("expected .data, got \(String(describing: doc.fields["blob"]))")
        }
        XCTAssertEqual(d, Data([0x41, 0x42]))
    }

    func testFieldValueDecoderRejectsMalformedDate() {
        let registry = AutomationActionRegistry()
        var doc = TestSupport.makeDocument(fields: [:])
        XCTAssertThrowsError(
            try registry.execute(
                actionType: "set_value",
                parameters: ["field": "due", "value": "not-a-date", "type": "date"],
                on: &doc,
                context: AutomationContext(trigger: "on_save")
            )
        )
    }
}

