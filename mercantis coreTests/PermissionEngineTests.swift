//
//  PermissionEngineTests.swift
//  mercantis coreTests
//
//  Covers the flat PermissionEngine API described in ADR-011 — `canPerform`,
//  `canAccessField`, and the P1.7 expression-backed `canAccessRow`.
//

import XCTest
@testable import mercantis_core

final class PermissionEngineTests: XCTestCase {

    private let engine = PermissionEngine()

    // MARK: - canAccessRow: no-restriction short-circuits

    func testCanAccessRowReturnsTrueWhenExpressionIsNil() {
        let doc = TestSupport.makeDocument()
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: nil
        ))
    }

    func testCanAccessRowReturnsTrueWhenExpressionIsEmpty() {
        let doc = TestSupport.makeDocument()
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: ""
        ))
    }

    func testCanAccessRowReturnsTrueWhenExpressionIsWhitespace() {
        let doc = TestSupport.makeDocument()
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "   \n\t "
        ))
    }

    // MARK: - canAccessRow: document field references

    func testCanAccessRowEvaluatesEqualityOverDocumentField() {
        let doc = TestSupport.makeDocument(fields: ["warehouse": .string("WH-01")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == \"WH-01\""
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == \"WH-02\""
        ))
    }

    func testCanAccessRowSupportsCompoundBooleanExpressions() {
        let doc = TestSupport.makeDocument(fields: [
            "warehouse": .string("WH-01"),
            "status":    .string("Submitted"),
            "total":     .double(15_000)
        ])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == \"WH-01\" && total > 10000"
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == \"WH-02\" || total < 1000"
        ))
    }

    func testCanAccessRowSupportsNumericComparisonsOverFields() {
        let doc = TestSupport.makeDocument(fields: ["total": .double(250)])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "total > 100"
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "total > 1000"
        ))
    }

    func testCanAccessRowSupportsTypedDateComparison() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let doc = TestSupport.makeDocument(fields: [
            "deadline": .dateTime(now),
            "started":  .dateTime(earlier)
        ])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "started < deadline"
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "started > deadline"
        ))
    }

    // MARK: - canAccessRow: user.* namespace

    func testCanAccessRowMatchesOwnerAgainstUserId() {
        let doc = TestSupport.makeDocument(fields: ["owner": .string("alice")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "owner == user.id",
            userId: "alice"
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "owner == user.id",
            userId: "bob"
        ))
    }

    func testCanAccessRowExposesUserIdAsEmptyStringWhenNotProvided() {
        let doc = TestSupport.makeDocument(fields: ["owner": .string("")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "owner == user.id"
        ))
    }

    func testCanAccessRowExposesUserAttributesUnderUserNamespace() {
        let doc = TestSupport.makeDocument(fields: ["warehouse": .string("WH-01")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == user.warehouse",
            userAttributes: ["warehouse": .string("WH-01")]
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "warehouse == user.warehouse",
            userAttributes: ["warehouse": .string("WH-02")]
        ))
    }

    func testCanAccessRowAcceptsAlreadyNamespacedUserAttributeKeys() {
        let doc = TestSupport.makeDocument(fields: ["region": .string("EU")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "region == user.region",
            userAttributes: ["user.region": .string("EU")]
        ))
    }

    func testUserAttributeOverridesStandardUserId() {
        let doc = TestSupport.makeDocument(fields: ["owner": .string("override-id")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "owner == user.id",
            userId: "default-id",
            userAttributes: ["id": .string("override-id")]
        ))
    }

    func testUserNamespaceOverridesDocumentFieldOfSameKey() {
        // A document field named literally "user.id" must not be reachable as
        // `user.id` — the user namespace wins.
        let doc = TestSupport.makeDocument(fields: ["user.id": .string("attacker")])
        XCTAssertTrue(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "user.id == \"alice\"",
            userId: "alice"
        ))
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "user.id == \"attacker\"",
            userId: "alice"
        ))
    }

    // MARK: - canAccessRow: fail-closed on evaluator errors

    /// An undefined identifier resolves to `.null` in the boolean parser and a
    /// `null > 0` comparison evaluates to false — denying access.
    func testCanAccessRowFailsClosedOnUndefinedField() {
        let doc = TestSupport.makeDocument(fields: ["status": .string("Draft")])
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "missing_field > 0"
        ))
    }

    /// A missing RHS leaves the parser with `.null` against `.string`; the
    /// equality short-circuits to false — denying access.
    func testCanAccessRowFailsClosedOnMalformedExpression() {
        let doc = TestSupport.makeDocument(fields: ["status": .string("Draft")])
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "status =="
        ))
    }

    /// Unary minus on a string identifier throws `EvaluatorError.typeMismatch`;
    /// `canAccessRow` swallows the throw and denies.
    func testCanAccessRowFailsClosedWhenEvaluatorThrows() {
        let doc = TestSupport.makeDocument(fields: [
            "status": .string("Draft"),
            "name":   .string("alpha")
        ])
        XCTAssertFalse(engine.canAccessRow(
            document: doc,
            userRoles: [],
            rowExpression: "status == -name"
        ))
    }

    // MARK: - canPerform sanity

    func testCanPerformGrantsWriteWhenRoleMatchesAndRuleAllows() {
        let docType = TestSupport.makeDocType(permissions: [TestSupport.permissionRule(role: "Editor")])
        XCTAssertTrue(engine.canPerform(operation: .write, on: docType, userRoles: ["Editor"]))
    }

    func testCanPerformDeniesWriteWhenNoMatchingRole() {
        let docType = TestSupport.makeDocType(permissions: [TestSupport.permissionRule(role: "Editor")])
        XCTAssertFalse(engine.canPerform(operation: .write, on: docType, userRoles: ["Viewer"]))
    }

    // MARK: - canAccessField sanity

    func testCanAccessFieldReturnsTrueWhenFieldHasNoPermissionBlock() {
        let docType = TestSupport.makeDocType()
        XCTAssertTrue(engine.canAccessField(
            fieldKey: "title",
            on: docType,
            userRoles: ["Anything"],
            operation: .read
        ))
    }

    func testCanAccessFieldEnforcesReadRolesWhenPermissionBlockPresent() {
        let restrictedField = FieldDefinition(
            key: "salary",
            label: "Salary",
            type: .decimal,
            required: false,
            permissions: FieldPermission(readRoles: ["HR"], writeRoles: ["HR"])
        )
        let docType = TestSupport.makeDocType(fields: [restrictedField])
        XCTAssertTrue(engine.canAccessField(
            fieldKey: "salary",
            on: docType,
            userRoles: ["HR"],
            operation: .read
        ))
        XCTAssertFalse(engine.canAccessField(
            fieldKey: "salary",
            on: docType,
            userRoles: ["Sales"],
            operation: .read
        ))
    }
}
