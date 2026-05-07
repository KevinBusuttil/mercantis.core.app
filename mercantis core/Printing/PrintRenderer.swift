//
//  PrintRenderer.swift
//  mercantis core
//
//  Phase C / P3.2 (ADR-044) — Renderer protocol + shared helpers used by
//  every concrete renderer (plain text, PDF). Renderers are stateless and
//  Sendable; per-call state arrives via `PrintRenderContext`.
//

import Foundation

/// Output format requested from `PrintService.render(...)`.
public enum PrintOutputKind: String, Sendable, Codable {
    case plainText
    case pdf
}

/// Inputs assembled by `PrintService` for one render call.
public struct PrintRenderContext: Sendable {
    public let format: PrintFormat
    public let document: Document
    public let letterHead: LetterHead?
    /// MIME type the resulting bytes claim. Set by the renderer.
    public let now: Date

    public init(
        format: PrintFormat,
        document: Document,
        letterHead: LetterHead?,
        now: Date = Date()
    ) {
        self.format = format
        self.document = document
        self.letterHead = letterHead
        self.now = now
    }
}

public struct PrintRenderResult: Sendable {
    public let data: Data
    public let mimeType: String
    public let suggestedFileName: String

    public init(data: Data, mimeType: String, suggestedFileName: String) {
        self.data = data
        self.mimeType = mimeType
        self.suggestedFileName = suggestedFileName
    }
}

/// One concrete output backend. Each backend handles one
/// `PrintOutputKind`. `PrintService` picks the right backend by kind.
public protocol PrintRenderer: Sendable {
    var outputKind: PrintOutputKind { get }
    func render(_ context: PrintRenderContext) throws -> PrintRenderResult
}

public enum PrintRenderError: Error, Sendable, Equatable {
    case missingFieldInTemplate(field: String)
    case unsupportedSection(reason: String)
    case backendUnavailable(reason: String)
}

// MARK: - Shared helpers

/// Helpers shared by every renderer: `{field}` substitution and the
/// default formatting of a `FieldValue` to a printable string.
///
/// All methods are `nonisolated` so they can be called from any actor
/// context (Swift 6 strict-concurrency builds infer `@MainActor` on
/// some module-level statics; explicit `nonisolated` keeps the
/// renderer pipeline portable).
public enum PrintTemplate {

    /// Substitute every `{key}` placeholder in `template` with the
    /// formatted `document.fields[key]`. Unknown keys are left as-is
    /// (`"{unknown}"` literal in output) so format authors can spot
    /// typos without the renderer crashing.
    nonisolated public static func substitute(_ template: String, in document: Document) -> String {
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{",
               let close = template[i...].firstIndex(of: "}") {
                let keyStart = template.index(after: i)
                let key = String(template[keyStart..<close])
                if !key.isEmpty, !key.contains("{") {
                    if let value = lookup(key: key, in: document) {
                        out += format(value)
                    } else {
                        out += "{\(key)}"
                    }
                    i = template.index(after: close)
                    continue
                }
            }
            out.append(template[i])
            i = template.index(after: i)
        }
        return out
    }

    /// Lookup `key` against the document's fields plus a few system-column
    /// conveniences (`id`, `status`, `docStatus`, `createdAt`, `updatedAt`,
    /// `company`).
    nonisolated public static func lookup(key: String, in document: Document) -> FieldValue? {
        if let field = document.fields[key] { return field }
        switch key {
        case "id":          return .string(document.id)
        case "company":     return .string(document.company)
        case "status":      return .string(document.status)
        case "docStatus":   return .int(document.docStatus)
        case "createdAt":   return .dateTime(document.createdAt)
        case "updatedAt":   return .dateTime(document.updatedAt)
        default:            return nil
        }
    }

    /// Default printable form of a `FieldValue`. Renderers can override
    /// per-type formatting if they need locale-aware money / date output.
    nonisolated public static func format(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return formattedDouble(d)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return ""
        case .date(let d):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: d)
        case .dateTime(let d):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        case .data(let d):   return "<\(d.count) bytes>"
        case .array(let xs): return xs.map(format).joined(separator: ", ")
        }
    }

    nonisolated private static func formattedDouble(_ d: Double) -> String {
        if d == d.rounded() {
            return String(format: "%.0f", d)
        }
        return String(format: "%g", d)
    }

    /// Humanise a snake_case or camelCase field key into a label.
    nonisolated public static func defaultLabel(forKey key: String) -> String {
        if key.isEmpty { return key }
        var spaced = ""
        for (i, ch) in key.enumerated() {
            if ch == "_" {
                spaced += " "
            } else if ch.isUppercase, i > 0 {
                spaced += " "
                spaced.append(ch)
            } else {
                spaced.append(ch)
            }
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
