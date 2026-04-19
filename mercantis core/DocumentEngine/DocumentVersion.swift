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
