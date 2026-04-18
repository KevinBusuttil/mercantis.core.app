import SwiftUI

private struct FormBuilderSection: Identifiable {
    let id = UUID()
    var title: String
    var columns: [[EditableField]]
}

public struct FormBuilderView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    @Environment(\.dismiss) private var dismiss

    private let onSave: (() -> Void)?

    @State private var docTypeId = ""
    @State private var name = ""
    @State private var module = ""
    @State private var isSubmittable = false
    @State private var isChildTable = false
    @State private var titleField = ""
    @State private var searchFields = ""
    @State private var selectedFieldID: UUID?
    @State private var sections: [FormBuilderSection] = [
        FormBuilderSection(title: "Main", columns: [[], []])
    ]
    @State private var validationError: String?

    public init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 0) {
            fieldPalette
                .frame(width: 180)
            Divider()
            canvas
            Divider()
            inspector
                .frame(width: 300)
            Divider()
            preview
                .frame(minWidth: 320)
        }
        .navigationTitle("Form Builder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save", action: save)
            }
        }
        .overlay(alignment: .top) {
            if let validationError {
                Text(validationError)
                    .padding(8)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    private var fieldPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Field Palette")
                .font(.headline)
            ScrollView {
                ForEach(FieldType.allCases, id: \.self) { fieldType in
                    Text(fieldType.rawValue)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .draggable(fieldType.rawValue)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var canvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                basicInfoCard

                ForEach(Array(sections.indices), id: \.self) { sectionIndex in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sections[sectionIndex].title)
                            .font(.headline)

                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(sections[sectionIndex].columns.indices), id: \.self) { columnIndex in
                                dropColumn(sectionIndex: sectionIndex, columnIndex: columnIndex)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DocType")
                .font(.headline)
            TextField("DocType ID", text: $docTypeId)
            TextField("Name", text: $name)
            TextField("Module", text: $module)
            TextField("Title Field", text: $titleField)
            TextField("Search Fields (comma-separated)", text: $searchFields)
            Toggle("Submittable", isOn: $isSubmittable)
            Toggle("Child Table", isOn: $isChildTable)
        }
        .padding()
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func dropColumn(sectionIndex: Int, columnIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections[sectionIndex].columns[columnIndex]) { field in
                let isSelected = field.id == selectedFieldID
                Text(displayName(for: field))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(isSelected ? .blue.opacity(0.2) : .secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedFieldID = field.id
                    }
            }

            Text("Drop field here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            guard let rawValue = items.first, let type = FieldType(rawValue: rawValue) else { return false }
            let nextCount = sections[sectionIndex].columns[columnIndex].count + 1
            sections[sectionIndex].columns[columnIndex].append(
                EditableField(
                    key: "field_\(nextCount)",
                    label: "Field \(nextCount)",
                    type: type
                )
            )
            return true
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspector")
                .font(.headline)

            if let binding = selectedFieldBinding {
                TextField("Key", text: binding.key)
                TextField("Label", text: binding.label)
                Picker("Type", selection: binding.type) {
                    ForEach(FieldType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                Toggle("Required", isOn: binding.required)
                TextField("Options", text: binding.optionsText)
                TextField("Linked DocType", text: binding.linkedDocType)
                TextField("Visibility Expression", text: binding.visibilityExpression)
                TextField("Child DocType", text: binding.childDocType)
            } else {
                Text("Select a field on the canvas to edit properties.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Preview")
                .font(.headline)
            GenericFormView(
                docType: previewDocType,
                document: .constant(previewDocument)
            )
            .disabled(true)
        }
        .padding()
    }

    private var selectedFieldBinding: Binding<EditableField>? {
        guard let selectedFieldID else { return nil }

        for sectionIndex in sections.indices {
            for columnIndex in sections[sectionIndex].columns.indices {
                if let fieldIndex = sections[sectionIndex].columns[columnIndex].firstIndex(where: { $0.id == selectedFieldID }) {
                    return $sections[sectionIndex].columns[columnIndex][fieldIndex]
                }
            }
        }

        return nil
    }

    private var allFields: [EditableField] {
        sections.flatMap { $0.columns.flatMap { $0 } }
    }

    private func displayName(for field: EditableField) -> String {
        if !field.label.isEmpty {
            return field.label
        }
        if !field.key.isEmpty {
            return field.key
        }
        return "Untitled Field"
    }

    private var previewDocType: DocType {
        let fields = allFields.map(\.fieldDefinition)
        return DocType(
            id: docTypeId.isEmpty ? "PreviewDocType" : docTypeId,
            name: name.isEmpty ? "Preview DocType" : name,
            module: module.isEmpty ? "Setup" : module,
            appId: "custom.local",
            isChildTable: isChildTable,
            isSubmittable: isSubmittable,
            fields: fields,
            permissions: [],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: searchFields
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            titleField: titleField,
            isCustom: true
        )
    }

    private var previewDocument: Document {
        let values = Dictionary(uniqueKeysWithValues: allFields.map { ($0.key, FieldValue.string("")) })
        return Document(
            id: UUID().uuidString,
            docType: previewDocType.id,
            company: "",
            status: "Draft",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: values,
            children: [:]
        )
    }

    private func save() {
        validationError = nil
        let docType = previewDocType

        do {
            try tooling.save(docType: docType)
            onSave?()
            dismiss()
        } catch {
            validationError = tooling.errorMessage(for: error)
        }
    }
}
