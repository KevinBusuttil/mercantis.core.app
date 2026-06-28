import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Developer ▸ Data Browser: a read-only SQL console with a flexible result
/// table (sort, per-column filter, global search, CSV / clipboard export) and
/// saved queries. Query execution is injected as a closure so this view stays
/// independent of the engine; the host wires it to a guarded, read-only runner.
public struct DataBrowserView: View {

    private let runQuery: (String) throws -> ReadOnlyQueryResult

    @State private var sql: String
    @State private var result: ReadOnlyQueryResult?
    @State private var errorMessage: String?
    @State private var elapsed: String?

    @State private var sortColumn: Int?
    @State private var sortAscending = true
    @State private var columnFilters: [Int: String] = [:]
    @State private var globalSearch = ""

    @State private var savedQueries: [SavedQuery] = []
    @State private var tables: [String] = []
    @State private var showSaveSheet = false
    @State private var saveName = ""

    /// Cap the number of rows actually rendered (the result itself can hold
    /// more); keeps the table responsive. Narrow with filters to see the rest.
    private let renderCap = 1_000

    public init(runQuery: @escaping (String) throws -> ReadOnlyQueryResult) {
        self.runQuery = runQuery
        _sql = State(initialValue: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                editorPane
                Divider()
                resultsPane
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .navigationTitle("Data Browser")
        .onAppear {
            loadSaved()
            loadTables()
        }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("Saved queries") {
                if savedQueries.isEmpty {
                    Text("Save a query to reuse it later.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(savedQueries) { item in
                    HStack {
                        Button(item.name) { sql = item.sql }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            savedQueries.removeAll { $0.id == item.id }
                            persistSaved()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Delete saved query")
                    }
                }
            }
            Section("Tables") {
                if tables.isEmpty {
                    Text("No tables found.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(tables, id: \.self) { table in
                    Button {
                        sql = "SELECT * FROM \(table) LIMIT 100;"
                        run()
                    } label: {
                        Label(table, systemImage: "tablecells").font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 200)
    }

    // MARK: - Editor

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("READ-ONLY SQL")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(MercantisTheme.textMuted)
                Spacer()
                Button { saveName = ""; showSaveSheet = true } label: {
                    Label("Save…", systemImage: "bookmark")
                }
                .controlSize(.small)
                .disabled(sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { run() } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            TextEditor(text: $sql)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 90, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MercantisTheme.border, lineWidth: 1))

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(MercantisTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsPane: some View {
        if let result {
            let rows = processedRows(result)
            VStack(spacing: 0) {
                resultsToolbar(result: result, shown: rows.count)
                Divider()
                if result.columns.isEmpty {
                    emptyResult("Query ran, but returned no columns.")
                } else {
                    resultsTable(columns: result.columns, rows: Array(rows.prefix(renderCap)))
                }
            }
        } else {
            emptyResult("Run a query to see results here.")
        }
    }

    private func resultsToolbar(result: ReadOnlyQueryResult, shown: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search results", text: $globalSearch).textFieldStyle(.plain).frame(maxWidth: 220)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(MercantisTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))

            Text(resultSummary(result: result, shown: shown))
                .font(.caption).foregroundStyle(.secondary)

            Spacer()

            Button { copyCSV(result: result) } label: { Label("Copy", systemImage: "doc.on.doc") }
                .controlSize(.small)
            #if os(macOS)
            Button { exportCSV(result: result) } label: { Label("Export CSV", systemImage: "square.and.arrow.down") }
                .controlSize(.small)
            #endif
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func resultsTable(columns: [String], rows: [[String]]) -> some View {
        let width: CGFloat = 180
        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        Button { toggleSort(i) } label: {
                            HStack(spacing: 4) {
                                Text(columns[i]).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                if sortColumn == i {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: width, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(MercantisTheme.surfaceMuted)

                // Per-column filters
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        TextField("Filter", text: filterBinding(i))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: width, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Rectangle().stroke(MercantisTheme.border.opacity(0.4), lineWidth: 0.5))
                    }
                }

                Divider()

                // Rows
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(columns.indices, id: \.self) { c in
                                Text(c < rows[r].count ? rows[r][c] : "")
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(width: width, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                            }
                        }
                        .background(r.isMultiple(of: 2) ? Color.clear : MercantisTheme.surfaceMuted.opacity(0.4))
                    }
                }
            }
        }
    }

    private func emptyResult(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Save sheet

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save query").font(.headline)
            TextField("Name", text: $saveName).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }
                Button("Save") {
                    let name = saveName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    savedQueries.append(SavedQuery(name: name, sql: sql))
                    persistSaved()
                    showSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18).frame(width: 380)
    }

    // MARK: - Logic

    private func toggleSort(_ column: Int) {
        if sortColumn == column { sortAscending.toggle() }
        else { sortColumn = column; sortAscending = true }
    }

    private func filterBinding(_ column: Int) -> Binding<String> {
        Binding(
            get: { columnFilters[column] ?? "" },
            set: { columnFilters[column] = $0.isEmpty ? nil : $0 }
        )
    }

    private func run() {
        errorMessage = nil
        do {
            result = try runQuery(sql)
            // Reset view state for the new result shape.
            sortColumn = nil
            columnFilters = [:]
            globalSearch = ""
        } catch {
            errorMessage = (error as NSError).localizedDescription
            result = nil
        }
    }

    private func loadTables() {
        if let r = try? runQuery("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") {
            tables = r.rows.compactMap(\.first)
        }
    }

    private func processedRows(_ result: ReadOnlyQueryResult) -> [[String]] {
        var rows = result.rows

        let global = globalSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !global.isEmpty {
            rows = rows.filter { row in row.contains { $0.lowercased().contains(global) } }
        }
        for (column, needle) in columnFilters {
            let lowered = needle.lowercased()
            guard !lowered.isEmpty else { continue }
            rows = rows.filter { $0.indices.contains(column) && $0[column].lowercased().contains(lowered) }
        }
        if let sortColumn {
            rows.sort { a, b in
                let av = a.indices.contains(sortColumn) ? a[sortColumn] : ""
                let bv = b.indices.contains(sortColumn) ? b[sortColumn] : ""
                let ascending: Bool
                if let ad = Double(av), let bd = Double(bv) {
                    ascending = ad < bd
                } else {
                    ascending = av.localizedStandardCompare(bv) == .orderedAscending
                }
                return sortAscending ? ascending : !ascending
            }
        }
        return rows
    }

    private func resultSummary(result: ReadOnlyQueryResult, shown: Int) -> String {
        var parts: [String] = []
        if shown == result.rows.count {
            parts.append("\(shown) row\(shown == 1 ? "" : "s")")
        } else {
            parts.append("\(shown) of \(result.rows.count) rows")
        }
        if shown > renderCap { parts.append("showing first \(renderCap)") }
        if result.truncated { parts.append("query capped") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saved queries persistence

    private static let savedKey = "databrowser.savedQueries"

    private func loadSaved() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let decoded = try? JSONDecoder().decode([SavedQuery].self, from: data) else { return }
        savedQueries = decoded
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedQueries) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        }
    }

    // MARK: - Export

    private func csvString(result: ReadOnlyQueryResult) -> String {
        func escape(_ s: String) -> String {
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        let rows = processedRows(result)
        var out = result.columns.map(escape).joined(separator: ",") + "\n"
        for row in rows { out += row.map(escape).joined(separator: ",") + "\n" }
        return out
    }

    private func copyCSV(result: ReadOnlyQueryResult) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvString(result: result), forType: .string)
        #endif
    }

    #if os(macOS)
    private func exportCSV(result: ReadOnlyQueryResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "query-result.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csvString(result: result).data(using: .utf8)?.write(to: url)
    }
    #endif

    struct SavedQuery: Identifiable, Codable, Hashable {
        var id = UUID()
        var name: String
        var sql: String
    }
}
