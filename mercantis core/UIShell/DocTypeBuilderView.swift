import SwiftUI

@MainActor
final class DocTypeToolingContext: ObservableObject {
    @Published var docTypes: [DocType] = []

    let validator = SchemaValidator()
    let registry: MetadataRegistry
    private let database: MercantisDatabase

    init() {
        let dbURL = Self.databaseURL()
        do {
            database = try MercantisDatabase(databaseURL: dbURL)
        } catch {
            fatalError("Failed to initialize metadata database at \(dbURL.path). Verify the app has write access to Application Support. Error: \(error)")
        }

        registry = MetadataRegistry(database: database)
        do {
            try BuiltInDocTypes.registerAll(in: registry, validator: validator)
        } catch {
            print("Warning: Failed to register built-in DocTypes. Existing persisted metadata may still be used. Error: \(error)")
        }
        reload()
    }

    func reload() {
        docTypes = registry
            .all()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(docType: DocType) throws {
        try validator.validate(docType)
        try registry.register(docType)
        reload()
    }

    func errorMessage(for error: Error) -> String {
        guard let validationError = error as? SchemaValidator.ValidationError else {
            return error.localizedDescription
        }

        switch validationError {
        case .emptyDocTypeId:
            return "DocType ID cannot be empty."
        case .emptyFieldKey(let docType):
            return "Field key cannot be empty in \(docType)."
        case .duplicateFieldKey(let docType, let key):
            return "Duplicate field key '\(key)' in \(docType)."
        case .missingLinkedDocType(let docType, let fieldKey):
            return "Field '\(fieldKey)' in \(docType) requires a linked DocType."
        case .missingChildDocType(let docType, let fieldKey):
            return "Table field '\(fieldKey)' in \(docType) requires a child DocType."
        case .financialDocTypeMustUseVersionChecked(let docType):
            return "\(docType) must use versionChecked sync policy."
        case .titleFieldNotFound(let docType, let titleField):
            return "Title field '\(titleField)' does not exist in \(docType)."
        }
    }

    private static func databaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseURL.appendingPathComponent("mercantis-core", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("metadata.sqlite")
    }
}

struct EditableField: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var label: String
    var type: FieldType
    var required: Bool
    var optionsText: String
    var linkedDocType: String
    var childDocType: String
    var visibilityExpression: String

    init(
        key: String = "",
        label: String = "",
        type: FieldType = .text,
        required: Bool = false,
        optionsText: String = "",
        linkedDocType: String = "",
        childDocType: String = "",
        visibilityExpression: String = ""
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.optionsText = optionsText
        self.linkedDocType = linkedDocType
        self.childDocType = childDocType
        self.visibilityExpression = visibilityExpression
    }

    init(_ field: FieldDefinition) {
        self.init(
            key: field.key,
            label: field.label,
            type: field.type,
            required: field.required,
            optionsText: (field.options ?? []).joined(separator: ","),
            linkedDocType: field.linkedDocType ?? "",
            childDocType: field.childDocType ?? "",
            visibilityExpression: field.visibilityExpression ?? ""
        )
    }

    var fieldDefinition: FieldDefinition {
        let options = optionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return FieldDefinition(
            key: key,
            label: label.isEmpty ? key : label,
            type: type,
            required: required,
            options: options.isEmpty ? nil : options,
            linkedDocType: linkedDocType.isEmpty ? nil : linkedDocType,
            childDocType: childDocType.isEmpty ? nil : childDocType,
            visibilityExpression: visibilityExpression.isEmpty ? nil : visibilityExpression
        )
    }
}

struct EditablePermission: Identifiable, Hashable {
    let id = UUID()
    var role: String
    var canRead: Bool
    var canWrite: Bool
    var canCreate: Bool
    var canDelete: Bool
    var canSubmit: Bool
    var canAmend: Bool

    init(
        role: String = "",
        canRead: Bool = true,
        canWrite: Bool = false,
        canCreate: Bool = false,
        canDelete: Bool = false,
        canSubmit: Bool = false,
        canAmend: Bool = false
    ) {
        self.role = role
        self.canRead = canRead
        self.canWrite = canWrite
        self.canCreate = canCreate
        self.canDelete = canDelete
        self.canSubmit = canSubmit
        self.canAmend = canAmend
    }

    init(_ permission: PermissionRule) {
        self.init(
            role: permission.role,
            canRead: permission.canRead,
            canWrite: permission.canWrite,
            canCreate: permission.canCreate,
            canDelete: permission.canDelete,
            canSubmit: permission.canSubmit,
            canAmend: permission.canAmend
        )
    }

    var permissionRule: PermissionRule {
        PermissionRule(
            role: role,
            canRead: canRead,
            canWrite: canWrite,
            canCreate: canCreate,
            canDelete: canDelete,
            canSubmit: canSubmit,
            canAmend: canAmend
        )
    }
}

struct EditableIndex: Identifiable, Hashable {
    let id = UUID()
    var fieldKey: String
    var unique: Bool

    init(fieldKey: String = "", unique: Bool = false) {
        self.fieldKey = fieldKey
        self.unique = unique
    }

    init(_ index: IndexDefinition) {
        self.init(fieldKey: index.fieldKey, unique: index.unique)
    }

    var indexDefinition: IndexDefinition {
        IndexDefinition(fieldKey: fieldKey, unique: unique)
    }
}

