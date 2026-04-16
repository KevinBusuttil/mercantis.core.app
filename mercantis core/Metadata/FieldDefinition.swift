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
public enum FieldValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}

extension FieldValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode FieldValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i):    try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b):   try container.encode(b)
        case .null:          try container.encodeNil()
        }
    }
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
    public var formulaExpression: String?      // for formula fields; arithmetic expression returning a value
    public var permissions: FieldPermission?
    public var isSearchable: Bool
    public var isSynced: Bool
    public var allowOnSubmit: Bool                 // If true, this field can be edited on submitted documents (ADR-013)

    public init(
        key: String,
        label: String,
        type: FieldType,
        required: Bool,
        defaultValue: FieldValue? = nil,
        options: [String]? = nil,
        linkedDocType: String? = nil,
        childDocType: String? = nil,
        validationRules: [ValidationRule] = [],
        visibilityExpression: String? = nil,
        readOnlyExpression: String? = nil,
        formulaExpression: String? = nil,
        permissions: FieldPermission? = nil,
        isSearchable: Bool = false,
        isSynced: Bool = true,
        allowOnSubmit: Bool = false
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
        self.linkedDocType = linkedDocType
        self.childDocType = childDocType
        self.validationRules = validationRules
        self.visibilityExpression = visibilityExpression
        self.readOnlyExpression = readOnlyExpression
        self.formulaExpression = formulaExpression
        self.permissions = permissions
        self.isSearchable = isSearchable
        self.isSynced = isSynced
        self.allowOnSubmit = allowOnSubmit
    }
}

/// A validation rule for a field.
public struct ValidationRule: Codable, Sendable {
    public let ruleType: String    // e.g. "regex", "range", "required_if"
    public let expression: String
    public let message: String     // error message shown on failure

    public init(ruleType: String, expression: String, message: String) {
        self.ruleType = ruleType
        self.expression = expression
        self.message = message
    }
}

/// Field-level permission override.
public struct FieldPermission: Codable, Sendable {
    public let readRoles: [String]
    public let writeRoles: [String]

    public init(readRoles: [String], writeRoles: [String]) {
        self.readRoles = readRoles
        self.writeRoles = writeRoles
    }
}
