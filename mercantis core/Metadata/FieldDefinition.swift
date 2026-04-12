//
//  FieldDefinition.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// The type of a field in a DocType.
public enum FieldType: String, Codable, Sendable {
    case text
    case longText
    case number
    case decimal
    case currency
    case boolean
    case date
    case datetime
    case email
    case phone
    case select
    case multiselect
    case link
    case table
    case attachment
    case status
    case formula
}

/// A value that can be assigned to a field.
public enum FieldValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}

/// Defines a single field within a DocType. (ADR-003)
public struct FieldDefinition: Codable, Identifiable, Sendable {
    public var id: String { key }

    public let key: String
    public var label: String
    public var type: FieldType
    public var required: Bool
    public var defaultValue: FieldValue?
    public var options: [String]?              // for select / multiselect
    public var linkedDocType: String?          // for link fields
    public var childDocType: String?           // for table fields
    public var validationRules: [ValidationRule]
    public var visibilityExpression: String?   // boolean expression; field shown only when true
    public var readOnlyExpression: String?
    public var permissions: FieldPermission?
    public var isSearchable: Bool
    public var isSynced: Bool
}

/// A validation rule for a field.
public struct ValidationRule: Codable, Sendable {
    public let ruleType: String    // e.g. "regex", "range", "required_if"
    public let expression: String
    public let message: String     // error message shown on failure
}

/// Field-level permission override.
public struct FieldPermission: Codable, Sendable {
    public let readRoles: [String]
    public let writeRoles: [String]
}
