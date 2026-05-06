//
//  DashboardEngineTests.swift
//  mercantis coreTests
//
//  Phase C / §3.10 (ADR-045) — DashboardEngine resolves DashboardWidget
//  declarations against DocumentEngine + ReportEngine into a typed
//  DashboardResult that a UI layer can render.
//

import XCTest
@testable import mercantis_core

final class DashboardEngineTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var dashboardEngine: DashboardEngine!
    private var reportEngine: ReportEngine!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        reportEngine = ReportEngine(documentEngine: harness.engine)
        dashboardEngine = DashboardEngine(
            documentEngine: harness.engine,
            reportEngine: reportEngine
        )
        try harness.registry.register(TestSupport.makeDocType(
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("priority"),
                TestSupport.textField("status"),
            ]
        ))
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        dashboardEngine = nil
        reportEngine = nil
        harness = nil
    }

    // MARK: - Helpers

    private func saveNote(_ id: String, priority: Int, status: String = "Open") throws {
        var doc = TestSupport.makeDocument(
            id: id,
            fields: [
                "title": .string(id),
                "priority": .int(priority),
                "status": .string(status),
            ]
        )
        doc.status = status
        try harness.engine.save(doc)
    }

    // MARK: - Resolution

    func testCountWidgetReturnsTotalDocumentsForDocType() throws {
        try saveNote("a", priority: 1)
        try saveNote("b", priority: 2)
        try saveNote("c", priority: 3)

        let dashboard = DashboardDefinition(id: "home", name: "Home", widgets: [
            DashboardWidget(type: "count", title: "Open notes", docType: "Note", parameters: [:])
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "home")
        XCTAssertEqual(result.dashboardName, "Home")
        XCTAssertEqual(result.widgets.count, 1)
        guard case let .count(_, value, docType) = result.widgets[0] else {
            return XCTFail("expected count case, got \(result.widgets[0])")
        }
        XCTAssertEqual(value, 3)
        XCTAssertEqual(docType, "Note")
    }

    func testCountWidgetAppliesEqualityFilterFromParameters() throws {
        try saveNote("a", priority: 1, status: "Open")
        try saveNote("b", priority: 2, status: "Closed")
        try saveNote("c", priority: 3, status: "Open")

        let dashboard = DashboardDefinition(id: "open", name: "Open", widgets: [
            DashboardWidget(
                type: "count", title: "Open",
                docType: "Note", parameters: ["status": "Open"]
            )
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "open")
        guard case let .count(_, value, _) = result.widgets[0] else {
            return XCTFail("expected count case")
        }
        XCTAssertEqual(value, 2)
    }

    func testCountWidgetAppliesOperatorFilterFromWhereParameter() throws {
        try saveNote("low",  priority: 1)
        try saveNote("mid",  priority: 5)
        try saveNote("high", priority: 9)

        let dashboard = DashboardDefinition(id: "p", name: "P", widgets: [
            DashboardWidget(
                type: "count", title: "Big",
                docType: "Note", parameters: ["where.priority__gt": "3"]
            )
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "p")
        guard case let .count(_, value, _) = result.widgets[0] else {
            return XCTFail("expected count case")
        }
        XCTAssertEqual(value, 2)
    }

    func testListWidgetReturnsExplicitColumnsAndRespectsLimit() throws {
        try saveNote("a", priority: 1)
        try saveNote("b", priority: 2)
        try saveNote("c", priority: 3)

        let dashboard = DashboardDefinition(id: "list", name: "List", widgets: [
            DashboardWidget(
                type: "list", title: "Recent notes",
                docType: "Note",
                parameters: ["columns": "id,title", "limit": "2"]
            )
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "list")
        guard case let .list(_, columns, rows, _) = result.widgets[0] else {
            return XCTFail("expected list case")
        }
        XCTAssertEqual(columns, ["id", "title"])
        XCTAssertEqual(rows.count, 2)
    }

    func testChartWidgetExecutesUnderlyingReport() throws {
        try saveNote("a", priority: 5)
        try saveNote("b", priority: 7)

        let report = ReportDefinition(
            id: "priority-report", name: "Priorities", docType: "Note",
            columns: ["title", "priority"], filters: []
        )
        reportEngine.register(report)

        let dashboard = DashboardDefinition(id: "charts", name: "Charts", widgets: [
            DashboardWidget(
                type: "chart", title: "Priority chart",
                reportId: "priority-report", parameters: [:]
            )
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "charts")
        guard case let .chart(_, columns, rows, reportId) = result.widgets[0] else {
            return XCTFail("expected chart case")
        }
        XCTAssertEqual(columns, ["title", "priority"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(reportId, "priority-report")
    }

    func testChartWidgetReportsErrorWhenReportEngineMissing() throws {
        let bare = DashboardEngine(documentEngine: harness.engine, reportEngine: nil)
        bare.register(DashboardDefinition(id: "d", name: "D", widgets: [
            DashboardWidget(type: "chart", title: "X", reportId: "anything", parameters: [:])
        ]))

        let result = try bare.resolve(dashboardId: "d")
        guard case let .error(_, reason) = result.widgets[0] else {
            return XCTFail("expected error case")
        }
        XCTAssertTrue(reason.contains("ReportEngine"))
    }

    func testShortcutWidgetCarriesTargetForRouting() throws {
        let dashboard = DashboardDefinition(id: "s", name: "S", widgets: [
            DashboardWidget(
                type: "shortcut", title: "Open all notes",
                docType: "Note", parameters: ["target": "/notes"]
            )
        ])
        dashboardEngine.register(dashboard)

        let result = try dashboardEngine.resolve(dashboardId: "s")
        guard case let .shortcut(_, target) = result.widgets[0] else {
            return XCTFail("expected shortcut case")
        }
        XCTAssertEqual(target, "/notes")
    }

    func testUnknownDashboardThrows() {
        XCTAssertThrowsError(try dashboardEngine.resolve(dashboardId: "nope")) { error in
            guard case DashboardEngine.DashboardEngineError.unknownDashboard = error else {
                return XCTFail("expected unknownDashboard, got \(error)")
            }
        }
    }

    func testUnknownWidgetTypeBecomesErrorWidget() throws {
        dashboardEngine.register(DashboardDefinition(id: "d", name: "D", widgets: [
            DashboardWidget(type: "carousel", title: "Bad widget", parameters: [:])
        ]))
        let result = try dashboardEngine.resolve(dashboardId: "d")
        guard case let .error(title, reason) = result.widgets[0] else {
            return XCTFail("expected error case")
        }
        XCTAssertEqual(title, "Bad widget")
        XCTAssertTrue(reason.contains("Unknown widget type"))
    }
}
