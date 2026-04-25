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
        case moduleNotFound(docType: String, module: String)
        /// A `visibilityExpression` / `readOnlyExpression` / `formulaExpression`
        /// failed to parse. (P2.1)
        case expressionParseFailed(docType: String, fieldKey: String, expressionKind: String, message: String, position: Int)
        /// A `visibilityExpression` / `readOnlyExpression` / `formulaExpression`
        /// references a field key that the DocType does not declare. (P2.1)
        case unknownFieldInExpression(docType: String, fieldKey: String, expressionKind: String, referenced: String)
    }

    /// When set, module names are validated against this list.
    public var knownModules: Set<String>?

    /// When `false`, skip the field-level `visibilityExpression` /
    /// `readOnlyExpression` / `formulaExpression` static-analysis checks.
    /// Defaults to `true`. The check costs one parse per non-empty
    /// expression at install time and surfaces undeclared field
    /// references before the DocType ever runs against a real document.
    /// (P2.1)
    public var validatesExpressions: Bool = true

    public init() {}

    /// Validate a DocType definition. Throws on first error.
    public func validate(_ docType: DocType) throws {
        guard !docType.id.isEmpty else {
            throw ValidationError.emptyDocTypeId
        }

        // Validate module exists if known modules are provided.
        if let knownModules, !knownModules.isEmpty {
            let trimmedModule = docType.module.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModule.isEmpty && !knownModules.contains(trimmedModule) {
                throw ValidationError.moduleNotFound(docType: docType.id, module: trimmedModule)
            }
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

        // Field-level expression checks (P2.1). Done after the structural
        // pass so we can rely on `seenKeys` as the declared-field set.
        if validatesExpressions {
            try validateExpressions(in: docType, declaredFields: seenKeys)
        }
    }

    // MARK: - Expression validation (P2.1)

    private func validateExpressions(in docType: DocType, declaredFields: Set<String>) throws {
        let evaluator = ExpressionEvaluator()
        for field in docType.fields {
            try check(
                expression: field.visibilityExpression,
                kind: "visibilityExpression",
                in: docType,
                fieldKey: field.key,
                declaredFields: declaredFields,
                evaluator: evaluator
            )
            try check(
                expression: field.readOnlyExpression,
                kind: "readOnlyExpression",
                in: docType,
                fieldKey: field.key,
                declaredFields: declaredFields,
                evaluator: evaluator
            )
            try check(
                expression: field.formulaExpression,
                kind: "formulaExpression",
                in: docType,
                fieldKey: field.key,
                declaredFields: declaredFields,
                evaluator: evaluator
            )
        }
    }

    private func check(
        expression: String?,
        kind: String,
        in docType: DocType,
        fieldKey: String,
        declaredFields: Set<String>,
        evaluator: ExpressionEvaluator
    ) throws {
        guard let raw = expression else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let referenced: Set<String>
        do {
            referenced = try evaluator.referencedFields(in: trimmed)
        } catch ExpressionEvaluator.EvaluatorError.parseError(let parseError) {
            throw ValidationError.expressionParseFailed(
                docType: docType.id,
                fieldKey: fieldKey,
                expressionKind: kind,
                message: parseError.message,
                position: parseError.position
            )
        } catch ExpressionEvaluator.EvaluatorError.unexpectedToken(let token) {
            throw ValidationError.expressionParseFailed(
                docType: docType.id,
                fieldKey: fieldKey,
                expressionKind: kind,
                message: token,
                position: 0
            )
        } catch {
            // `referencedFields` only walks the parser, so the only
            // errors it can raise are parse errors. Surface anything
            // unexpected as a parse failure rather than letting an
            // arbitrary error escape into install code.
            throw ValidationError.expressionParseFailed(
                docType: docType.id,
                fieldKey: fieldKey,
                expressionKind: kind,
                message: "\(error)",
                position: 0
            )
        }

        for name in referenced {
            // Identifiers with a `.` are treated as out-of-DocType
            // namespaces (`user.id`, `user.roles`) — not enforced here.
            // The `MetaComposer` / `PermissionEngine` populate them.
            if name.contains(".") { continue }
            if !declaredFields.contains(name) {
                throw ValidationError.unknownFieldInExpression(
                    docType: docType.id,
                    fieldKey: fieldKey,
                    expressionKind: kind,
                    referenced: name
                )
            }
        }
    }
}
