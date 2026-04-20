import SwiftUI
import Combine
import GRDB

@MainActor
final class DocTypeToolingContext: ObservableObject {
    @Published var docTypes: [DocType] = []
    @Published var reports: [ReportDefinition] = []
    @Published var dashboards: [DashboardDefinition] = []
    /// Canonical module record names for validation and module-management workflows.
    /// This supports Module tooling and metadata integrity, not per-module sidebar groupings.
    @Published var moduleNames: [String] = []

    /// Validator is mutable because `knownModules` is updated on each `reload()`
    /// to reflect the current set of registered modules.
    var validator = SchemaValidator()
    let registry: MetadataRegistry
    private let database: MercantisDatabase
    private let eventBus = EventBus()
    private lazy var metaComposer = MetaComposer(registry: registry)
    private lazy var documentEngine = DocumentEngine(
        database: database,
        registry: registry,
        eventBus: eventBus,
        deviceId: "local-device",
        userId: "local-user"
    )
    private var reportEngine: ReportEngine?

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

        // Derive canonical module names from non-child-table DocTypes for metadata and module-management workflows.
        moduleNames = Array(Set(
            docTypes.filter { !$0.isChildTable }.map(\.module)
        )).sorted()

        // Update validator with known modules so new DocTypes must reference an existing module.
        validator.knownModules = Set(moduleNames)

        let manifests = loadInstalledManifests()
        let manifestReports = manifests.flatMap(\.reports)
        let generatedReports = generatedListReports(from: docTypes)
        reports = deduplicateReports(manifestReports + generatedReports)

        let engine = ReportEngine(documentEngine: documentEngine)
        reports.forEach { engine.register($0) }
        reportEngine = engine

