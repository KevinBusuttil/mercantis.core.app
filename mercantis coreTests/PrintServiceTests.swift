//
//  PrintServiceTests.swift
//  mercantis coreTests
//
//  Phase C / P3.2 (ADR-044) — PrintService + PlainTextPrintRenderer.
//  PDF rendering is exercised via byte-prefix sanity (the bytes start with
//  `%PDF-`). Pixel-level PDF tests are out of scope.
//

import XCTest
@testable import mercantis_core

final class PrintServiceTests: XCTestCase {

    // MARK: - Helpers

    private func sampleDocument() -> Document {
        var doc = TestSupport.makeDocument(
            id: "INV-001",
            docType: "Invoice",
            fields: [
                "customer":    .string("ACME Corp"),
                "currency":    .string("EUR"),
                "subtotal":    .double(150),
                "grand_total": .double(165),
            ]
        )
        doc.children["items"] = [
            ChildRow(id: "r1", rowIndex: 0, fields: [
                "name": .string("Widget"),  "qty": .int(2), "price": .double(50)
            ]),
            ChildRow(id: "r2", rowIndex: 1, fields: [
                "name": .string("Gizmo"),   "qty": .int(1), "price": .double(50)
            ]),
        ]
        return doc
    }

    private func sampleFormat() -> PrintFormat {
        PrintFormat(
            id: "invoice-default",
            name: "Default Invoice",
            docType: "Invoice",
            letterHeadId: "lh-acme",
            sections: [
                .heading(text: "Invoice {id}"),
                .fields(keys: ["customer", "currency"]),
                .table(
                    tableKey: "items",
                    columns: ["name", "qty", "price"],
                    labels: ["qty": "Qty"]
                ),
                .keyValue(label: "Subtotal", value: "{subtotal}"),
                .keyValue(label: "Total",    value: "{grand_total} {currency}"),
            ]
        )
    }

    private func makeService() -> PrintService {
        let s = PrintService()
        s.register(format: sampleFormat())
        s.register(letterHead: LetterHead(
            id: "lh-acme", name: "ACME",
            header: "ACME Corp — Invoices",
            footer: "Thank you for your business."
        ))
        return s
    }

    // MARK: - Registry

    func testRegisteredFormatsAreLookupable() {
        let s = makeService()
        XCTAssertEqual(s.registeredFormatIds(), ["invoice-default"])
        XCTAssertEqual(s.formats(forDocType: "Invoice").count, 1)
        XCTAssertEqual(s.formats(forDocType: "Customer").count, 0)
    }

    func testUnregisterRemovesFormatAndLetterHead() {
        let s = makeService()
        s.unregister(formatId: "invoice-default")
        s.unregister(letterHeadId: "lh-acme")
        XCTAssertTrue(s.registeredFormatIds().isEmpty)
    }

    // MARK: - Render plain text

    func testPlainTextOutputIncludesLetterHeadAndHeading() throws {
        let result = try makeService().render(
            formatId: "invoice-default",
            document: sampleDocument(),
            as: .plainText
        )
        XCTAssertEqual(result.mimeType, "text/plain; charset=utf-8")
        let text = String(data: result.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("ACME Corp — Invoices"), "letter head header missing")
        XCTAssertTrue(text.contains("Invoice INV-001"), "heading substitution failed")
        XCTAssertTrue(text.contains("Thank you for your business."), "letter head footer missing")
    }

    func testPlainTextRendersFieldsGridAndChildTable() throws {
        let result = try makeService().render(
            formatId: "invoice-default", document: sampleDocument(), as: .plainText
        )
        let text = String(data: result.data, encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("Customer"), "fields label missing")
        XCTAssertTrue(text.contains("ACME Corp"), "fields value missing")

        // Table heading (custom labels.qty + default label for `name`/`price`).
        XCTAssertTrue(text.contains("Name"))
        XCTAssertTrue(text.contains("Qty"))
        XCTAssertTrue(text.contains("Price"))

        // Row data.
        XCTAssertTrue(text.contains("Widget"))
        XCTAssertTrue(text.contains("Gizmo"))
    }

    func testPlainTextSubstitutesPlaceholdersInKeyValueRows() throws {
        let result = try makeService().render(
            formatId: "invoice-default", document: sampleDocument(), as: .plainText
        )
        let text = String(data: result.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Total: 165 EUR"))
    }

    func testPlainTextLeavesUnknownPlaceholdersLiteral() throws {
        let format = PrintFormat(
            id: "x", name: "X", docType: "Note",
            sections: [.paragraph(text: "Hello {missing_field} world")]
        )
        let s = PrintService()
        s.register(format: format)

        let result = try s.render(
            formatId: "x",
            document: TestSupport.makeDocument(id: "n1", docType: "Note", fields: ["title": .string("t")]),
            as: .plainText
        )
        let text = String(data: result.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("{missing_field}"),
                      "unknown placeholder must round-trip literal so authors notice")
    }

    // MARK: - Errors

    func testRenderThrowsForUnknownFormat() {
        XCTAssertThrowsError(try makeService().render(
            formatId: "does-not-exist",
            document: sampleDocument(),
            as: .plainText
        )) { error in
            guard case PrintService.PrintServiceError.unknownFormat = error else {
                return XCTFail("expected unknownFormat, got \(error)")
            }
        }
    }

    func testRenderThrowsOnDocTypeMismatch() {
        var wrong = TestSupport.makeDocument(id: "x", docType: "Note")
        wrong.fields = ["title": .string("x")]

        XCTAssertThrowsError(try makeService().render(
            formatId: "invoice-default",
            document: wrong,
            as: .plainText
        )) { error in
            guard case PrintService.PrintServiceError.docTypeMismatch = error else {
                return XCTFail("expected docTypeMismatch, got \(error)")
            }
        }
    }

    // MARK: - PDF byte sanity

    func testPDFOutputStartsWithPDFMagicBytes() throws {
        let result = try makeService().render(
            formatId: "invoice-default", document: sampleDocument(), as: .pdf
        )
        XCTAssertEqual(result.mimeType, "application/pdf")
        let prefix = result.data.prefix(5)
        XCTAssertEqual(Array(prefix), Array("%PDF-".utf8),
                       "PDF output must begin with the %PDF- magic header")
    }

    // MARK: - PrintFormat round-trip

    func testPrintFormatRoundTripsThroughCodable() throws {
        let original = sampleFormat()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PrintFormat.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
