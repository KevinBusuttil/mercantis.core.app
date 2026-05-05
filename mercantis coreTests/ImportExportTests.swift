//
//  ImportExportTests.swift
//  mercantis coreTests
//
//  Phase C / P3.3 (ADR-046) — DataExporter + DataImporter round trips
//  through CSV and JSON. Imports re-route through `DocumentEngine.save`,
//  so naming, validation, audit log, and per-device counter blocks all
//  fire identically to interactive saves.
//

import XCTest
@testable import mercantis_core

final class ImportExportTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var exporter: DataExporter!
    private var importer: DataImporter!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        exporter = DataExporter(documentEngine: harness.engine, registry: harness.registry)
        importer = DataImporter(documentEngine: harness.engine, registry: harness.registry)
        try harness.registry.register(TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("priority"),
                TestSupport.textField("category"),
            ]
        ))
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        exporter = nil
        importer = nil
        harness = nil
    }

    private func saveDoc(_ id: String, title: String, priority: Int? = nil, category: String? = nil) throws {
        var fields: [String: FieldValue] = ["title": .string(title)]
        if let p = priority { fields["priority"] = .int(p) }
        if let c = category { fields["category"] = .string(c) }
        try harness.engine.save(TestSupport.makeDocument(id: id, fields: fields))
    }

    // MARK: - CSV codec

    func testCSVEscapesCommasAndQuotes() {
        XCTAssertEqual(CSVCodec.escape("plain"), "plain")
        XCTAssertEqual(CSVCodec.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVCodec.escape("she said \"hi\""), "\"she said \"\"hi\"\"\"")
    }

    func testCSVDecodesQuotedCellsWithEmbeddedCommas() throws {
        let bytes = Data("name,desc\nAlice,\"Hello, world\"\n".utf8)
        let table = try CSVCodec.decode(bytes)
        XCTAssertEqual(table.headers, ["name", "desc"])
        XCTAssertEqual(table.rows.first?["desc"], "Hello, world")
    }

    func testCSVDecodeRejectsUnterminatedQuotedCell() {
        let bytes = Data("a,b\n\"unterminated".utf8)
        XCTAssertThrowsError(try CSVCodec.decode(bytes)) { error in
            guard case ImportExportError.malformedCSV = error else {
                return XCTFail("expected malformedCSV, got \(error)")
            }
        }
    }

    // MARK: - CSV export / import

    func testCSVExportEmitsDeclaredFieldColumnsAndSystemColumns() throws {
        try saveDoc("a", title: "Alpha", priority: 1, category: "x")
        try saveDoc("b", title: "Bravo", priority: 2, category: "y")

        let bytes = try exporter.export(docType: "Note", format: .csv)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))

        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "id,status,docStatus,title,priority,category")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.contains(where: { $0.contains("Alpha") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Bravo") }))
    }

    func testCSVImportInsertsNewDocumentsThroughDocumentEngine() throws {
        let csv = """
        id,status,docStatus,title,priority,category
        n1,Open,0,First,5,Alpha
        n2,Open,0,Second,7,Beta
        """
        let report = try importer.import(docType: "Note", data: Data(csv.utf8), format: .csv)
        XCTAssertEqual(report.rowsRead, 2)
        XCTAssertEqual(report.insertedCount, 2)

        let n1 = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "n1"))
        XCTAssertEqual(n1.fields["title"], .string("First"))
        XCTAssertEqual(n1.fields["priority"], .int(5))
    }

    func testCSVImportSkipExistingPolicyDoesNotOverwrite() throws {
        try saveDoc("dup", title: "Original", priority: 1)

        let csv = """
        id,status,docStatus,title,priority,category
        dup,Open,0,Replaced,99,X
        """
        let report = try importer.import(
            docType: "Note", data: Data(csv.utf8),
            format: .csv, conflictPolicy: .skipExisting
        )
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.updatedCount, 0)

        let unchanged = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "dup"))
        XCTAssertEqual(unchanged.fields["title"], .string("Original"))
    }

    func testCSVImportOverwritePolicyUpdatesExistingDocument() throws {
        try saveDoc("dup", title: "Old", priority: 1)

        let csv = """
        id,status,docStatus,title,priority,category
        dup,Open,0,New,42,X
        """
        let report = try importer.import(docType: "Note", data: Data(csv.utf8), format: .csv)
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(report.insertedCount, 0)

        let updated = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "dup"))
        XCTAssertEqual(updated.fields["title"], .string("New"))
        XCTAssertEqual(updated.fields["priority"], .int(42))
    }

    func testCSVImportMalformedNumberFailsRowIndividually() throws {
        let csv = """
        id,status,docStatus,title,priority,category
        good,Open,0,Good,5,X
        bad,Open,0,Bad,abc,Y
        """
        let report = try importer.import(docType: "Note", data: Data(csv.utf8), format: .csv)
        XCTAssertEqual(report.insertedCount, 1)
        XCTAssertEqual(report.failedCount, 1)
    }

    // MARK: - JSON round trip

    func testJSONRoundTripPreservesChildrenAndTypedFieldValues() throws {
        // Save a parent doc with a child table to verify JSON keeps
        // children that CSV can't.
        var parent = TestSupport.makeDocument(
            id: "p1",
            fields: ["title": .string("Parent")]
        )
        parent.children["lines"] = [
            ChildRow(id: "l1", rowIndex: 0, fields: ["sku": .string("X"), "qty": .int(2)]),
            ChildRow(id: "l2", rowIndex: 1, fields: ["sku": .string("Y"), "qty": .int(3)]),
        ]
        try harness.engine.save(parent)

        let bytes = try exporter.export(docType: "Note", format: .json)

        // Wipe and re-import.
        try harness.engine.delete(docType: "Note", id: "p1")
        XCTAssertNil(try harness.engine.fetch(docType: "Note", id: "p1"))

        let report = try importer.import(docType: "Note", data: bytes, format: .json)
        XCTAssertEqual(report.insertedCount, 1)

        let restored = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "p1"))
        XCTAssertEqual(restored.fields["title"], .string("Parent"))
        XCTAssertEqual(restored.children["lines"]?.count, 2)
        XCTAssertEqual(restored.children["lines"]?[0].fields["qty"], .int(2))
    }

    func testJSONImportRejectsMalformedPayload() throws {
        let bytes = Data("{not really json".utf8)
        XCTAssertThrowsError(try importer.import(docType: "Note", data: bytes, format: .json)) { error in
            guard case ImportExportError.malformedJSON = error else {
                return XCTFail("expected malformedJSON, got \(error)")
            }
        }
    }

    func testExportOfUnregisteredDocTypeThrows() {
        XCTAssertThrowsError(try exporter.export(docType: "Unknown", format: .csv)) { error in
            guard case ImportExportError.docTypeNotRegistered = error else {
                return XCTFail("expected docTypeNotRegistered, got \(error)")
            }
        }
    }

    // MARK: - Predicate-bound export

    func testExportRespectsPredicateFilter() throws {
        try saveDoc("a", title: "Alpha", priority: 1)
        try saveDoc("b", title: "Bravo", priority: 9)

        let bytes = try exporter.export(
            docType: "Note", format: .csv,
            predicates: [ListFilter("priority", .gt(.int(5)))]
        )
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let dataLines = text.split(separator: "\n").dropFirst()
        XCTAssertEqual(dataLines.count, 1)
        XCTAssertTrue(dataLines.first?.contains("Bravo") ?? false)
    }
}