        let manifestDashboards = manifests.flatMap(\.dashboards)
        dashboards = deduplicateDashboards(manifestDashboards + generatedDashboards(from: docTypes))
    }

    func save(docType: DocType) throws {
        try validator.validate(docType)
        try registry.register(docType)
        metaComposer.invalidateAll()
        reload()
    }

    func delete(docTypeId id: String) throws {
        try registry.remove(id)
        metaComposer.invalidateAll()
        reload()
    }

    func docType(withId id: String) -> DocType? {
        docTypes.first(where: { $0.id == id }) ?? registry.get(id)
    }

    func resolvedMeta(for docTypeId: String) -> ResolvedMeta? {
        metaComposer.resolve(docType: docTypeId)
    }

    func resolvedMeta(forDefinition docType: DocType) -> ResolvedMeta {
        metaComposer.resolve(docTypeDefinition: docType)
    }

    func report(withId id: String) -> ReportDefinition? {
        reports.first(where: { $0.id == id })
    }

    func dashboard(withId id: String) -> DashboardDefinition? {
        dashboards.first(where: { $0.id == id })
    }

    var navigableDocTypes: [DocType] {
        docTypes.filter { !$0.isChildTable }
    }

    func listDocuments(docTypeId: String) -> [Document] {
        (try? documentEngine.list(docType: docTypeId)) ?? []
    }

    func createDraftDocument(for docType: DocType) -> Document {
        let now = Date()
        let defaultFields = Dictionary(uniqueKeysWithValues: docType.fields.map { field in
            (field.key, defaultFieldValue(for: field))
        })
        return Document(
            id: UUID().uuidString,
            docType: docType.id,
            company: "",
            status: "Draft",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: defaultFields,
            children: [:]
        )
    }

    func saveDocument(_ document: Document) throws {
        try documentEngine.save(document)
    }

    func executeReport(_ report: ReportDefinition, filters: [String: FieldValue] = [:]) -> ReportResult? {
        guard let reportEngine else { return nil }
        return try? reportEngine.execute(report: report, filters: filters)
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
        case .moduleNotFound(let docType, let module):
            return "Module '\(module)' does not exist. Create the module first or select an existing one when defining \(docType)."
        }
    }

    private static func databaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseURL.appendingPathComponent("mercantis-core", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("metadata.sqlite")
    }

    private func loadInstalledManifests() -> [AppManifest] {
        let rows: [Row]
        do {
            rows = try database.read { db in
                try Row.fetchAll(db, sql: "SELECT payload FROM apps", arguments: [])
            }
        } catch {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return rows.compactMap { row in
            guard let payloadString: String = row[0],
                  let payloadData = payloadString.data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(AppManifest.self, from: payloadData)
        }
    }

    private func generatedListReports(from docTypes: [DocType]) -> [ReportDefinition] {
        docTypes
            .filter { !BuiltInDocTypes.systemMetaDocTypeIds.contains($0.id) }
            .map { docType in
                let candidateColumns = ([docType.titleField] + docType.searchFields).uniqued().prefix(4)
                return ReportDefinition(
                    id: "generated.report.\(docType.id)",
                    name: "\(docType.name) List",
                    docType: docType.id,
                    columns: Array(candidateColumns),
                    filters: []
                )
            }
    }

    private func generatedDashboards(from docTypes: [DocType]) -> [DashboardDefinition] {
        let eligible = docTypes.filter { !BuiltInDocTypes.systemMetaDocTypeIds.contains($0.id) }
        let grouped = Dictionary(grouping: eligible, by: \.module)
        return grouped.keys.sorted().map { module in
            let widgets = grouped[module, default: []].prefix(4).map { docType in
                DashboardWidget(
                    type: "count",
                    title: docType.name,
                    reportId: "generated.report.\(docType.id)",
                    docType: docType.id,
                    parameters: [:]
                )
            }
            return DashboardDefinition(
                id: "generated.dashboard.\(slug(module))",
                name: "\(module) Workspace",
                widgets: Array(widgets)
            )
        }
    }

    private func deduplicateReports(_ items: [ReportDefinition]) -> [ReportDefinition] {
        var seen = Set<String>()
        return items.filter { report in
            seen.insert(report.id).inserted
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func deduplicateDashboards(_ items: [DashboardDefinition]) -> [DashboardDefinition] {
        var seen = Set<String>()
        return items.filter { dashboard in
            seen.insert(dashboard.id).inserted
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func defaultFieldValue(for field: FieldDefinition) -> FieldValue {
        if let defaultValue = field.defaultValue {
            return defaultValue
        }
        switch field.type {
        case .boolean:
            return .bool(false)
        case .number:
            return .int(0)
        case .decimal, .currency:
            return .double(0)
        default:
            return .string("")
        }
    }

    private func slug(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
    var readOnlyExpression: String
    var section: String
    var column: Int

    nonisolated init(
        key: String = "",
        label: String = "",
        type: FieldType = .text,
        required: Bool = false,
        optionsText: String = "",
        linkedDocType: String = "",
        childDocType: String = "",
        visibilityExpression: String = "",
        readOnlyExpression: String = "",
        section: String = "",
        column: Int = 0
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.optionsText = optionsText
        self.linkedDocType = linkedDocType
        self.childDocType = childDocType
        self.visibilityExpression = visibilityExpression
        self.readOnlyExpression = readOnlyExpression
        self.section = section
        self.column = column
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
            visibilityExpression: field.visibilityExpression ?? "",
            readOnlyExpression: field.readOnlyExpression ?? "",
            section: field.section ?? "",
            column: field.column ?? 0
        )
    }

    nonisolated init(_ field: ResolvedFieldDefinition) {
        self.init(
            key: field.key,
            label: field.label,
            type: field.type,
            required: field.isRequired,
            optionsText: (field.options ?? []).joined(separator: ","),
            linkedDocType: field.linkedDocType ?? "",
            childDocType: field.childDocType ?? "",
            visibilityExpression: field.visibilityExpression ?? "",
            readOnlyExpression: field.readOnlyExpression ?? "",
            section: field.section ?? "",
            column: field.column ?? 0
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
            visibilityExpression: visibilityExpression.isEmpty ? nil : visibilityExpression,
            readOnlyExpression: readOnlyExpression.isEmpty ? nil : readOnlyExpression,
            section: section.isEmpty ? nil : section,
            column: column <= 0 ? nil : column
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
    private let formLabelWidth: CGFloat = 190

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
                    labeledFormRow("DocType ID") {
                        TextField("DocType ID", text: $docTypeId)
                            .mercantisInput()
                    }
                    labeledFormRow("Name") {
                        TextField("Name", text: $name)
                            .mercantisInput()
                    }
                    labeledFormRow("Module") {
                        Picker("Module", selection: $module) {
                            if module.isEmpty || !tooling.moduleNames.contains(module) {
                                Text("Select Module").tag("")
                            }
                            ForEach(tooling.moduleNames, id: \.self) { moduleName in
                                Text(moduleName).tag(moduleName)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .mercantisPicker()
                    }
                    labeledFormRow("Title Field") {
                        TextField("Title Field", text: $titleField)
                            .mercantisInput()
                    }
                    labeledFormRow("Search Fields") {
                        TextField("comma-separated", text: $searchFields)
                            .mercantisInput()
                    }
                    checkboxRow("Submittable", isOn: $isSubmittable)
                    checkboxRow("Child Table", isOn: $isChildTable)
                }
                .mercantisCard()

                MercantisSectionHeading(title: "Fields")
                VStack(spacing: 12) {
                    ForEach($fields) { $field in
                        VStack(alignment: .leading, spacing: 10) {
                            labeledFormRow("Key") {
                                TextField("field_key", text: $field.key)
                                    .mercantisInput()
                            }
                            labeledFormRow("Label") {
                                TextField("Field Label", text: $field.label)
                                    .mercantisInput()
                            }
                            labeledFormRow("Type") {
                                Picker("Type", selection: $field.type) {
                                    ForEach(FieldType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .mercantisPicker()
                            }
                            checkboxRow("Required", isOn: $field.required)
                            labeledFormRow("Options") {
                                TextField("comma-separated options", text: $field.optionsText)
                                    .mercantisInput()
                            }
                            labeledFormRow("Linked DocType") {
                                TextField("Linked DocType", text: $field.linkedDocType)
                                    .mercantisInput()
                            }
                            labeledFormRow("Child DocType") {
                                TextField("Child DocType", text: $field.childDocType)
                                    .mercantisInput()
                            }
                            labeledFormRow("Visibility") {
                                TextField("Expression", text: $field.visibilityExpression)
                                    .mercantisInput()
                            }
                            labeledFormRow("Section") {
                                TextField("Section", text: $field.section)
                                    .mercantisInput()
                            }
                            labeledFormRow("Column") {
                                Stepper(value: $field.column, in: 0...4) {
                                    Text(field.column <= 0 ? "Automatic" : "\(field.column)")
                                }
                            }
                            Button("Remove Field", role: .destructive) {
                                removeField(with: field.id)
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
                    ForEach($permissions) { $permission in
                        VStack(alignment: .leading, spacing: 10) {
                            labeledFormRow("Role") {
                                TextField("Role", text: $permission.role)
                                    .mercantisInput()
                            }
                            checkboxRow("Read", isOn: $permission.canRead)
                            checkboxRow("Write", isOn: $permission.canWrite)
                            checkboxRow("Create", isOn: $permission.canCreate)
                            checkboxRow("Delete", isOn: $permission.canDelete)
                            checkboxRow("Submit", isOn: $permission.canSubmit)
                            checkboxRow("Amend", isOn: $permission.canAmend)
                            Button("Remove Permission", role: .destructive) {
                                removePermission(with: permission.id)
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
                    labeledFormRow("Conflict Resolution") {
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
                    ForEach($indexes) { $index in
                        VStack(alignment: .leading, spacing: 10) {
                            labeledFormRow("Field Key") {
                                TextField("Field Key", text: $index.fieldKey)
                                    .mercantisInput()
                            }
                            checkboxRow("Unique", isOn: $index.unique)
                            Button("Remove Index", role: .destructive) {
                                removeIndex(with: index.id)
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

    private func labeledFormRow<Content: View>(_ label: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
                } else {
                    Spacer()
                        .accessibilityHidden(true)
                }
            }
            .frame(width: formLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkboxRow(_ label: String, isOn: Binding<Bool>) -> some View {
        labeledFormRow(label) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func removeField(with id: UUID) {
        fields.removeAll { $0.id == id }
    }

    private func removePermission(with id: UUID) {
        permissions.removeAll { $0.id == id }
    }

    private func removeIndex(with id: UUID) {
        indexes.removeAll { $0.id == id }
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
