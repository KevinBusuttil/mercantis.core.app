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
            case .cancel: if rule.canCancel { return true }
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
    /// `rowExpression` is a sandboxed boolean expression evaluated by
    /// `ExpressionEvaluator` (ADR-017, P1.7). The expression sees:
    /// - every entry in `document.fields` at its declared key, and
    /// - a `user.*` namespace populated from `userId`, `userRoles`, and any
    ///   caller-supplied `userAttributes`.
    ///
    /// Standard `user.*` entries:
    /// - `user.id` — the caller's user id (empty string if `userId` is `""`).
    /// - `user.roles` — the caller's role set as `.array([.string(role), ...])`,
    ///   sorted for deterministic ordering.
    ///
    /// `userAttributes` keys that already start with `"user."` are taken as-is;
    /// any other key is namespaced by prefixing `"user."`. Entries provided this
    /// way override the standard `user.id` / `user.roles` keys, and any `user.*`
    /// key overrides a document field that happens to share the same name.
    ///
    /// A `nil`, empty, or whitespace-only `rowExpression` grants access (no
    /// row-level restriction). An expression that fails to evaluate — parse error,
    /// undefined identifier, type mismatch — fails closed: returns `false`.
    ///
    /// Examples:
    /// - `"owner == user.id"` — only the document owner may read it.
    /// - `"warehouse == user.warehouse"` with
    ///   `userAttributes: ["warehouse": .string("WH-01")]`.
    public func canAccessRow(
        document: Document,
        userRoles: Set<String>,
        rowExpression: String?,
        userId: String = "",
        userAttributes: [String: FieldValue] = [:],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()
    ) -> Bool {
        guard let expression = rowExpression?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expression.isEmpty else {
            return true
        }

        var context = document.fields
        context["user.id"] = .string(userId)
        context["user.roles"] = .array(userRoles.sorted().map { .string($0) })
        for (key, value) in userAttributes {
            let namespaced = key.hasPrefix("user.") ? key : "user.\(key)"
            context[namespaced] = value
        }

        do {
            return try expressionEvaluator.evaluateBool(expression: expression, context: context)
        } catch {
            return false
        }
    }
}

// MARK: - Operation Types

public enum DocumentOperation: Sendable {
    case read, write, create, delete, submit, amend, cancel
}

public enum FieldOperation: Sendable {
    case read, write
}
