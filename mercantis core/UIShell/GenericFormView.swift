//
//  GenericFormView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

/// A SwiftUI view that renders a form dynamically from a `DocType` and a `Document`.
///
/// Each `FieldDefinition` in the DocType is rendered as an appropriate control:
/// text, toggle, date picker, select dropdown, number field, etc.
public struct GenericFormView: View {

    let docType: DocType
    @Binding var document: Document
    let userRoles: Set<String>
    let expressionEvaluator: ExpressionEvaluator

    public init(
        docType: DocType,
        document: Binding<Document>,
        userRoles: Set<String> = [],
        expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()
    ) {
        self.docType = docType
        self._document = document
        self.userRoles = userRoles
        self.expressionEvaluator = expressionEvaluator
    }

    public var body: some View {
        Form {
            ForEach(visibleFields) { field in
                fieldRow(for: field)
            }
        }
        .navigationTitle(docType.name)
    }

    // MARK: - Visible Fields

    private var visibleFields: [FieldDefinition] {
        docType.fields.filter { field in
            guard let expr = field.visibilityExpression, !expr.isEmpty else { return true }
            return (try? expressionEvaluator.evaluateBool(
                expression: expr,
                context: document.fields
            )) ?? true
        }
    }

    // MARK: - Field Row

    @ViewBuilder
    private func fieldRow(for field: FieldDefinition) -> some View {
        let isReadOnly = isReadOnly(field: field)

        switch field.type {
        case .text, .longText, .email, .phone:
            textField(field: field, isReadOnly: isReadOnly)

        case .number, .decimal, .currency:
            numberField(field: field, isReadOnly: isReadOnly)

        case .boolean:
            toggleField(field: field, isReadOnly: isReadOnly)

        case .date, .datetime:
            dateField(field: field, isReadOnly: isReadOnly)

        case .select, .status:
            selectField(field: field, isReadOnly: isReadOnly)

        case .link:
            linkField(field: field, isReadOnly: isReadOnly)

        case .formula:
            formulaField(field: field)

        case .multiselect, .table, .attachment:
            Text(field.label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Control Builders

    private func textField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = stringBinding(for: field)
        return LabeledContent(field.label) {
            if isReadOnly {
                Text(binding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: binding)
            }
        }
    }

    private func numberField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let strBinding = stringBinding(for: field)
        return LabeledContent(field.label) {
            if isReadOnly {
                Text(strBinding.wrappedValue).foregroundStyle(.secondary)
            } else {
                TextField(field.label, text: strBinding)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
            }
        }
    }

    private func toggleField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = boolBinding(for: field)
        return Toggle(field.label, isOn: binding)
            .disabled(isReadOnly)
    }

    private func dateField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let binding = dateBinding(for: field)
        return DatePicker(
            field.label,
            selection: binding,
            displayedComponents: field.type == .datetime ? [.date, .hourAndMinute] : [.date]
        )
        .disabled(isReadOnly)
    }

    private func selectField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let options = field.options ?? []
        let strBinding = stringBinding(for: field)
        return LabeledContent(field.label) {
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
            }
        }
    }

    private func linkField(field: FieldDefinition, isReadOnly: Bool) -> some View {
        let strBinding = stringBinding(for: field)
        return LabeledContent(field.label) {
            if isReadOnly {
                Text(strBinding.wrappedValue).foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField(field.linkedDocType ?? "Link", text: strBinding)
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
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
        return LabeledContent(field.label) {
            Text(display).foregroundStyle(.secondary)
        }
    }

    // MARK: - Read-Only Check

    private func isReadOnly(field: FieldDefinition) -> Bool {
        guard let expr = field.readOnlyExpression, !expr.isEmpty else { return false }
        return (try? expressionEvaluator.evaluateBool(
            expression: expr,
            context: document.fields
        )) ?? false
    }

    // MARK: - Bindings

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
                if case .string(let s) = document.fields[field.key] {
                    return ISO8601DateFormatter().date(from: s) ?? Date()
                }
                return Date()
            },
            set: { newValue in
                let str = ISO8601DateFormatter().string(from: newValue)
                document.fields[field.key] = .string(str)
            }
        )
    }
}
