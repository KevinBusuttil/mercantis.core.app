//
//  GenericFormView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// A SwiftUI view that renders a form dynamically from a `DocType` and a `Document`.
///
/// Layout follows native macOS HIG (`Docs/UX-DIRECTION.md` §5.4 / §6).
/// Sections render as native `Form` sections; field rows render as
/// `LabeledContent` (label-left, control-right) for narrow controls and as
/// stacked label/control pairs for tall controls (`longText`, `richText`,
/// `table`, `multiselect`, `image`). The renderer reads
/// `docType.formLayout` when present and otherwise falls back to grouping
/// by `FieldDefinition.section`, so DocTypes that haven't declared a
/// FormLayout keep working unchanged.
///
/// Pass `linkSearchProvider` to enable search-and-pick for `FieldType.link` fields.
/// The closure receives `(targetDocType, query)` and returns matching documents;
/// it typically wraps `engine.list(docType:whereExpression:)`. When `nil` (the
/// default), link fields fall back to plain text entry so existing callers are
/// unaffected. (W4 / ADR-030)
///
/// Pass `childDocTypeProvider` to enable inline editing of `.table` fields. The
/// closure receives a child DocType id and returns the resolved `DocType`. When
/// `nil` (the default), table fields degrade to the static row-count label so
/// existing callers are unaffected. (W5 / ADR-031)
public struct GenericFormView: View {

    let docType: DocType
    @Binding var document: Document
    let userRoles: Set<String>
    let expressionEvaluator: ExpressionEvaluator
    let linkSearchProvider: ((String, String) -> [Document])?
    /// Resolves a single linked document by (targetDocType, id) so link fields
    /// can render a human label for the current selection instead of its id.
    let linkResolveProvider: ((String, String) -> Document?)?
    let childDocTypeProvider: ((String) -> DocType?)?
    /// Builds a blank draft of a target DocType so link fields can offer inline
    /// "create new" record creation in their picker.
    let linkCreateProvider: ((String) -> Document?)?
    /// Persists an inline-created draft and returns the saved document.
    let linkCommitProvider: ((Document) throws -> Document)?

    /// Tracks which editor currently has keyboard focus so we can validate a
    /// field the moment the user tabs/clicks away from it (on blur), instead of
    /// only at Save time.
    @FocusState private var focusedField: String?
    /// Per-field validation messages, keyed by field key. Populated on blur and
    /// cleared as soon as the user edits the offending field.
    @State private var fieldErrors: [String: String] = [:]

    public init(
        docType: DocType,
        document: Binding<Document>,
        userRoles: Set<String> = [],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        linkResolveProvider: ((String, String) -> Document?)? = nil,
        childDocTypeProvider: ((String) -> DocType?)? = nil,
        linkCreateProvider: ((String) -> Document?)? = nil,
        linkCommitProvider: ((Document) throws -> Document)? = nil
    ) {
        self.docType = docType
        self._document = document
        self.userRoles = userRoles
        self.expressionEvaluator = expressionEvaluator
        self.linkSearchProvider = linkSearchProvider
        self.linkResolveProvider = linkResolveProvider
        self.childDocTypeProvider = childDocTypeProvider
        self.linkCreateProvider = linkCreateProvider
        self.linkCommitProvider = linkCommitProvider
    }

