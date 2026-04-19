//
//  ResolvedMeta.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

/// The authoritative runtime representation of a DocType. (ADR-021)
///
/// Produced by `MetaComposer.resolve(docType:)` by merging three layers:
/// 1. Base definition — the `DocType` from the manifest / `doctypes` table.
/// 2. Custom fields — user-added fields from the `custom_fields` table.
/// 3. Property overrides — `PropertySetter` records that override field properties.
///
/// **All runtime consumers use `ResolvedMeta`, not raw `DocType`.** `MetadataRegistry`
/// remains the source of raw definitions; `MetaComposer` is the gateway for runtime use.
public struct ResolvedMeta: Sendable {

    /// The DocType name/id.
    public let docTypeName: String

    /// The display name of the DocType.
    public let displayName: String

    /// The module this DocType belongs to.
    public let module: String

    /// The app that owns this DocType.
    public let appId: String

    /// The fully resolved field list (base + custom fields + property overrides applied).
    public let fields: [ResolvedFieldDefinition]

    /// DocType-level permission rules.
    public let permissionRules: [PermissionRule]

    /// The sync policy for this DocType.
    public let syncPolicy: SyncPolicy

    /// Index definitions for query performance.
    public let indexDefinitions: [IndexDefinition]

    /// Optional workflow reference.
    public let workflowId: String?

    /// Whether this DocType supports the Submit/Cancel/Amend lifecycle.
    public let isSubmittable: Bool

    /// Whether this DocType is a singleton.
    public let isSingle: Bool

    /// Whether this DocType is a child table.
    public let isChildTable: Bool

    /// Whether this is a custom (user-created) DocType.
    public let isCustom: Bool

    /// The field key used as the display title.
    public let titleField: String

    /// Field keys used for search.
    public let searchFields: [String]

    /// The autoname strategy string.
    public let autoname: String?

    public init(
        docTypeName: String,
        displayName: String,
        module: String,
        appId: String,
        fields: [ResolvedFieldDefinition],
        permissionRules: [PermissionRule],
        syncPolicy: SyncPolicy,
        indexDefinitions: [IndexDefinition],
        workflowId: String?,
        isSubmittable: Bool,
        isSingle: Bool,
        isChildTable: Bool,
        isCustom: Bool,
        titleField: String,
        searchFields: [String],
        autoname: String?
    ) {
        self.docTypeName = docTypeName
        self.displayName = displayName
        self.module = module
        self.appId = appId
        self.fields = fields
        self.permissionRules = permissionRules
        self.syncPolicy = syncPolicy
        self.indexDefinitions = indexDefinitions
        self.workflowId = workflowId
        self.isSubmittable = isSubmittable
        self.isSingle = isSingle
        self.isChildTable = isChildTable
        self.isCustom = isCustom
        self.titleField = titleField
        self.searchFields = searchFields
        self.autoname = autoname
    }
}

// MARK: - Resolved Field Definition

/// A fully resolved field definition after merging base + custom fields + property overrides.
public struct ResolvedFieldDefinition: Sendable, Identifiable {
    public let id: String  // fieldKey

    /// The field key.
    public let key: String

    /// The display label (may be overridden by a PropertySetter).
    public let label: String

    /// The field type.
    public let type: FieldType

    /// Whether the field is required.
    public let isRequired: Bool

    /// Default value (may be overridden).
    public let defaultValue: FieldValue?

    /// Options for select/multiselect fields (may be overridden).
    public let options: [String]?

    /// For Link fields: the linked DocType.
    public let linkedDocType: String?

    /// For Table fields: the child DocType.
    public let childDocType: String?

    /// Validation rules.
    public let validationRules: [ValidationRule]

    /// Expression controlling field visibility.
    public let visibilityExpression: String?

    /// Expression controlling read-only state.
    public let readOnlyExpression: String?

    /// Formula expression for computed fields.
    public let formulaExpression: String?

    /// Field-level permission rules.
    public let permissions: FieldPermission?

    /// Whether this field is indexed for search.
    public let isSearchable: Bool

    /// Whether this field is synced.
    public let isSynced: Bool

    /// Whether this field can be edited after document submission.
    public let allowOnSubmit: Bool

    /// Whether this field originated from a custom field (not the base definition).
    public let isCustom: Bool

    /// Section grouping.
    public let section: String?

    /// Column index for grid layout.
    public let column: Int?

    public init(
        key: String,
        label: String,
        type: FieldType,
        isRequired: Bool = false,
        defaultValue: FieldValue? = nil,
        options: [String]? = nil,
        linkedDocType: String? = nil,
        childDocType: String? = nil,
        validationRules: [ValidationRule] = [],
        visibilityExpression: String? = nil,
        readOnlyExpression: String? = nil,
        formulaExpression: String? = nil,
        permissions: FieldPermission? = nil,
        isSearchable: Bool = false,
        isSynced: Bool = true,
        allowOnSubmit: Bool = false,
        isCustom: Bool = false,
        section: String? = nil,
        column: Int? = nil
    ) {
        self.id = key
        self.key = key
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.options = options
        self.linkedDocType = linkedDocType
        self.childDocType = childDocType
        self.validationRules = validationRules
        self.visibilityExpression = visibilityExpression
        self.readOnlyExpression = readOnlyExpression
        self.formulaExpression = formulaExpression
        self.permissions = permissions
        self.isSearchable = isSearchable
        self.isSynced = isSynced
        self.allowOnSubmit = allowOnSubmit
        self.isCustom = isCustom
        self.section = section
        self.column = column
    }
}
