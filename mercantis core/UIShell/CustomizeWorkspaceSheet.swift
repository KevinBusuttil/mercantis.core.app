//
//  CustomizeWorkspaceSheet.swift
//  mercantis core
//
//  End-user "Customize fields" sheet. Reachable from the workspace
//  toolbar's pencil/slider icon on `RecordCollectionHostView`. Designed
//  for small-business users: minimum required choices (label, type,
//  position, required toggle), automatic field-key derivation, and
//  inline list of existing custom fields with edit/remove.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// Subset of `FieldType` that we expose to end users. Power-user types
/// (link, table, image, attachment, formula, status, …) are intentionally
/// excluded from v1 — they each need a much richer authoring UI.
enum CustomizableFieldType: String, CaseIterable, Identifiable {
    case text
    case longText
    case number
    case decimal
    case currency
    case boolean
    case date
    case select

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text:     return "Text"
        case .longText: return "Long text"
        case .number:   return "Number (whole)"
        case .decimal:  return "Number (decimal)"
        case .currency: return "Money"
        case .boolean:  return "Yes / No"
        case .date:     return "Date"
        case .select:   return "Choice list"
        }
    }

    var symbol: String {
        switch self {
        case .text:     return "textformat"
        case .longText: return "text.alignleft"
        case .number:   return "number"
        case .decimal:  return "number.square"
        case .currency: return "dollarsign.circle"
        case .boolean:  return "checkmark.square"
        case .date:     return "calendar"
        case .select:   return "list.bullet"
        }
    }

    var fieldType: FieldType {
        switch self {
        case .text:     return .text
        case .longText: return .longText
        case .number:   return .number
        case .decimal:  return .decimal
        case .currency: return .currency
        case .boolean:  return .boolean
        case .date:     return .date
        case .select:   return .select
        }
    }

    /// Best-effort reverse mapping for editing existing fields. Returns
    /// `.text` for types we don't expose in the customize UI so an
    /// imported / power-user-authored field still renders something.
    static func from(_ type: FieldType) -> CustomizableFieldType {
        switch type {
        case .text:      return .text
        case .longText:  return .longText
        case .number:    return .number
        case .decimal:   return .decimal
        case .currency:  return .currency
        case .boolean:   return .boolean
        case .date:      return .date
        case .select:    return .select
        default:         return .text
        }
    }
}

/// Sheet body. Owned by `RecordCollectionHostView` so all callers share
/// the same UX without re-implementing it.
struct CustomizeWorkspaceSheet: View {

    let docTypeName: String
    /// Field keys that already exist on the base DocType. Used both for
    /// the "Position after" picker and for uniqueness checks.
    let baseFields: [BaseFieldEntry]
    /// Existing custom fields (so the user can edit/remove them).
    let customFields: [CustomField]

    let onAdd: (CustomField) throws -> Void
    let onUpdate: (CustomField) throws -> Void
    let onRemove: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editorState: EditorState?
    @State private var errorMessage: String?
    @State private var pendingRemoval: CustomField?

