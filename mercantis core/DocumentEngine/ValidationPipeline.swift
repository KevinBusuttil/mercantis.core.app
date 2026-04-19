//
//  ValidationPipeline.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

// MARK: - Validation Error

/// A structured validation error produced by a `ValidationStage`. (ADR-022)
public struct DocumentValidationError: Error, Sendable {
    /// The stage that produced this error (e.g. "TypeCoercion", "RequiredField").
    public let stage: String

    /// The field key this error relates to, if applicable.
    public let field: String?

    /// A user-visible error message.
    public let message: String

    public init(stage: String, field: String? = nil, message: String) {
        self.stage = stage
        self.field = field
        self.message = message
    }
}

// MARK: - Validation Context

/// Context available to each validation stage during pipeline execution.
public struct ValidationContext: Sendable {
    /// The DocType metadata (resolved).
    public let docType: DocType

    /// The user performing the operation.
    public let userId: String

    /// The user's roles.
    public let userRoles: Set<String>

    /// An expression evaluator for condition-based validation rules.
    public let expressionEvaluator: ExpressionEvaluator

    /// Function to check whether a linked document exists.
    /// Parameters: (docType, documentId) -> Bool
    public let documentExists: @Sendable (String, String) -> Bool

    /// Function to check for unique constraint violations.
    /// Parameters: (docType, fieldKey, fieldValue, excludeDocumentId) -> Bool (true = conflict exists)
    public let uniqueConflictExists: @Sendable (String, String, FieldValue, String) -> Bool

    public init(
        docType: DocType,
        userId: String = "",
        userRoles: Set<String> = [],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        documentExists: @escaping @Sendable (String, String) -> Bool = { _, _ in true },
        uniqueConflictExists: @escaping @Sendable (String, String, FieldValue, String) -> Bool = { _, _, _, _ in false }
    ) {
        self.docType = docType
        self.userId = userId
        self.userRoles = userRoles
        self.expressionEvaluator = expressionEvaluator
        self.documentExists = documentExists
        self.uniqueConflictExists = uniqueConflictExists
    }
}

// MARK: - Validation Stage Protocol

/// A single stage in the document validation pipeline. (ADR-022)
///
/// Each stage is independently testable and returns zero or more
/// `DocumentValidationError` values. The pipeline halts on the first
/// stage that produces errors.
public protocol ValidationStage {
    /// The human-readable name of this stage (used in error attribution).
    var stageName: String { get }

    /// Validate a document and return any errors found.
    func validate(document: Document, context: ValidationContext) -> [DocumentValidationError]
}

// MARK: - Validation Pipeline

/// An ordered sequence of `ValidationStage` conformances. (ADR-022)
///
/// Stages are executed in declared order on every `save()` call.
/// If any stage produces errors, the pipeline halts and the errors
/// are returned to the caller. The document is not persisted.
public final class ValidationPipeline {

    private let stages: [ValidationStage]

    /// Create a pipeline with the default set of stages.
    public init() {
        self.stages = [
            TypeCoercionStage(),
            RequiredFieldStage(),
            LinkValidationStage(),
            UniqueConstraintStage(),
            ValidationRuleStage(),
            WorkflowGuardStage(),
            PermissionStage()
        ]
    }

    /// Create a pipeline with a custom subset of stages (e.g. for testing or import paths).
    public init(stages: [ValidationStage]) {
        self.stages = stages
    }

    /// Execute all stages in order. Returns the first set of errors encountered,
    /// or an empty array if validation passes.
    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        for stage in stages {
            let errors = stage.validate(document: document, context: context)
            if !errors.isEmpty {
                return errors
            }
        }
        return []
    }
}

// MARK: - Stage 1: Type Coercion

/// Field values are checked against their declared `FieldType`. (ADR-022)
///
/// Mismatched types produce errors (or are coerced where safe,
/// e.g. string "42" → number 42).
public struct TypeCoercionStage: ValidationStage {
    public let stageName = "TypeCoercion"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields {
            guard let value = document.fields[field.key] else { continue }

            // Skip null values — they are handled by RequiredFieldStage.
            if case .null = value { continue }

            if !isTypeCompatible(value: value, fieldType: field.type) {
                errors.append(DocumentValidationError(
                    stage: stageName,
                    field: field.key,
                    message: "Field '\(field.label)' has an incompatible value type for '\(field.type)'."
                ))
            }
        }

        return errors
    }

    private func isTypeCompatible(value: FieldValue, fieldType: FieldType) -> Bool {
        switch fieldType {
        case .text, .longText, .email, .phone, .select, .status, .multiselect, .link, .attachment:
            if case .string = value { return true }
            return false
        case .number:
            switch value {
            case .int, .double: return true
            case .string(let s): return Int(s) != nil || Double(s) != nil
            default: return false
            }
        case .decimal, .currency:
            switch value {
            case .int, .double: return true
            case .string(let s): return Double(s) != nil
            default: return false
            }
        case .boolean:
            if case .bool = value { return true }
            return false
        case .date, .datetime:
            // Dates are stored as ISO8601 strings.
            if case .string = value { return true }
            return false
        case .formula:
            // Formula fields are computed — any stored value is acceptable.
            return true
        case .table:
            // Table fields are stored in children, not in the fields dictionary.
            return true
        }
    }
}

