//
//  SchemaValidator.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Validates DocType and FieldDefinition metadata before it is committed to the registry.
/// All definitions must pass validation. (ADR-003)
public struct SchemaValidator {

    public enum ValidationError: Error, Sendable {
        case emptyDocTypeId
        case emptyFieldKey(docType: String)
        case duplicateFieldKey(docType: String, key: String)
        case missingLinkedDocType(docType: String, fieldKey: String)
        case missingChildDocType(docType: String, fieldKey: String)
        case financialDocTypeMustUseVersionChecked(docType: String)
        case titleFieldNotFound(docType: String, titleField: String)
    }

    public init() {}

    /// Validate a DocType definition. Throws on first error.
    public func validate(_ docType: DocType) throws {
        guard !docType.id.isEmpty else {
            throw ValidationError.emptyDocTypeId
        }

        var seenKeys = Set<String>()
        for field in docType.fields {
            guard !field.key.isEmpty else {
                throw ValidationError.emptyFieldKey(docType: docType.id)
            }
            guard !seenKeys.contains(field.key) else {
                throw ValidationError.duplicateFieldKey(docType: docType.id, key: field.key)
            }
            seenKeys.insert(field.key)

            if field.type == .link && (field.linkedDocType ?? "").isEmpty {
                throw ValidationError.missingLinkedDocType(docType: docType.id, fieldKey: field.key)
            }
            if field.type == .table && (field.childDocType ?? "").isEmpty {
                throw ValidationError.missingChildDocType(docType: docType.id, fieldKey: field.key)
            }
        }

        if !docType.titleField.isEmpty {
            guard docType.fields.contains(where: { $0.key == docType.titleField }) else {
                throw ValidationError.titleFieldNotFound(docType: docType.id, titleField: docType.titleField)
            }
        }
    }
}
