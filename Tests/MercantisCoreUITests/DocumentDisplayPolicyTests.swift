//
//  DocumentDisplayPolicyTests.swift
//  MercantisCoreUITests
//
//  Exercises the generic, data-driven display-policy engine that lets a host
//  present Core's lifecycle / workflow states with business-friendly,
//  document-specific wording. The fixture mirrors the shape of the Mercantis
//  Hub mapping (Submitted → Posted / Confirmed / Sent / Active / Released …)
//  so these assertions guard the exact translations the product relies on.
//

import XCTest
@testable import MercantisCore

final class DocumentDisplayPolicyTests: XCTestCase {

    // A representative policy mirroring the Hub wording.
    private let policy = DocumentDisplayPolicy(mappings: [
        "SalesInvoice": DocTypeDisplayMapping(
            statuses: [
                "Submitted": .init(label: "Posted", tone: .brand),
                "Paid": .init(label: "Paid", tone: .success),
            ],
            actions: [
                "Submit": .init(label: "Post Invoice", confirmation: "Posting locks fields and creates entries."),
                "Cancel": .init(label: "Cancel Invoice", confirmation: "Reversal entries will be created."),
            ]
        ),
        "SalesOrder": DocTypeDisplayMapping(
            statuses: ["Submitted": .init(label: "Confirmed", tone: .brand)],
            actions: ["Submit": .init(label: "Confirm Order")]
        ),
        "Quotation": DocTypeDisplayMapping(
            statuses: ["Submitted": .init(label: "Sent", tone: .info)],
            actions: ["Submit": .init(label: "Send Quote")]
        ),
        "StockEntry": DocTypeDisplayMapping(
            statuses: [
                "Submitted": .init(label: "Posted", tone: .brand),
                "Cancelled": .init(label: "Reversed", tone: .danger),
            ],
            actions: ["Submit": .init(label: "Post Stock Movement", confirmation: "Updates stock history.")]
        ),
        "BOM": DocTypeDisplayMapping(
            statuses: ["Submitted": .init(label: "Active", tone: .success)],
            actions: ["Submit": .init(label: "Activate BOM")]
        ),
        "WorkOrder": DocTypeDisplayMapping(
            statuses: [
                "Submitted": .init(label: "Released", tone: .brand),
                "InProgress": .init(label: "In Progress", tone: .info),
            ],
            actions: ["Submit": .init(label: "Release Work Order")]
        ),
        "PaymentEntry": DocTypeDisplayMapping(
            statuses: ["Submitted": .init(label: "Posted", tone: .brand)],
            actions: ["Submit": .init(label: "Post Payment")]
        ),
    ])

    // MARK: - Status display mapping

    func test_status_aliases_resolve_per_doctype() {
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesInvoice", state: "Submitted").label, "Posted")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesOrder", state: "Submitted").label, "Confirmed")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "Quotation", state: "Submitted").label, "Sent")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "StockEntry", state: "Submitted").label, "Posted")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "BOM", state: "Submitted").label, "Active")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "WorkOrder", state: "Submitted").label, "Released")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "WorkOrder", state: "InProgress").label, "In Progress")
    }

    func test_status_lookup_is_case_insensitive() {
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesInvoice", state: "submitted").label, "Posted")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesInvoice", state: "SUBMITTED").label, "Posted")
    }

    func test_status_tones_are_carried_through() {
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesInvoice", state: "Submitted").tone, .brand)
        XCTAssertEqual(policy.statusDisplay(docTypeId: "SalesInvoice", state: "Paid").tone, .success)
        XCTAssertEqual(policy.statusDisplay(docTypeId: "StockEntry", state: "Cancelled").tone, .danger)
    }

    // MARK: - Lifecycle (docStatus) mapping

    func test_lifecycle_maps_docStatus_through_aliases() {
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "SalesInvoice", docStatus: 0).label, "Draft")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "SalesInvoice", docStatus: 1).label, "Posted")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "StockEntry", docStatus: 2).label, "Reversed")
    }

    // MARK: - Action label mapping

    func test_action_aliases_resolve_per_doctype() {
        XCTAssertEqual(policy.actionDisplay(docTypeId: "SalesInvoice", action: "Submit").label, "Post Invoice")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "PaymentEntry", action: "Submit").label, "Post Payment")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "StockEntry", action: "Submit").label, "Post Stock Movement")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "SalesOrder", action: "Submit").label, "Confirm Order")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "Quotation", action: "Submit").label, "Send Quote")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "BOM", action: "Submit").label, "Activate BOM")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "WorkOrder", action: "Submit").label, "Release Work Order")
    }

    func test_ledger_actions_carry_confirmation_copy() {
        XCTAssertTrue(policy.actionDisplay(docTypeId: "SalesInvoice", action: "Submit").requiresConfirmation)
        XCTAssertTrue(policy.actionDisplay(docTypeId: "SalesInvoice", action: "Cancel").requiresConfirmation)
        // A plain transition without configured copy needs no confirmation.
        XCTAssertFalse(policy.actionDisplay(docTypeId: "SalesOrder", action: "Submit").requiresConfirmation)
    }

    // MARK: - Safe fallbacks

    func test_unknown_status_falls_back_to_raw_string() {
        let display = policy.statusDisplay(docTypeId: "SalesInvoice", state: "SomeBespokeState")
        XCTAssertEqual(display.label, "SomeBespokeState")
    }

    func test_unknown_doctype_falls_back_to_raw_string() {
        XCTAssertEqual(policy.statusDisplay(docTypeId: "Unmapped", state: "Whatever").label, "Whatever")
        XCTAssertEqual(policy.actionDisplay(docTypeId: "Unmapped", action: "Frobnicate").label, "Frobnicate")
    }

    func test_empty_status_renders_as_draft() {
        XCTAssertEqual(policy.statusDisplay(docTypeId: "Unmapped", state: "").label, "Draft")
        XCTAssertEqual(policy.statusDisplay(docTypeId: "Unmapped", state: "   ").label, "Draft")
    }

    func test_passthrough_policy_surfaces_everything_verbatim() {
        let pass = DocumentDisplayPolicy.passthrough
        XCTAssertEqual(pass.statusDisplay(docTypeId: "SalesInvoice", state: "Submitted").label, "Submitted")
        XCTAssertEqual(pass.actionDisplay(docTypeId: "SalesInvoice", action: "Submit").label, "Submit")
        XCTAssertFalse(pass.hasMapping(docTypeId: "SalesInvoice"))
    }

    // MARK: - Tone classification fallback

    func test_tone_classification_is_sensible() {
        XCTAssertEqual(DocumentStatusTone.classify("Paid"), .success)
        XCTAssertEqual(DocumentStatusTone.classify("Overdue"), .warning)
        XCTAssertEqual(DocumentStatusTone.classify("Cancelled"), .danger)
        XCTAssertEqual(DocumentStatusTone.classify("Posted"), .brand)
        XCTAssertEqual(DocumentStatusTone.classify("In Progress"), .info)
        XCTAssertEqual(DocumentStatusTone.classify("Draft"), .muted)
        // Unknown strings degrade to a neutral tone rather than crashing.
        XCTAssertEqual(DocumentStatusTone.classify("Xyzzy"), .muted)
    }
}
