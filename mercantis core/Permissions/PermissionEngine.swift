//
//  PermissionEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Evaluates permission rules for document operations. (ADR-003)
public final class PermissionEngine {

    public init() {}

    // MARK: - DocType-level

    /// Check whether a user with the given roles can perform an operation on a DocType.
    public func canPerform(
        operation: DocumentOperation,
        on docType: DocType,
        userRoles: Set<String>
    ) -> Bool {
        for rule in docType.permissions {
            guard userRoles.contains(rule.role) else { continue }
            switch operation {
            case .read:   if rule.canRead   { return true }
            case .write:  if rule.canWrite  { return true }
            case .create: if rule.canCreate { return true }
            case .delete: if rule.canDelete { return true }
            case .submit: if rule.canSubmit { return true }
            case .amend:  if rule.canAmend  { return true }
            }
        }
        return false
    }

    // MARK: - Field-level

    /// Check whether a user with the given roles can read or write a specific field.
    ///
    /// If the field has no `FieldPermission` set, access is granted to anyone who
    /// already has DocType-level access.
    public func canAccessField(
        fieldKey: String,
        on docType: DocType,
        userRoles: Set<String>,
        operation: FieldOperation
    ) -> Bool {
        guard let field = docType.fields.first(where: { $0.key == fieldKey }) else {
            return false
        }
        guard let fieldPermission = field.permissions else {
            // No field-level restriction — rely on DocType-level checks.
            return true
        }
        switch operation {
        case .read:
            return fieldPermission.readRoles.contains(where: { userRoles.contains($0) })
        case .write:
            return fieldPermission.writeRoles.contains(where: { userRoles.contains($0) })
        }
    }

    // MARK: - Row-level

    /// Check whether a user with the given roles can access a specific document row.
    ///
    /// `rowFilter` is a dictionary of field key → required value pairs. The user can
    /// access the row only if all filter conditions match (i.e. the document's field
    /// values satisfy the row-level constraints for that user).
    ///
    /// Example: `rowFilter = ["warehouse": .string("WH-01")]` — the user can only see
    /// documents whose `warehouse` field equals "WH-01".
    ///
    /// Passing `nil` for `rowFilter` grants access (no row-level restriction).
    public func canAccessRow(
        document: Document,
        userRoles: Set<String>,
        rowFilter: [String: FieldValue]?
    ) -> Bool {
        guard let rowFilter = rowFilter, !rowFilter.isEmpty else {
            return true
        }
        return rowFilter.allSatisfy { key, requiredValue in
            document.fields[key] == requiredValue
        }
    }
}

// MARK: - Operation Types

public enum DocumentOperation: Sendable {
    case read, write, create, delete, submit, amend
}

public enum FieldOperation: Sendable {
    case read, write
}
