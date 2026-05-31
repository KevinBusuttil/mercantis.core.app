//
//  DocumentDisplayPolicy.swift
//  mercantis core
//
//  A generic, data-driven mapping layer that lets a host application present
//  Core's lifecycle (`docStatus`) and workflow (`Document.status`) using
//  business-friendly, document-specific wording — without weakening any of
//  Core's posting / audit / reversal discipline.
//
//  Core deliberately ships NO domain knowledge here: it only knows how to
//  look a label up and how to fall back safely. The host (e.g. Mercantis Hub)
//  injects the actual aliases. (B/C of the lifecycle-wording initiative.)
//

import Foundation

/// Semantic tone for a status / lifecycle badge.
///
/// Kept SwiftUI-free so it lives in the headless `MercantisCore` library and
/// stays unit-testable. The UI layer maps each case onto a concrete colour
/// treatment. Colour is never the only signal — the label text always shows.
public enum DocumentStatusTone: String, Codable, Sendable, CaseIterable {
    case muted
    case info
    case brand
    case success
    case warning
    case danger

    /// Best-effort classification of an arbitrary status string. Used as the
    /// fallback tone whenever a host hasn't configured an explicit alias, so
    /// unknown statuses still get a sensible colour instead of crashing.
    public static func classify(_ raw: String) -> DocumentStatusTone {
        let compact = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch compact {
        case "paid", "completed", "complete", "done", "reconciled", "settled",
             "active", "accepted", "received", "delivered", "fulfilled":
            return .success
        case "submitted", "posted", "issued", "confirmed", "released", "ordered",
             "approved":
            return .brand
        case "sent", "inprogress", "processing", "planned", "open", "recorded":
            return .info
        case "overdue", "stopped", "onhold", "hold", "unpaid", "suspended",
             "pending":
            return .warning
        case "cancelled", "canceled", "reversed", "lost", "rejected", "failed",
             "void", "expired", "error":
            return .danger
        case "draft", "new", "closed", "inactive", "disabled", "archived":
            return .muted
        default:
            // Keyword fallbacks for compound statuses.
            if compact.contains("overdue") || compact.contains("unpaid") { return .warning }
            if compact.contains("paid") || compact.contains("complete") { return .success }
            if compact.contains("cancel") || compact.contains("revers") || compact.contains("reject") { return .danger }
            if compact.contains("post") || compact.contains("submit") || compact.contains("confirm") { return .brand }
            if compact.contains("progress") || compact.contains("sent") { return .info }
            if compact.contains("draft") || compact.contains("close") || compact.contains("inactive") { return .muted }
            return .muted
        }
    }
}

/// The user-facing presentation of a single status / lifecycle state.
public struct DocumentStatusDisplay: Equatable, Sendable {
    /// Always-shown, business-friendly label (e.g. "Posted", "Confirmed").
    public let label: String
    /// Semantic tone for the badge colour treatment.
    public let tone: DocumentStatusTone
    /// Optional tooltip / help text explaining the state.
    public let help: String?

    public init(label: String, tone: DocumentStatusTone, help: String? = nil) {
        self.label = label
        self.tone = tone
        self.help = help
    }
}

/// The user-facing presentation of a lifecycle / workflow action (button).
public struct DocumentActionDisplay: Equatable, Sendable {
    /// Always-shown button label (e.g. "Post Invoice", "Confirm Order").
    public let label: String
    /// Optional confirmation copy shown before a ledger / stock-affecting
    /// action runs. `nil` means "no confirmation step needed".
    public let confirmation: String?

    public var requiresConfirmation: Bool { confirmation != nil }

    public init(label: String, confirmation: String? = nil) {
        self.label = label
        self.confirmation = confirmation
    }
}

/// A single DocType's display mapping: workflow-state aliases plus action
/// aliases. Lookups are case-insensitive on the raw key so a host can declare
/// `"Submitted"` and still match `document.status == "submitted"`.
public struct DocTypeDisplayMapping: Sendable {
    /// Raw workflow-state string → business display. Keyed lower-cased.
    public let statuses: [String: DocumentStatusDisplay]
    /// Raw action name → business display. Keyed lower-cased.
    public let actions: [String: DocumentActionDisplay]

    public init(
        statuses: [String: DocumentStatusDisplay] = [:],
        actions: [String: DocumentActionDisplay] = [:]
    ) {
        self.statuses = Dictionary(
            statuses.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        self.actions = Dictionary(
            actions.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }
}

/// Generic, data-driven display policy. Maps `(docTypeId, state/action)` onto
/// business-friendly labels, tones and confirmation copy with safe fallbacks.
///
/// A pure value type — the host injects domain mappings rather than Core
/// hard-coding them. When no mapping is found the raw string is surfaced
/// verbatim (tone-classified), so an unconfigured or brand-new DocType never
/// renders blank or crashes.
public struct DocumentDisplayPolicy: Sendable {
    private let mappings: [String: DocTypeDisplayMapping]

    public init(mappings: [String: DocTypeDisplayMapping] = [:]) {
        self.mappings = mappings
    }

    /// A no-op policy that surfaces every raw status / action verbatim. Used
    /// as the default so Core components work with or without a host policy.
    public static let passthrough = DocumentDisplayPolicy()

    // MARK: - Status

    /// Display for a workflow-state string. Falls back to the tone-classified
    /// raw string when no alias is configured. Empty strings render as Draft.
    public func statusDisplay(docTypeId: String, state: String) -> DocumentStatusDisplay {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = mappings[docTypeId]?.statuses[trimmed.lowercased()] {
            return mapped
        }
        let label = trimmed.isEmpty ? "Draft" : trimmed
        return DocumentStatusDisplay(label: label, tone: DocumentStatusTone.classify(label))
    }

    /// Display for the Core `docStatus` lifecycle (0 Draft / 1 Submitted /
    /// 2 Cancelled), resolved through the same DocType aliases so a submitted
    /// invoice's lifecycle reads "Posted" rather than the raw "Submitted".
    public func lifecycleDisplay(docTypeId: String, docStatus: Int) -> DocumentStatusDisplay {
        let canonical: String
        switch docStatus {
        case 1:  canonical = "Submitted"
        case 2:  canonical = "Cancelled"
        default: canonical = "Draft"
        }
        return statusDisplay(docTypeId: docTypeId, state: canonical)
    }

    // MARK: - Actions

    /// Display for a lifecycle / workflow action. Falls back to the raw action
    /// string (e.g. "Submit") when no alias is configured.
    public func actionDisplay(docTypeId: String, action: String) -> DocumentActionDisplay {
        if let mapped = mappings[docTypeId]?.actions[action.lowercased()] {
            return mapped
        }
        return DocumentActionDisplay(label: action)
    }

    /// Whether the host configured any mapping for this DocType. Useful for
    /// callers that want to special-case fully-unmapped (e.g. master-data)
    /// DocTypes.
    public func hasMapping(docTypeId: String) -> Bool {
        mappings[docTypeId] != nil
    }
}
