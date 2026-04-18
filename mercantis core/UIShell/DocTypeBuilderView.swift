import SwiftUI
import Combine

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

    nonisolated init(
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

    nonisolated init(_ field: FieldDefinition) {
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

    nonisolated init(
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

    nonisolated init(_ permission: PermissionRule) {
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

    nonisolated init(fieldKey: String = "", unique: Bool = false) {
        self.fieldKey = fieldKey
        self.unique = unique
    }

    nonisolated init(_ index: IndexDefinition) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let validationError {
                    Text(validationError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MercantisTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mercantisCard()
                }

                MercantisSectionHeading(title: "Basic Info")
                VStack(spacing: 12) {
                    formRow("DocType ID") {
                        TextField("DocType ID", text: $docTypeId)
                            .mercantisInput()
                    }
                    formRow("Name") {
                        TextField("Name", text: $name)
                            .mercantisInput()
                    }
                    formRow("Module") {
                        TextField("Module", text: $module)
                            .mercantisInput()
                    }
                    formRow("Title Field") {
                        TextField("Title Field", text: $titleField)
                            .mercantisInput()
                    }
                    formRow("Search Fields") {
                        TextField("comma-separated", text: $searchFields)
                            .mercantisInput()
                    }
                    checkboxRow("Submittable", isOn: $isSubmittable)
                    checkboxRow("Child Table", isOn: $isChildTable)
                }
                .mercantisCard()

                MercantisSectionHeading(title: "Fields")
                VStack(spacing: 12) {
                    ForEach(Array(fields.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            formRow("Key") {
                                TextField("field_key", text: $fields[index].key)
                                    .mercantisInput()
                            }
                            formRow("Label") {
                                TextField("Field Label", text: $fields[index].label)
                                    .mercantisInput()
                            }
                            formRow("Type") {
                                Picker("Type", selection: $fields[index].type) {
                                    ForEach(FieldType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .mercantisPicker()
                            }
                            checkboxRow("Required", isOn: $fields[index].required)
                            formRow("Options") {
                                TextField("comma-separated options", text: $fields[index].optionsText)
                                    .mercantisInput()
                            }
                            formRow("Linked DocType") {
                                TextField("Linked DocType", text: $fields[index].linkedDocType)
                                    .mercantisInput()
                            }
                            formRow("Child DocType") {
                                TextField("Child DocType", text: $fields[index].childDocType)
                                    .mercantisInput()
                            }
                            formRow("Visibility") {
                                TextField("Expression", text: $fields[index].visibilityExpression)
                                    .mercantisInput()
                            }
                            Button("Remove Field", role: .destructive) {
                                fields.remove(at: index)
                            }
                            .buttonStyle(MercantisDestructiveButtonStyle())
                        }
                        .mercantisCard()
                    }

                    Button("Add Field") {
                        fields.append(EditableField())
                    }
                    .buttonStyle(MercantisSecondaryButtonStyle())
                }

                MercantisSectionHeading(title: "Permission Rules")
                VStack(spacing: 12) {
                    ForEach(Array(permissions.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            formRow("Role") {
                                TextField("Role", text: $permissions[index].role)
                                    .mercantisInput()
                            }
                            checkboxRow("Read", isOn: $permissions[index].canRead)
                            checkboxRow("Write", isOn: $permissions[index].canWrite)
                            checkboxRow("Create", isOn: $permissions[index].canCreate)
                            checkboxRow("Delete", isOn: $permissions[index].canDelete)
                            checkboxRow("Submit", isOn: $permissions[index].canSubmit)
                            checkboxRow("Amend", isOn: $permissions[index].canAmend)
                            Button("Remove Permission", role: .destructive) {
                                permissions.remove(at: index)
                            }
                            .buttonStyle(MercantisDestructiveButtonStyle())
                        }
                        .mercantisCard()
                    }

                    Button("Add Permission Rule") {
                        permissions.append(EditablePermission())
                    }
                    .buttonStyle(MercantisSecondaryButtonStyle())
                }

                MercantisSectionHeading(title: "Sync Policy")
                VStack(spacing: 12) {
                    formRow("Conflict Resolution") {
                        Picker("Conflict Resolution", selection: $conflictResolution) {
                            ForEach(ConflictResolution.allCases, id: \.self) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .mercantisPicker()
                    }
                    checkboxRow("Immutable After Submit", isOn: $immutableAfterSubmit)
                }
                .mercantisCard()

                MercantisSectionHeading(title: "Indexes")
                VStack(spacing: 12) {
                    ForEach(Array(indexes.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            formRow("Field Key") {
                                TextField("Field Key", text: $indexes[index].fieldKey)
                                    .mercantisInput()
                            }
                            checkboxRow("Unique", isOn: $indexes[index].unique)
                            Button("Remove Index", role: .destructive) {
                                indexes.remove(at: index)
                            }
                            .buttonStyle(MercantisDestructiveButtonStyle())
                        }
                        .mercantisCard()
                    }

                    Button("Add Index") {
                        indexes.append(EditableIndex())
                    }
                    .buttonStyle(MercantisSecondaryButtonStyle())
                }
            }
            .padding()
        }
        .background(MercantisTheme.background)
        .navigationTitle(existingDocType == nil ? "New DocType" : "Edit DocType")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("Save", action: save)
                    .buttonStyle(MercantisPrimaryButtonStyle())
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

    private func formRow<Content: View>(_ label: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 190, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkboxRow(_ label: String, isOn: Binding<Bool>) -> some View {
        formRow(nil) {
            Toggle(label, isOn: isOn)
                .frame(maxWidth: .infinity, alignment: .leading)
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
