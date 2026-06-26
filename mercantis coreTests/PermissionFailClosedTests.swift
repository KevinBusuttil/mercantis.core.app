//
//  PermissionFailClosedTests.swift
//  mercantis coreTests
//
//  Phase 0 / P0.4 — when a deployment opts in, submittable (financial)
//  DocTypes are fail-CLOSED: an unauthenticated write, or a DocType with no
//  permission rules, is denied rather than silently allowed. The legacy
//  permissive behaviour is preserved when the flag is off and for
//  non-submittable masters.
//

import XCTest
@testable import mercantis_core

final class PermissionFailClosedTests: XCTestCase {

    private func makeSubmittable(perms: [PermissionRule]) -> DocType {
        TestSupport.makeDocType(
            id: "Invoice",
            fields: [TestSupport.textField("title", required: true)],
            permissions: perms,
            isSubmittable: true,
            syncPolicy: TestSupport.submittableSyncPolicy()
        )
    }

    private func invoice(_ id: String) -> Document {
        TestSupport.makeDocument(id: id, docType: "Invoice", fields: ["title": .string("X")])
    }

    private func assertPermissionDenied(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case DocumentEngineError.validationFailed(let errors) = error else {
            return XCTFail("expected validationFailed, got \(error)", file: file, line: line)
        }
        XCTAssertTrue(
            errors.contains { $0.stage == "Permission" },
            "expected a Permission-stage denial; got \(errors.map { $0.stage })",
            file: file, line: line
        )
    }

    func testFlagOffKeepsLegacyPermissiveBehaviour() throws {
        let h = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: []))
        // Submittable, no rules, no operator — legacy behaviour still allows it.
        XCTAssertNoThrow(try h.engine.save(invoice("i1")))
    }

    func testFailClosedDeniesSubmittableWithoutOperator() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        XCTAssertThrowsError(try h.engine.save(invoice("i2"))) { assertPermissionDenied($0) }
    }

    func testFailClosedDeniesSubmittableWithNoRules() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: []))
        let ctx = ExecutionContext(operatorId: "u", roles: ["Accountant"], deviceId: "d")
        XCTAssertThrowsError(try h.engine.save(invoice("i3"), context: ctx)) { assertPermissionDenied($0) }
    }

    func testFailClosedAllowsGrantingRole() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        let ctx = ExecutionContext(operatorId: "u", roles: ["Accountant"], deviceId: "d")
        XCTAssertNoThrow(try h.engine.save(invoice("i4"), context: ctx))
    }

    func testFailClosedDeniesNonGrantingRole() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        let ctx = ExecutionContext(operatorId: "u", roles: ["Clerk"], deviceId: "d")
        XCTAssertThrowsError(try h.engine.save(invoice("i5"), context: ctx)) { assertPermissionDenied($0) }
    }

    func testFailClosedAllowsExplicitSystemOperation() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: []))
        let ctx = ExecutionContext.system(deviceId: "d")
        XCTAssertNoThrow(try h.engine.save(invoice("i6"), context: ctx))
    }

    func testFailClosedIgnoresNonSubmittableMasters() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(TestSupport.makeDocType(id: "Note", permissions: []))
        XCTAssertNoThrow(try h.engine.save(TestSupport.makeDocument(id: "n1", fields: ["title": .string("X")])))
    }
}
