//
//  DocumentVersion.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

/// An immutable record of a single document version (field-level diff). (ADR-024)
///
/// On every `DocumentEngine.save()`, before writing the new payload,
/// `DocumentEngine` computes a field-level diff and stores it as a
/// `DocumentVersion` record. This provides a complete field-level
/// change history for audit-sensitive documents.
///
/// `DocumentVersion` records are append-only — they are never modified or deleted.
public struct DocumentVersion: Identifiable, Codable, Sendable {
    /// Unique identifier for this version record.
    public let id: String

    /// The document this version belongs to.
    public let documentId: String

    /// The DocType of the document.
    public let docType: String

    /// When this version was saved.
    public let savedAt: Date

    /// The user who saved this version.
    public let savedBy: String

    /// The field-level diffs in this version.
    public let fieldDiffs: [FieldDiff]

    public init(
        id: String = UUID().uuidString,
        documentId: String,
        docType: String,
        savedAt: Date = Date(),
        savedBy: String,
        fieldDiffs: [FieldDiff]
    ) {
        self.id = id
        self.documentId = documentId
        self.docType = docType
        self.savedAt = savedAt
        self.savedBy = savedBy
        self.fieldDiffs = fieldDiffs
    }
}

/// A single field-level change within a `DocumentVersion`. (ADR-024)
public struct FieldDiff: Codable, Sendable {
    /// The field key that changed.
    public let fieldKey: String

    /// The old value (nil for newly added fields).
    public let oldValue: FieldValue?

    /// The new value (nil for removed fields).
    public let newValue: FieldValue?

    public init(fieldKey: String, oldValue: FieldValue?, newValue: FieldValue?) {
        self.fieldKey = fieldKey
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

// MARK: - Diff Computation

/// Computes field-level diffs between two sets of field values. (ADR-024)
///
/// Returns an array of `FieldDiff` for every field that changed (added, removed, or modified).
public func computeFieldDiffs(
    oldFields: [String: FieldValue],
    newFields: [String: FieldValue]
) -> [FieldDiff] {
    var diffs: [FieldDiff] = []

    // All keys from both old and new to detect additions, changes, and removals.
    let allKeys = Set(oldFields.keys).union(newFields.keys)

    for key in allKeys.sorted() {
        let oldValue = oldFields[key]
        let newValue = newFields[key]

        if oldValue != newValue {
            diffs.append(FieldDiff(
                fieldKey: key,
                oldValue: oldValue,
                newValue: newValue
            ))
        }
    }

    return diffs
}

/// Computes child-table diffs as flattened `FieldDiff` entries. (P0.6)
///
/// Before this, document versions captured only parent-field changes, so a
/// submitted invoice's line-item edits (add/remove a row, change a qty or rate)
/// left no version history. Each changed child cell is recorded with a
/// `tableName[rowIndex].fieldKey` key; whole-row additions and removals are
/// recorded as a `tableName[rowIndex]` entry whose value carries the row id.
///
/// Rows are matched by their stable `id` (not position) so reordering a table
/// does not masquerade as a full rewrite.
public func computeChildDiffs(
    oldChildren: [String: [ChildRow]],
    newChildren: [String: [ChildRow]]
) -> [FieldDiff] {
    var diffs: [FieldDiff] = []
    let tables = Set(oldChildren.keys).union(newChildren.keys)

    for table in tables.sorted() {
        let oldRows = oldChildren[table] ?? []
        let newRows = newChildren[table] ?? []
        let oldById = Dictionary(oldRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newById = Dictionary(newRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(oldById.keys).union(newById.keys)

        for id in ids.sorted() {
            switch (oldById[id], newById[id]) {
            case let (.some(oldRow), .some(newRow)):
                for fd in computeFieldDiffs(oldFields: oldRow.fields, newFields: newRow.fields) {
                    diffs.append(FieldDiff(
                        fieldKey: "\(table)[\(newRow.rowIndex)].\(fd.fieldKey)",
                        oldValue: fd.oldValue,
                        newValue: fd.newValue
                    ))
                }
            case let (.some(oldRow), .none):
                diffs.append(FieldDiff(
                    fieldKey: "\(table)[\(oldRow.rowIndex)]",
                    oldValue: .string("row:\(id)"),
                    newValue: nil
                ))
            case let (.none, .some(newRow)):
                diffs.append(FieldDiff(
                    fieldKey: "\(table)[\(newRow.rowIndex)]",
                    oldValue: nil,
                    newValue: .string("row:\(id)")
                ))
            case (.none, .none):
                break
            }
        }
    }

    return diffs
}
