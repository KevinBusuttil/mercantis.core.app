//
//  BuiltInActionHandlers.swift
//  mercantis core
//
//  P1.2 — Built-in `AutomationActionHandler` conformances. (ADR-019, ADR-025)
//
//  The five built-ins map to the action type table in ADR-025:
//
//      | actionType         | Handler                    |
//      |--------------------|----------------------------|
//      | set_value          | SetValueHandler            |
//      | set_status         | SetStatusHandler           |
//      | send_notification  | SendNotificationHandler    |
//      | validate           | ValidateHandler            |
//      | assign             | AssignHandler              |
//

import Foundation

// MARK: - Bulk registration

/// Convenience registrar for all built-in handlers. Called by the
/// `AutomationActionRegistry` initialiser unless the caller opts out.
public enum BuiltInAutomationActions {
    public static func registerAll(into registry: AutomationActionRegistry) {
        registry.register(SetValueHandler())
        registry.register(SetStatusHandler())
        registry.register(SendNotificationHandler())
        registry.register(ValidateHandler())
        registry.register(AssignHandler())
    }
}

// MARK: - set_value

/// Set a single field on the document to a literal value.
///
/// Parameters:
/// - `field` (required) — the field key to write.
/// - `value` (required) — the literal value. Interpreted via
///   `FieldValueDecoder.decode(_:)` so `"42"` becomes `.int(42)`,
///   `"true"` becomes `.bool(true)`, etc.
/// - `type` (optional) — force a specific `FieldValue` case:
///   `"string" | "int" | "double" | "bool" | "null"`. When present,
///   overrides the automatic inference.
public struct SetValueHandler: AutomationActionHandler {
    public static let actionType = "set_value"
    public init() {}

    public func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        guard let field = parameters["field"], !field.isEmpty else {
            throw AutomationActionError.missingParameter(
                actionType: Self.actionType, name: "field"
            )
        }
        guard let raw = parameters["value"] else {
            throw AutomationActionError.missingParameter(
                actionType: Self.actionType, name: "value"
            )
        }
        let value = try FieldValueDecoder.decode(raw, forcedType: parameters["type"])
        document.fields[field] = value
    }
}

// MARK: - set_status

/// Change the document's workflow `status`.
///
/// This only writes to `document.status`. ADR-013's `docStatus` lifecycle
/// (Draft/Submitted/Cancelled) is controlled by `DocumentEngine.submit/cancel/amend`
/// and is deliberately not a target of this handler — automation must go
/// through those paths to preserve the submit immutability guard.
///
/// Parameters:
/// - `status` (required) — the target workflow state name.
public struct SetStatusHandler: AutomationActionHandler {
    public static let actionType = "set_status"
    public init() {}

    public func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        guard let status = parameters["status"], !status.isEmpty else {
            throw AutomationActionError.missingParameter(
                actionType: Self.actionType, name: "status"
            )
        }
        document.status = status
    }
}

// MARK: - send_notification

/// Emit a notification-log entry. The handler never sends email or push
/// itself — delivery is the sink's responsibility. The default sink
/// (`InMemoryNotificationLog`) just records the entry.
///
/// Parameters:
/// - `channel` (optional, default `"default"`) — logical transport, e.g.
///   `"email"`, `"push"`, `"ops"`.
/// - `recipient` (optional) — user id, email address, or role name, depending
///   on the channel.
/// - `subject` (optional, default `""`).
/// - `body` (optional, default `""`). Placeholders of the form `{field}` are
///   substituted from `document.fields`; unknown placeholders are left as-is.
public struct SendNotificationHandler: AutomationActionHandler {
    public static let actionType = "send_notification"
    public init() {}

    public func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        let channel = parameters["channel"] ?? "default"
        let recipient = parameters["recipient"]
        let subject = ParameterInterpolator.interpolate(
            parameters["subject"] ?? "", in: document
        )
        let body = ParameterInterpolator.interpolate(
            parameters["body"] ?? "", in: document
        )
        let entry = NotificationLogEntry(
            appId: context.appId,
            docType: context.docType.isEmpty ? document.docType : context.docType,
            documentId: context.documentId.isEmpty ? document.id : context.documentId,
            channel: channel,
            recipient: recipient,
            subject: subject,
            body: body,
            emittedAt: context.now
        )
        context.notificationSink.write(entry)
    }
}

// MARK: - validate

/// Throw a `validationFailed` error when the condition expression evaluates
/// to `false`. Intended to block a save when run inside the save transaction
/// — ADR-019 calls this the "blocking save" path. When run post-commit
/// (which is what the P1.3 extension-point resolver currently does), a
/// thrown error is surfaced to the dispatcher's error reporter; the commit
/// is not rolled back.
///
/// Parameters:
/// - `expression` (required) — a boolean `ExpressionEvaluator` expression.
/// - `message` (optional, default `"Validation failed."`) — error text.
public struct ValidateHandler: AutomationActionHandler {
    public static let actionType = "validate"
    public init() {}

