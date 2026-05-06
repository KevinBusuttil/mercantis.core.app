//
//  ReportEngineRoleFilterTests.swift
//  mercantis coreTests
//
//  Phase D / item 14 (ADR-049) — `ReportDefinition.allowedRoles` gates
//  visibility through `ReportEngine.availableReports(for:)`.
//

import XCTest
@testable import mercantis_core

final class ReportEngineRoleFilterTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var reportEngine: ReportEngine!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        reportEngine = ReportEngine(documentEngine: harness.engine)
        try harness.registry.register(TestSupport.makeDocType())
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        reportEngine = nil
        harness = nil
    }

    private func register(
        _ id: String,
        name: String,
        allowedRoles: [String]? = nil
    ) {
        reportEngine.register(ReportDefinition(
            id: id,
            name: name,
            docType: "Note",
            columns: ["title"],
            filters: [],
            allowedRoles: allowedRoles
        ))
    }

    func testReportsWithoutAllowedRolesAreVisibleToAnyone() {
        register("a", name: "Always visible", allowedRoles: nil)
        register("b", name: "Empty list",     allowedRoles: [])
        let visible = reportEngine.availableReports(for: ["Stranger"])
        XCTAssertEqual(visible.map(\.id).sorted(), ["a", "b"])
    }

    func testReportRequiresIntersectingRole() {
        register("a", name: "Sales report",
                 allowedRoles: ["Sales Manager", "System Manager"])
        register("b", name: "HR report",
                 allowedRoles: ["HR Manager"])

        let asSales = reportEngine.availableReports(for: ["Sales Manager"])
        XCTAssertEqual(asSales.map(\.id), ["a"])

        let asHR = reportEngine.availableReports(for: ["HR Manager"])
        XCTAssertEqual(asHR.map(\.id), ["b"])

        let asSystem = reportEngine.availableReports(for: ["System Manager"])
        XCTAssertEqual(asSystem.map(\.id), ["a"])
    }

    func testEmptyUserRolesSetCannotSeeRestrictedReports() {
        register("restricted", name: "Restricted", allowedRoles: ["Owner"])
        register("public",     name: "Public", allowedRoles: nil)

        let visible = reportEngine.availableReports(for: [])
        XCTAssertEqual(visible.map(\.id), ["public"])
    }

    func testAvailableReportsAreSortedByName() {
        register("z", name: "Zeta")
        register("a", name: "Alpha")
        register("m", name: "Mu")

        let names = reportEngine.availableReports(for: []).map(\.name)
        XCTAssertEqual(names, ["Alpha", "Mu", "Zeta"])
    }

    // MARK: - Codable round trip

    func testReportDefinitionRoundTripsAllowedRoles() throws {
        let original = ReportDefinition(
            id: "r", name: "R", docType: "Note",
            columns: ["title"], filters: [],
            allowedRoles: ["Sales Manager"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ReportDefinition.self, from: data)
        XCTAssertEqual(decoded.allowedRoles, ["Sales Manager"])
    }

    func testReportDefinitionDecodesLegacyManifestWithoutAllowedRoles() throws {
        // Older manifests don't carry `allowedRoles`. They must still decode.
        let json = """
        {
            "id": "legacy",
            "name": "Legacy",
            "docType": "Note",
            "columns": ["title"],
            "filters": []
        }
        """
        let decoded = try JSONDecoder().decode(
            ReportDefinition.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertNil(decoded.allowedRoles)
    }
}
