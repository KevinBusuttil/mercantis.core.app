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
}

public enum DocumentOperation: Sendable {
    case read, write, create, delete, submit, amend
}
