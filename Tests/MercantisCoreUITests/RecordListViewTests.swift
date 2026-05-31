//
//  RecordListViewTests.swift
//  MercantisCoreUITests
//
//  Unit coverage for the headless list-view model (RecordListFilter /
//  RecordListViewDefinition / DateRangePreset) that drives GenericListView's
//  filter bar, plus a smoke test that GenericListView instantiates with the
//  new saved-view / link-provider surface.
//

import XCTest
import SwiftUI
import MercantisCore
import MercantisCoreUI

final class RecordListViewTests: XCTestCase {

    // MARK: - Fixtures

    private func doc(
        id: String,
        status: String = "",
        docStatus: Int = 0,
        fields: [String: FieldValue] = [:],
        updatedAt: Date = Date()
    ) -> Document {
        Document(
            id: id, docType: "SalesInvoice", company: "", status: status,
            createdAt: Date(), updatedAt: updatedAt, syncVersion: 0, syncState: .local,
            docStatus: docStatus, fields: fields, children: [:]
        )
    }

    // MARK: - RecordListFilter: predicates

    func testEqualityOnSystemColumnAndField() {
        let d = doc(id: "A", status: "Paid", docStatus: 1, fields: ["customer": .string("Acme")])
        XCTAssertTrue(RecordListFilter.matches(ListFilter("status", .eq(.string("Paid"))), d))
        XCTAssertFalse(RecordListFilter.matches(ListFilter("status", .eq(.string("Draft"))), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("docStatus", .eq(.int(1))), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("customer", .eq(.string("Acme"))), d))
    }

    func testNumericComparisonsWithIntDoubleCoercion() {
        let d = doc(id: "A", fields: ["outstanding_amount": .double(150)])
        XCTAssertTrue(RecordListFilter.matches(ListFilter("outstanding_amount", .gt(.double(0))), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("outstanding_amount", .gte(.int(150))), d))
        XCTAssertFalse(RecordListFilter.matches(ListFilter("outstanding_amount", .lt(.double(100))), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("outstanding_amount", .between(.int(100), .int(200))), d))
    }

    func testBooleanIsNotCoercedToNumber() {
        let d = doc(id: "A", fields: ["is_stock_item": .bool(true)])
        XCTAssertTrue(RecordListFilter.matches(ListFilter("is_stock_item", .eq(.bool(true))), d))
        XCTAssertFalse(RecordListFilter.matches(ListFilter("is_stock_item", .eq(.bool(false))), d))
        // .bool(true) must NOT equal .int(1)
        XCTAssertFalse(RecordListFilter.matches(ListFilter("is_stock_item", .eq(.int(1))), d))
    }

    func testLikeAndInAndNullness() {
        let d = doc(id: "A", fields: ["customer": .string("Acme Corp")])
        XCTAssertTrue(RecordListFilter.matches(ListFilter("customer", .like("%cme%")), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("customer", .in([.string("Acme Corp"), .string("X")])), d))
        XCTAssertFalse(RecordListFilter.matches(ListFilter("customer", .in([.string("X")])), d))
        // Empty string and missing key both read as null-ish.
        XCTAssertTrue(RecordListFilter.matches(ListFilter("missing", .isNull), d))
        XCTAssertTrue(RecordListFilter.matches(ListFilter("customer", .isNotNull), d))
    }

    func testMatchesAllIsAndSemantics() {
        let d = doc(id: "A", status: "Submitted", docStatus: 1, fields: ["outstanding_amount": .double(50)])
        let preds = [
            ListFilter("docStatus", .eq(.int(1))),
            ListFilter("outstanding_amount", .gt(.double(0)))
        ]
        XCTAssertTrue(RecordListFilter.matchesAll(preds, d))
        let preds2 = preds + [ListFilter("status", .eq(.string("Paid")))]
        XCTAssertFalse(RecordListFilter.matchesAll(preds2, d))
    }

    // MARK: - RecordListFilter: sorting

    func testSortByUpdatedDescendingAndTitleAscending() {
        let old = doc(id: "old", fields: ["customer": .string("Bravo")], updatedAt: Date(timeIntervalSince1970: 1000))
        let new = doc(id: "new", fields: ["customer": .string("Alpha")], updatedAt: Date(timeIntervalSince1970: 2000))
        let byUpdatedDesc = [old, new].sorted {
            RecordListFilter.areInIncreasingOrder($0, $1, by: [ListSort(fieldKey: "updatedAt", direction: .descending)])
        }
        XCTAssertEqual(byUpdatedDesc.map(\.id), ["new", "old"])

        let byCustomerAsc = [old, new].sorted {
            RecordListFilter.areInIncreasingOrder($0, $1, by: [ListSort(fieldKey: "customer", direction: .ascending)])
        }
        XCTAssertEqual(byCustomerAsc.map(\.id), ["new", "old"]) // Alpha < Bravo
    }

    // MARK: - DateRangePreset

    func testDateRangePresetProducesBetweenPredicate() {
        let preset = DateRangePreset.thisMonth
        let predicate = preset.predicate(fieldKey: "createdAt")
        XCTAssertEqual(predicate.fieldKey, "createdAt")
        if case .between(let lo, let hi) = predicate.op,
           case .date(let start) = lo, case .date(let end) = hi {
            XCTAssertLessThanOrEqual(start, end)
        } else {
            XCTFail("Expected a between(date, date) predicate")
        }
    }

    func testTodayRangeContainsNow() {
        let now = Date()
        let r = DateRangePreset.today.range(now: now)
        XCTAssertLessThanOrEqual(r.start, now)
        XCTAssertGreaterThanOrEqual(r.end, now)
    }

    // MARK: - RecordListViewDefinition

    func testAllViewHasNoPredicates() {
        let all = RecordListViewDefinition.all()
        XCTAssertEqual(all.id, "all")
        XCTAssertTrue(all.predicates.isEmpty)
        XCTAssertTrue(all.isBuiltIn)
    }

    // MARK: - GenericListView smoke (new surface)

    func testGenericListViewInstantiatesWithSavedViewsAndProviders() {
        let docType = DocType(
            id: "SalesInvoice", name: "Sales Invoice", module: "Selling",
            appId: "app.test", isChildTable: false, isSubmittable: true,
            fields: [
                FieldDefinition(key: "customer", label: "Customer", type: .link,
                                required: true, linkedDocType: "Customer"),
                FieldDefinition(key: "outstanding_amount", label: "Outstanding", type: .currency, required: false)
            ],
            permissions: [],
            syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
            indexes: [], searchFields: ["customer"], titleField: "customer"
        )
        let documents = [
            doc(id: "INV-1", status: "Paid", docStatus: 1, fields: ["customer": .string("Acme")]),
            doc(id: "INV-2", status: "Submitted", docStatus: 1, fields: ["outstanding_amount": .double(99)])
        ]
        let views: [RecordListViewDefinition] = [
            .all(),
            RecordListViewDefinition(id: "outstanding", label: "Outstanding",
                                     predicates: [ListFilter("outstanding_amount", .gt(.double(0)))])
        ]
        let list = GenericListView(
            docType: docType,
            documents: documents,
            selectedDocumentID: nil,
            onSelect: { _ in },
            onCreate: { },
            listViews: views,
            preferenceKey: "test.SalesInvoice",
            linkSearchProvider: { _, _ in [] },
            linkResolveProvider: { _, _ in nil },
            linkTargetMetaProvider: { _ in nil }
        )
        XCTAssertNotNil(list)
    }
}
