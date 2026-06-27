//
//  PrintFormat.swift
//  mercantis core
//
//  Phase C / P3.2 (ADR-044) — Declarative print formats and letter heads.
//  Manifests declare a PrintFormat per (DocType, format-id) pair; the
//  Print subsystem renders one to bytes (plain text or PDF) for any
//  document of that DocType.
//

import Foundation

/// Reusable header / footer chrome attached to print formats. Stored
/// once per app and referenced by `PrintFormat.letterHeadId`.
public struct LetterHead: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Plain text rendered above the document body. Supports `{field}`
    /// substitution from `document.fields`.
    public let header: String
    /// Optional plain-text footer rendered below the document body.
    public let footer: String?

    public init(id: String, name: String, header: String, footer: String? = nil) {
        self.id = id
        self.name = name
        self.header = header
        self.footer = footer
    }
}

/// How a link field renders on a printed document. An opaque id (UUID) is
/// never printed as a code regardless of mode — it falls back to the name.
public enum PrintLinkDisplay: String, Codable, Sendable, CaseIterable {
    /// The linked record's name only ("Kevin Busuttil").
    case name
    /// The id/code only ("CUST-2026-0002"); falls back to name for UUID keys.
    case code
    /// Both, "code — name" ("CUST-2026-0002 — Kevin Busuttil"); name only for
    /// UUID keys.
    case codeAndName
}

/// Declarative print format for one DocType.
///
/// Sections are rendered in order. Each section is a self-describing
/// structural unit (heading / paragraph / field grid / child-table grid)
/// so renderers can lay them out for the chosen output kind without
/// re-parsing markup.
public struct PrintFormat: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let docType: String
    public let letterHeadId: String?
    /// When several formats exist for a DocType, the one to use unless the
    /// operator picks another. At most one per DocType should set this.
    public let isDefault: Bool
    /// Default rendering for link fields in this format.
    public let linkDisplay: PrintLinkDisplay
    /// Per-field overrides of `linkDisplay`, keyed by field key (header or
    /// child-row column), so a format can show, say, the item as code + name
    /// while keeping the currency as name only.
    public let fieldLinkDisplays: [String: PrintLinkDisplay]
    public let sections: [PrintSection]

    public init(
        id: String,
        name: String,
        docType: String,
        letterHeadId: String? = nil,
        isDefault: Bool = false,
        linkDisplay: PrintLinkDisplay = .name,
        fieldLinkDisplays: [String: PrintLinkDisplay] = [:],
        sections: [PrintSection]
    ) {
        self.id = id
        self.name = name
        self.docType = docType
        self.letterHeadId = letterHeadId
        self.isDefault = isDefault
        self.linkDisplay = linkDisplay
        self.fieldLinkDisplays = fieldLinkDisplays
        self.sections = sections
    }

    /// The display mode for a given field key (override → format default).
    public func linkDisplay(forField key: String) -> PrintLinkDisplay {
        fieldLinkDisplays[key] ?? linkDisplay
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, docType, letterHeadId, isDefault
        case linkDisplay, fieldLinkDisplays, sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        docType = try c.decode(String.self, forKey: .docType)
        letterHeadId = try c.decodeIfPresent(String.self, forKey: .letterHeadId)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        linkDisplay = try c.decodeIfPresent(PrintLinkDisplay.self, forKey: .linkDisplay) ?? .name
        fieldLinkDisplays = try c.decodeIfPresent([String: PrintLinkDisplay].self, forKey: .fieldLinkDisplays) ?? [:]
        sections = try c.decode([PrintSection].self, forKey: .sections)
    }
}

/// One renderable unit inside a `PrintFormat`. The kind decides which
/// associated payload is meaningful — fields documented per-case.
public enum PrintSection: Codable, Sendable, Equatable {
    /// Top-level heading. `text` supports `{field}` substitution.
    case heading(text: String)
    /// A paragraph of body text. Supports `{field}` substitution.
    case paragraph(text: String)
    /// Two-column "label / value" grid over a fixed list of field keys.
    /// `labels[k]` overrides the default "humanised key" label per key.
    case fields(keys: [String], labels: [String: String] = [:])
    /// A grid for one of the document's child tables. `tableKey` is the
    /// `Document.children` map key (i.e. the parent-side `FieldType.table`
    /// field key); `columns` are the child row field keys to render in
    /// order. Empty `columns` falls back to "every key seen in the rows".
    case table(tableKey: String, columns: [String], labels: [String: String] = [:])
    /// Free-form key-value pair line, e.g. for totals: "Subtotal: 150.00".
    /// Both `label` and `value` support `{field}` substitution.
    case keyValue(label: String, value: String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind, text, keys, labels, tableKey, columns, label, value
    }

    private enum Kind: String, Codable {
        case heading, paragraph, fields, table, keyValue
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let text):
            try c.encode(Kind.heading, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .paragraph(let text):
            try c.encode(Kind.paragraph, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .fields(let keys, let labels):
            try c.encode(Kind.fields, forKey: .kind)
            try c.encode(keys, forKey: .keys)
            try c.encode(labels, forKey: .labels)
        case .table(let tableKey, let columns, let labels):
            try c.encode(Kind.table, forKey: .kind)
            try c.encode(tableKey, forKey: .tableKey)
            try c.encode(columns, forKey: .columns)
            try c.encode(labels, forKey: .labels)
        case .keyValue(let label, let value):
            try c.encode(Kind.keyValue, forKey: .kind)
            try c.encode(label, forKey: .label)
            try c.encode(value, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .heading:
            self = .heading(text: try c.decode(String.self, forKey: .text))
        case .paragraph:
            self = .paragraph(text: try c.decode(String.self, forKey: .text))
        case .fields:
            self = .fields(
                keys: try c.decode([String].self, forKey: .keys),
                labels: try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
            )
        case .table:
            self = .table(
                tableKey: try c.decode(String.self, forKey: .tableKey),
                columns: try c.decodeIfPresent([String].self, forKey: .columns) ?? [],
                labels: try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
            )
        case .keyValue:
            self = .keyValue(
                label: try c.decode(String.self, forKey: .label),
                value: try c.decode(String.self, forKey: .value)
            )
        }
    }
}
