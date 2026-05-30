//
//  LinkLabelTests.swift
//  MercantisCoreUITests
//
//  Unit coverage for `LinkLabel` — the shared display-label resolver for
//  link fields. Link fields persist the target document's id; the label is
//  resolved at render time from the target DocType's `titleField`. These
//  tests pin that resolution (and its fallbacks) so the collapsed picker
//  shows a human label rather than the raw key id.
//

import XCTest
import MercantisCore
import MercantisCoreUI

final class LinkLabelTests: XCTestCase {

    /// Minimal DocType carrying just a `titleField` — the only thing
    /// `LinkLabel` reads from meta.
    private func makeMeta(titleField: String) -> DocType {
        DocType(
            id: "Target",
            name: "Target",
            module: "Test",
            appId: "app.mercantis.test",
            isChildTable: false,
            fields: [
                FieldDefinition(key: titleField, label: titleField, type: .text, required: false)
            ],
            permissions: [],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: [titleField],
            titleField: titleField
        )
    }

    private func makeDoc(id: String, fields: [String: FieldValue]) -> Document {
        let now = Date()
        return Document(
            id: id,
            docType: "Target",
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
    }

    /// The authoritative path: the target DocType declares `titleField`, so the
    /// label is that field's value — not the id.
    func testPrefersDeclaredTitleField() {
        let meta = makeMeta(titleField: "group_name")
        let doc = makeDoc(id: "CG-001", fields: ["group_name": .string("Commercial")])

        XCTAssertEqual(LinkLabel.title(for: doc, meta: meta), "Commercial")
    }

    /// Without resolved meta, falls back to a conventional title key.
    func testFallsBackToConventionalKeyWhenNoMeta() {
        let doc = makeDoc(id: "ITEM-1", fields: ["item_name": .string("Widget")])

        XCTAssertEqual(LinkLabel.title(for: doc, meta: nil), "Widget")
    }

    /// An empty/blank declared title field doesn't win — resolution continues
    /// past it to a conventional key.
    func testSkipsEmptyTitleField() {
        let meta = makeMeta(titleField: "group_name")
        let doc = makeDoc(id: "CG-002", fields: [
            "group_name": .string(""),
            "name": .string("Retail")
        ])

        XCTAssertEqual(LinkLabel.title(for: doc, meta: meta), "Retail")
    }

    /// Last resort: a document with no usable string field shows its id, which
    /// is the pre-fix behaviour and the safe floor.
    func testFallsBackToIdWhenNoLabelAvailable() {
        let doc = makeDoc(id: "CG-003", fields: [:])

        XCTAssertEqual(LinkLabel.title(for: doc, meta: nil), "CG-003")
    }
}
