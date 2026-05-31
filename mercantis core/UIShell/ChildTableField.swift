//
//  ChildTableField.swift
//  mercantis core
//
//  W5: inline editable child-table grid for GenericFormView table fields.
//  UX-3: full-sheet-width grid with per-column min widths, zebra striping,
//  and an NSPopover-style per-row detail editor (Option A).
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
    /// Link providers for `.link` fields inside child rows. Mirror the ones
    /// `GenericFormView` passes to top-level `LinkPickerField`s so a child-row
    /// link cell renders the same searchable picker rather than a plain text
    /// field. All optional: when `nil`, link cells degrade to plain text entry
    /// exactly as before (backwards-compatible for unwired callers).
    let linkSearchProvider: ((String, String) -> [Document])?
    let linkResolveProvider: ((String, String) -> Document?)?
    /// Resolves target-DocType metadata so the picker can read the target's
    /// `titleField` for display labels.
    let childDocTypeProvider: ((String) -> DocType?)?

    @State private var popoverRowID: String?

    public init(
        field: FieldDefinition,
        childDocType: DocType?,
        rows: Binding<[ChildRow]>,
        isReadOnly: Bool,
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        linkResolveProvider: ((String, String) -> Document?)? = nil,
        childDocTypeProvider: ((String) -> DocType?)? = nil
    ) {
        self.field = field
        self.childDocType = childDocType
        self._rows = rows
        self.isReadOnly = isReadOnly
        self.linkSearchProvider = linkSearchProvider
        self.linkResolveProvider = linkResolveProvider
        self.childDocTypeProvider = childDocTypeProvider
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
        // Horizontal scroll guarantees usability when the consumer happens to
        // declare a very wide table (>8 columns) — header and rows scroll in
        // lockstep via the shared `gridWidth`. At typical column counts the
        // content fits the sheet width and never engages the scroller.
        let gridWidth = totalMinWidth(docType: docType)

        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow(docType: docType)
                        .frame(width: gridWidth, alignment: .leading)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        dataRow(docType: docType, rowIdx: idx, rowID: row.id)
                            .frame(width: gridWidth, alignment: .leading)
                        if idx < rows.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                    if rows.isEmpty {
                        emptyState
                            .frame(width: gridWidth, alignment: .center)
                    }
                }
            }

            Divider()

            footerBar
        }
    }

    // Shared between header and data rows so column edges line up exactly —
    // any drift here multiplies across N columns and pushes the header out
    // of register with its data cells.
    private static let cellHPadding: CGFloat = 8

    // MARK: - Header

    private func headerRow(docType: DocType) -> some View {
        HStack(spacing: 0) {
            indexCell { Text("#").font(.system(size: 11, weight: .semibold)).foregroundStyle(MercantisTheme.textMuted) }
            ForEach(docType.fields) { f in
                Text(f.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: minWidth(for: f), maxWidth: .infinity, alignment: alignment(for: f))
                    .padding(.horizontal, Self.cellHPadding)
            }
            trailingCell { Color.clear }
        }
        .padding(.vertical, 8)
        .background(MercantisTheme.surfaceMuted)
    }

    // MARK: - Data row

    @ViewBuilder
    private func dataRow(docType: DocType, rowIdx: Int, rowID: String) -> some View {
        HStack(spacing: 0) {
            indexCell {
                Text("\(rowIdx + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(MercantisTheme.textMuted)
                    .monospacedDigit()
            }
            ForEach(docType.fields) { f in
                childFieldCell(field: f, rowIdx: rowIdx)
                    // No `alignment:` here — the control inside already
                    // fills the cell via `.frame(maxWidth: .infinity)`, so
                    // any text alignment happens via
                    // `.multilineTextAlignment(...)` inside the control.
                    .frame(minWidth: minWidth(for: f), maxWidth: .infinity)
                    .padding(.horizontal, Self.cellHPadding)
            }
            trailingCell {
                if !isReadOnly {
                    rowActionsButton(docType: docType, rowIdx: rowIdx, rowID: rowID)
                }
            }
        }
        .padding(.vertical, 6)
        .background(rowIdx.isMultiple(of: 2) ? Color.clear : MercantisTheme.surfaceMuted.opacity(0.5))
    }

    // MARK: - Cell layouts

    @ViewBuilder
    private func indexCell<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: 36, alignment: .center)
    }

    @ViewBuilder
    private func trailingCell<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: 44, alignment: .center)
    }

    @ViewBuilder
    private func childFieldCell(field f: FieldDefinition, rowIdx: Int) -> some View {
        // `.frame(maxWidth: .infinity)` on each control forces the visible
        // chrome (rounded input background, date picker, toggle) to fill the
        // cell allocation, so column edges line up with the header `Text`
        // above. Without this, controls sit at their ideal content width and
        // shift left/right relative to the column.
        switch f.type {
        case .number, .decimal, .currency:
            TextField(f.label, text: numberCellBinding(field: f, idx: rowIdx))
                .mercantisInput()
                .multilineTextAlignment(.trailing)
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
        case .date, .datetime:
            DatePicker(
                "",
                selection: dateCellBinding(field: f, idx: rowIdx),
                displayedComponents: f.type == .datetime ? [.date, .hourAndMinute] : [.date]
            )
            .labelsHidden()
            .disabled(isReadOnly)
            .frame(maxWidth: .infinity, alignment: alignment(for: f))
        case .link where linkSearchProvider != nil || isReadOnly:
            // Render the same searchable picker used for top-level link
            // fields. We only take this branch when a search provider is
            // wired (so editing works) or when read-only (so we can still
            // show a resolved label); otherwise fall through to plain text
            // so unwired callers keep their previous behaviour.
            linkCell(field: f, rowIdx: rowIdx)
                .frame(maxWidth: .infinity)
        default:
            TextField(f.label, text: stringCellBinding(field: f, idx: rowIdx))
                .mercantisInput()
                .disabled(isReadOnly)
                .frame(maxWidth: .infinity)
        }
    }

    /// Builds a `LinkPickerField` bound to `rows[rowIdx].fields[field.key]`,
    /// resolving the target DocType from `field.linkedDocType` and reusing the
    /// injected providers (scoped to that target). Shared shape with
    /// `GenericFormView.linkField` so child-row links behave identically.
    @ViewBuilder
    private func linkCell(field f: FieldDefinition, rowIdx: Int) -> some View {
        let target = f.linkedDocType ?? ""
        LinkPickerField(
            targetDocType: target.isEmpty ? "Link" : target,
            value: stringCellBinding(field: f, idx: rowIdx),
            isReadOnly: isReadOnly,
            targetMeta: childDocTypeProvider?(target),
            searchProvider: linkSearchProvider.map { base in { _, query in base(target, query) } },
            resolveDocument: linkResolveProvider.map { base in { id in base(target, id) } }
        )
    }

    // MARK: - Row actions / popover

    private func rowActionsButton(docType: DocType, rowIdx: Int, rowID: String) -> some View {
        Button {
            popoverRowID = rowID
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(MercantisTheme.textMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Edit row…")
        .popover(
            isPresented: Binding(
                get: { popoverRowID == rowID },
                set: { if !$0 { popoverRowID = nil } }
            ),
            arrowEdge: .leading
        ) {
            ChildRowEditor(
                docType: docType,
                rowIndex: rowIdx,
                row: Binding(
                    get: {
                        guard rowIdx < rows.count else { return ChildRow(id: rowID, rowIndex: rowIdx, fields: [:]) }
                        return rows[rowIdx]
                    },
                    set: { newValue in
                        guard rowIdx < rows.count else { return }
                        rows[rowIdx] = newValue
                    }
                ),
                isReadOnly: isReadOnly,
                linkSearchProvider: linkSearchProvider,
                linkResolveProvider: linkResolveProvider,
                childDocTypeProvider: childDocTypeProvider,
                onRemove: {
                    popoverRowID = nil
                    guard rowIdx < rows.count else { return }
                    rows.remove(at: rowIdx)
                },
                onDone: { popoverRowID = nil }
            )
        }
    }

    // MARK: - Footer / empty / fallback

    private var emptyState: some View {
        Text("No rows yet.")
            .font(.system(size: 12))
            .foregroundStyle(MercantisTheme.textMuted)
            .padding(.vertical, 18)
    }

    private var footerBar: some View {
        HStack {
            if !isReadOnly, let docType = childDocType {
                Button {
                    let newRow = blankRow(for: docType, index: rows.count)
                    rows.append(newRow)
                } label: {
                    Label("Add Row", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(MercantisTheme.accent)
            }
            Spacer()
            Text("\(rows.count) row\(rows.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(MercantisTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MercantisTheme.surfaceMuted.opacity(0.6))
    }

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

    // MARK: - Column sizing

    private func minWidth(for field: FieldDefinition) -> CGFloat {
        switch field.type {
        case .number, .decimal, .currency: return 90
        case .boolean: return 60
        case .date, .datetime: return 130
        case .select, .status: return 120
        case .link: return 150
        case .longText, .richText: return 200
        default:
            // Heuristic: keys like *_name / description deserve more room.
            let key = field.key.lowercased()
            if key.contains("name") || key.contains("description") || key.contains("notes") {
                return 200
            }
            return 130
        }
    }

    private func alignment(for field: FieldDefinition) -> Alignment {
        switch field.type {
        case .number, .decimal, .currency: return .trailing
        case .boolean: return .center
        default: return .leading
        }
    }

    private func totalMinWidth(docType: DocType) -> CGFloat {
        let columns = docType.fields.reduce(into: CGFloat(0)) { acc, f in
            acc += minWidth(for: f) + 16  // + horizontal padding
        }
        return 36 + columns + 44  // index + columns + trailing actions
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

    private func dateCellBinding(field f: FieldDefinition, idx: Int) -> Binding<Date> {
        Binding<Date>(
            get: {
                guard idx < rows.count else { return Date() }
                switch rows[idx].fields[f.key] {
                case .date(let d), .dateTime(let d): return d
                default: return Date()
                }
            },
            set: { newValue in
                guard idx < rows.count else { return }
                rows[idx].fields[f.key] = (f.type == .datetime) ? .dateTime(newValue) : .date(newValue)
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

// MARK: - Per-row detail editor (Option A popover)

/// Vertical form rendered inside an NSPopover anchored to a table row. Mirrors
/// the inline cells but stacks them label-above-control so every field — not
/// just the ones that happen to fit in the visible columns — is reachable.
private struct ChildRowEditor: View {
    let docType: DocType
    let rowIndex: Int
    @Binding var row: ChildRow
    let isReadOnly: Bool
    let linkSearchProvider: ((String, String) -> [Document])?
    let linkResolveProvider: ((String, String) -> Document?)?
    let childDocTypeProvider: ((String) -> DocType?)?
    let onRemove: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(docType.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(MercantisTheme.textMuted)
                            control(for: field)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit \(docType.name) · #\(rowIndex + 1)")
                    .font(.system(size: 13, weight: .semibold))
                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(MercantisTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MercantisTheme.surface)
    }

    private var footer: some View {
        HStack {
            if !isReadOnly {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove row")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(MercantisTheme.danger)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MercantisTheme.surface)
    }

    private var summaryLine: String {
        if !docType.titleField.isEmpty, let v = row.fields[docType.titleField] {
            return stringify(v)
        }
        if let first = docType.fields.first, let v = row.fields[first.key] {
            return stringify(v)
        }
        return ""
    }

    private func stringify(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "Yes" : "No"
        case .date(let d): return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        case .dateTime(let d): return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short)
        default: return ""
        }
    }

    @ViewBuilder
    private func control(for field: FieldDefinition) -> some View {
        switch field.type {
        case .number, .decimal, .currency:
            TextField(field.label, text: numberBinding(for: field))
                .mercantisInput()
                .multilineTextAlignment(.trailing)
                .disabled(isReadOnly)
        case .boolean:
            Toggle("", isOn: boolBinding(for: field))
                .labelsHidden()
                .disabled(isReadOnly)
        case .date, .datetime:
            DatePicker(
                "",
                selection: dateBinding(for: field),
                displayedComponents: field.type == .datetime ? [.date, .hourAndMinute] : [.date]
            )
            .labelsHidden()
            .disabled(isReadOnly)
        case .longText, .richText:
            TextEditor(text: stringBinding(for: field))
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MercantisTheme.border, lineWidth: 1)
                )
                .disabled(isReadOnly)
        case .link where linkSearchProvider != nil || isReadOnly:
            // Same searchable picker as the inline grid, bound to this row's
            // field. Falls through to plain text when no provider is wired.
            let target = field.linkedDocType ?? ""
            LinkPickerField(
                targetDocType: target.isEmpty ? "Link" : target,
                value: stringBinding(for: field),
                isReadOnly: isReadOnly,
                targetMeta: childDocTypeProvider?(target),
                searchProvider: linkSearchProvider.map { base in { _, query in base(target, query) } },
                resolveDocument: linkResolveProvider.map { base in { id in base(target, id) } }
            )
        default:
            TextField(field.label, text: stringBinding(for: field))
                .mercantisInput()
                .disabled(isReadOnly)
        }
    }

    // MARK: - Bindings (mirror ChildTableField, scoped to this row)

    private func stringBinding(for f: FieldDefinition) -> Binding<String> {
        Binding<String>(
            get: {
                switch row.fields[f.key] {
                case .string(let s): return s
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .bool(let b): return b ? "true" : "false"
                default: return ""
                }
            },
            set: { row.fields[f.key] = .string($0) }
        )
    }

    private func numberBinding(for f: FieldDefinition) -> Binding<String> {
        Binding<String>(
            get: {
                switch row.fields[f.key] {
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .string(let s): return s
                default: return ""
                }
            },
            set: { newValue in
                if f.type == .number, let i = Int(newValue) {
                    row.fields[f.key] = .int(i)
                } else if let d = Double(newValue) {
                    row.fields[f.key] = .double(d)
                } else {
                    row.fields[f.key] = .string(newValue)
                }
            }
        )
    }

    private func boolBinding(for f: FieldDefinition) -> Binding<Bool> {
        Binding<Bool>(
            get: { if case .bool(let b) = row.fields[f.key] { return b } else { return false } },
            set: { row.fields[f.key] = .bool($0) }
        )
    }

    private func dateBinding(for f: FieldDefinition) -> Binding<Date> {
        Binding<Date>(
            get: {
                switch row.fields[f.key] {
                case .date(let d), .dateTime(let d): return d
                default: return Date()
                }
            },
            set: { newValue in
                row.fields[f.key] = (f.type == .datetime) ? .dateTime(newValue) : .date(newValue)
            }
        )
    }
}
