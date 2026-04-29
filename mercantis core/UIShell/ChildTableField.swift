//
//  ChildTableField.swift
//  mercantis core
//
//  W5: inline editable child-table grid for GenericFormView table fields.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// Inline editable grid for a `.table` field.
///
/// When `childDocType` is nil (provider not wired) the view degrades to the
/// static row-count label so existing callers see no crash. (W5 / ADR-031)
public struct ChildTableField: View {

    let field: FieldDefinition
    let childDocType: DocType?
    @Binding var rows: [ChildRow]
    let isReadOnly: Bool

    public init(
        field: FieldDefinition,
        childDocType: DocType?,
        rows: Binding<[ChildRow]>,
        isReadOnly: Bool
    ) {
        self.field = field
        self.childDocType = childDocType
        self._rows = rows
        self.isReadOnly = isReadOnly
    }

    public var body: some View {
        if let docType = childDocType {
            wiredGrid(docType: docType)
        } else {
            fallbackLabel
        }
    }

    // MARK: - Wired grid (child DocType resolved)

    @ViewBuilder
    private func wiredGrid(docType: DocType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column headers
            if !docType.fields.isEmpty {
                headerRow(docType: docType)
            }

            // Data rows
            ForEach(rows.indices, id: \.self) { idx in
                dataRow(docType: docType, idx: idx)
            }

            // Add-row button
            if !isReadOnly {
                Button {
                    let newRow = blankRow(for: docType, index: rows.count)
                    rows.append(newRow)
                } label: {
                    Label("Add Row", systemImage: "plus.circle")
                        .font(.caption)
                }
                .padding(.top, 4)
            }
        }
    }

    private func headerRow(docType: DocType) -> some View {
        HStack(spacing: 8) {
            ForEach(docType.fields) { f in
                Text(f.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Spacer for the delete button column
            if !isReadOnly {
                Spacer().frame(width: 28)
            }
        }
    }

    private func dataRow(docType: DocType, idx: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(docType.fields) { f in
                childFieldCell(field: f, rowIdx: idx)
            }
            if !isReadOnly {
                Button(role: .destructive) {
                    rows.remove(at: idx)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .frame(width: 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(MercantisTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func childFieldCell(field f: FieldDefinition, rowIdx: Int) -> some View {
        switch f.type {
        case .number, .decimal, .currency:
            TextField(f.label, text: numberCellBinding(field: f, idx: rowIdx))
                .mercantisInput()
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .disabled(isReadOnly)
                .frame(maxWidth: .infinity)
        case .boolean:
            Toggle("", isOn: boolCellBinding(field: f, idx: rowIdx))
                .labelsHidden()
                .disabled(isReadOnly)
                .frame(maxWidth: .infinity)
        default:
            TextField(f.label, text: stringCellBinding(field: f, idx: rowIdx))
                .mercantisInput()
                .disabled(isReadOnly)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Fallback (no provider wired)

    private var fallbackLabel: some View {
        HStack {
            Text("\(rows.count) row\(rows.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Table")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cell bindings

    private func stringCellBinding(field f: FieldDefinition, idx: Int) -> Binding<String> {
        Binding<String>(
            get: {
                guard idx < rows.count else { return "" }
                switch rows[idx].fields[f.key] {
                case .string(let s): return s
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .bool(let b): return b ? "true" : "false"
                default: return ""
                }
            },
            set: { newValue in
                guard idx < rows.count else { return }
                rows[idx].fields[f.key] = .string(newValue)
            }
        )
    }

    private func numberCellBinding(field f: FieldDefinition, idx: Int) -> Binding<String> {
        Binding<String>(
            get: {
                guard idx < rows.count else { return "" }
                switch rows[idx].fields[f.key] {
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .string(let s): return s
                default: return ""
                }
            },
            set: { newValue in
                guard idx < rows.count else { return }
                if f.type == .number, let i = Int(newValue) {
                    rows[idx].fields[f.key] = .int(i)
                } else if let d = Double(newValue) {
                    rows[idx].fields[f.key] = .double(d)
                } else {
                    rows[idx].fields[f.key] = .string(newValue)
                }
            }
        )
    }

    private func boolCellBinding(field f: FieldDefinition, idx: Int) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                guard idx < rows.count else { return false }
                if case .bool(let b) = rows[idx].fields[f.key] { return b }
                return false
            },
            set: { newValue in
                guard idx < rows.count else { return }
                rows[idx].fields[f.key] = .bool(newValue)
            }
        )
    }

    // MARK: - Blank row factory

    private func blankRow(for docType: DocType, index: Int) -> ChildRow {
        ChildRow(
            id: UUID().uuidString,
            rowIndex: index,
            fields: Dictionary(uniqueKeysWithValues: docType.fields.compactMap { f in
                f.defaultValue.map { (f.key, $0) }
            })
        )
    }
}
