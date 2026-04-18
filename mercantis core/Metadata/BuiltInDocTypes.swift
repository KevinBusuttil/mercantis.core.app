import Foundation

/// Built-in system DocTypes that bootstrap customization tooling.
public enum BuiltInDocTypes {
    private static let coreAppId = "core.system"

    public static let docTypeField = DocType(
        id: "DocTypeField",
        name: "DocType Field",
        module: "Core",
        appId: coreAppId,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "key", label: "Key", type: .text, required: true),
            FieldDefinition(key: "label", label: "Label", type: .text, required: true),
            FieldDefinition(key: "type", label: "Type", type: .select, required: true, options: FieldType.allCases.map(\.rawValue)),
            FieldDefinition(key: "required", label: "Required", type: .boolean, required: false),
            FieldDefinition(key: "options", label: "Options", type: .longText, required: false)
        ],
        permissions: [],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["key", "label"],
        titleField: "label"
    )

    public static let docTypePermission = DocType(
        id: "DocTypePermission",
        name: "DocType Permission",
        module: "Core",
        appId: coreAppId,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "role", label: "Role", type: .text, required: true),
            FieldDefinition(key: "canRead", label: "Read", type: .boolean, required: false),
            FieldDefinition(key: "canWrite", label: "Write", type: .boolean, required: false),
            FieldDefinition(key: "canCreate", label: "Create", type: .boolean, required: false),
            FieldDefinition(key: "canDelete", label: "Delete", type: .boolean, required: false),
            FieldDefinition(key: "canSubmit", label: "Submit", type: .boolean, required: false),
            FieldDefinition(key: "canAmend", label: "Amend", type: .boolean, required: false)
        ],
        permissions: [],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["role"],
        titleField: "role"
    )

    public static let docType = DocType(
        id: "DocType",
        name: "DocType",
        module: "Core",
        appId: coreAppId,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "name", label: "Name", type: .text, required: true),
            FieldDefinition(key: "module", label: "Module", type: .text, required: true),
            FieldDefinition(key: "isSubmittable", label: "Is Submittable", type: .boolean, required: false),
            FieldDefinition(key: "isChildTable", label: "Is Child Table", type: .boolean, required: false),
            FieldDefinition(key: "titleField", label: "Title Field", type: .text, required: false),
            FieldDefinition(key: "searchFields", label: "Search Fields", type: .text, required: false),
            FieldDefinition(key: "fields", label: "Fields", type: .table, required: false, childDocType: docTypeField.id),
            FieldDefinition(key: "permissions", label: "Permissions", type: .table, required: false, childDocType: docTypePermission.id)
        ],
        permissions: [],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["name", "module"],
        titleField: "name"
    )

    public static var all: [DocType] {
        [docTypeField, docTypePermission, docType]
    }

    public static func registerAll(in registry: MetadataRegistry, validator: SchemaValidator = SchemaValidator()) throws {
        for docType in all {
            try validator.validate(docType)
            try registry.register(docType)
        }
    }
}
