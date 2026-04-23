//
//  NamingTests.swift
//  mercantis coreTests
//
//  P1.1 / ADR-014 — Document naming subsystem.
//

import XCTest
@testable import mercantis_core

final class NamingTests: XCTestCase {

    // MARK: - Fixed "now" for deterministic date-token expansion

    /// 2026-04-23 12:00 UTC — "noon" is safe across all reasonable local timezones
    /// without rolling into the next or previous day.
    private let fixedNow: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 23
        components.hour = 12
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    // MARK: - In-memory counter provider for strategy-level tests

    private final class InMemoryCounters: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Int] = [:]

        func provider() -> @Sendable (_ seriesKey: String) throws -> Int {
            { [weak self] key in
                guard let self else { return 0 }
                return self.lock.withLock {
                    let next = (self.values[key] ?? 0) + 1
                    self.values[key] = next
                    return next
                }
            }
        }

        func value(for key: String) -> Int {
            lock.withLock { values[key] ?? 0 }
        }
    }

    // MARK: - NamingService dispatch

    func testServiceDefaultsToUUIDWhenAutonameIsNil() throws {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Widget", autoname: nil)
        let doc = TestSupport.makeDocument(id: "", docType: "Widget")
        let context = NamingContext(now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertTrue(Self.isUUIDv7(id), "Expected UUID v7 but got \(id)")
    }

    func testServiceDefaultsToUUIDWhenAutonameIsExplicitlyUUID() throws {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Widget", autoname: "UUID")
        let doc = TestSupport.makeDocument(id: "", docType: "Widget")
        let context = NamingContext(now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertTrue(Self.isUUIDv7(id))
    }

    func testServiceThrowsOnUnknownStrategyToken() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Widget", autoname: "frobnicate:anything")
        let doc = TestSupport.makeDocument(id: "", docType: "Widget")
        let context = NamingContext(now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context)) { error in
            guard case NamingError.unknownStrategy(let token) = error else {
                XCTFail("Expected unknownStrategy, got \(error)"); return
            }
            XCTAssertEqual(token, "frobnicate")
        }
    }

    func testServiceAllowsCustomStrategyRegistration() throws {
        struct ConstantStrategy: NamingStrategy {
            var handles: Set<String> { ["constant"] }
            func resolve(docType: DocType, document: Document, argument: String?, context: NamingContext) throws -> String {
                argument ?? "CONSTANT"
            }
        }
        let service = NamingService()
        service.register(ConstantStrategy())
        let docType = TestSupport.makeDocType(id: "Widget", autoname: "constant:FIXED-42")
        let doc = TestSupport.makeDocument(id: "", docType: "Widget")
        let context = NamingContext(now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "FIXED-42")
    }

    // MARK: - UUIDv7Strategy

    func testUUIDv7GeneratesWellFormedTimeOrderedIds() {
        let earlier = UUIDv7Strategy.generate(at: Date(timeIntervalSince1970: 1_700_000_000))
        let later = UUIDv7Strategy.generate(at: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertTrue(Self.isUUIDv7(earlier))
        XCTAssertTrue(Self.isUUIDv7(later))
        // Time-ordered: the earlier 48-bit timestamp prefix must sort before the later one.
        XCTAssertLessThan(earlier, later)
    }

    func testUUIDv7GeneratesUniqueIdsWhenCalledRepeatedly() {
        var seen = Set<String>()
        for _ in 0..<500 {
            seen.insert(UUIDv7Strategy.generate())
        }
        XCTAssertEqual(seen.count, 500, "UUID v7 generator produced collisions")
    }

    // MARK: - NamingSeriesStrategy

    func testNamingSeriesExpandsDateTokensAndCounter() throws {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "SalesInvoice",
            autoname: "naming_series:SINV-.YYYY.-.####"
        )
        let doc = TestSupport.makeDocument(id: "", docType: "SalesInvoice")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "SINV-2026-0001")
        XCTAssertEqual(counters.value(for: "SalesInvoice::SINV-2026-"), 1)
    }

    func testNamingSeriesIncrementsCounterAcrossCalls() throws {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "SalesInvoice",
            autoname: "naming_series:SINV-.YYYY.-.####"
        )
        let doc = TestSupport.makeDocument(id: "", docType: "SalesInvoice")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        let first = try service.resolve(docType: docType, document: doc, context: context)
        let second = try service.resolve(docType: docType, document: doc, context: context)
        let third = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(first, "SINV-2026-0001")
        XCTAssertEqual(second, "SINV-2026-0002")
        XCTAssertEqual(third, "SINV-2026-0003")
    }

    func testNamingSeriesScopesCountersByDocType() throws {
        let counters = InMemoryCounters()
        let service = NamingService()
        let invoice = TestSupport.makeDocType(
            id: "SalesInvoice",
            autoname: "naming_series:INV-.YYYY.-.####"
        )
        let purchase = TestSupport.makeDocType(
            id: "PurchaseOrder",
            autoname: "naming_series:INV-.YYYY.-.####"
        )
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        let a = try service.resolve(
            docType: invoice,
            document: TestSupport.makeDocument(id: "", docType: "SalesInvoice"),
            context: context
        )
        let b = try service.resolve(
            docType: purchase,
            document: TestSupport.makeDocument(id: "", docType: "PurchaseOrder"),
            context: context
        )

        XCTAssertEqual(a, "INV-2026-0001")
        XCTAssertEqual(b, "INV-2026-0001", "Same prefix in a different DocType must not share the counter")
    }

    func testNamingSeriesSupportsAllDateTokens() throws {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Ticket",
            autoname: "naming_series:T-.YY.-.MM.-.DD.-.####"
        )
        let doc = TestSupport.makeDocument(id: "", docType: "Ticket")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "T-26-04-23-0001")
    }

    func testNamingSeriesCounterWidthControlsZeroPadding() throws {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Thing",
            autoname: "naming_series:X-.##"
        )
        let doc = TestSupport.makeDocument(id: "", docType: "Thing")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "X-01")
    }

    func testNamingSeriesThrowsWhenCounterTokenMissing() {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Thing",
            autoname: "naming_series:T-.YYYY."
        )
        let doc = TestSupport.makeDocument(id: "", docType: "Thing")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context)) { error in
            guard case NamingError.invalidNamingSeries = error else {
                XCTFail("Expected invalidNamingSeries, got \(error)"); return
            }
        }
    }

    func testNamingSeriesThrowsOnUnknownDateToken() {
        let counters = InMemoryCounters()
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Thing",
            autoname: "naming_series:T-.BOGUS.-.####"
        )
        let doc = TestSupport.makeDocument(id: "", docType: "Thing")
        let context = NamingContext(now: fixedNow, counterProvider: counters.provider())

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context))
    }

    // MARK: - FieldDerivedStrategy

    func testFieldDerivedUsesFieldValueAsId() throws {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Contact", autoname: "field:email")
        let doc = TestSupport.makeDocument(
            id: "",
            docType: "Contact",
            fields: ["email": .string("alice@example.com")]
        )
        let context = NamingContext(now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "alice@example.com")
    }

    func testFieldDerivedThrowsWhenFieldMissing() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Contact", autoname: "field:email")
        let doc = TestSupport.makeDocument(id: "", docType: "Contact", fields: [:])
        let context = NamingContext(now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context)) { error in
            guard case NamingError.missingFieldValue(let key) = error else {
                XCTFail("Expected missingFieldValue, got \(error)"); return
            }
            XCTAssertEqual(key, "email")
        }
    }

    func testFieldDerivedThrowsOnEmptyStringValue() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Contact", autoname: "field:email")
        let doc = TestSupport.makeDocument(
            id: "",
            docType: "Contact",
            fields: ["email": .string("")]
        )
        let context = NamingContext(now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context))
    }

    // MARK: - PromptStrategy

    func testPromptStrategyUsesUserSuppliedName() throws {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Ledger", autoname: "prompt")
        let doc = TestSupport.makeDocument(id: "", docType: "Ledger")
        let context = NamingContext(userSuppliedName: "Acme Opening Balance", now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "Acme Opening Balance")
    }

    func testPromptStrategyThrowsWhenNameMissing() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(id: "Ledger", autoname: "prompt")
        let doc = TestSupport.makeDocument(id: "", docType: "Ledger")
        let context = NamingContext(userSuppliedName: nil, now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context)) { error in
            XCTAssertEqual(error as? NamingError, NamingError.missingUserSuppliedName)
        }
    }

    // MARK: - FormatStrategy

    func testFormatStrategyInterpolatesFields() throws {
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Subscription",
            autoname: "format:{customer}-{year}"
        )
        let doc = TestSupport.makeDocument(
            id: "",
            docType: "Subscription",
            fields: ["customer": .string("Acme"), "year": .int(2026)]
        )
        let context = NamingContext(now: fixedNow)

        let id = try service.resolve(docType: docType, document: doc, context: context)

        XCTAssertEqual(id, "Acme-2026")
    }

    func testFormatStrategyThrowsOnUnmatchedBrace() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Subscription",
            autoname: "format:{customer"
        )
        let doc = TestSupport.makeDocument(
            id: "",
            docType: "Subscription",
            fields: ["customer": .string("Acme")]
        )
        let context = NamingContext(now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context))
    }

    func testFormatStrategyThrowsOnMissingField() {
        let service = NamingService()
        let docType = TestSupport.makeDocType(
            id: "Subscription",
            autoname: "format:{customer}-{year}"
        )
        let doc = TestSupport.makeDocument(
            id: "",
            docType: "Subscription",
            fields: ["customer": .string("Acme")]
        )
        let context = NamingContext(now: fixedNow)

        XCTAssertThrowsError(try service.resolve(docType: docType, document: doc, context: context))
    }

    // MARK: - DocumentEngine integration

    func testSaveAssignsUUIDv7WhenDocumentIdIsEmpty() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(id: "Note")   // no autoname => UUIDv7 default
        )
        let draft = TestSupport.makeDocument(id: "", docType: "Note")

        let saved = try harness.engine.save(draft)

        XCTAssertFalse(saved.id.isEmpty)
        XCTAssertTrue(Self.isUUIDv7(saved.id), "Expected UUID v7 default, got \(saved.id)")
        XCTAssertNotNil(try harness.engine.fetch(docType: "Note", id: saved.id))
    }

    func testSavePreservesCallerSuppliedId() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(
                id: "Note",
                autoname: "naming_series:N-.YYYY.-.####"
            )
        )
        let explicit = TestSupport.makeDocument(id: "caller-set-id", docType: "Note")

        let saved = try harness.engine.save(explicit)

        XCTAssertEqual(saved.id, "caller-set-id", "Naming must not override a caller-supplied id")
    }

    func testSaveAssignsSequentialSeriesAcrossMultipleDocuments() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(
                id: "SalesInvoice",
                autoname: "naming_series:SINV-.YYYY.-.####"
            )
        )

        // Saves don't let us inject context.now, so we accept whatever the
        // current year is and only assert the counter portion.
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let prefix = "SINV-\(String(format: "%04d", currentYear))-"

        let first = try harness.engine.save(
            TestSupport.makeDocument(id: "", docType: "SalesInvoice")
        )
        let second = try harness.engine.save(
            TestSupport.makeDocument(id: "", docType: "SalesInvoice")
        )
        let third = try harness.engine.save(
            TestSupport.makeDocument(id: "", docType: "SalesInvoice")
        )

        XCTAssertEqual(first.id, "\(prefix)0001")
        XCTAssertEqual(second.id, "\(prefix)0002")
        XCTAssertEqual(third.id, "\(prefix)0003")
    }

    func testSaveCounterSurvivesAcrossEngineInstances() throws {
        let url = TestSupport.tempDatabaseURL("naming-persist")
        defer { TestSupport.cleanUp(databaseURL: url) }

        let database = try TestSupport.makeDatabase(at: url)
        let registry = MetadataRegistry(database: database)
        try registry.register(
            TestSupport.makeDocType(
                id: "SalesInvoice",
                autoname: "naming_series:SINV-.YYYY.-.####"
            )
        )

        let engine1 = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: "d1",
            userId: "u1"
        )
        let first = try engine1.save(TestSupport.makeDocument(id: "", docType: "SalesInvoice"))

        // Fresh engine against the same database — the naming counter row
        // survives because it's persisted in `naming_counters`.
        let engine2 = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: "d1",
            userId: "u1"
        )
        let second = try engine2.save(TestSupport.makeDocument(id: "", docType: "SalesInvoice"))

        XCTAssertTrue(first.id.hasSuffix("0001"))
        XCTAssertTrue(second.id.hasSuffix("0002"))
    }

    func testSaveUsesUserSuppliedNameForPromptAutoname() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(id: "Ledger", autoname: "prompt")
        )
        let draft = TestSupport.makeDocument(id: "", docType: "Ledger")

        let saved = try harness.engine.save(draft, userSuppliedName: "Opening Balance 2026")

        XCTAssertEqual(saved.id, "Opening Balance 2026")
    }

    func testSaveThrowsWhenPromptAutonameReceivesNoName() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(id: "Ledger", autoname: "prompt")
        )
        let draft = TestSupport.makeDocument(id: "", docType: "Ledger")

        XCTAssertThrowsError(try harness.engine.save(draft))
    }

    func testSaveLeavesCounterGapOnValidationFailure() throws {
        // A required field that is absent will fail validation. The counter
        // increment happens before validation (ADR-014 gap-on-failure), so
        // the next successful save skips the burned number.
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(
                id: "SalesInvoice",
                fields: [TestSupport.textField("customer", required: true)],
                autoname: "naming_series:SINV-.YYYY.-.####"
            )
        )
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let prefix = "SINV-\(String(format: "%04d", currentYear))-"

        // Invalid: missing required "customer" field => validation fails.
        let invalid = TestSupport.makeDocument(id: "", docType: "SalesInvoice", fields: [:])
        XCTAssertThrowsError(try harness.engine.save(invalid))

        // Valid save gets counter #2, proving the counter burned on the prior attempt.
        let valid = try harness.engine.save(
            TestSupport.makeDocument(
                id: "",
                docType: "SalesInvoice",
                fields: ["customer": .string("Acme")]
            )
        )
        XCTAssertEqual(valid.id, "\(prefix)0002")
    }

    // MARK: - Helpers

    /// A UUID v7 has the version nibble (`7`) in the 13th character of the
    /// hyphenated 8-4-4-4-12 form (index 14 including dashes).
    private static func isUUIDv7(_ string: String) -> Bool {
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }
}