    struct BaseFieldEntry: Identifiable, Hashable {
        let key: String
        let label: String
        var id: String { key }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let editorState {
                editor(state: editorState)
            } else {
                listPane
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 460, idealHeight: 560)
        .alert(
            "Remove this field?",
            isPresented: removalBinding,
            presenting: pendingRemoval
        ) { field in
            Button("Remove", role: .destructive) {
                guard let field = pendingRemoval else { return }
                runProtected { try onRemove(field.id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { field in
            Text("Records that already have a value for \"\(field.fieldDefinition.label)\" will keep it, but the field won't show on the form anymore.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MercantisTheme.accent)
                .frame(width: 28, height: 28)
                .background(MercantisTheme.accentFillSoft, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Customize \(docTypeName)")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add your own fields without touching the original record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if editorState == nil {
                Button {
                    editorState = EditorState(mode: .add, draft: makeDraft())
                } label: {
                    Label("Add Field", systemImage: "plus")
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
            }

            Button("Done") { dismiss() }
                .buttonStyle(MercantisSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MercantisTheme.surface)
    }

    // MARK: - List of existing custom fields

    @ViewBuilder
    private var listPane: some View {
        if customFields.isEmpty {
            ContentUnavailableView(
                "No custom fields yet",
                systemImage: "rectangle.dashed",
                description: Text("Tap **Add Field** to add the first one. It will appear on every \(docTypeName) record.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(customFields, id: \.id) { field in
                    row(for: field)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func row(for field: CustomField) -> some View {
        let typeLabel = CustomizableFieldType.from(field.fieldDefinition.type).label
        let position: String = {
            if let after = field.insertAfter, !after.isEmpty,
               let base = baseFields.first(where: { $0.key == after }) {
                return "After \(base.label)"
            }
            return "End of form"
        }()

        return HStack(spacing: 10) {
            Image(systemName: CustomizableFieldType.from(field.fieldDefinition.type).symbol)
                .foregroundStyle(MercantisTheme.accent)
                .frame(width: 22, height: 22)
                .background(MercantisTheme.accentFillSoft, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(field.fieldDefinition.label)
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Text(typeLabel)
                    Text("·")
                    Text(position)
                    if field.fieldDefinition.required {
                        Text("·")
                        Text("Required").foregroundStyle(MercantisTheme.warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editorState = EditorState(mode: .edit(field.id), draft: Draft(from: field, baseFields: baseFields))
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit field")

            Button(role: .destructive) {
                pendingRemoval = field
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove field")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Editor (add / edit)

    private func editor(state: EditorState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(state.mode.title)
                    .font(.system(size: 14, weight: .semibold))

                draftForm(state: state)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") {
                    editorState = nil
                    errorMessage = nil
                }
                .buttonStyle(MercantisSecondaryButtonStyle())

                Spacer()

                Button(state.mode.commitTitle) {
                    commit(state: state)
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                .disabled(!state.draft.isCommitReady)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func draftForm(state: EditorState) -> some View {
        let bound = bindingForState()

        Form {
            Section {
                LabeledContent("Label") {
                    TextField("e.g. VAT Number", text: bound.label)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Field key") {
                    Text(bound.derivedKey.wrappedValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Toggle("Required", isOn: bound.required)
            } header: {
                Text("Basics")
            } footer: {
                Text("The field key is derived from the label and used internally. It can't be changed after creating the field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Type") {
                Picker("Type", selection: bound.type) {
                    ForEach(CustomizableFieldType.allCases) { type in
                        Label(type.label, systemImage: type.symbol).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .disabled(state.mode.isEdit)
                .help(state.mode.isEdit
                      ? "Type can't be changed after creating the field — remove and re-add to switch type."
                      : "")

                if bound.type.wrappedValue == .select {
                    LabeledContent("Choices") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: bound.optionsText)
                                .frame(minHeight: 72)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator, lineWidth: 1)
                                )
                            Text("One choice per line.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Position") {
                Picker("Place after", selection: bound.insertAfter) {
                    Text("End of form").tag(String?.none)
                    ForEach(positionCandidates(for: state), id: \.key) { entry in
                        Text(entry.label).tag(String?.some(entry.key))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func bindingForState() -> EditorBindings {
        EditorBindings(
            label: Binding(
                get: { editorState?.draft.label ?? "" },
                set: { editorState?.draft.label = $0 }
            ),
            type: Binding(
                get: { editorState?.draft.type ?? .text },
                set: { editorState?.draft.type = $0 }
            ),
            required: Binding(
                get: { editorState?.draft.required ?? false },
                set: { editorState?.draft.required = $0 }
            ),
            insertAfter: Binding(
                get: { editorState?.draft.insertAfter },
                set: { editorState?.draft.insertAfter = $0 }
            ),
            optionsText: Binding(
                get: { editorState?.draft.optionsText ?? "" },
                set: { editorState?.draft.optionsText = $0 }
            ),
            derivedKey: Binding(
                get: { editorState?.draft.derivedKey ?? "—" },
                set: { _ in }
            )
        )
    }

    // MARK: - Commit

    private func commit(state: EditorState) {
        let draft = state.draft
        guard let definition = draft.makeFieldDefinition() else {
            errorMessage = "Please enter a label for the field."
            return
        }

        if case .add = state.mode {
            if reservedKeys.contains(definition.key) {
                errorMessage = "\"\(definition.key)\" is already used on this form. Pick a different label."
                return
            }
        } else if case .edit(let id) = state.mode {
            let conflicting = reservedKeys
                .subtracting(currentEditingFieldKey(id: id))
            if conflicting.contains(definition.key) {
                errorMessage = "\"\(definition.key)\" clashes with another field. Pick a different label."
                return
            }
        }

        runProtected {
            switch state.mode {
            case .add:
                try onAdd(CustomField(
                    docType: docTypeName,
                    fieldDefinition: definition,
                    insertAfter: draft.insertAfter
                ))
            case .edit(let id):
                try onUpdate(CustomField(
                    id: id,
                    docType: docTypeName,
                    fieldDefinition: definition,
                    insertAfter: draft.insertAfter
                ))
            }
            editorState = nil
        }
    }

    private func runProtected(_ block: () throws -> Void) {
        do {
            try block()
            errorMessage = nil
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    // MARK: - Validation helpers

    /// Position picker options. Excludes the field currently being edited
    /// so users can't place a field after itself (which would no-op in the
    /// merge step but is still confusing UX).
    private func positionCandidates(for state: EditorState) -> [BaseFieldEntry] {
        guard case .edit(let id) = state.mode,
              let editing = customFields.first(where: { $0.id == id }) else {
            return baseFields
        }
        return baseFields.filter { $0.key != editing.fieldDefinition.key }
    }

    private var reservedKeys: Set<String> {
        // baseFields already includes existing custom fields' keys (the
        // host passes the composed list), so this single set covers both
        // built-in and custom collisions.
        Set(baseFields.map(\.key))
    }

    private func currentEditingFieldKey(id: String) -> Set<String> {
        if let existing = customFields.first(where: { $0.id == id }) {
            return [existing.fieldDefinition.key]
        }
        return []
    }

    private var removalBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private func makeDraft() -> Draft {
        Draft(
            label: "",
            type: .text,
            required: false,
            insertAfter: nil,
            optionsText: ""
        )
    }
}

// MARK: - Draft / editor state

extension CustomizeWorkspaceSheet {

    /// Mutable shape of the field being authored. We translate to / from
    /// `FieldDefinition` only at commit time so the user can change their
    /// mind freely.
    struct Draft {
        var label: String
        var type: CustomizableFieldType
        var required: Bool
        var insertAfter: String?
        var optionsText: String
        /// In edit mode, the field's persistent key is locked to its
        /// original value so existing document payloads keep matching.
        /// `nil` in add mode (key is derived from the label).
        var lockedKey: String?

        init(label: String, type: CustomizableFieldType, required: Bool, insertAfter: String?, optionsText: String, lockedKey: String? = nil) {
            self.label = label
            self.type = type
            self.required = required
            self.insertAfter = insertAfter
            self.optionsText = optionsText
            self.lockedKey = lockedKey
        }

        init(from field: CustomField, baseFields: [BaseFieldEntry]) {
            self.label = field.fieldDefinition.label
            self.type = CustomizableFieldType.from(field.fieldDefinition.type)
            self.required = field.fieldDefinition.required
            self.insertAfter = field.insertAfter
            self.optionsText = (field.fieldDefinition.options ?? []).joined(separator: "\n")
            self.lockedKey = field.fieldDefinition.key
        }

        var derivedKey: String {
            if let lockedKey, !lockedKey.isEmpty { return lockedKey }
            let candidate = Self.deriveKey(from: label)
            return candidate.isEmpty ? "—" : candidate
        }

        var isCommitReady: Bool {
            !derivedKey.isEmpty && derivedKey != "—"
        }

        func makeFieldDefinition() -> FieldDefinition? {
            let key: String
            if let lockedKey, !lockedKey.isEmpty {
                key = lockedKey
            } else {
                key = Self.deriveKey(from: label)
                guard !key.isEmpty else { return nil }
            }

            let options: [String]?
            if type == .select {
                let parsed = optionsText
                    .split(whereSeparator: { $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                options = parsed.isEmpty ? nil : parsed
            } else {
                options = nil
            }

            return FieldDefinition(
                key: key,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type.fieldType,
                required: required,
                options: options
            )
        }

        /// "VAT Number" → "vat_number". Strips diacritics, collapses
        /// non-alphanumerics into a single underscore, lowercases, and
        /// trims leading digits so the result is a usable identifier.
        static func deriveKey(from label: String) -> String {
            let folded = label.folding(options: .diacriticInsensitive, locale: .current)
            var current = ""
            var lastWasSeparator = false
            for ch in folded {
                if ch.isLetter || ch.isNumber {
                    current.append(Character(ch.lowercased()))
                    lastWasSeparator = false
                } else if !current.isEmpty && !lastWasSeparator {
                    current.append("_")
                    lastWasSeparator = true
                }
            }
            while current.hasSuffix("_") { current.removeLast() }
            while let first = current.first, first.isNumber || first == "_" {
                current.removeFirst()
            }
            return current
        }
    }

    enum EditorMode: Equatable {
        case add
        case edit(String)

        var title: String {
            switch self {
            case .add: return "New field"
            case .edit: return "Edit field"
            }
        }

        var commitTitle: String {
            switch self {
            case .add: return "Add Field"
            case .edit: return "Save Changes"
            }
        }

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    struct EditorState: Equatable {
        let mode: EditorMode
        var draft: Draft

        static func == (lhs: EditorState, rhs: EditorState) -> Bool {
            lhs.mode == rhs.mode
                && lhs.draft.label == rhs.draft.label
                && lhs.draft.type == rhs.draft.type
                && lhs.draft.required == rhs.draft.required
                && lhs.draft.insertAfter == rhs.draft.insertAfter
                && lhs.draft.optionsText == rhs.draft.optionsText
        }
    }

    struct EditorBindings {
        var label: Binding<String>
        var type: Binding<CustomizableFieldType>
        var required: Binding<Bool>
        var insertAfter: Binding<String?>
        var optionsText: Binding<String>
        var derivedKey: Binding<String>
    }
}