public struct DocTypeBuilderView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    @Environment(\.dismiss) private var dismiss

    private let existingDocType: DocType?
    private let onSave: (() -> Void)?

    @State private var docTypeId = ""
    @State private var name = ""
    @State private var module = ""
    @State private var isSubmittable = false
    @State private var isChildTable = false
    @State private var titleField = ""
    @State private var searchFields = ""
    @State private var conflictResolution: ConflictResolution = .lastWriteWins
    @State private var immutableAfterSubmit = false
    @State private var fields: [EditableField] = []
    @State private var permissions: [EditablePermission] = []
    @State private var indexes: [EditableIndex] = []
    @State private var validationError: String?
    @State private var didLoadExisting = false

    public init(docType: DocType? = nil, onSave: (() -> Void)? = nil) {
        self.existingDocType = docType
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            if let validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(.red)
                }
            }

            Section("Basic Info") {
                TextField("DocType ID", text: $docTypeId)
                TextField("Name", text: $name)
                TextField("Module", text: $module)
                Toggle("Submittable", isOn: $isSubmittable)
                Toggle("Child Table", isOn: $isChildTable)
                TextField("Title Field", text: $titleField)
                TextField("Search Fields (comma-separated)", text: $searchFields)
            }

            Section("Fields") {
                ForEach($fields) { $field in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Key", text: $field.key)
                        TextField("Label", text: $field.label)
                        Picker("Type", selection: $field.type) {
                            ForEach(FieldType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        Toggle("Required", isOn: $field.required)
                        TextField("Options (comma-separated)", text: $field.optionsText)
                        TextField("Linked DocType", text: $field.linkedDocType)
                        TextField("Child DocType", text: $field.childDocType)
                        TextField("Visibility Expression", text: $field.visibilityExpression)
                    }
                }
                .onDelete { fields.remove(atOffsets: $0) }
                .onMove { fields.move(fromOffsets: $0, toOffset: $1) }

                Button("Add Field") {
                    fields.append(EditableField())
                }
            }

            Section("Permission Rules") {
                ForEach($permissions) { $permission in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $permission.role)
                        Toggle("Read", isOn: $permission.canRead)
                        Toggle("Write", isOn: $permission.canWrite)
                        Toggle("Create", isOn: $permission.canCreate)
                        Toggle("Delete", isOn: $permission.canDelete)
                        Toggle("Submit", isOn: $permission.canSubmit)
                        Toggle("Amend", isOn: $permission.canAmend)
                    }
                }
                .onDelete { permissions.remove(atOffsets: $0) }

                Button("Add Permission Rule") {
                    permissions.append(EditablePermission())
                }
            }

            Section("Sync Policy") {
                Picker("Conflict Resolution", selection: $conflictResolution) {
                    ForEach(ConflictResolution.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Toggle("Immutable After Submit", isOn: $immutableAfterSubmit)
            }

            Section("Indexes") {
                ForEach($indexes) { $index in
                    HStack {
                        TextField("Field Key", text: $index.fieldKey)
                        Toggle("Unique", isOn: $index.unique)
                    }
                }
                .onDelete { indexes.remove(atOffsets: $0) }

                Button("Add Index") {
                    indexes.append(EditableIndex())
                }
            }
        }
        .navigationTitle(existingDocType == nil ? "New DocType" : "Edit DocType")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save", action: save)
            }
        }
        .onAppear {
            guard !didLoadExisting, let existingDocType else { return }
            docTypeId = existingDocType.id
            name = existingDocType.name
            module = existingDocType.module
            isSubmittable = existingDocType.isSubmittable
            isChildTable = existingDocType.isChildTable
            titleField = existingDocType.titleField
            searchFields = existingDocType.searchFields.joined(separator: ",")
            conflictResolution = existingDocType.syncPolicy.conflictResolution
            immutableAfterSubmit = existingDocType.syncPolicy.immutableAfterSubmit
            fields = existingDocType.fields.map(EditableField.init)
            permissions = existingDocType.permissions.map(EditablePermission.init)
            indexes = existingDocType.indexes.map(EditableIndex.init)
            didLoadExisting = true
        }
    }

    private func save() {
        validationError = nil

        let searchFieldList = searchFields
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let sanitizedId = docTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBuiltIn = BuiltInDocTypes.all.contains(where: { $0.id == sanitizedId })

        let docType = DocType(
            id: sanitizedId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            module: module.trimmingCharacters(in: .whitespacesAndNewlines),
            appId: existingDocType?.appId ?? "custom.local",
            isChildTable: isChildTable,
            isSubmittable: isSubmittable,
            fields: fields.map(\.fieldDefinition),
            permissions: permissions.map(\.permissionRule),
            syncPolicy: SyncPolicy(
                conflictResolution: conflictResolution,
                immutableAfterSubmit: immutableAfterSubmit
            ),
            indexes: indexes
                .map(\.indexDefinition)
                .filter { !$0.fieldKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            searchFields: searchFieldList,
            titleField: titleField.trimmingCharacters(in: .whitespacesAndNewlines),
            isCustom: !isBuiltIn
        )

        do {
            try tooling.save(docType: docType)
            onSave?()
            dismiss()
        } catch {
            validationError = tooling.errorMessage(for: error)
        }
    }
}
