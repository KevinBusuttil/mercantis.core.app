//
//  DocumentLookupResolverTests.swift
//  mercantis coreTests
//
//  Covers the cross-document `lookup(...)` shape (ADR-029, P2.2):
//  the call interpretation in `ExpressionEvaluator`, the
//  `CachingDocumentLookupResolver`'s read-through behaviour and
//  per-save invalidation, and the `DocumentEngine.list`
//  whereExpression / lookup integration.
//

import Foundation
import XCTest
@testable import mercantis_core

final class DocumentLookupResolverTests: XCTestCase {

    // MARK: - Stubs

    /// A minimal in-memory resolver that counts calls. Used for the
    /// caching tests so we can observe pass-through vs cache-hit.
    final class StubResolver: DocumentLookupResolver {
        var data: [String: [String: [String: FieldValue]]] = [:]
        var callCount: Int = 0
        var throwNext: Error? = nil

        func put(docType: String, name: String, fields: [String: FieldValue]) {
            data[docType, default: [:]][name] = fields
        }

        func lookup(docType: String, name: String, field: String) throws -> FieldValue? {
            callCount += 1
            if let err = throwNext {
                throwNext = nil
                throw err
            }
            return data[docType]?[name]?[field]
        }
    }

    enum StubError: Error { case io }

    // MARK: - Evaluator: lookup() call form

