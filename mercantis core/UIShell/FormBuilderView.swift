import SwiftUI

private struct BuilderPaletteGroup: Identifiable {
    let id: String
    let title: String
    let controls: [BuilderControlItem]
}

private struct BuilderControlItem: Identifiable {
    enum Kind {
        case field(FieldType)
        case section
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let kind: Kind

    var dragToken: String {
        switch kind {
        case .field(let type):
            return "field:\(type.rawValue)"
        case .section:
            return "layout:section"
        }
    }
}

private struct BuilderStatusItem: Identifiable {
    let id: String
    let title: String
    let tone: MercantisSemanticTone
    let icon: String
}

private struct BuilderTimelineEvent: Identifiable {
    let id = UUID()
    let title: String
    let timestamp: Date
    let tone: MercantisSemanticTone
}

private enum BuilderPaneWidth {
    static let controlsMin: CGFloat = 220
    static let controlsIdeal: CGFloat = 260
    static let controlsMax: CGFloat = 320
    static let canvasMin: CGFloat = 360
    static let canvasIdeal: CGFloat = 640
    static let inspectorMin: CGFloat = 260
    static let inspectorIdeal: CGFloat = 320
    static let inspectorMax: CGFloat = 380
}

public struct FormBuilderView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext

    private let initialDocTypeID: String?
    private let onSave: (() -> Void)?

    @State private var docTypeId = ""
    @State private var name = ""
    @State private var module = ""
    @State private var isSubmittable = false
    @State private var isChildTable = false
    @State private var titleField = ""
    @State private var searchFields = ""
    @State private var fields: [EditableField] = []
    @State private var uniqueFieldKeys: Set<String> = []
    @State private var selectedFieldID: UUID?
    @State private var selectedSourceDocTypeID = ""

    @State private var paletteSearchText = ""
    @State private var expandedPaletteGroupIDs: Set<String> = []
    @State private var nextGeneratedSection = 1
    @State private var validationError: String?
    @State private var isDeployed = false
    @State private var timelineEvents: [BuilderTimelineEvent] = []
    @State private var hasAttemptedInitialDocTypeLoad = false

    private let paletteGroups: [BuilderPaletteGroup] = [
        BuilderPaletteGroup(
            id: "data",
            title: "Data",
            controls: [
                BuilderControlItem(id: "text", title: "Text", subtitle: "Single line value", icon: "character.textbox", kind: .field(.text)),
                BuilderControlItem(id: "longText", title: "Long Text", subtitle: "Multi-line text", icon: "text.alignleft", kind: .field(.longText)),
                BuilderControlItem(id: "check", title: "Check", subtitle: "Boolean toggle", icon: "checkmark.square", kind: .field(.boolean)),
                BuilderControlItem(id: "date", title: "Date", subtitle: "Calendar date", icon: "calendar", kind: .field(.date)),
                BuilderControlItem(id: "datetime", title: "DateTime", subtitle: "Date and time", icon: "calendar.badge.clock", kind: .field(.datetime))
            ]
        ),
        BuilderPaletteGroup(
            id: "relations",
            title: "Relations",
            controls: [
                BuilderControlItem(id: "link", title: "Link", subtitle: "Reference another DocType", icon: "link", kind: .field(.link)),
                BuilderControlItem(id: "table", title: "Table", subtitle: "Child row collection", icon: "tablecells", kind: .field(.table))
            ]
        ),
        BuilderPaletteGroup(
            id: "choice",
            title: "Choice / Selection",
            controls: [
                BuilderControlItem(id: "select", title: "Select", subtitle: "Single option list", icon: "list.bullet", kind: .field(.select)),
                BuilderControlItem(id: "multiselect", title: "Multi Select", subtitle: "Multiple options", icon: "checklist", kind: .field(.multiselect))
            ]
        ),
        BuilderPaletteGroup(
            id: "numeric",
            title: "Numeric",
            controls: [
                BuilderControlItem(id: "number", title: "Int", subtitle: "Whole number", icon: "number", kind: .field(.number)),
                BuilderControlItem(id: "decimal", title: "Decimal", subtitle: "Decimal number", icon: "sum", kind: .field(.decimal)),
                BuilderControlItem(id: "currency", title: "Currency", subtitle: "Monetary value", icon: "dollarsign.circle", kind: .field(.currency))
            ]
        ),
        BuilderPaletteGroup(
            id: "layout",
            title: "Layout",
            controls: [
                BuilderControlItem(id: "sectionBreak", title: "Section Break", subtitle: "Create a metadata section", icon: "rectangle.split.1x2", kind: .section)
            ]
        ),
        BuilderPaletteGroup(
            id: "advanced",
            title: "Advanced",
            controls: [
                BuilderControlItem(id: "formula", title: "Formula", subtitle: "Computed expression", icon: "function", kind: .field(.formula)),
                BuilderControlItem(id: "attachment", title: "Attachment", subtitle: "Upload file", icon: "paperclip", kind: .field(.attachment))
            ]
        )
    ]

