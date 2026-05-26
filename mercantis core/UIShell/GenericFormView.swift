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
    let childDocTypeProvider: ((String) -> DocType?)?

    public init(
        docType: DocType,
        document: Binding<Document>,
        userRoles: Set<String> = [],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        childDocTypeProvider: ((String) -> DocType?)? = nil
    ) {
        self.docType = docType
        self._document = document
        self.userRoles = userRoles
        self.expressionEvaluator = expressionEvaluator
        self.linkSearchProvider = linkSearchProvider
        self.childDocTypeProvider = childDocTypeProvider
    }

    public var body: some View {
        // Hand-rolled card-style layout in place of SwiftUI's grouped `Form`.
        // The grouped Form on macOS constrains every row to a narrow content
        // column, which made wide child-table sections unusable and made the
        // `FormLayoutSection.columns: 2` hint meaningless. Driving the layout
        // ourselves lets `.table` fields claim the full sheet width (UX-3
        // Option C) and lets compact sections lay out two fields per row.
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
        .background(MercantisTheme.surfaceMuted)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        #endif
        .navigationTitle(docType.name)
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
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MercantisTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(MercantisTheme.border.opacity(0.8), lineWidth: 1)
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

        if stacked || usesStackedLayout(field) {
            VStack(alignment: .leading, spacing: 5) {
                fieldLabel(for: field)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MercantisTheme.textMuted)
                fieldControl(for: field, isReadOnly: isReadOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                fieldLabel(for: field)
                    .font(.system(size: 12))
                    .foregroundStyle(MercantisTheme.textPrimary)
                    .frame(width: 150, alignment: .leading)
                fieldControl(for: field, isReadOnly: isReadOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        case .longText, .richText, .table, .multiselect, .image:
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
        case .longText:
            longTextField(field: field, isReadOnly: isReadOnly)
        case .richText:
            richTextField(field: field, isReadOnly: isReadOnly)
        case .number, .decimal, .currency:
            numberField(field: field, isReadOnly: isReadOnly)
        case .boolean:
            toggleField(field: field, isReadOnly: isReadOnly)
        case .date, .datetime:
            dateField(field: field, isReadOnly: isReadOnly)
        case .select, .status:
            selectField(field: field, isReadOnly: isReadOnly)
        case .multiselect:
            multiselectField(field: field, isReadOnly: isReadOnly)
        case .link:
            linkField(field: field, isReadOnly: isReadOnly)
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
                TextField(field.label, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
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
                TextField(field.label, text: strBinding)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
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
        let provider: ((String, String) -> [Document])? = linkSearchProvider.map { base in
            { _, query in base(field.linkedDocType ?? "", query) }
        }
        return LinkPickerField(
            targetDocType: field.linkedDocType ?? "Link",
            value: stringBinding(for: field),
            isReadOnly: isReadOnly,
            searchProvider: provider
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
            isReadOnly: false
        )
    }

    private func attachmentField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue.isEmpty ? "No attachment" : binding.wrappedValue)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Attachment reference", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
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
                if field.type == .number, let intVal = Int(newValue) {
                    document.fields[field.key] = .int(intVal)
                } else if let doubleVal = Double(newValue) {
                    document.fields[field.key] = .double(doubleVal)
                } else {
                    document.fields[field.key] = .string(newValue)
                }
            }
        )
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
