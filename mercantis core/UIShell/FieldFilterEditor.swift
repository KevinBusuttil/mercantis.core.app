//
//  FieldFilterEditor.swift
//  mercantis core
//
//  Type-aware popover for building a single `ListFilter` predicate over one
//  DocType field, used by `GenericListView`'s "Filter" menu. Each field type
//  exposes only the operators that make sense for it (A.3); link fields reuse
//  `LinkPickerField` so filtering a link feels exactly like editing one (E).
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

struct FieldFilterEditor: View {
    let field: FieldDefinition
    let linkSearchProvider: ((String, String) -> [Document])?
    let linkResolveProvider: ((String, String) -> Document?)?
    let linkTargetMeta: DocType?
    /// Hands back the built predicate plus a human-readable chip label.
    let onApply: (ListFilter, String) -> Void
    let onCancel: () -> Void

    // Shared editing state — only the fields relevant to `field.type` are used.
    @State private var textValue = ""
    @State private var textOp: TextOp = .contains
    @State private var numberValue = ""
    @State private var numberValue2 = ""
    @State private var numberOp: NumberOp = .eq
    @State private var boolValue = true
    @State private var selectValue = ""
    @State private var linkValue = ""
    @State private var datePreset: DateRangePreset = .thisMonth
    @State private var useCustomRange = false
    @State private var customStart = Calendar.current.startOfDay(for: Date())
    @State private var customEnd = Date()

    private enum TextOp: String, CaseIterable, Identifiable {
        case contains, equals
        var id: String { rawValue }
        var label: String { self == .contains ? "contains" : "equals" }
    }

    private enum NumberOp: String, CaseIterable, Identifiable {
        case eq, gt, lt, between
        var id: String { rawValue }
        var label: String {
            switch self {
            case .eq: return "equals"
            case .gt: return "greater than"
            case .lt: return "less than"
            case .between: return "between"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by \(field.label)")
                .font(.headline)

            editor

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Apply", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var editor: some View {
        switch field.type {
        case .text, .email, .phone:
            Picker("", selection: $textOp) {
                ForEach(TextOp.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            TextField(field.label, text: $textValue)
                .textFieldStyle(.roundedBorder)

        case .select, .status:
            Picker("", selection: $selectValue) {
                Text("—").tag("")
                ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()

        case .boolean:
            Picker("", selection: $boolValue) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

        case .link:
            LinkPickerField(
                targetDocType: (field.linkedDocType?.isEmpty == false) ? field.linkedDocType! : "Link",
                value: $linkValue,
                isReadOnly: false,
                targetMeta: linkTargetMeta,
                searchProvider: linkSearchProvider.map { base in
                    { _, query in base(field.linkedDocType ?? "", query) }
                },
                resolveDocument: linkResolveProvider.map { base in
                    { id in base(field.linkedDocType ?? "", id) }
                }
            )

        case .number, .decimal, .currency:
            Picker("", selection: $numberOp) {
                ForEach(NumberOp.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            HStack {
                TextField("Value", text: $numberValue)
                    .textFieldStyle(.roundedBorder)
                if numberOp == .between {
                    Text("and").foregroundStyle(.secondary)
                    TextField("Value", text: $numberValue2)
                        .textFieldStyle(.roundedBorder)
                }
            }

        case .date, .datetime:
            Picker("", selection: $useCustomRange) {
                Text("Preset").tag(false)
                Text("Custom").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            if useCustomRange {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            } else {
                Picker("", selection: $datePreset) {
                    ForEach(DateRangePreset.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }

        default:
            TextField(field.label, text: $textValue)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var canApply: Bool {
        switch field.type {
        case .text, .email, .phone: return !textValue.trimmingCharacters(in: .whitespaces).isEmpty
        case .select, .status: return !selectValue.isEmpty
        case .link: return !linkValue.isEmpty
        case .number, .decimal, .currency:
            if numberOp == .between { return Double(numberValue) != nil && Double(numberValue2) != nil }
            return Double(numberValue) != nil
        default: return true
        }
    }

    private func apply() {
        guard let (predicate, display) = buildPredicate() else { return }
        onApply(predicate, display)
    }

    private func buildPredicate() -> (ListFilter, String)? {
        let label = field.label
        switch field.type {
        case .text, .email, .phone:
            let v = textValue.trimmingCharacters(in: .whitespaces)
            switch textOp {
            case .contains:
                return (ListFilter(field.key, .like("%\(v)%")), "\(label) contains “\(v)”")
            case .equals:
                return (ListFilter(field.key, .eq(.string(v))), "\(label) = \(v)")
            }

        case .select, .status:
            return (ListFilter(field.key, .eq(.string(selectValue))), "\(label): \(selectValue)")

        case .boolean:
            return (ListFilter(field.key, .eq(.bool(boolValue))), "\(label): \(boolValue ? "Yes" : "No")")

        case .link:
            let display = linkResolveProvider?(field.linkedDocType ?? "", linkValue)
                .map { LinkLabel.title(for: $0, meta: linkTargetMeta) } ?? linkValue
            return (ListFilter(field.key, .eq(.string(linkValue))), "\(label): \(display)")

        case .number, .decimal, .currency:
            guard let a = Double(numberValue) else { return nil }
            switch numberOp {
            case .eq: return (ListFilter(field.key, .eq(.double(a))), "\(label) = \(numberValue)")
            case .gt: return (ListFilter(field.key, .gt(.double(a))), "\(label) > \(numberValue)")
            case .lt: return (ListFilter(field.key, .lt(.double(a))), "\(label) < \(numberValue)")
            case .between:
                guard let b = Double(numberValue2) else { return nil }
                return (ListFilter(field.key, .between(.double(a), .double(b))), "\(label): \(numberValue)–\(numberValue2)")
            }

        case .date, .datetime:
            if useCustomRange {
                let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1),
                                                to: Calendar.current.startOfDay(for: customEnd)) ?? customEnd
                let start = Calendar.current.startOfDay(for: customStart)
                let f = DateFormatter(); f.dateStyle = .short
                return (ListFilter(field.key, .between(.date(start), .date(end))),
                        "\(label): \(f.string(from: start))–\(f.string(from: customEnd))")
            } else {
                return (datePreset.predicate(fieldKey: field.key), "\(label): \(datePreset.label)")
            }

        default:
            let v = textValue.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return nil }
            return (ListFilter(field.key, .like("%\(v)%")), "\(label) contains “\(v)”")
        }
    }
}