    public var body: some View {
        // Hand-rolled card-style layout in place of SwiftUI's grouped `Form`.
        // The grouped Form on macOS constrains every row to a narrow content
        // column, which made wide child-table sections unusable and made the
        // `FormLayoutSection.columns: 2` hint meaningless. Driving the layout
        // ourselves lets `.table` fields claim the full sheet width (UX-3
        // Option C) and lets compact sections lay out two fields per row.
        //
        // No explicit background — the sheet's natural surface shows through
        // and cards differentiate via their stroke alone. Matches the modern
        // macOS HIG sheet pattern (System Settings, Notes).
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(resolvedSections) { section in
                    sectionCard(for: section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
        .scrollContentBackground(.hidden)
        #endif
        .navigationTitle(docType.name)
        .onChange(of: focusedField) { previous, _ in
            // Validate the field the user just left (blur), so errors surface
            // field-by-field instead of all at once on Save.
            if let previous { validateField(key: previous) }
        }
    }

    // MARK: - Section rendering

    @ViewBuilder
    private func sectionCard(for section: ResolvedSection) -> some View {
        let containsTable = section.fields.contains { $0.type == .table }
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title, !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(MercantisTheme.textMuted)
                    .padding(.horizontal, 4)
            }

            sectionBody(for: section, containsTable: containsTable)
                // Tables hug the card edges so their grid can spread out;
                // regular sections get generous inner padding.
                .padding(containsTable
                    ? EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
                    : EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                // With no muted backdrop behind us, the card is the same
                // surface as the sheet — the stroke alone has to carry the
                // visual grouping, so it runs at full opacity.
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MercantisTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(MercantisTheme.border, lineWidth: 1)
                )

            if let help = section.helpText, !help.isEmpty {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func sectionBody(for section: ResolvedSection, containsTable: Bool) -> some View {
        // A section that mixes in a stacked `.table` field should still benefit
        // from two-column layout on its compact siblings; the table itself
        // always spans full width via `usesStackedLayout`.
        if section.columns == 2 {
            twoColumnLayout(fields: section.fields)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(section.fields) { field in
                    fieldRow(for: field, stacked: false)
                }
            }
        }
    }

    @ViewBuilder
    private func twoColumnLayout(fields: [FieldDefinition]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 14) {
            ForEach(Array(pairedRows(fields).enumerated()), id: \.offset) { _, row in
                GridRow {
                    switch row {
                    case .pair(let lhs, let rhs):
                        fieldRow(for: lhs, stacked: true)
                        if let rhs {
                            fieldRow(for: rhs, stacked: true)
                        } else {
                            // Empty placeholder keeps the left field at ~half
                            // width instead of expanding to fill the row.
                            Color.clear
                        }
                    case .full(let f):
                        fieldRow(for: f, stacked: true)
                            .gridCellColumns(2)
                    }
                }
            }
        }
    }

    private enum PairedRow {
        case pair(FieldDefinition, FieldDefinition?)
        case full(FieldDefinition)
    }

    /// Walk fields in order and bucket non-stacked compacts into pairs.
    /// Stacked fields (table, longText, richText, multiselect, image) break
    /// the pair and span both columns.
    private func pairedRows(_ fields: [FieldDefinition]) -> [PairedRow] {
        var rows: [PairedRow] = []
        var pending: FieldDefinition?
        for field in fields {
            if usesStackedLayout(field) {
                if let p = pending {
                    rows.append(.pair(p, nil))
                    pending = nil
                }
                rows.append(.full(field))
            } else if let p = pending {
                rows.append(.pair(p, field))
                pending = nil
            } else {
                pending = field
            }
        }
        if let p = pending { rows.append(.pair(p, nil)) }
        return rows
    }

    @ViewBuilder
    private func fieldRow(for field: FieldDefinition, stacked: Bool) -> some View {
        let isReadOnly = isReadOnly(field: field)

        if isLayoutSeparator(field) {
            // Headings / section / column breaks are pure layout — they carry
            // their own label and span the full width with no leading label cell.
            layoutSeparator(field: field)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let stackedLayout = stacked || usesStackedLayout(field)
            VStack(alignment: .leading, spacing: 4) {
                if stackedLayout {
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel(for: field)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MercantisTheme.textMuted)
                        decoratedControl(for: field, isReadOnly: isReadOnly)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    fieldFootnotes(for: field, indented: false)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        fieldLabel(for: field)
                            .font(.system(size: 12))
                            .foregroundStyle(MercantisTheme.textPrimary)
                            .frame(width: 150, alignment: .leading)
                        decoratedControl(for: field, isReadOnly: isReadOnly)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    fieldFootnotes(for: field, indented: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The field's editor with a red outline when it currently has an inline
    /// error. Focus tracking (for blur validation) lives on the individual text
    /// editors, where `.focused` binds reliably.
    private func decoratedControl(for field: FieldDefinition, isReadOnly: Bool) -> some View {
        fieldControl(for: field, isReadOnly: isReadOnly)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.danger, lineWidth: 1)
                    .opacity(fieldErrors[field.key] != nil ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }

    /// Inline error (if any) plus the field's help text, shown beneath the
    /// control. In the two-column / label-left layout these are indented to line
    /// up under the control rather than the label.
    @ViewBuilder
    private func fieldFootnotes(for field: FieldDefinition, indented: Bool) -> some View {
        let help = field.helpText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = fieldErrors[field.key]
        if (help?.isEmpty == false) || (error?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 2) {
                if let error, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(MercantisTheme.danger)
                }
                if let help, !help.isEmpty {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, indented ? 162 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Field label with a red asterisk appended when the field is
    /// required, plus an accessibility hint so VoiceOver announces it.
    @ViewBuilder
    private func fieldLabel(for field: FieldDefinition) -> some View {
        if field.required {
            HStack(spacing: 2) {
                Text(field.label)
                Text("*")
                    .foregroundStyle(MercantisTheme.danger)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Text("\(field.label), required"))
        } else {
            Text(field.label)
        }
    }

    private func usesStackedLayout(_ field: FieldDefinition) -> Bool {
        switch field.type {
        case .longText, .richText, .table, .multiselect, .image,
             .code, .signature, .tableMultiSelect,
             .heading, .sectionBreak, .columnBreak:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func fieldControl(for field: FieldDefinition, isReadOnly: Bool) -> some View {
        switch field.type {
        case .text, .email, .phone:
            textField(field: field, isReadOnly: isReadOnly)
        case .longText, .code:
            // `.code` renders a monospaced multi-line editor; `.longText` keeps
            // the plain TextEditor below.
            if field.type == .code {
                codeField(field: field, isReadOnly: isReadOnly)
            } else {
                longTextField(field: field, isReadOnly: isReadOnly)
            }
        case .richText:
            richTextField(field: field, isReadOnly: isReadOnly)
        case .number, .decimal, .currency:
            numberField(field: field, isReadOnly: isReadOnly)
        case .percent:
            percentField(field: field, isReadOnly: isReadOnly)
        case .boolean:
            toggleField(field: field, isReadOnly: isReadOnly)
        case .date, .datetime:
            dateField(field: field, isReadOnly: isReadOnly)
        case .time:
            timeField(field: field, isReadOnly: isReadOnly)
        case .select, .status:
            selectField(field: field, isReadOnly: isReadOnly)
        case .multiselect, .tableMultiSelect:
            // `.tableMultiSelect` has no dedicated Swift editor yet; it falls
            // back to the chip-style multiselect (closest existing editor),
            // matching the Flutter app's graceful degradation.
            multiselectField(field: field, isReadOnly: isReadOnly)
        case .link, .dynamicLink:
            // `.dynamicLink` falls back to the standard link picker.
            linkField(field: field, isReadOnly: isReadOnly)
        case .autocomplete:
            // No bespoke autocomplete editor; degrade to plain text entry.
            textField(field: field, isReadOnly: isReadOnly)
        case .password:
            passwordField(field: field, isReadOnly: isReadOnly)
        case .rating:
            ratingField(field: field, isReadOnly: isReadOnly)
        case .duration:
            durationField(field: field, isReadOnly: isReadOnly)
        case .color:
            colorField(field: field, isReadOnly: isReadOnly)
        case .signature:
            signatureField(field: field, isReadOnly: isReadOnly)
        case .geolocation:
            // No map picker yet; degrade to plain text entry (lat,lng string),
            // matching the Flutter app's text-based geolocation fallback.
            textField(field: field, isReadOnly: isReadOnly)
        case .heading, .sectionBreak, .columnBreak:
            layoutSeparator(field: field)
        case .formula:
            formulaField(field: field)
        case .table:
            tableField(field: field)
        case .attachment:
            attachmentField(field: field, isReadOnly: isReadOnly)
        case .image:
            imageField(field: field, isReadOnly: isReadOnly)
        case .barcode:
            barcodeField(field: field, isReadOnly: isReadOnly)
        }
    }

    // MARK: - Layout resolution

    private struct ResolvedSection: Identifiable {
        let id: String
        let title: String?
        let helpText: String?
        let columns: Int
        let fields: [FieldDefinition]
    }

    private var resolvedSections: [ResolvedSection] {
        if let layout = docType.formLayout, !layout.sections.isEmpty {
            return resolveDeclared(layout: layout)
        }
        return resolveLegacy()
    }

    /// Resolve a DocType-declared FormLayout into renderable sections.
    /// Field keys not present on the DocType are skipped silently.
    private func resolveDeclared(layout: FormLayout) -> [ResolvedSection] {
        let visible = visibleFields
        let fieldByKey = Dictionary(uniqueKeysWithValues: visible.map { ($0.key, $0) })

        return layout.sections.compactMap { section in
            let resolvedFields = section.fieldKeys.compactMap { fieldByKey[$0] }
            guard !resolvedFields.isEmpty else { return nil }
            return ResolvedSection(
                id: section.key,
                title: section.title,
                helpText: section.helpText,
                columns: section.columns,
                fields: resolvedFields
            )
        }
    }

    /// Fallback grouping for DocTypes without a declared FormLayout — keeps
    /// the prior behavior of bucketing by `FieldDefinition.section` and
    /// ordering within a section by `column`.
    private func resolveLegacy() -> [ResolvedSection] {
        let grouped = Dictionary(grouping: visibleFields) { field in
            (field.section?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Main"
        }

        return grouped.keys.sorted().map { key in
            let fields = grouped[key, default: []].sorted { lhs, rhs in
                (lhs.column ?? .max) < (rhs.column ?? .max)
            }
            return ResolvedSection(
                id: key,
                title: key,
                helpText: nil,
                columns: 1,
                fields: fields
            )
        }
    }

    private var visibleFields: [FieldDefinition] {
        docType.fields.filter { field in
            guard let expr = field.visibilityExpression, !expr.isEmpty else { return true }
            return (try? expressionEvaluator.evaluateBool(
                expression: expr,
                context: document.fields
            )) ?? true
        }
    }

    // MARK: - Field controls

    private func textField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: binding, prompt: promptText(for: field))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusedField, equals: field.key)
            }
        }
    }

    private func longTextField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextEditor(text: binding)
                    .frame(minHeight: 90)
                    .focused($focusedField, equals: field.key)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    )
            }
        }
    }

    private func richTextField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        RichTextField(value: stringBinding(for: field), isReadOnly: isReadOnly)
    }

