//
//  FormLayout.swift
//  mercantis core
//
//  Form-layout metadata for DocTypes (Core UX Phase UX-3).
//
//  See `Docs/UX-DIRECTION.md` §5.4. Field metadata answers "what data
//  exists?" while form-layout metadata answers "how should this DocType
//  read?". Keeping them separate lets simple DocTypes ship with no
//  FormLayout (the renderer falls back to per-field `section` hints) and
//  lets richer DocTypes group, order, and explain their fields without
//  contaminating field validation metadata.
//

import Foundation

/// Declarative layout for the form rendered by `GenericFormView`.
///
/// A DocType with `formLayout == nil` continues to render via the legacy
/// `FieldDefinition.section` / `column` grouping. A DocType with a
/// `FormLayout` controls section ordering, headers, footers, and which
/// fields appear in which section explicitly.
public struct FormLayout: Codable, Sendable, Equatable {
    public var sections: [FormLayoutSection]

    public init(sections: [FormLayoutSection]) {
        self.sections = sections
    }
}

/// A single section in a `FormLayout`.
///
/// Sections render as native `Form` sections. `title` is the section
/// header (omit for an unlabelled leading section). `helpText` renders as
/// the section footer in a muted style. `columns` is a hint for renderers
/// that can lay out two fields per row at sufficient width; values outside
/// `1...2` are clamped to `1`. `fieldKeys` lists the field keys assigned
/// to this section in display order — keys not present in the parent
/// DocType are skipped at render time.
public struct FormLayoutSection: Codable, Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let key: String
    public var title: String?
    public var helpText: String?
    public var columns: Int
    public var collapsible: Bool
    public var defaultExpanded: Bool
    public var fieldKeys: [String]

    public init(
        key: String,
        title: String? = nil,
        helpText: String? = nil,
        columns: Int = 1,
        collapsible: Bool = false,
        defaultExpanded: Bool = true,
        fieldKeys: [String]
    ) {
        self.key = key
        self.title = title
        self.helpText = helpText
        self.columns = max(1, min(2, columns))
        self.collapsible = collapsible
        self.defaultExpanded = defaultExpanded
        self.fieldKeys = fieldKeys
    }
}