    public func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        guard let expression = parameters["expression"], !expression.isEmpty else {
            throw AutomationActionError.missingParameter(
                actionType: Self.actionType, name: "expression"
            )
        }
        let message = parameters["message"] ?? "Validation failed."

        let passes: Bool
        do {
            passes = try context.expressionEvaluator.evaluateBool(
                expression: expression,
                context: document.fields
            )
        } catch {
            throw AutomationActionError.expressionFailed(
                actionType: Self.actionType,
                expression: expression,
                underlying: "\(error)"
            )
        }
        if !passes {
            throw AutomationActionError.validationFailed(message: message)
        }
    }
}

// MARK: - assign

/// Record an assignment of the document to a user or role.
///
/// Parameters:
/// - `user` or `role` (one of, required).
/// - `note` (optional).
public struct AssignHandler: AutomationActionHandler {
    public static let actionType = "assign"
    public init() {}

    public func execute(
        document: inout Document,
        parameters: [String: String],
        context: AutomationContext
    ) throws {
        let target: AssignmentLogEntry.Target
        if let user = parameters["user"], !user.isEmpty {
            target = .user(user)
        } else if let role = parameters["role"], !role.isEmpty {
            target = .role(role)
        } else {
            throw AutomationActionError.missingParameter(
                actionType: Self.actionType, name: "user|role"
            )
        }

        let entry = AssignmentLogEntry(
            appId: context.appId,
            docType: context.docType.isEmpty ? document.docType : context.docType,
            documentId: context.documentId.isEmpty ? document.id : context.documentId,
            target: target,
            note: parameters["note"],
            assignedBy: context.userId,
            assignedAt: context.now
        )
        context.assignmentSink.write(entry)
    }
}

// MARK: - Helpers

/// Converts a string literal from a manifest declaration into a `FieldValue`.
///
/// Disambiguation: a manifest only carries strings, so `"42"` could mean the
/// number 42 or the string `"42"`. Callers can force the interpretation
/// via an explicit `type` parameter; otherwise the decoder infers from the
/// literal shape (bool → int → double → string, in that order).
enum FieldValueDecoder {
    static func decode(_ raw: String, forcedType: String?) throws -> FieldValue {
        if let forced = forcedType?.lowercased(), !forced.isEmpty {
            switch forced {
            case "string":
                return .string(raw)
            case "int", "integer":
                guard let n = Int(raw) else {
                    throw AutomationActionError.invalidParameter(
                        actionType: "set_value",
                        name: "value",
                        reason: "expected Int, got '\(raw)'"
                    )
                }
                return .int(n)
            case "double", "decimal", "number":
                guard let d = Double(raw) else {
                    throw AutomationActionError.invalidParameter(
                        actionType: "set_value",
                        name: "value",
                        reason: "expected Double, got '\(raw)'"
                    )
                }
                return .double(d)
            case "bool", "boolean":
                switch raw.lowercased() {
                case "true", "yes", "1":  return .bool(true)
                case "false", "no", "0":  return .bool(false)
                default:
                    throw AutomationActionError.invalidParameter(
                        actionType: "set_value",
                        name: "value",
                        reason: "expected Bool, got '\(raw)'"
                    )
                }
            case "null":
                return .null
            default:
                throw AutomationActionError.invalidParameter(
                    actionType: "set_value",
                    name: "type",
                    reason: "unknown type '\(forced)'"
                )
            }
        }
        // Inference path. Preserve this order: a bare `"1"` should decode as
        // an Int, not a Bool, so the explicit literals come first.
        switch raw.lowercased() {
        case "true":  return .bool(true)
        case "false": return .bool(false)
        case "null":  return .null
        default: break
        }
        if let n = Int(raw) { return .int(n) }
        if let d = Double(raw) { return .double(d) }
        return .string(raw)
    }
}

/// Very small `{field}` placeholder expander used by
/// `SendNotificationHandler`. Unknown placeholders are left as `{name}` so
/// tests can detect them and callers can iterate.
enum ParameterInterpolator {
    static func interpolate(_ template: String, in document: Document) -> String {
        guard template.contains("{") else { return template }
        var result = ""
        var buffer = ""
        var inPlaceholder = false
        for ch in template {
            if ch == "{" {
                result.append(buffer)
                buffer = ""
                inPlaceholder = true
                continue
            }
            if ch == "}" && inPlaceholder {
                if let value = document.fields[buffer] {
                    result.append(stringify(value))
                } else {
                    result.append("{")
                    result.append(buffer)
                    result.append("}")
                }
                buffer = ""
                inPlaceholder = false
                continue
            }
            buffer.append(ch)
        }
        // Trailing open brace: restore literally.
        if inPlaceholder {
            result.append("{")
            result.append(buffer)
        } else {
            result.append(buffer)
        }
        return result
    }

    private static func stringify(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return ""
        }
    }
}
