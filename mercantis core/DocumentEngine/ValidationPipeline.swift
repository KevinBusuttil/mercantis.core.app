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

    /// The operation being performed. Used by `PermissionStage` to call
    /// `PermissionEngine.canPerform(operation:on:userRoles:)`. Defaults to `.write`.
    public let operation: DocumentOperation

    /// An expression evaluator for condition-based validation rules.
    public let expressionEvaluator: ExpressionEvaluator

    /// The permission engine used by `PermissionStage`. Defaults to a fresh instance.
    public let permissionEngine: PermissionEngine

    /// Function to check whether a linked document exists.
    /// Parameters: (docType, documentId) -> Bool
    public let documentExists: @Sendable (String, String) -> Bool

    /// Function to check for unique constraint violations.
    /// Parameters: (docType, fieldKey, fieldValue, excludeDocumentId) -> Bool (true = conflict exists)
    public let uniqueConflictExists: @Sendable (String, String, FieldValue, String) -> Bool

    /// Lookup the `WorkflowDefinition` for a given workflow id. Returns nil if the workflow
    /// cannot be resolved. Used by `WorkflowGuardStage`. Default: always nil.
    public let workflowProvider: @Sendable (String) -> WorkflowDefinition?

    /// Lookup the previously-persisted workflow `status` for a document, if any.
    /// Parameters: (docType, documentId). Returns nil for brand-new documents. Used by
    /// `WorkflowGuardStage` to detect state transitions. Default: always nil.
    public let previousStatus: @Sendable (String, String) -> String?

    /// Resolve a child DocType definition by name. Used by
    /// `ChildTableValidationStage` (P0.5) to validate table rows against their
    /// declared child DocType. Default: always nil (no child validation).
    public let childDocTypeProvider: @Sendable (String) -> DocType?

    public init(
        docType: DocType,
        userId: String = "",
        userRoles: Set<String> = [],
        operation: DocumentOperation = .write,
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        permissionEngine: PermissionEngine = PermissionEngine(),
        documentExists: @escaping @Sendable (String, String) -> Bool = { _, _ in true },
        uniqueConflictExists: @escaping @Sendable (String, String, FieldValue, String) -> Bool = { _, _, _, _ in false },
        workflowProvider: @escaping @Sendable (String) -> WorkflowDefinition? = { _ in nil },
        previousStatus: @escaping @Sendable (String, String) -> String? = { _, _ in nil },
        childDocTypeProvider: @escaping @Sendable (String) -> DocType? = { _ in nil }
    ) {
        self.docType = docType
        self.userId = userId
        self.userRoles = userRoles
        self.operation = operation
        self.expressionEvaluator = expressionEvaluator
        self.permissionEngine = permissionEngine
        self.documentExists = documentExists
        self.uniqueConflictExists = uniqueConflictExists
        self.workflowProvider = workflowProvider
        self.previousStatus = previousStatus
        self.childDocTypeProvider = childDocTypeProvider
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

    /// Mutate a document before validation when a safe coercion is available.
    func coerce(document: inout Document, context: ValidationContext) -> [DocumentValidationError]

    /// Validate a document and return any errors found.
    func validate(document: Document, context: ValidationContext) -> [DocumentValidationError]
}

