//
//  SavedReportEngineTests.swift
//  mercantis coreTests
//
//  Saved-report infrastructure (ADR-050): configuration, conversion from a
//  built-in `ReportDefinition`, and execution into a `ReportResult`.
//

import XCTest
@testable import mercantis_core

final class SavedReportEngineTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var engine: SavedReportEngine!

    private let docTypeId = "Invoice"

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness(userId: "alice")
        engine = SavedReportEngine(documentEngine: harness.engine, registry: harness.registry)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        engine = nil
        harness = nil
    }

    // MARK: - Fixtures

    /// Register the `Invoice` DocType and seed three documents.
    private func seed() throws {
        let docType = TestSupport.makeDocType(
            id: docTypeId,
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("amount"),
                TestSupport.textField("city")
            ],
            titleField: "title"
        )
        try harness.registry.register(docType)

        try save(title: "Alpha", amount: 100, city: "Valletta")
        try save(title: "Beta",  amount: 50,  city: "Sliema")
        try save(title: "Gamma", amount: 200, city: "Valletta")
    }

    private func save(title: String, amount: Int, city: String) throws {
        let doc = TestSupport.makeDocument(
            docType: docTypeId,
            fields: [
                "title": .string(title),
                "amount": .int(amount),
                "city": .string(city)
            ]
        )
        try harness.engine.save(doc)
    }

    private func column(_ key: String, order: Int, visible: Bool = true, label: String? = nil) -> SavedReportColumn {
        SavedReportColumn(fieldKey: key, labelOverride: label, visible: visible, order: order)
    }

    private func makeReport(
        columns: [SavedReportColumn],
        filters: [SavedReportFilter] = [],
        sorts: [SavedReportSort] = [],
        owner: String = "alice",
        visibility: SavedReportVisibility = .private
    ) -> SavedReportDefinition {
        SavedReportDefinition(
            id: "saved-1",
            name: "My Invoices",
            baseReportId: nil,
            sourceDocType: docTypeId,
            ownerUserId: owner,
            visibility: visibility,
            columns: columns,
            filters: filters,
            sorts: sorts
        )
    }

    // MARK: - Conversion

    func testConvertBuiltInReportClonesColumnsAndFilters() throws {
        let builtIn = ReportDefinition(
            id: "builtin-invoices",
            name: "Invoices",
            docType: docTypeId,
            columns: ["title", "amount", "city"],
            filters: [
                ReportFilter(fieldKey: "city", label: "City", defaultValue: .string("Valletta"))
            ],
            allowedRoles: ["Accounts Manager"]
        )

        let saved = engine.convert(builtIn, id: "saved-x", ownerUserId: "alice")

        XCTAssertEqual(saved.baseReportId, "builtin-invoices")
        XCTAssertEqual(saved.sourceDocType, docTypeId)
        XCTAssertEqual(saved.name, "Invoices")
        XCTAssertEqual(saved.ownerUserId, "alice")
        XCTAssertEqual(saved.visibility, .private)

        // Columns cloned in declaration order, all visible.
        XCTAssertEqual(saved.columns.map(\.fieldKey), ["title", "amount", "city"])
        XCTAssertEqual(saved.columns.map(\.order), [0, 1, 2])
        XCTAssertTrue(saved.columns.allSatisfy(\.visible))

        // Filter cloned with the built-in default seeded.
        XCTAssertEqual(saved.filters.count, 1)
        XCTAssertEqual(saved.filters[0].fieldKey, "city")
        XCTAssertEqual(saved.filters[0].op, .equals)
        XCTAssertEqual(saved.filters[0].defaultValue, .string("Valletta"))

        // Convert registers it so the engine can find it again.
        XCTAssertEqual(engine.get("saved-x")?.id, "saved-x")
    }

    // MARK: - Execution

    func testExecuteReturnsVisibleColumnsAndRows() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0), column("amount", order: 1)],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.columns, ["title", "amount"])
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(result.rows, [
            ["Alpha", "100"],
            ["Beta", "50"],
            ["Gamma", "200"]
        ])
    }

    func testHiddenColumnsAreExcluded() throws {
        try seed()
        let report = makeReport(
            columns: [
                column("title", order: 0),
                column("amount", order: 1, visible: false),
                column("city", order: 2)
            ],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.columns, ["title", "city"])
        XCTAssertEqual(result.rows.first, ["Alpha", "Valletta"])
    }

    func testColumnsAreRenderedInOrder() throws {
        try seed()
        // Declared amount-before-title but ordered title-first.
        let report = makeReport(
            columns: [column("amount", order: 1), column("title", order: 0)],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.columns, ["title", "amount"])
        XCTAssertEqual(result.rows.first, ["Alpha", "100"])
    }

    func testLabelOverrideBecomesColumnHeader() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0, label: "Invoice Name")],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.columns, ["Invoice Name"])
    }

    // MARK: - Filters

    func testStoredFilterValueIsApplied() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "city", op: .equals, value: .string("Valletta"))],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.rows, [["Alpha"], ["Gamma"]])
    }

    func testDefaultFilterValueIsUsedWhenNoValueOrOverride() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(
                fieldKey: "city", op: .equals, value: nil, defaultValue: .string("Sliema")
            )],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.rows, [["Beta"]])
    }

    func testRuntimeOverrideBeatsStoredAndDefault() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(
                fieldKey: "city", op: .equals,
                value: .string("Sliema"), defaultValue: .string("Sliema")
            )],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(
            savedReport: report,
            runtimeFilterValues: ["city": .string("Valletta")]
        )

        XCTAssertEqual(result.rows, [["Alpha"], ["Gamma"]])
    }

    func testComparisonOperatorFilter() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "amount", op: .greaterThanOrEqual, value: .int(100))],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.rows, [["Alpha"], ["Gamma"]])
    }

    func testContainsFilter() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "city", op: .contains, value: .string("etta"))],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.rows, [["Alpha"], ["Gamma"]])
    }

    func testOptionalFilterWithoutValueIsSkipped() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "city", op: .equals, required: false)],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        // No value anywhere → filter ignored, all rows returned.
        XCTAssertEqual(result.rowCount, 3)
    }

    func testRequiredFilterWithoutValueThrows() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "city", op: .equals, required: true)]
        )

        XCTAssertThrowsError(try engine.execute(savedReport: report)) { error in
            XCTAssertEqual(error as? SavedReportError, .missingRequiredFilter(fieldKey: "city"))
        }
    }

    // MARK: - Sorting

    func testSortDescendingIsApplied() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0), column("amount", order: 1)],
            sorts: [SavedReportSort(fieldKey: "amount", direction: .descending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.rows.map { $0[0] }, ["Gamma", "Alpha", "Beta"])
    }

    // MARK: - Validation

    func testUnknownColumnFieldThrows() throws {
        try seed()
        let report = makeReport(columns: [column("nope", order: 0)])

        XCTAssertThrowsError(try engine.execute(savedReport: report)) { error in
            XCTAssertEqual(
                error as? SavedReportError,
                .unknownField(fieldKey: "nope", docType: docTypeId)
            )
        }
    }

    func testUnknownFilterFieldThrows() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            filters: [SavedReportFilter(fieldKey: "ghost", op: .isNotNull)]
        )

        XCTAssertThrowsError(try engine.execute(savedReport: report)) { error in
            XCTAssertEqual(
                error as? SavedReportError,
                .unknownField(fieldKey: "ghost", docType: docTypeId)
            )
        }
    }

    func testSystemColumnIsAllowed() throws {
        try seed()
        // `id` is a system column, not a declared field, but is valid.
        let report = makeReport(
            columns: [column("id", order: 0), column("title", order: 1)],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)]
        )

        let result = try engine.execute(savedReport: report)

        XCTAssertEqual(result.columns, ["id", "title"])
        XCTAssertEqual(result.rowCount, 3)
    }

    func testUnregisteredDocTypeThrows() throws {
        let report = SavedReportDefinition(
            name: "Ghost report",
            sourceDocType: "Ghost",
            ownerUserId: "alice",
            columns: [column("title", order: 0)]
        )

        XCTAssertThrowsError(try engine.execute(savedReport: report)) { error in
            XCTAssertEqual(error as? SavedReportError, .docTypeNotRegistered("Ghost"))
        }
    }

    func testNoVisibleColumnsThrows() throws {
        try seed()
        let report = makeReport(columns: [column("title", order: 0, visible: false)])

        XCTAssertThrowsError(try engine.execute(savedReport: report)) { error in
            XCTAssertEqual(error as? SavedReportError, .noVisibleColumns(savedReportId: "saved-1"))
        }
    }

    // MARK: - Ownership / sharing

    func testPrivateReportRejectsOtherUser() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            owner: "alice",
            visibility: .private
        )

        XCTAssertThrowsError(
            try engine.execute(savedReport: report, requestingUserId: "bob")
        ) { error in
            XCTAssertEqual(
                error as? SavedReportError,
                .notAuthorized(savedReportId: "saved-1", userId: "bob")
            )
        }
    }

    func testSharedReportAllowsAnyUser() throws {
        try seed()
        let report = makeReport(
            columns: [column("title", order: 0)],
            sorts: [SavedReportSort(fieldKey: "title", direction: .ascending)],
            owner: "alice",
            visibility: .shared
        )

        let result = try engine.execute(savedReport: report, requestingUserId: "bob")
        XCTAssertEqual(result.rowCount, 3)
    }

    func testAccessibleSavedReportsHonourVisibility() {
        engine.register(makeReport(columns: [column("title", order: 0)], owner: "alice", visibility: .private))
        engine.register(SavedReportDefinition(
            id: "shared-1", name: "Shared", sourceDocType: docTypeId,
            ownerUserId: "carol", visibility: .shared,
            columns: [column("title", order: 0)]
        ))
        engine.register(SavedReportDefinition(
            id: "bob-private", name: "Bob only", sourceDocType: docTypeId,
            ownerUserId: "bob", visibility: .private,
            columns: [column("title", order: 0)]
        ))

        let forAlice = engine.accessibleSavedReports(forUserId: "alice").map(\.id)
        XCTAssertEqual(Set(forAlice), Set(["saved-1", "shared-1"]))

        let forBob = engine.accessibleSavedReports(forUserId: "bob").map(\.id)
        XCTAssertEqual(Set(forBob), Set(["bob-private", "shared-1"]))
    }

    // MARK: - Codable

    func testSavedReportRoundTrips() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SavedReportDefinition(
            id: "rt",
            name: "Round Trip",
            baseReportId: "builtin",
            sourceDocType: docTypeId,
            ownerUserId: "alice",
            visibility: .shared,
            columns: [
                column("title", order: 0, label: "Name"),
                column("amount", order: 1, visible: false)
            ],
            filters: [SavedReportFilter(
                fieldKey: "city", op: .contains,
                value: .string("V"), defaultValue: .string("Valletta"), required: true
            )],
            sorts: [SavedReportSort(fieldKey: "amount", direction: .descending)],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedReportDefinition.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLenientDecodeFillsDefaults() throws {
        // A minimal payload omitting visibility / collections / timestamps.
        let json = """
        {
            "id": "min",
            "name": "Minimal",
            "sourceDocType": "Invoice",
            "ownerUserId": "alice",
            "columns": [{ "fieldKey": "title", "order": 0 }]
        }
        """
        let decoded = try JSONDecoder().decode(SavedReportDefinition.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.visibility, .private)
        XCTAssertTrue(decoded.filters.isEmpty)
        XCTAssertTrue(decoded.sorts.isEmpty)
        XCTAssertEqual(decoded.columns.count, 1)
        XCTAssertTrue(decoded.columns[0].visible)   // defaulted true
    }

    // MARK: - Built-in report path unchanged

    func testBuiltInReportEngineStillWorks() throws {
        try seed()
        let reportEngine = ReportEngine(documentEngine: harness.engine)
        let report = ReportDefinition(
            id: "r", name: "All Invoices", docType: docTypeId,
            columns: ["title", "amount"], filters: []
        )
        reportEngine.register(report)

        let result = try reportEngine.execute(report: report)
        XCTAssertEqual(result.columns, ["title", "amount"])
        XCTAssertEqual(result.rowCount, 3)
    }
}