// MARK: - Stage 2: Required Field

/// Fields marked `required: true` must have a non-empty value. (ADR-022)
public struct RequiredFieldStage: ValidationStage {
    public let stageName = "RequiredField"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields where field.required {
            let value = document.fields[field.key]

            if isValueEmpty(value) {
                errors.append(DocumentValidationError(
                    stage: stageName,
                    field: field.key,
                    message: "'\(field.label)' is required."
                ))
            }
        }

        return errors
    }

    private func isValueEmpty(_ value: FieldValue?) -> Bool {
        guard let value = value else { return true }
        switch value {
        case .null: return true
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .int, .double, .bool: return false
        }
    }
}

// MARK: - Stage 3: Link Validation

/// For fields of type `link`, the referenced document must exist. (ADR-022)
public struct LinkValidationStage: ValidationStage {
    public let stageName = "LinkValidation"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields where field.type == .link {
            guard let linkedDocType = field.linkedDocType, !linkedDocType.isEmpty else { continue }
            guard let value = document.fields[field.key],
                  case .string(let linkedId) = value,
                  !linkedId.isEmpty else { continue }

            if !context.documentExists(linkedDocType, linkedId) {
                errors.append(DocumentValidationError(
                    stage: stageName,
                    field: field.key,
                    message: "Linked document '\(linkedId)' of type '\(linkedDocType)' does not exist."
                ))
            }
        }

        return errors
    }
}

// MARK: - Stage 4: Unique Constraint

/// Fields or index definitions marked `unique: true` are checked
/// against existing documents. (ADR-022)
public struct UniqueConstraintStage: ValidationStage {
    public let stageName = "UniqueConstraint"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        // Check unique indexes.
        for index in context.docType.indexes where index.unique {
            guard let value = document.fields[index.fieldKey], !isNull(value) else { continue }

            if context.uniqueConflictExists(document.docType, index.fieldKey, value, document.id) {
                errors.append(DocumentValidationError(
                    stage: stageName,
                    field: index.fieldKey,
                    message: "A document with the same value for '\(index.fieldKey)' already exists."
                ))
            }
        }

        return errors
    }

    private func isNull(_ value: FieldValue) -> Bool {
        if case .null = value { return true }
        return false
    }
}

// MARK: - Stage 5: Validation Rule

/// `ValidationRule` expressions declared in the DocType are evaluated
/// by `ExpressionEvaluator`. A failing rule produces a user-visible error message. (ADR-022)
public struct ValidationRuleStage: ValidationStage {
    public let stageName = "ValidationRule"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields {
            for rule in field.validationRules {
                let passes: Bool
                do {
                    passes = try context.expressionEvaluator.evaluateBool(
                        expression: rule.expression,
                        context: document.fields
                    )
                } catch {
                    // If the expression fails to evaluate, treat it as a validation failure.
                    errors.append(DocumentValidationError(
                        stage: stageName,
                        field: field.key,
                        message: "Validation rule error on '\(field.label)': \(error.localizedDescription)"
                    ))
                    continue
                }

                if !passes {
                    errors.append(DocumentValidationError(
                        stage: stageName,
                        field: field.key,
                        message: rule.message
                    ))
                }
            }
        }

        return errors
    }
}

// MARK: - Stage 6: Workflow Guard

/// If the document has an associated workflow, the current transition (if any)
/// is validated for allowed roles and condition expression. (ADR-022)
public struct WorkflowGuardStage: ValidationStage {
    public let stageName = "WorkflowGuard"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        // Workflow guard is only relevant when a workflow is attached to the DocType.
        // The actual workflow transition validation happens in WorkflowEngine.
        // This stage acts as a placeholder for integration; real workflow checks
        // are performed when `WorkflowEngine.transition(...)` is called.
        guard context.docType.workflowId != nil else { return [] }

        // If the document status has changed, the caller should have already
        // validated it through WorkflowEngine. This stage returns no errors
        // by default — it exists to hold the position in the pipeline.
        return []
    }
}

// MARK: - Stage 7: Permission

/// The permission evaluator chain is invoked to confirm the current user
/// may perform the save operation. (ADR-022)
public struct PermissionStage: ValidationStage {
    public let stageName = "Permission"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        // Permission checking requires the full PermissionEngine evaluator chain
        // (ADR-011), which operates at a higher level than individual document
        // validation. This stage acts as the integration point.
        //
        // When PermissionEngine is fully wired into the validation pipeline,
        // this stage will call `permissionEngine.canPerform(.write, on: document, context:)`.
        //
        // For now, if userRoles are provided but the DocType has permission rules,
        // perform a basic DocType-level permission check.
        guard !context.userRoles.isEmpty else { return [] }

        let docTypePermissions = context.docType.permissions
        guard !docTypePermissions.isEmpty else { return [] }

        // Check if any of the user's roles grant write access.
        let hasWriteAccess = docTypePermissions.contains { rule in
            context.userRoles.contains(rule.role) && rule.canWrite
        }

        if !hasWriteAccess {
            return [DocumentValidationError(
                stage: stageName,
                field: nil,
                message: "You do not have permission to save '\(context.docType.name)' documents."
            )]
        }

        return []
    }
}
