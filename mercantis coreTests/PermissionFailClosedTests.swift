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

    // MARK: - P1 review fix: explicit operator with no roles fails closed

    /// Independent of the fail-closed flag: an authenticated operator context
    /// that carries no roles must NOT bypass a DocType that declares rules.
    func testExplicitOperatorWithoutRolesIsDeniedOnRuleBearingDocType() throws {
        let h = try TestSupport.makeHarness() // flag OFF on purpose
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        let ctx = ExecutionContext(operatorId: "u", roles: [], deviceId: "d")
        XCTAssertThrowsError(try h.engine.save(invoice("i7"), context: ctx)) { assertPermissionDenied($0) }
    }

    /// The legacy fallback (no caller context) stays permissive for backward
    /// compatibility, even on a rule-bearing DocType, when the flag is off.
    func testLegacyNoContextStaysPermissive() throws {
        let h = try TestSupport.makeHarness() // flag OFF
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        XCTAssertNoThrow(try h.engine.save(invoice("i8")))
    }

    // MARK: - Distinct lifecycle rights (submit / cancel / amend)

    /// A submittable transition consults its own right, not just `.write`: a
    /// role that may create the draft but is not granted submit is denied.
    func testSubmitDeniedForNonGrantingRole() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        let granting = ExecutionContext(operatorId: "u", roles: ["Accountant"], deviceId: "d")
        var doc = try h.engine.save(invoice("L1"), context: granting)
        let nonGranting = ExecutionContext(operatorId: "v", roles: ["Clerk"], deviceId: "d")
        XCTAssertThrowsError(try h.engine.submit(&doc, context: nonGranting)) { assertPermissionDenied($0) }
    }

    /// `canCancel` is distinct from `canSubmit`: a role that may post is not
    /// implicitly allowed to reverse unless it is also granted cancel.
    func testCancelRequiresCancelRightEvenWhenSubmitGranted() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        let postNotReverse = PermissionRule(
            role: "Poster", canRead: true, canWrite: true, canCreate: true,
            canDelete: false, canSubmit: true, canAmend: false, canCancel: false
        )
        try h.registry.register(makeSubmittable(perms: [postNotReverse]))
        let ctx = ExecutionContext(operatorId: "u", roles: ["Poster"], deviceId: "d")
        var doc = try h.engine.save(invoice("L2"), context: ctx)
        try h.engine.submit(&doc, context: ctx) // submit is granted
        if let fetched = try h.engine.fetch(docType: "Invoice", id: "L2") { doc = fetched }
        XCTAssertThrowsError(try h.engine.cancel(&doc, context: ctx)) { assertPermissionDenied($0) }
    }

    /// A fully granted role completes the whole submit → cancel → amend cycle.
    func testGrantingRoleCompletesLifecycle() throws {
        let h = try TestSupport.makeHarness(failClosedForSubmittable: true)
        defer { TestSupport.cleanUp(databaseURL: h.url) }
        try h.registry.register(makeSubmittable(perms: [TestSupport.permissionRule(role: "Accountant")]))
        let ctx = ExecutionContext(operatorId: "u", roles: ["Accountant"], deviceId: "d")
        var doc = try h.engine.save(invoice("L3"), context: ctx)
        XCTAssertNoThrow(try h.engine.submit(&doc, context: ctx))
        if let fetched = try h.engine.fetch(docType: "Invoice", id: "L3") { doc = fetched }
        XCTAssertNoThrow(try h.engine.cancel(&doc, context: ctx))
        if let fetched = try h.engine.fetch(docType: "Invoice", id: "L3") { doc = fetched }
        XCTAssertNoThrow(try h.engine.amend(doc, context: ctx))
    }
}