    public init(initialDocTypeID: String? = nil, onSave: (() -> Void)? = nil) {
        self.initialDocTypeID = initialDocTypeID
        self.onSave = onSave
    }

    public var body: some View {
        HSplitView {
            controlsPalette
                .frame(
                    minWidth: BuilderPaneWidth.controlsMin,
                    idealWidth: BuilderPaneWidth.controlsIdeal,
                    maxWidth: BuilderPaneWidth.controlsMax,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                // Keep the palette visible while the canvas absorbs most resize pressure.
                .layoutPriority(2)

            metadataCanvas
                .frame(
                    minWidth: BuilderPaneWidth.canvasMin,
                    idealWidth: BuilderPaneWidth.canvasIdeal,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .layoutPriority(1)

            inspectorPane
                .frame(
                    minWidth: BuilderPaneWidth.inspectorMin,
                    idealWidth: BuilderPaneWidth.inspectorIdeal,
                    maxWidth: BuilderPaneWidth.inspectorMax,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save", action: save)
                    .buttonStyle(MercantisPrimaryButtonStyle())
            }
        }
        .overlay(alignment: .top) {
            if let validationError {
                Text(validationError)
                    .padding(8)
                    .background(MercantisTheme.fillSoft(for: .danger))
                    .foregroundStyle(MercantisTheme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .background(MercantisTheme.background)
        .onAppear {
            if expandedPaletteGroupIDs.isEmpty {
                expandedPaletteGroupIDs = Set(paletteGroups.map(\.id))
            }
            if shouldLoadInitialDocType {
                loadInitialDocType()
                hasAttemptedInitialDocTypeLoad = true
            }
        }
    }

    // Kept as a dedicated predicate so the onAppear startup path remains easy to scan.
    private var shouldLoadInitialDocType: Bool {
        !hasAttemptedInitialDocTypeLoad && docTypeId.isEmpty && fields.isEmpty
    }

    private var windowTitle: String {
        if let preferredName = trimmedIfNotEmpty(name) {
            return "Visual Builder — \(preferredName)"
        }

        if let fallbackId = trimmedIfNotEmpty(docTypeId) {
            return "Visual Builder — \(fallbackId)"
        }

        return "Visual Builder"
    }

    private func trimmedIfNotEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var controlsPalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls")
                .font(.headline)

            TextField("Search controls", text: $paletteSearchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredPaletteGroups) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedPaletteGroupIDs.contains(group.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedPaletteGroupIDs.insert(group.id)
                                    } else {
                                        expandedPaletteGroupIDs.remove(group.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.controls) { control in
                                    Button {
                                        insert(control: control)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: control.icon)
                                                .frame(width: 16)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(control.title)
                                                Text(control.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .background(MercantisTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .draggable(control.dragToken)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .mercantisCard()
    }

    private var metadataCanvas: some View {
        let selectedFieldKey = selectedFieldBinding?.wrappedValue.key
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                builderHeader

                if canvasSections.isEmpty {
                    ContentUnavailableView("No fields in layout", systemImage: "square.stack.3d.down.right")
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .background(MercantisTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(canvasSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.headline)

                            HStack(alignment: .top, spacing: 12) {
                                ForEach(section.groups) { group in
                                    let groupHasSelection = group.fields.contains { $0.key == selectedFieldKey }
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(group.fields) { field in
                                            canvasFieldRow(field, selectedFieldKey: selectedFieldKey)
                                        }

                                        if group.fields.isEmpty {
                                            Text("Drop field here")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                                    .background(
                                        groupHasSelection ? MercantisTheme.inspectorHighlight : MercantisTheme.surfaceMuted,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(groupHasSelection ? MercantisTheme.accentBorder : MercantisTheme.border.opacity(0.6), lineWidth: 1)
                                    )
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let token = items.first else { return false }
                                        return insertFromDragToken(token, intoSection: section.title)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(section.groups.contains(where: { $0.fields.contains(where: { $0.key == selectedFieldKey }) }) ? MercantisTheme.accentBorder : MercantisTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
        .mercantisCard()
    }

    @ViewBuilder
    private func canvasFieldRow(_ field: CanvasFieldViewModel, selectedFieldKey: String?) -> some View {
        let selected = selectedFieldKey == field.key
        Button {
            if let selectedField = fields.first(where: { $0.key == field.key }) {
                selectedFieldID = selectedField.id
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.callout)
                    Text("\(field.key) · \(field.type.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if field.isRequired {
                    Image(systemName: "asterisk")
                        .font(.caption2)
                        .foregroundStyle(MercantisTheme.warning)
                }
                if isReadOnlyExpression(field.readOnlyExpression) {
                    Image(systemName: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .mercantisBuilderSelection(isSelected: selected)
        }
        .buttonStyle(.plain)
    }

    private var builderHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata Canvas")
                .font(.headline)
            Text("Sections and groups are projected from ResolvedMeta field section and column hints.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !docTypeId.isEmpty {
                Text("Editing DocType: \(docTypeId)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("DocType ID", text: $docTypeId)
                    .mercantisInput()
                TextField("Display Name", text: $name)
                    .mercantisInput()
                Picker("Module", selection: $module) {
                    if module.isEmpty || !tooling.moduleNames.contains(module) {
                        Text("Select Module").tag("")
                    }
                    ForEach(tooling.moduleNames, id: \.self) { moduleName in
                        Text(moduleName).tag(moduleName)
                    }
                }
                .pickerStyle(.menu)
                .mercantisPicker()
                HStack {
                    Toggle("Submittable", isOn: $isSubmittable)
                    Toggle("Child Table", isOn: $isChildTable)
                }
                TextField("Title Field", text: $titleField)
                    .mercantisInput()
                TextField("Search Fields (comma-separated)", text: $searchFields)
                    .mercantisInput()
            }
            .padding(10)
            .background(MercantisTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Picker("Source", selection: $selectedSourceDocTypeID) {
                    Text("Current Draft").tag("")
                    ForEach(tooling.docTypes.filter { !$0.isChildTable }, id: \.id) { docType in
                        Text(docType.name).tag(docType.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedSourceDocTypeID) { _, value in
                    guard !value.isEmpty else { return }
                    loadDocType(id: value)
                }

                Button("Clear Selection") {
                    selectedFieldID = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                fieldInspectorCard
                statusHistoryCard
                timelineCard
            }
            .padding(.bottom, 4)
        }
        .mercantisCard()
    }

    private var fieldInspectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Field Properties")
                .font(.headline)

            if let binding = selectedFieldBinding {
                TextField("Key", text: binding.key)
                    .mercantisInput()
                    .onChange(of: binding.key.wrappedValue) { oldValue, newValue in
                        syncUniqueKeyChange(oldKey: oldValue, newKey: newValue)
                    }
                TextField("Label", text: binding.label)
                    .mercantisInput()
                Picker("Type", selection: binding.type) {
                    ForEach(FieldType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .mercantisPicker()
                Toggle("Required", isOn: binding.required)
                Toggle(
                    "Read Only",
                    isOn: Binding(
                        get: { isReadOnlyExpression(binding.readOnlyExpression.wrappedValue) },
                        set: { binding.readOnlyExpression.wrappedValue = $0 ? "true" : "" }
                    )
                )
                Toggle(
                    "Unique",
                    isOn: Binding(
                        get: { uniqueFieldKeys.contains(binding.key.wrappedValue) },
                        set: { isUnique in
                            if isUnique {
                                uniqueFieldKeys.insert(binding.key.wrappedValue)
                            } else {
                                uniqueFieldKeys.remove(binding.key.wrappedValue)
                            }
                        }
                    )
                )
                TextField("Options (comma-separated)", text: binding.optionsText)
                    .mercantisInput()
                TextField("Linked DocType", text: binding.linkedDocType)
                    .mercantisInput()
                TextField("Child DocType", text: binding.childDocType)
                    .mercantisInput()
                TextField("Section", text: binding.section)
                    .mercantisInput()
                Stepper(value: binding.column, in: 0...4) {
                    Text("Group: \(ResolvedMetaCanvasAdapter.columnGroupTitle(forColumn: binding.column.wrappedValue))")
                }
                TextField("Visibility Expression", text: binding.visibilityExpression)
                    .mercantisInput()
                HStack(spacing: 6) {
                    Text("Field Type")
                        .foregroundStyle(.secondary)
                    Text(binding.type.wrappedValue.rawValue)
                        .mercantisSemanticBadge(tone: .accent)
                }
                Text("Placeholder/help text are not yet represented in the core field metadata model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a field from the canvas to edit properties.")
                    .foregroundStyle(.secondary)
            }
        }
        .mercantisCard()
    }

    private var statusHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status History")
                .font(.headline)

            ForEach(statusItems) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .foregroundStyle(MercantisTheme.tint(for: item.tone))
                    Text(item.title)
                        .font(.callout)
                    Spacer()
                }
            }
        }
        .mercantisCard()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.headline)

            if timelineEvents.isEmpty {
                Text("No recent builder activity")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentTimelineEvents) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(MercantisTheme.tint(for: event.tone))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.callout)
                            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .mercantisCard()
    }

    private var filteredPaletteGroups: [BuilderPaletteGroup] {
        let query = paletteSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return paletteGroups }

        return paletteGroups.compactMap { group in
            let controls = group.controls.filter { control in
                control.title.lowercased().contains(query) || control.subtitle.lowercased().contains(query)
            }
            guard !controls.isEmpty else { return nil }
            return BuilderPaletteGroup(id: group.id, title: group.title, controls: controls)
        }
    }

    private var selectedFieldBinding: Binding<EditableField>? {
        guard let selectedFieldID else { return nil }
        guard let index = fields.firstIndex(where: { $0.id == selectedFieldID }) else { return nil }
        return $fields[index]
    }

    private var statusItems: [BuilderStatusItem] {
        [
            BuilderStatusItem(
                id: "draft",
                title: "Draft defined",
                tone: normalizedDocTypeId.isEmpty ? .info : .success,
                icon: normalizedDocTypeId.isEmpty ? "info.circle.fill" : "checkmark.circle.fill"
            ),
            BuilderStatusItem(
                id: "layout",
                title: "Layout validated",
                tone: canvasSections.isEmpty ? .warning : .success,
                icon: canvasSections.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
            ),
            BuilderStatusItem(
                id: "deployment",
                title: "Fields deployed",
                tone: isDeployed ? .success : .danger,
                icon: isDeployed ? "checkmark.circle.fill" : "xmark.octagon.fill"
            )
        ]
    }

    private var recentTimelineEvents: [BuilderTimelineEvent] {
        Array(timelineEvents.suffix(10).reversed())
    }

    private var normalizedDocTypeId: String {
        docTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedModule: String {
        module.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewDocType: DocType {
        let outputFields = fields.map(\.fieldDefinition)
        return DocType(
            id: normalizedDocTypeId.isEmpty ? "PreviewDocType" : normalizedDocTypeId,
            name: normalizedName.isEmpty ? "Preview DocType" : normalizedName,
            module: normalizedModule.isEmpty ? "Setup" : normalizedModule,
            appId: "custom.local",
            isChildTable: isChildTable,
            isSubmittable: isSubmittable,
            fields: outputFields,
            permissions: [],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: uniqueFieldKeys.sorted().map { IndexDefinition(fieldKey: $0, unique: true) },
            searchFields: searchFields
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            titleField: titleField,
            isCustom: true
        )
    }

    private var resolvedMeta: ResolvedMeta {
        tooling.resolvedMeta(forDefinition: previewDocType)
    }

    private var canvasSections: [CanvasSectionViewModel] {
        ResolvedMetaCanvasAdapter.project(resolvedMeta)
    }

    private func insert(control: BuilderControlItem, targetSection: String? = nil) {
        switch control.kind {
        case .field(let type):
            let section = targetSection ?? fields.last?.section ?? "Main"
            let nextKey = nextFieldKey(for: type)
            fields.append(
                EditableField(
                    key: nextKey,
                    label: nextKey.replacingOccurrences(of: "_", with: " ").capitalized,
                    type: type,
                    section: section
                )
            )
            selectedFieldID = fields.last?.id
            trackEvent("Field added: \(nextKey)", tone: .info)
        case .section:
            let sectionName = "Section \(nextGeneratedSection)"
            nextGeneratedSection += 1
            trackEvent("Section created: \(sectionName)", tone: .info)
            if let binding = selectedFieldBinding {
                binding.section.wrappedValue = sectionName
            }
        }
    }

    private func insertFromDragToken(_ token: String, intoSection section: String) -> Bool {
        guard let item = paletteGroups
            .flatMap(\.controls)
            .first(where: { $0.dragToken == token }) else {
            return false
        }
        insert(control: item, targetSection: section)
        return true
    }

    private func nextFieldKey(for fieldType: FieldType) -> String {
        let base = fieldType.rawValue.lowercased()
        var index = 1
        var candidate = "\(base)_\(index)"
        while fields.contains(where: { $0.key == candidate }) {
            index += 1
            candidate = "\(base)_\(index)"
        }
        return candidate
    }

    private func loadInitialDocType() {
        if let initialDocTypeID,
           let initialDocType = tooling.docType(withId: initialDocTypeID),
           !initialDocType.isChildTable {
            selectedSourceDocTypeID = initialDocTypeID
            loadDocType(id: initialDocTypeID)
            return
        }

        guard let firstDocType = tooling.docTypes.first(where: { !$0.isChildTable }) else { return }
        selectedSourceDocTypeID = firstDocType.id
        loadDocType(id: firstDocType.id)
    }

    private func loadDocType(id: String) {
        guard let docType = tooling.docType(withId: id) else { return }
        let meta = tooling.resolvedMeta(for: id)

        docTypeId = docType.id
        name = docType.name
        module = docType.module
        isSubmittable = docType.isSubmittable
        isChildTable = docType.isChildTable
        titleField = docType.titleField
        searchFields = docType.searchFields.joined(separator: ", ")
        uniqueFieldKeys = Set(docType.indexes.filter(\.unique).map(\.fieldKey))

        if let meta {
            fields = meta.fields.map(EditableField.init)
        } else {
            fields = docType.fields.map(EditableField.init)
        }
        selectedFieldID = fields.first?.id
        trackEvent("Loaded DocType: \(docType.id)", tone: .info)
    }

    private func syncUniqueKeyChange(oldKey: String, newKey: String) {
        guard oldKey != newKey else { return }
        if uniqueFieldKeys.remove(oldKey) != nil {
            uniqueFieldKeys.insert(newKey)
        }
    }

    private func isReadOnlyExpression(_ expression: String?) -> Bool {
        let normalized = expression?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized == "true" || normalized == "1" || normalized == "yes"
    }

    private func trackEvent(_ title: String, tone: MercantisSemanticTone) {
        timelineEvents.append(BuilderTimelineEvent(title: title, timestamp: Date(), tone: tone))
    }

    private func save() {
        validationError = nil
        let docType = previewDocType

        do {
            try tooling.save(docType: docType)
            isDeployed = true
            trackEvent("Fields deployed", tone: .success)
            onSave?()
            // Keep the builder open so window-based editing sessions can continue after save.
        } catch {
            validationError = tooling.errorMessage(for: error)
            trackEvent("Save failed", tone: .danger)
        }
    }
}
