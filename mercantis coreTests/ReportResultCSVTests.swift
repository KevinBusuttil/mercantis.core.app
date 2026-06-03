//
//  ReportResultCSVTests.swift
//  mercantis coreTests
//
//  Reusable `ReportResult.csvString()` serialisation (RFC-4180 escaping).
//

import XCTest
@testable import mercantis_core

final class ReportResultCSVTests: XCTestCase {

    func testHeaderAndRows() {
        let result = ReportResult(
            columns: ["A", "B"],
            rows: [["1", "2"], ["3", "4"]]
        )
        XCTAssertEqual(result.csvString(), "A,B\n1,2\n3,4")
    }

    func testQuotesFieldsWithCommasAndDoublesEmbeddedQuotes() {
        let result = ReportResult(
            columns: ["Name", "Note"],
            rows: [["Acme, Inc.", "He said \"hi\""]]
        )
        let lines = result.csvString().components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Name,Note")
        XCTAssertEqual(lines[1], "\"Acme, Inc.\",\"He said \"\"hi\"\"\"")
    }

    func testNilCellsBecomeEmptyFields() {
        let result = ReportResult(columns: ["A", "B"], rows: [["x", nil]])
        XCTAssertEqual(result.csvString(), "A,B\nx,")
    }

    func testNewlineInsideFieldIsQuoted() {
        let result = ReportResult(columns: ["A"], rows: [["line1\nline2"]])
        XCTAssertEqual(result.csvString(), "A\n\"line1\nline2\"")
    }

    func testEmptyResultEmitsHeaderOnly() {
        let result = ReportResult(columns: ["A", "B"], rows: [])
        XCTAssertEqual(result.csvString(), "A,B")
    }
}
