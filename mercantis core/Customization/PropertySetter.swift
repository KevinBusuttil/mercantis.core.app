//
//  PropertySetter.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

/// A runtime property override for an existing field. (ADR-021)
///
/// Property setters allow overriding individual properties of existing fields
/// (label, default, hidden, read_only, options, etc.) without modifying the
/// base DocType definition. Applied by `MetaComposer` during metadata resolution.
public struct PropertySetter: Codable, Identifiable, Sendable {
    /// Unique identifier for this property setter record.
    public let id: String

    /// The DocType whose field is being overridden.
    public let docType: String

    /// The field key being overridden.
    public let fieldKey: String

    /// The property name being set (e.g. "label", "hidden", "readOnly", "default", "options").
    public let property: String

    /// The new value for the property (stored as a string; type-coerced at resolution time).
    public let value: String

    public init(
        id: String = UUID().uuidString,
        docType: String,
        fieldKey: String,
        property: String,
        value: String
    ) {
        self.id = id
        self.docType = docType
        self.fieldKey = fieldKey
        self.property = property
        self.value = value
    }
}
