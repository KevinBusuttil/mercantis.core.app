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
/// Pass `linkSearchProvider` to enable search-and-pick for `FieldType.link` fields.
/// The closure receives `(targetDocType, query)` and returns matching documents;
/// it typically wraps `engine.list(docType:whereExpression:)`. When `nil` (the
/// default), link fields fall back to plain text entry so existing callers are
/// unaffected. (W4 / ADR-030)
public struct GenericFormView: View {

    let docType: DocType
    @Binding var document: Document
    let userRoles: Set<String>
    let expressionEvaluator: ExpressionEvaluator
    let linkSearchProvider: ((String, String) -> [Document])?

    public init(
        docType: DocType,
        document: Binding<Document>,
        userRoles: Set<String> = [],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator(),
        linkSearchProvider: ((String, String) -> [Document])? = nil
    ) {
        self.docType = docType
        self._document = document
        self.userRoles = userRoles
        self.expressionEvaluator = expressionEvaluator
        self.linkSearchProvider = linkSearchProvider
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sectionGroups) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.headline)

                            LazyVGrid(columns: gridColumns(for: proxy.size.width), alignment: .leading, spacing: 12) {
                                ForEach(section.fields) { field in
                                    fieldCard(for: field)
                                }
                            }
                        }
                        .mercantisCard()
                    }
                }
                .padding()
            }
            .background(MercantisTheme.background)
        }
        .navigationTitle(docType.name)
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        width > 900
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
    }

    private var sectionGroups: [FieldSectionGroup] {
        let grouped = Dictionary(grouping: visibleFields) { field in
            field.section?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? field.section!
                : "Main"
        }

        return grouped.keys.sorted().map { key in
            let fields = grouped[key, default: []].sorted { lhs, rhs in
                (lhs.column ?? .max) < (rhs.column ?? .max)
            }
            return FieldSectionGroup(title: key, fields: fields)
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

    @ViewBuilder
    private func fieldCard(for field: FieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            fieldRow(for: field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(MercantisTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func fieldRow(for field: FieldDefinition) -> some View {
        let isReadOnly = isReadOnly(field: field)

        switch field.type {
        case .text, .email, .phone:
            textField(field: field, isReadOnly: isReadOnly)
        case .longText:
            longTextField(field: field, isReadOnly: isReadOnly)
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
        }
    }

    private func textField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: binding)
                    .mercantisInput()
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
                    .padding(6)
                    .background(MercantisTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func numberField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let strBinding = numberBinding(for: field)
        return Group {
            if isReadOnly {
                Text(strBinding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: strBinding)
                    .mercantisInput()
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
        }
    }

    private func toggleField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = boolBinding(for: field)
        return Toggle("", isOn: binding)
            .labelsHidden()
            .disabled(isReadOnly)
    }

    private func dateField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = dateBinding(for: field)
        return DatePicker(
            "",
            selection: binding,
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
                Text(strBinding.wrappedValue).foregroundStyle(.secondary)
            } else {
                Picker(field.label, selection: strBinding) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .mercantisPicker()
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
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? MercantisTheme.primary.opacity(0.2) : MercantisTheme.surface)
                .clipShape(Capsule())
            }
        }
    }

    private func linkField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        // W4: delegate to LinkPickerField. When linkSearchProvider is nil the
        // picker falls back to plain text entry (no behaviour change for callers
        // that haven't wired a provider yet).
        let provider: ((String, String) -> [Document])? = linkSearchProvider.map { base in
            { query in base(field.linkedDocType ?? "", query) }
        }
        return LinkPickerField(
            targetDocType: field.linkedDocType ?? "Link",
            value: stringBinding(for: field),
            isReadOnly: isReadOnly,
            searchProvider: provider
        )
    }

    private func tableField(field: FieldDefinition) -> some View {
        let rows = document.children[field.key, default: []]
        return HStack {
            Text("\(rows.count) row\(rows.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Table")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func attachmentField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return Group {
            if isReadOnly {
                Text(binding.wrappedValue.isEmpty ? "No attachment" : binding.wrappedValue)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Attachment reference", text: binding)
                    .mercantisInput()
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

private struct FieldSectionGroup: Identifiable {
    let id = UUID()
    let title: String
    let fields: [FieldDefinition]
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
