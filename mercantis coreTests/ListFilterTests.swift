//
//  ListFilterTests.swift
//  mercantis coreTests
//
//  Phase A §3.1 — typed `ListFilter` operators on `DocumentEngine.list(...)`.
//  Exercises both SQL-pushed and in-memory pushdown paths.
//

import XCTest
import GRDB
@testable import mercantis_core

final class ListFilterTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    // MARK: - Helpers

    private func registerDocType(indexed: Bool = true) throws {
        let docType = TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("priority"),
                TestSupport.textField("category"),
            ],
            indexes: indexed ? [
                IndexDefinition(fieldKey: "priority", unique: false),
                IndexDefinition(fieldKey: "category", unique: false),
            ] : []
        )
        try harness.registry.register(docType)
    }

    private func save(
        id: String,
        title: String,
        priority: Int? = nil,
        category: String? = nil
    ) throws {
        var fields: [String: FieldValue] = ["title": .string(title)]
        if let p = priority { fields["priority"] = .int(p) }
        if let c = category { fields["category"] = .string(c) }
        try harness.engine.save(TestSupport.makeDocument(id: id, fields: fields))
    }

    // MARK: - Comparison operators

    func testGreaterThanFilterPushedToSQL() throws {
        try registerDocType()
        try save(id: "a", title: "A", priority: 1)
        try save(id: "b", title: "B", priority: 5)
        try save(id: "c", title: "C", priority: 9)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .gt(.int(3)))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["b", "c"])
    }

    func testGreaterOrEqualFilterIncludesBoundary() throws {
        try registerDocType()
        try save(id: "a", title: "A", priority: 1)
        try save(id: "b", title: "B", priority: 5)
        try save(id: "c", title: "C", priority: 9)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .gte(.int(5)))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["b", "c"])
    }

    func testLessThanFilter() throws {
        try registerDocType()
        try save(id: "a", title: "A", priority: 1)
        try save(id: "b", title: "B", priority: 5)
        try save(id: "c", title: "C", priority: 9)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .lt(.int(5)))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["a"])
    }

    func testNotEqualFilter() throws {
        try registerDocType()
        try save(id: "a", title: "A", category: "x")
        try save(id: "b", title: "B", category: "y")
        try save(id: "c", title: "C", category: "x")

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("category", .neq(.string("x")))]
        )
        XCTAssertEqual(docs.map(\.id), ["b"])
    }

    func testBetweenInclusive() throws {
        try registerDocType()
        try save(id: "a", title: "A", priority: 1)
        try save(id: "b", title: "B", priority: 5)
        try save(id: "c", title: "C", priority: 9)
        try save(id: "d", title: "D", priority: 12)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .between(.int(5), .int(9)))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["b", "c"])
    }

    func testInOperatorMatchesAnyValue() throws {
        try registerDocType()
        try save(id: "a", title: "A", category: "alpha")
        try save(id: "b", title: "B", category: "beta")
        try save(id: "c", title: "C", category: "gamma")

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("category", .in([.string("alpha"), .string("gamma")]))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["a", "c"])
    }

    func testEmptyInOperatorMatchesNothing() throws {
        try registerDocType()
        try save(id: "a", title: "A", category: "alpha")

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("category", .in([]))]
        )
        XCTAssertTrue(docs.isEmpty)
    }

    func testLikeOperatorMatchesWildcard() throws {
        try registerDocType()
        try save(id: "a", title: "Hello World")
        try save(id: "b", title: "Hello Mercantis")
        try save(id: "c", title: "Goodbye")

        // `title` is a non-indexed string field — runs in memory.
        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("title", .like("Hello%"))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["a", "b"])
    }

    func testLikeOperatorOnIndexedFieldPushesToSQL() throws {
        try registerDocType()
        try save(id: "alpha-1", title: "A", category: "alpha-one")
        try save(id: "alpha-2", title: "B", category: "alpha-two")
        try save(id: "beta-1",  title: "C", category: "beta-one")

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("category", .like("alpha-%"))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["alpha-1", "alpha-2"])
    }

    func testIsNullOperator() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(
            id: "with",
            fields: ["title": .string("With"), "priority": .int(5)]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "without",
            fields: ["title": .string("Without")]
        ))

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .isNull)]
        )
        XCTAssertEqual(docs.map(\.id), ["without"])
    }

    func testIsNotNullOperator() throws {
        try registerDocType()
        try harness.engine.save(TestSupport.makeDocument(
            id: "with",
            fields: ["title": .string("With"), "priority": .int(5)]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "without",
            fields: ["title": .string("Without")]
        ))

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .isNotNull)]
        )
        XCTAssertEqual(docs.map(\.id), ["with"])
    }

    // MARK: - In-memory fallback for non-indexed fields

    func testGreaterThanFallsBackToInMemoryForNonIndexedField() throws {
        try registerDocType(indexed: false)
        try save(id: "a", title: "A", priority: 1)
        try save(id: "b", title: "B", priority: 5)
        try save(id: "c", title: "C", priority: 9)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("priority", .gt(.int(3)))]
        )
        XCTAssertEqual(Set(docs.map(\.id)), ["b", "c"])
    }

    func testCombinedPredicatesAndForLogic() throws {
        try registerDocType()
        try save(id: "a", title: "A", priority: 1, category: "x")
        try save(id: "b", title: "B", priority: 5, category: "y")
        try save(id: "c", title: "C", priority: 9, category: "x")

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [
                ListFilter("priority", .gte(.int(5))),
                ListFilter("category", .eq(.string("x"))),
            ]
        )
        XCTAssertEqual(docs.map(\.id), ["c"])
    }

    func testSystemColumnPredicatePushesToSQL() throws {
        try registerDocType()
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)

        var older = TestSupport.makeDocument(
            id: "older", fields: ["title": .string("Older")], updatedAt: earlier
        )
        var newer = TestSupport.makeDocument(
            id: "newer", fields: ["title": .string("Newer")], updatedAt: now
        )
        older.status = "Open"
        newer.status = "Closed"
        try harness.engine.save(older)
        try harness.engine.save(newer)

        let docs = try harness.engine.list(
            docType: "Note",
            predicates: [ListFilter("status", .in([.string("Open"), .string("Pending")]))]
        )
        XCTAssertEqual(docs.map(\.id), ["older"])
    }
}
