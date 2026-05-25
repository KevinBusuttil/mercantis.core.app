//
//  CustomizeWorkspaceSheetTests.swift
//  MercantisCoreUITests
//
//  Covers the small-business-friendly bits of the customize sheet: the
//  label → key derivation and the make-FieldDefinition translation.
//

import XCTest
@testable import MercantisCoreUI
@testable import MercantisCore

final class CustomizeWorkspaceSheetTests: XCTestCase {

    typealias Draft = CustomizeWorkspaceSheet.Draft

    // MARK: - deriveKey

    func testDeriveKeySnakeCasesMultiWordLabels() {
        XCTAssertEqual(Draft.deriveKey(from: "VAT Number"), "vat_number")
        XCTAssertEqual(Draft.deriveKey(from: "Customer  Loyalty   Tier"), "customer_loyalty_tier")
    }

    func testDeriveKeyStripsDiacritics() {
        XCTAssertEqual(Draft.deriveKey(from: "Numéro Fiscal"), "numero_fiscal")
    }

    func testDeriveKeyStripsPunctuationAndSymbols() {
        XCTAssertEqual(Draft.deriveKey(from: "VAT-#1 Number!"), "vat_1_number")
    }

    func testDeriveKeyTrimsTrailingUnderscores() {
        XCTAssertEqual(Draft.deriveKey(from: "Discount %"), "discount")
    }

    func testDeriveKeyDropsLeadingDigits() {
        XCTAssertEqual(Draft.deriveKey(from: "2024 quota"), "quota")
    }

    func testDeriveKeyReturnsEmptyForEmptyLabel() {
        XCTAssertEqual(Draft.deriveKey(from: ""), "")
        XCTAssertEqual(Draft.deriveKey(from: "   "), "")
    }

    // MARK: - makeFieldDefinition

    func testMakeFieldDefinitionDerivesKeyAndCarriesType() throws {
        let draft = Draft(
            label: "VAT Number",
            type: .text,
            required: true,
            insertAfter: "email",
            optionsText: ""
        )
        let definition = try XCTUnwrap(draft.makeFieldDefinition())
        XCTAssertEqual(definition.key, "vat_number")
        XCTAssertEqual(definition.label, "VAT Number")
        XCTAssertEqual(definition.type, .text)
        XCTAssertTrue(definition.required)
        XCTAssertNil(definition.options, "Non-select fields shouldn't carry an options array.")
    }

    func testMakeFieldDefinitionParsesSelectOptionsLineByLine() throws {
        let draft = Draft(
            label: "Tier",
            type: .select,
            required: false,
            insertAfter: nil,
            optionsText: "Bronze\nSilver\n   \nGold"
        )
        let definition = try XCTUnwrap(draft.makeFieldDefinition())
        XCTAssertEqual(definition.type, .select)
        XCTAssertEqual(definition.options, ["Bronze", "Silver", "Gold"])
    }

    func testMakeFieldDefinitionPreservesLockedKeyOnEdit() throws {
        // User created "VAT" → key "vat". Later they rename the label to
        // "VAT Number". The persisted key must stay "vat" so existing
        // documents that store `fields["vat"]` still match.
        let draft = Draft(
            label: "VAT Number",
            type: .text,
            required: false,
            insertAfter: nil,
            optionsText: "",
            lockedKey: "vat"
        )
        let definition = try XCTUnwrap(draft.makeFieldDefinition())
        XCTAssertEqual(definition.key, "vat")
        XCTAssertEqual(definition.label, "VAT Number")
    }

    func testMakeFieldDefinitionReturnsNilForEmptyLabel() {
        let draft = Draft(
            label: "  ",
            type: .text,
            required: false,
            insertAfter: nil,
            optionsText: ""
        )
        XCTAssertNil(draft.makeFieldDefinition())
    }
}
