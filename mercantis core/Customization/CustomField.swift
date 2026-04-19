//
//  CustomField.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

/// A user-added field on an existing DocType. (ADR-021)
///
/// Custom fields are stored separately from the base DocType definition and
/// merged at runtime by `MetaComposer` into a `ResolvedMeta`.
public struct CustomField: Codable, Identifiable, Sendable {
    /// Unique identifier for this custom field record.
    public let id: String

    /// The DocType this custom field is added to.
    public let docType: String

    /// The field definition for this custom field.
    public let fieldDefinition: FieldDefinition

    /// The field key after which this custom field should be inserted.
    /// If `nil` or empty, the field is appended at the end.
    public let insertAfter: String?

    public init(
        id: String = UUID().uuidString,
        docType: String,
        fieldDefinition: FieldDefinition,
        insertAfter: String? = nil
    ) {
        self.id = id
        self.docType = docType
        self.fieldDefinition = fieldDefinition
        self.insertAfter = insertAfter
    }
}