public extension ValidationStage {
    func coerce(document: inout Document, context: ValidationContext) -> [DocumentValidationError] {
        []
    }
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
            ChildTableValidationStage(),
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
        var document = document
        return validate(document: &document, context: context)
    }

    /// Execute all stages in order, allowing them to coerce the document in place
    /// before validation.
    public func validate(document: inout Document, context: ValidationContext) -> [DocumentValidationError] {
        for stage in stages {
            let coercionErrors = stage.coerce(document: &document, context: context)
            if !coercionErrors.isEmpty {
                return coercionErrors
            }

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

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init() {}

    public func coerce(document: inout Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields {
            guard let value = document.fields[field.key] else { continue }

            switch (field.type, value) {
            case (.date, .string(let raw)):
                guard let parsed = Self.parseDate(raw) else {
                    errors.append(invalidValueError(for: field, expected: "ISO8601 date"))
                    continue
                }
                document.fields[field.key] = .date(parsed)
            case (.datetime, .string(let raw)):
                guard let parsed = Self.parseDateTime(raw) else {
                    errors.append(invalidValueError(for: field, expected: "ISO8601 date-time"))
                    continue
                }
                document.fields[field.key] = .dateTime(parsed)
            default:
                continue
            }
        }

        return errors
    }

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
        case .text, .longText, .richText, .email, .phone, .select, .status, .multiselect, .link, .barcode:
            if case .string = value { return true }
            return false
        case .attachment, .image:
            // Attachments identify a blob — string id today, P1.6 `.data` inline path.
            switch value {
            case .string, .data: return true
            default: return false
            }
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
        case .date:
            switch value {
            case .date, .dateTime: return true
            case .string(let s): return Self.parseDate(s) != nil
            default: return false
            }
        case .datetime:
            switch value {
            case .dateTime, .date: return true
            case .string(let s): return Self.parseDateTime(s) != nil
            default: return false
            }
        case .formula:
            // Formula fields are computed — any stored value is acceptable.
            return true
        case .table:
            // Table fields are stored in children, not in the fields dictionary.
            return true
        case .password, .code, .color, .signature, .geolocation, .autocomplete, .dynamicLink:
            // String-backed editors (secure text, code, hex colour, signature JSON,
            // lat/long string, autocomplete/dynamic-link selections).
            if case .string = value { return true }
            return false
        case .tableMultiSelect:
            // Stored as a string list today; accept the string or array shapes.
            switch value {
            case .string, .array: return true
            default: return false
            }
        case .percent:
            switch value {
            case .int, .double: return true
            case .string(let s): return Double(s) != nil
            default: return false
            }
        case .rating, .duration:
            // Whole-number editors (star count / total seconds).
            switch value {
            case .int, .double: return true
            case .string(let s): return Int(s) != nil || Double(s) != nil
            default: return false
            }
        case .time:
            switch value {
            case .dateTime, .date: return true
            case .string(let s): return Self.parseDateTime(s) != nil || Self.parseDate(s) != nil
            default: return false
            }
        case .heading, .sectionBreak, .columnBreak:
            // Layout-only separators carry no persisted value.
            return true
        }
    }

    private func invalidValueError(for field: FieldDefinition, expected: String) -> DocumentValidationError {
        DocumentValidationError(
            stage: stageName,
            field: field.key,
            message: "Field '\(field.label)' must be a valid \(expected)."
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        // Legacy payloads sometimes stored date-only fields as full ISO8601
        // timestamps. Prefer a strict yyyy-mm-dd parse, but accept that older
        // shape so save() can coerce it back to the typed `.date` case.
        dateFormatter.date(from: raw) ?? parseDateTime(raw)
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        fractionalDateTimeFormatter.date(from: raw) ?? dateTimeFormatter.date(from: raw)
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
            // Child-table rows live in `document.children`, not in `fields`, so a
            // required `.table` is satisfied by having at least one child row.
            let isEmpty: Bool
            if field.type == .table {
                isEmpty = (document.children[field.key] ?? []).isEmpty
            } else {
                isEmpty = isValueEmpty(document.fields[field.key])
            }

            if isEmpty {
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
        case .int, .double, .bool, .date, .dateTime: return false
        case .data(let d): return d.isEmpty
        case .array(let xs): return xs.isEmpty
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

// MARK: - Stage 4b: Child Table Validation (P0.5)

/// Recursively validates child-table rows against their declared child DocType.
///
/// Before this stage, a `.table` field was only checked for emptiness
/// (`RequiredFieldStage`); the *contents* of each row received no type, option,
/// link, or rule validation, so financial line items (qty, rate, item link,
/// tax code) could be persisted with invalid or dangling values. This stage
/// runs the field-level stages (`TypeCoercion`, `RequiredField`,
/// `LinkValidation`, `ValidationRule`) against every row of every table field
/// whose child DocType resolves via `context.childDocTypeProvider`, and also
/// enforces the child DocType's unique indexes *within the table scope*
/// (e.g. no duplicate item line if the child DocType marks `item` unique).
///
/// Errors are re-attributed with a `tableKey[rowIndex].field` path and a
/// human-readable "Row N:" prefix so the UI can point at the offending cell.
///
/// When a table field has no resolvable child DocType (legacy / untyped
/// tables), its rows are skipped — behaviour is unchanged for those.
public struct ChildTableValidationStage: ValidationStage {
    public let stageName = "ChildTableValidation"

    /// Field-level stages re-used per child row. Unique/Workflow/Permission are
    /// parent-scoped and intentionally excluded; child uniqueness is handled
    /// table-locally below.
    private let rowStages: [ValidationStage] = [
        TypeCoercionStage(),
        RequiredFieldStage(),
        LinkValidationStage(),
        ValidationRuleStage()
    ]

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []

        for field in context.docType.fields where field.type == .table {
            guard let childTypeName = field.childDocType,
                  let childType = context.childDocTypeProvider(childTypeName) else {
                continue
            }
            let rows = document.children[field.key] ?? []

            // Per-row field validation.
            for (index, row) in rows.enumerated() {
                let childDoc = makeChildDocument(row: row, childType: childType, parent: document)
                let childContext = makeChildContext(childType: childType, parent: context)
                for stage in rowStages {
                    for error in stage.validate(document: childDoc, context: childContext) {
                        errors.append(DocumentValidationError(
                            stage: stageName,
                            field: rowFieldPath(table: field.key, index: index, field: error.field),
                            message: "Row \(index + 1): \(error.message)"
                        ))
                    }
                }
            }

            // Table-scoped uniqueness: enforce the child DocType's unique
            // indexes across the rows of this one table (P0.5 duplicate-row
            // detection). Legitimate exact-duplicate lines are allowed unless
            // the child DocType explicitly marks a field unique.
            errors.append(contentsOf: duplicateRowErrors(rows: rows, childType: childType, tableKey: field.key))
        }

        return errors
    }

    private func makeChildDocument(row: ChildRow, childType: DocType, parent: Document) -> Document {
        Document(
            id: row.id,
            docType: childType.id,
            company: parent.company,
            status: "",
            createdAt: parent.createdAt,
            updatedAt: parent.updatedAt,
            syncVersion: 0,
            syncState: .local,
            fields: row.fields,
            children: [:]
        )
    }

    private func makeChildContext(childType: DocType, parent: ValidationContext) -> ValidationContext {
        ValidationContext(
            docType: childType,
            userId: parent.userId,
            userRoles: parent.userRoles,
            operation: parent.operation,
            expressionEvaluator: parent.expressionEvaluator,
            permissionEngine: parent.permissionEngine,
            documentExists: parent.documentExists,
            // Child uniqueness is handled table-locally, not against the store.
            uniqueConflictExists: { _, _, _, _ in false },
            workflowProvider: { _ in nil },
            previousStatus: { _, _ in nil },
            childDocTypeProvider: parent.childDocTypeProvider
        )
    }

    private func rowFieldPath(table: String, index: Int, field: String?) -> String {
        guard let field else { return "\(table)[\(index)]" }
        return "\(table)[\(index)].\(field)"
    }

    private func duplicateRowErrors(rows: [ChildRow], childType: DocType, tableKey: String) -> [DocumentValidationError] {
        var errors: [DocumentValidationError] = []
        for index in childType.indexes where index.unique {
            // (value, firstRowIndex) pairs; linear scan keeps this dependent only
            // on FieldValue: Equatable (it is not guaranteed Hashable).
            var seen: [(value: FieldValue, row: Int)] = []
            for (rowIndex, row) in rows.enumerated() {
                guard let value = row.fields[index.fieldKey], !isNull(value) else { continue }
                if let first = seen.first(where: { $0.value == value }) {
                    errors.append(DocumentValidationError(
                        stage: stageName,
                        field: rowFieldPath(table: tableKey, index: rowIndex, field: index.fieldKey),
                        message: "Row \(rowIndex + 1): duplicates '\(index.fieldKey)' from row \(first.row + 1)."
                    ))
                } else {
                    seen.append((value, rowIndex))
                }
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

/// If the document has an associated workflow, any change to `status` must correspond
/// to a transition declared in the `WorkflowDefinition`. The transition's `allowedRoles`
/// and `conditionExpression` are enforced. (ADR-022, ADR-004, P1.5)
///
/// Scope:
/// - The DocType must declare `workflowId`, and the workflow must be resolvable via
///   `context.workflowProvider`. If either is absent, the stage passes.
/// - Creation (no previously-persisted status) is **not** a transition; accepted.
/// - Saves that leave `status` unchanged are **not** transitions; accepted.
/// - Saves that change `status` require a matching `WorkflowTransition`
///   (`from == previous`, `to == document.status`). Missing transitions, missing
///   roles, or failing conditions produce typed errors.
///
/// Role enforcement is skipped only when the caller provided no user roles
/// (system / import contexts), matching the convention used by `PermissionStage`.
public struct WorkflowGuardStage: ValidationStage {
    public let stageName = "WorkflowGuard"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        guard let workflowId = context.docType.workflowId,
              let workflow = context.workflowProvider(workflowId) else {
            return []
        }
        guard let previous = context.previousStatus(document.docType, document.id) else {
            return []
        }
        guard previous != document.status else { return [] }

        guard let transition = workflow.transitions.first(where: {
            $0.from == previous && $0.to == document.status
        }) else {
            return [DocumentValidationError(
                stage: stageName,
                field: nil,
                message: "Workflow '\(workflow.id)' does not declare a transition from '\(previous)' to '\(document.status)'."
            )]
        }

        // Role enforcement. System / import callers (empty userRoles) are exempt.
        if !context.userRoles.isEmpty,
           !transition.allowedRoles.isEmpty,
           !transition.allowedRoles.contains(where: { context.userRoles.contains($0) }) {
            return [DocumentValidationError(
                stage: stageName,
                field: nil,
                message: "User is not authorised to transition '\(context.docType.name)' from '\(previous)' to '\(document.status)'."
            )]
        }

        if let condition = transition.conditionExpression, !condition.isEmpty {
            do {
                let passes = try context.expressionEvaluator.evaluateBool(
                    expression: condition,
                    context: document.fields
                )
                if !passes {
                    return [DocumentValidationError(
                        stage: stageName,
                        field: nil,
                        message: "Workflow transition from '\(previous)' to '\(document.status)' is blocked by its condition."
                    )]
                }
            } catch {
                return [DocumentValidationError(
                    stage: stageName,
                    field: nil,
                    message: "Workflow transition condition failed to evaluate: \(error.localizedDescription)"
                )]
            }
        }

        return []
    }
}

// MARK: - Stage 7: Permission

/// Delegates to `PermissionEngine.canPerform(operation:on:userRoles:)` to confirm the
/// current user may perform `context.operation` on the DocType. (ADR-011, ADR-022, P1.5)
///
/// Scope:
/// - If `context.userRoles` is empty (system / import contexts), the stage passes.
/// - If the DocType declares no `PermissionRule`s, the stage passes — an unconstrained
///   DocType is assumed open to any caller with a role.
/// - Otherwise the operation must be granted by at least one matching role.
///
/// This is the flat-permissions wiring described in P1.5. Row-level and
/// field-level checks remain out of scope for the pipeline until the evaluator
/// chain (ADR-011 option B) lands.
public struct PermissionStage: ValidationStage {
    public let stageName = "Permission"

    public init() {}

    public func validate(document: Document, context: ValidationContext) -> [DocumentValidationError] {
        guard !context.userRoles.isEmpty else { return [] }
        guard !context.docType.permissions.isEmpty else { return [] }

        let allowed = context.permissionEngine.canPerform(
            operation: context.operation,
            on: context.docType,
            userRoles: context.userRoles
        )
        if !allowed {
            return [DocumentValidationError(
                stage: stageName,
                field: nil,
                message: "User does not have permission to \(describe(context.operation)) '\(context.docType.name)' documents."
            )]
        }
        return []
    }

    private func describe(_ operation: DocumentOperation) -> String {
        switch operation {
        case .read:   return "read"
        case .write:  return "save"
        case .create: return "create"
        case .delete: return "delete"
        case .submit: return "submit"
        case .amend:  return "amend"
        }
    }
}
