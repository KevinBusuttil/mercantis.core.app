//
//  FieldDefinition.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// The type of a field in a DocType.
public enum FieldType: String, Codable, Sendable, CaseIterable {
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
///
/// The primitive cases (`.string`, `.int`, `.double`, `.bool`, `.null`) encode
/// as untagged JSON so existing persisted payloads and sync-queue blobs
/// round-trip byte-for-byte. The typed cases added in P1.6
/// (`.date`, `.dateTime`, `.data`, `.array`) encode as a tagged envelope
/// `{"$type": "<tag>", "$value": <payload>}` to disambiguate them from the
/// string form the legacy wire used for dates and attachments.
public enum FieldValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case date(Date)
    case dateTime(Date)
    case data(Data)
    case array([FieldValue])
}

extension FieldValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type  = "$type"
        case value = "$value"
    }

    /// Tag strings used by the tagged envelope. Kept stable on the wire.
    private enum Tag {
        static let date     = "date"
        static let dateTime = "datetime"
        static let data     = "data"
        static let array    = "array"
    }

    public init(from decoder: Decoder) throws {
        // Tagged envelope path — used by the new P1.6 cases. Old payloads never
        // emit an object shape for a field value, so probing with `try?` is safe.
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let tag = try? keyed.decode(String.self, forKey: .type) {
            switch tag {
            case Tag.date:
                self = .date(try keyed.decode(Date.self, forKey: .value))
                return
            case Tag.dateTime:
                self = .dateTime(try keyed.decode(Date.self, forKey: .value))
                return
            case Tag.data:
                self = .data(try keyed.decode(Data.self, forKey: .value))
                return
            case Tag.array:
                self = .array(try keyed.decode([FieldValue].self, forKey: .value))
                return
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: keyed,
                    debugDescription: "Unknown FieldValue type tag '\(tag)'"
                )
            }
        }

        // Legacy untagged primitive path.
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
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        case .date(let d):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(Tag.date, forKey: .type)
            try c.encode(d, forKey: .value)
        case .dateTime(let d):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(Tag.dateTime, forKey: .type)
            try c.encode(d, forKey: .value)
        case .data(let d):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(Tag.data, forKey: .type)
            try c.encode(d, forKey: .value)
        case .array(let xs):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(Tag.array, forKey: .type)
            try c.encode(xs, forKey: .value)
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
    public var section: String?                    // logical form section/group
    public var column: Int?                        // preferred form column in wide layouts
    public var collapsible: Bool                   // marks the section/group as collapsible

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
        allowOnSubmit: Bool = false,
        section: String? = nil,
        column: Int? = nil,
        collapsible: Bool = false
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
        self.section = section
        self.column = column
        self.collapsible = collapsible
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