    private func numberField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let strBinding = numberBinding(for: field)
        return Group {
            if isReadOnly {
                Text(strBinding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: strBinding, prompt: promptText(for: field))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field.key)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
        }
    }

    private func toggleField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        Toggle("", isOn: boolBinding(for: field))
            .labelsHidden()
            .disabled(isReadOnly)
    }

    private func dateField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        DatePicker(
            "",
            selection: dateBinding(for: field),
            displayedComponents: field.type == .datetime ? [.date, .hourAndMinute] : [.date]
        )
        .labelsHidden()
        .disabled(isReadOnly)
        .onAppear {
            // A DatePicker can't represent "no value" — it always shows today.
            // For a required date with nothing stored, persist that displayed
            // default so it's actually saved; otherwise the record validates as
            // missing even though the user sees a date.
            guard !isReadOnly, field.required, isDateValueEmpty(document.fields[field.key]) else { return }
            let now = Date()
            document.fields[field.key] = field.type == .datetime ? .dateTime(now) : .date(now)
        }
    }

    /// Whether a date field has no usable stored value (nil / null / blank string).
    private func isDateValueEmpty(_ value: FieldValue?) -> Bool {
        switch value {
        case .none, .null:
            return true
        case .string(let s):
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private func selectField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let options = field.options ?? []
        let strBinding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(strBinding.wrappedValue.isEmpty ? "—" : strBinding.wrappedValue)
                    .foregroundStyle(.secondary)
            } else {
                Picker(field.label, selection: strBinding) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func multiselectField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let options = field.options ?? []
        let selection = stringBinding(for: field)
        let selectedValues = Set(selection.wrappedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = selectedValues.contains(option)
                Button(option) {
                    guard !isReadOnly else { return }
                    var values = selectedValues
                    if isSelected {
                        values.remove(option)
                    } else {
                        values.insert(option)
                    }
                    selection.wrappedValue = values.sorted().joined(separator: ",")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isSelected ? .accentColor : .secondary)
            }
        }
    }

    private func linkField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        // W4: delegate to LinkPickerField. When linkSearchProvider is nil the
        // picker falls back to plain text entry (no behaviour change for callers
        // that haven't wired a provider yet).
        let target = field.linkedDocType ?? ""
        let provider: ((String, String) -> [Document])? = linkSearchProvider.map { base in
            { _, query in base(target, query) }
        }
        let resolve: ((String) -> Document?)? = linkResolveProvider.map { base in
            { id in base(target, id) }
        }
        let make: (() -> Document?)? = linkCreateProvider.map { base in
            { base(target) }
        }
        return LinkPickerField(
            targetDocType: target.isEmpty ? "Link" : target,
            value: stringBinding(for: field),
            isReadOnly: isReadOnly,
            targetMeta: childDocTypeProvider?(target),
            searchProvider: provider,
            resolveDocument: resolve,
            makeDraft: make,
            commitDraft: linkCommitProvider
        )
    }

    private func tableField(field: FieldDefinition) -> some View {
        let childDocType = field.childDocType.flatMap { childDocTypeProvider?($0) }
        return ChildTableField(
            field: field,
            childDocType: childDocType,
            rows: Binding(
                get: { document.children[field.key, default: []] },
                set: { document.children[field.key] = $0 }
            ),
            isReadOnly: false,
            // Thread the same link providers used for top-level link fields so
            // `.link` columns inside child rows render the searchable picker
            // instead of a plain text field. (Child-table link support.)
            linkSearchProvider: linkSearchProvider,
            linkResolveProvider: linkResolveProvider,
            childDocTypeProvider: childDocTypeProvider
        )
    }

    private func attachmentField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue.isEmpty ? "No attachment" : binding.wrappedValue)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Attachment reference", text: binding, prompt: promptText(for: field))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusedField, equals: field.key)
            }
        }
    }

    private func imageField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = Binding<Data?>(
            get: {
                if case .data(let d) = document.fields[field.key] { return d }
                return nil
            },
            set: { newValue in
                document.fields[field.key] = newValue.map(FieldValue.data) ?? .null
            }
        )
        return ImageField(value: binding, isReadOnly: isReadOnly)
    }

    private func barcodeField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        BarcodeField(value: stringBinding(for: field), isReadOnly: isReadOnly)
    }

    // MARK: - Parity field controls

    /// `.percent` — numeric entry with a trailing `%` suffix. Stores a Double.
    private func percentField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let strBinding = numberBinding(for: field)
        return Group {
            if isReadOnly {
                Text(strBinding.wrappedValue.isEmpty ? "—" : "\(strBinding.wrappedValue)%")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    TextField(field.label, text: strBinding, prompt: promptText(for: field))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: field.key)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text("%").foregroundStyle(MercantisTheme.textMuted)
                }
            }
        }
    }

    /// `.password` — masked entry backed by `SecureField`. Stores a String.
    private func passwordField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue.isEmpty ? "—" : "••••••••")
                    .foregroundStyle(.secondary)
            } else {
                SecureField(field.label, text: binding, prompt: promptText(for: field))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusedField, equals: field.key)
            }
        }
    }

    /// `.time` — time-only picker. Persists the selection as the typed
    /// `.dateTime` FieldValue (only the hour/minute components are displayed).
    private func timeField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        DatePicker(
            "",
            selection: timeBinding(for: field),
            displayedComponents: [.hourAndMinute]
        )
        .labelsHidden()
        .disabled(isReadOnly)
    }

    private func ratingField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        RatingField(value: intBinding(for: field), isReadOnly: isReadOnly)
    }

    private func durationField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        DurationField(seconds: intBinding(for: field), isReadOnly: isReadOnly)
    }

    private func codeField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        CodeField(value: stringBinding(for: field), isReadOnly: isReadOnly)
    }

    private func colorField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        ColorField(value: stringBinding(for: field), isReadOnly: isReadOnly)
    }

    private func signatureField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        SignatureField(value: stringBinding(for: field), isReadOnly: isReadOnly)
    }

    private func isLayoutSeparator(_ field: FieldDefinition) -> Bool {
        switch field.type {
        case .heading, .sectionBreak, .columnBreak: return true
        default: return false
        }
    }

    /// `.heading` / `.sectionBreak` / `.columnBreak` — non-editable layout
    /// separators. A heading renders its label as a bold title; the breaks
    /// render a divider (with the label as a caption when present).
    @ViewBuilder
    private func layoutSeparator(field: FieldDefinition) -> some View {
        switch field.type {
        case .heading:
            Text(field.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
                .padding(.top, 4)
        default:
            VStack(alignment: .leading, spacing: 4) {
                if !field.label.isEmpty {
                    Text(field.label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(MercantisTheme.textMuted)
                }
                Divider()
            }
        }
    }

    private func formulaField(field: FieldDefinition) -> some View {
        let computed = field.formulaExpression.flatMap { expr in
            try? expressionEvaluator.evaluateFormula(expression: expr, context: document.fields)
        } ?? FieldValue.null
        let display: String
        switch computed {
        case .double(let d): display = String(format: "%.2f", d)
        case .int(let i): display = "\(i)"
        case .string(let s): display = s
        default: display = "—"
        }
        return Text(display).foregroundStyle(.secondary)
    }

    // MARK: - Bindings

    private func isReadOnly(field: FieldDefinition) -> Bool {
        guard let expr = field.readOnlyExpression, !expr.isEmpty else { return false }
        return (try? expressionEvaluator.evaluateBool(
            expression: expr,
            context: document.fields
        )) ?? false
    }

    private func stringBinding(for field: FieldDefinition) -> Binding<String> {
        Binding<String>(
            get: {
                switch document.fields[field.key] {
                case .string(let s): return s
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .bool(let b): return b ? "true" : "false"
                default: return ""
                }
            },
            set: { newValue in
                clearError(field.key)
                document.fields[field.key] = .string(newValue)
            }
        )
    }

    private func boolBinding(for field: FieldDefinition) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .bool(let b) = document.fields[field.key] { return b }
                return false
            },
            set: { newValue in
                document.fields[field.key] = .bool(newValue)
            }
        )
    }

    private func dateBinding(for field: FieldDefinition) -> Binding<Date> {
        Binding<Date>(
            get: {
                switch document.fields[field.key] {
                case .date(let d), .dateTime(let d): return d
                case .string(let s): return ISO8601DateFormatter().date(from: s) ?? Date()
                default: return Date()
                }
            },
            set: { newValue in
                // P1.6: write typed `.date` / `.dateTime` based on the declared
                // field type. Falls back to ISO8601 string only for UI fields
                // without a date type (should not happen through `dateField`).
                switch field.type {
                case .date:
                    document.fields[field.key] = .date(newValue)
                case .datetime:
                    document.fields[field.key] = .dateTime(newValue)
                default:
                    document.fields[field.key] = .string(ISO8601DateFormatter().string(from: newValue))
                }
            }
        )
    }

    /// Integer-backed binding used by rating (stars) and duration (seconds).
    /// Tolerates a stored Double or numeric String and always writes `.int`.
    private func intBinding(for field: FieldDefinition) -> Binding<Int> {
        Binding<Int>(
            get: {
                switch document.fields[field.key] {
                case .int(let i): return i
                case .double(let d): return Int(d.rounded())
                case .string(let s): return Int(s) ?? 0
                default: return 0
                }
            },
            set: { newValue in
                document.fields[field.key] = .int(newValue)
            }
        )
    }

    /// Time-only binding. Reads/writes the typed `.dateTime` FieldValue; only
    /// the hour/minute components are surfaced through the picker.
    private func timeBinding(for field: FieldDefinition) -> Binding<Date> {
        Binding<Date>(
            get: {
                switch document.fields[field.key] {
                case .dateTime(let d), .date(let d): return d
                case .string(let s): return ISO8601DateFormatter().date(from: s) ?? Date()
                default: return Date()
                }
            },
            set: { newValue in
                document.fields[field.key] = .dateTime(newValue)
            }
        )
    }

    private func numberBinding(for field: FieldDefinition) -> Binding<String> {
        Binding<String>(
            get: {
                switch document.fields[field.key] {
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .string(let s): return s
                default: return ""
                }
            },
            set: { newValue in
                clearError(field.key)
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    // An empty numeric field is "no value", not the string "" —
                    // storing "" fails `.decimal` / `.currency` type validation.
                    document.fields[field.key] = .null
                } else if field.type == .number, let intVal = Int(trimmed) {
                    document.fields[field.key] = .int(intVal)
                } else if let doubleVal = Double(trimmed) {
                    document.fields[field.key] = .double(doubleVal)
                } else {
                    document.fields[field.key] = .string(newValue)
                }
            }
        )
    }

    // MARK: - Inline validation

    /// Placeholder shown inside a text-like control. Falls back to `nil` (so the
    /// control shows nothing / its own default) when the field declares none.
    private func promptText(for field: FieldDefinition) -> Text? {
        guard let placeholder = field.placeholder, !placeholder.isEmpty else { return nil }
        return Text(placeholder)
    }

    /// Re-evaluate one field's inline error and store / clear it.
    private func validateField(key: String) {
        guard let field = docType.fields.first(where: { $0.key == key }) else { return }
        if let message = localValidationError(for: field) {
            fieldErrors[key] = message
        } else {
            fieldErrors.removeValue(forKey: key)
        }
    }

    /// Drop a field's error the instant the user starts editing it again, so the
    /// red outline clears without waiting for the next blur.
    private func clearError(_ key: String) {
        if fieldErrors[key] != nil { fieldErrors.removeValue(forKey: key) }
    }

    /// Cheap, local, DB-free validation used for immediate feedback: required
    /// fields that are empty and obvious type mismatches (non-numeric numbers,
    /// malformed emails). The full `ValidationPipeline` still runs on Save for
    /// link integrity, uniqueness, and cross-field rules.
    private func localValidationError(for field: FieldDefinition) -> String? {
        if isLayoutSeparator(field) || field.type == .formula || field.type == .table { return nil }
        if isReadOnly(field: field) { return nil }

        let value = document.fields[field.key]
        let empty = isValueEmpty(value)

        if field.required && empty {
            return "'\(field.label)' is required."
        }
        if empty { return nil }  // optional + empty is fine

        switch field.type {
        case .number, .decimal, .currency, .percent:
            if !isNumericValue(value) {
                return "'\(field.label)' must be a valid number."
            }
        case .email:
            if case .string(let s) = value, !looksLikeEmail(s) {
                return "'\(field.label)' must be a valid email address."
            }
        default:
            break
        }
        return nil
    }

    private func isValueEmpty(_ value: FieldValue?) -> Bool {
        switch value {
        case .none, .null:
            return true
        case .string(let s):
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let xs):
            return xs.isEmpty
        default:
            return false
        }
    }

    private func isNumericValue(_ value: FieldValue?) -> Bool {
        switch value {
        case .int, .double:
            return true
        case .string(let s):
            return Double(s.trimmingCharacters(in: .whitespaces)) != nil
        default:
            return false
        }
    }

    private func looksLikeEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let domain = t[t.index(after: at)...]
        return !domain.isEmpty && domain.contains(".") && !domain.hasSuffix(".") && !t.contains(" ")
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
