//
//  DocumentNamingRuleTests.swift
//  mercantis coreTests
//
//  Phase B §3.6 (ADR-040) — DocumentNamingRule selects the autoname spec
//  based on document field values. Lower priority wins; first match wins.
//  Fall through to DocType.autoname when no rule matches.
//

import XCTest
@testable import mercantis_core

final class DocumentNamingRuleTests: XCTestCase {

    private final class InMemoryCounters {
        private let lock = NSLock()
        private var values: [String: Int] = [:]
        func provider() -> @Sendable (_ seriesKey: String) throws -> Int {
            { [self] key in
                lock.lock(); defer { lock.unlock() }
                values[key, default: 0] += 1
                return values[key] ?? 0
            }
        }
    }

    private func makeDocType(
        autoname: String? = "naming_series:DEFAULT-.####",
        rules: [DocumentNamingRule] = []
    ) -> DocType {
        DocType(
            id: "Invoice",
            name: "Invoice",
            module: "Sales",
            appId: "app.test",
            isChildTable: false,
            fields: [
                FieldDefinition(key: "company", label: "Company", type: .text, required: false),
                FieldDefinition(key: "amount",  label: "Amount",  type: .number, required: false),
            ],
            permissions: [],
            autoname: autoname,
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: [],
            titleField: "company",
            namingRules: rules
        )
    }

    private func makeDoc(_ fields: [String: FieldValue] = [:]) -> Document {
        Document(
            id: "",
            docType: "Invoice",
            company: "",
            status: "",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
    }

    func testFirstMatchingRuleWinsByPriorityOrder() throws {
        let counters = InMemoryCounters()
        let docType = makeDocType(rules: [
            DocumentNamingRule(id: "acme",     priority: 10,  condition: "company == \"ACME\"",
                               autoname: "naming_series:SINV-ACME-.####"),
            DocumentNamingRule(id: "widgets",  priority: 20,  condition: "company == \"WIDGETS\"",
                               autoname: "naming_series:SINV-WID-.####"),
        ])
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let acme = try service.resolve(
            docType: docType,
            document: makeDoc(["company": .string("ACME")]),
            context: context
        )
        XCTAssertTrue(acme.hasPrefix("SINV-ACME-"))

        let widgets = try service.resolve(
            docType: docType,
            document: makeDoc(["company": .string("WIDGETS")]),
            context: context
        )
        XCTAssertTrue(widgets.hasPrefix("SINV-WID-"))
    }

    func testLowestPriorityNumberRunsFirst() throws {
        let counters = InMemoryCounters()
        // Two rules both match; priority 5 should win over priority 10.
        let docType = makeDocType(rules: [
            DocumentNamingRule(id: "loose", priority: 10, condition: nil,
                               autoname: "naming_series:LOOSE-.####"),
            DocumentNamingRule(id: "tight", priority: 5,  condition: "amount > 1000",
                               autoname: "naming_series:LARGE-.####"),
        ])
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let resolved = try service.resolve(
            docType: docType,
            document: makeDoc(["amount": .double(5000)]),
            context: context
        )
        XCTAssertTrue(resolved.hasPrefix("LARGE-"))
    }

    func testNilConditionMatchesEveryDocumentAsCatchAll() throws {
        let counters = InMemoryCounters()
        let docType = makeDocType(rules: [
            DocumentNamingRule(id: "specific", priority: 1, condition: "company == \"ACME\"",
                               autoname: "naming_series:ACME-.####"),
            DocumentNamingRule(id: "catchall", priority: 99, condition: nil,
                               autoname: "naming_series:CATCH-.####"),
        ])
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let resolved = try service.resolve(
            docType: docType,
            document: makeDoc(["company": .string("Other")]),
            context: context
        )
        XCTAssertTrue(resolved.hasPrefix("CATCH-"))
    }

    func testFallsThroughToDocTypeAutonameWhenNoRuleMatches() throws {
        let counters = InMemoryCounters()
        let docType = makeDocType(
            autoname: "naming_series:FALLBACK-.####",
            rules: [
                DocumentNamingRule(id: "only", priority: 1, condition: "company == \"NEVER\"",
                                   autoname: "naming_series:NEVER-.####"),
            ]
        )
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let resolved = try service.resolve(
            docType: docType,
            document: makeDoc(["company": .string("Other")]),
            context: context
        )
        XCTAssertTrue(resolved.hasPrefix("FALLBACK-"))
    }

    func testMalformedConditionFailsClosedAndContinues() throws {
        let counters = InMemoryCounters()
        // First rule has a malformed condition; runner should silently skip it
        // and fall through to the next.
        let docType = makeDocType(rules: [
            DocumentNamingRule(id: "broken",  priority: 1,
                               condition: "company == ", // syntactically incomplete
                               autoname: "naming_series:BROKEN-.####"),
            DocumentNamingRule(id: "ok",      priority: 2,
                               condition: nil,
                               autoname: "naming_series:OK-.####"),
        ])
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let resolved = try service.resolve(
            docType: docType,
            document: makeDoc(["company": .string("Anything")]),
            context: context
        )
        XCTAssertTrue(resolved.hasPrefix("OK-"))
    }

    func testEmptyRulesArrayUsesDocTypeAutoname() throws {
        let counters = InMemoryCounters()
        let docType = makeDocType(autoname: "naming_series:DEFAULT-.####", rules: [])
        let service = NamingService()
        let context = NamingContext(now: Date(), counterProvider: counters.provider())

        let resolved = try service.resolve(
            docType: docType,
            document: makeDoc(),
            context: context
        )
        XCTAssertTrue(resolved.hasPrefix("DEFAULT-"))
    }
}