    func testLookupCallReturnsFieldValueFromResolver() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "ITM-001", fields: ["rate": .double(12.5)])
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        let result = try evaluator.evaluateFormula(
            expression: "lookup(\"Item\", item, \"rate\") * qty",
            context: ["item": .string("ITM-001"), "qty": .double(3)]
        )
        XCTAssertEqual(result, .double(37.5))
    }

    func testLookupCallReturnsNullForUnknownDocument() throws {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        // Missing parent — lookup should resolve to .null. The OR fallback
        // shape is what an automation rule would write.
        let result = try evaluator.evaluateBool(
            expression: "lookup(\"Item\", \"missing\", \"rate\") == null",
            context: [:]
        )
        XCTAssertTrue(result)
    }

    func testLookupCallReturnsNullForUnknownField() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "ITM-001", fields: ["rate": .double(10)])
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        let result = try evaluator.evaluateBool(
            expression: "lookup(\"Item\", \"ITM-001\", \"nonexistent\") == null",
            context: [:]
        )
        XCTAssertTrue(result)
    }

    func testLookupWithNullNameResolvesToNullWithoutCallingResolver() throws {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        // `optional_link` is undefined in the context — lookup should
        // short-circuit to null without an underlying resolver call.
        let result = try evaluator.evaluateBool(
            expression: "lookup(\"Item\", optional_link, \"rate\") == null",
            context: [:]
        )
        XCTAssertTrue(result)
        XCTAssertEqual(stub.callCount, 0)
    }

    func testLookupWithEmptyStringNameResolvesToNullWithoutCallingResolver() throws {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        let result = try evaluator.evaluateBool(
            expression: "lookup(\"Item\", \"\", \"rate\") == null",
            context: [:]
        )
        XCTAssertTrue(result)
        XCTAssertEqual(stub.callCount, 0)
    }

    func testLookupWithoutResolverThrowsUnexpectedToken() {
        let evaluator = ExpressionEvaluator()   // no resolver

        XCTAssertThrowsError(
            try evaluator.evaluateBool(
                expression: "lookup(\"Item\", \"x\", \"rate\") > 0",
                context: [:]
            )
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.unexpectedToken(let msg) = error else {
                return XCTFail("expected unexpectedToken, got \(error)")
            }
            XCTAssertTrue(msg.contains("lookup"))
        }
    }

    func testLookupWrongArityThrows() {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        XCTAssertThrowsError(
            try evaluator.evaluateBool(expression: "lookup(\"Item\", \"x\") == null", context: [:])
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.unexpectedToken(let msg) = error else {
                return XCTFail("expected unexpectedToken, got \(error)")
            }
            XCTAssertTrue(msg.contains("3 arguments"))
        }
    }

    func testLookupWithNonStringDocTypeThrowsTypeMismatch() {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        XCTAssertThrowsError(
            try evaluator.evaluateBool(
                expression: "lookup(123, \"x\", \"rate\") > 0",
                context: [:]
            )
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.typeMismatch = error else {
                return XCTFail("expected typeMismatch, got \(error)")
            }
        }
    }

    func testLookupWithNonStringFieldThrowsTypeMismatch() {
        let stub = StubResolver()
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        XCTAssertThrowsError(
            try evaluator.evaluateBool(
                expression: "lookup(\"Item\", \"x\", 42) > 0",
                context: [:]
            )
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.typeMismatch = error else {
                return XCTFail("expected typeMismatch, got \(error)")
            }
        }
    }

    func testResolverThrowIsTreatedAsNull() throws {
        let stub = StubResolver()
        stub.throwNext = StubError.io
        let evaluator = ExpressionEvaluator(lookupResolver: stub)

        let result = try evaluator.evaluateBool(
            expression: "lookup(\"Item\", \"ITM-001\", \"rate\") == null",
            context: [:]
        )
        XCTAssertTrue(result)
    }

    func testUnknownCallNameThrows() {
        let evaluator = ExpressionEvaluator(lookupResolver: StubResolver())

        XCTAssertThrowsError(
            try evaluator.evaluateBool(expression: "frobnicate(1)", context: [:])
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.unexpectedToken(let msg) = error else {
                return XCTFail("expected unexpectedToken, got \(error)")
            }
            XCTAssertTrue(msg.contains("frobnicate"))
        }
    }

    // MARK: - Lookup budget

    func testLookupBudgetExceededThrows() {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(1)])
        stub.put(docType: "Item", name: "B", fields: ["rate": .double(1)])
        stub.put(docType: "Item", name: "C", fields: ["rate": .double(1)])
        let evaluator = ExpressionEvaluator(lookupResolver: stub, lookupBudget: 2)

        // Three lookups in one expression — the third trips the budget.
        XCTAssertThrowsError(
            try evaluator.evaluateFormula(
                expression: "lookup(\"Item\", \"A\", \"rate\") + lookup(\"Item\", \"B\", \"rate\") + lookup(\"Item\", \"C\", \"rate\")",
                context: [:]
            )
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.lookupBudgetExceeded(let limit) = error else {
                return XCTFail("expected lookupBudgetExceeded, got \(error)")
            }
            XCTAssertEqual(limit, 2)
        }
    }

    func testLookupBudgetZeroDisablesLookupEvenWithResolver() {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(5)])
        let evaluator = ExpressionEvaluator(lookupResolver: stub, lookupBudget: 0)

        XCTAssertThrowsError(
            try evaluator.evaluateBool(
                expression: "lookup(\"Item\", \"A\", \"rate\") > 0",
                context: [:]
            )
        ) { error in
            guard case ExpressionEvaluator.EvaluatorError.lookupBudgetExceeded = error else {
                return XCTFail("expected lookupBudgetExceeded, got \(error)")
            }
        }
    }

    func testLookupBudgetIsPerEvaluationNotPerEvaluator() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(5)])
        let evaluator = ExpressionEvaluator(lookupResolver: stub, lookupBudget: 1)

        // Each top-level evaluateBool gets its own fresh budget.
        for _ in 0 ..< 5 {
            XCTAssertTrue(
                try evaluator.evaluateBool(
                    expression: "lookup(\"Item\", \"A\", \"rate\") > 0",
                    context: [:]
                )
            )
        }
    }

    // MARK: - CachingDocumentLookupResolver

    func testCacheReadThroughHitsBaseExactlyOnce() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7)])
        let cache = CachingDocumentLookupResolver(base: stub)

        XCTAssertEqual(try cache.lookup(docType: "Item", name: "A", field: "rate"), .double(7))
        XCTAssertEqual(try cache.lookup(docType: "Item", name: "A", field: "rate"), .double(7))
        XCTAssertEqual(try cache.lookup(docType: "Item", name: "A", field: "rate"), .double(7))
        XCTAssertEqual(stub.callCount, 1)
    }

    func testCacheStoresMissAsAbsenceAndAvoidsRefetch() throws {
        let stub = StubResolver()
        // Empty data — every lookup returns nil.
        let cache = CachingDocumentLookupResolver(base: stub)

        XCTAssertNil(try cache.lookup(docType: "Item", name: "A", field: "rate"))
        XCTAssertNil(try cache.lookup(docType: "Item", name: "A", field: "rate"))
        XCTAssertEqual(stub.callCount, 1)
    }

    func testCacheEntriesAreScopedToFieldKey() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7), "name": .string("Widget")])
        let cache = CachingDocumentLookupResolver(base: stub)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        _ = try cache.lookup(docType: "Item", name: "A", field: "name")
        // Two distinct fields = two underlying calls, even though the
        // (docType, name) pair is the same.
        XCTAssertEqual(stub.callCount, 2)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        _ = try cache.lookup(docType: "Item", name: "A", field: "name")
        XCTAssertEqual(stub.callCount, 2)
    }

    func testManualInvalidationDropsAllFieldsForKey() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7), "name": .string("Widget")])
        let cache = CachingDocumentLookupResolver(base: stub)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        _ = try cache.lookup(docType: "Item", name: "A", field: "name")
        XCTAssertEqual(cache.cachedFieldCount, 2)

        cache.invalidate(docType: "Item", name: "A")
        XCTAssertEqual(cache.cachedFieldCount, 0)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        XCTAssertEqual(stub.callCount, 3)
    }

    func testEventEmitterDocumentSavedDropsCachedEntry() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7)])
        let emitter = EventEmitter()
        let cache = CachingDocumentLookupResolver(base: stub, eventEmitter: emitter)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        XCTAssertTrue(cache.isCached(docType: "Item", name: "A", field: "rate"))

        let document = TestSupport.makeDocument(id: "A", docType: "Item")
        emitter.publish(DocumentSavedEvent(document: document, docType: "Item"))
        XCTAssertFalse(cache.isCached(docType: "Item", name: "A", field: "rate"))
    }

    func testEventEmitterDocumentDeletedDropsCachedEntry() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7)])
        let emitter = EventEmitter()
        let cache = CachingDocumentLookupResolver(base: stub, eventEmitter: emitter)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        XCTAssertTrue(cache.isCached(docType: "Item", name: "A", field: "rate"))

        emitter.publish(DocumentDeletedEvent(documentId: "A", docType: "Item"))
        XCTAssertFalse(cache.isCached(docType: "Item", name: "A", field: "rate"))
    }

    func testEventEmitterDocumentSubmittedAndCancelledDropEntries() throws {
        let stub = StubResolver()
        stub.put(docType: "Invoice", name: "INV-1", fields: ["status": .string("Draft")])
        stub.put(docType: "Invoice", name: "INV-2", fields: ["status": .string("Submitted")])
        let emitter = EventEmitter()
        let cache = CachingDocumentLookupResolver(base: stub, eventEmitter: emitter)

        _ = try cache.lookup(docType: "Invoice", name: "INV-1", field: "status")
        _ = try cache.lookup(docType: "Invoice", name: "INV-2", field: "status")
        XCTAssertEqual(cache.cachedFieldCount, 2)

        emitter.publish(DocumentSubmittedEvent(
            document: TestSupport.makeDocument(id: "INV-1", docType: "Invoice"),
            docType: "Invoice"
        ))
        XCTAssertFalse(cache.isCached(docType: "Invoice", name: "INV-1", field: "status"))
        XCTAssertTrue(cache.isCached(docType: "Invoice", name: "INV-2", field: "status"))

        emitter.publish(DocumentCancelledEvent(
            document: TestSupport.makeDocument(id: "INV-2", docType: "Invoice"),
            docType: "Invoice"
        ))
        XCTAssertFalse(cache.isCached(docType: "Invoice", name: "INV-2", field: "status"))
    }

    func testInvalidationLeavesUnrelatedKeysAlone() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(7)])
        stub.put(docType: "Item", name: "B", fields: ["rate": .double(9)])
        let emitter = EventEmitter()
        let cache = CachingDocumentLookupResolver(base: stub, eventEmitter: emitter)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        _ = try cache.lookup(docType: "Item", name: "B", field: "rate")
        XCTAssertEqual(cache.cachedFieldCount, 2)

        emitter.publish(DocumentSavedEvent(
            document: TestSupport.makeDocument(id: "A", docType: "Item"),
            docType: "Item"
        ))
        XCTAssertFalse(cache.isCached(docType: "Item", name: "A", field: "rate"))
        XCTAssertTrue(cache.isCached(docType: "Item", name: "B", field: "rate"))
    }

    func testClearDropsEverything() throws {
        let stub = StubResolver()
        stub.put(docType: "Item", name: "A", fields: ["rate": .double(1)])
        stub.put(docType: "Item", name: "B", fields: ["rate": .double(2)])
        let cache = CachingDocumentLookupResolver(base: stub)

        _ = try cache.lookup(docType: "Item", name: "A", field: "rate")
        _ = try cache.lookup(docType: "Item", name: "B", field: "rate")
        XCTAssertEqual(cache.cachedFieldCount, 2)

        cache.clear()
        XCTAssertEqual(cache.cachedFieldCount, 0)
    }

    // MARK: - End-to-end: DocumentEngine + lookup-enabled list whereExpression

    func testDocumentEngineConformsAsLookupResolver() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let item = TestSupport.makeDocType(id: "Item", fields: [
            TestSupport.textField("name", required: true),
            TestSupport.numberField("rate")
        ], titleField: "name")
        try harness.registry.register(item)

        try harness.engine.save(TestSupport.makeDocument(
            id: "ITM-001",
            docType: "Item",
            fields: ["name": .string("Widget"), "rate": .double(12.5)]
        ))

        // Engine itself answers the resolver protocol.
        XCTAssertEqual(
            try harness.engine.lookup(docType: "Item", name: "ITM-001", field: "rate"),
            .double(12.5)
        )
        XCTAssertNil(
            try harness.engine.lookup(docType: "Item", name: "missing", field: "rate")
        )
    }

    func testDocumentEngineListWhereExpressionUsesLookup() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let item = TestSupport.makeDocType(id: "Item", fields: [
            TestSupport.textField("name", required: true),
            TestSupport.numberField("rate")
        ], titleField: "name")
        try harness.registry.register(item)

        let line = TestSupport.makeDocType(id: "OrderLine", fields: [
            TestSupport.linkField("item", targeting: "Item"),
            TestSupport.numberField("qty")
        ], titleField: "item")
        try harness.registry.register(line)

        try harness.engine.save(TestSupport.makeDocument(
            id: "ITM-001", docType: "Item",
            fields: ["name": .string("Widget"), "rate": .double(50)]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "ITM-002", docType: "Item",
            fields: ["name": .string("Cog"), "rate": .double(5)]
        ))

        try harness.engine.save(TestSupport.makeDocument(
            id: "L1", docType: "OrderLine",
            fields: ["item": .string("ITM-001"), "qty": .double(2)]
        ))
        try harness.engine.save(TestSupport.makeDocument(
            id: "L2", docType: "OrderLine",
            fields: ["item": .string("ITM-002"), "qty": .double(2)]
        ))

        // Filter lines by parent's rate. With caching, ITM-001 / ITM-002
        // are each fetched at most once across the two-row scan.
        let highValue = try harness.engine.list(
            docType: "OrderLine",
            whereExpression: "lookup(\"Item\", item, \"rate\") > 10"
        )
        XCTAssertEqual(highValue.map(\.id).sorted(), ["L1"])
    }

    func testEngineLookupCacheInvalidatesOnSave() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let item = TestSupport.makeDocType(id: "Item", fields: [
            TestSupport.textField("name", required: true),
            TestSupport.numberField("rate")
        ], titleField: "name")
        try harness.registry.register(item)

        try harness.engine.save(TestSupport.makeDocument(
            id: "ITM-001", docType: "Item",
            fields: ["name": .string("Widget"), "rate": .double(12.5)]
        ))

        let cache = harness.engine.lookupCache

        XCTAssertEqual(
            try cache.lookup(docType: "Item", name: "ITM-001", field: "rate"),
            .double(12.5)
        )
        XCTAssertTrue(cache.isCached(docType: "Item", name: "ITM-001", field: "rate"))

        // Re-save the parent with a new rate — the engine fires
        // DocumentSavedEvent which the cache subscribes to.
        let updated = try XCTUnwrap(harness.engine.fetch(docType: "Item", id: "ITM-001"))
        var mutated = updated
        mutated.fields["rate"] = .double(99)
        try harness.engine.save(mutated)

        XCTAssertFalse(cache.isCached(docType: "Item", name: "ITM-001", field: "rate"))
        XCTAssertEqual(
            try cache.lookup(docType: "Item", name: "ITM-001", field: "rate"),
            .double(99)
        )
    }
}
