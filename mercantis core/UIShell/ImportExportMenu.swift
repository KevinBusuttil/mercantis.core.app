//
//  ImportExportMenu.swift
//  mercantis core
//
//  UI for the bulk import / export engine (ADR-046). A SwiftUI `Menu`
//  offering Export CSV, Export JSON, and Import-from-file for one DocType's
//  list. On macOS, Export uses `NSSavePanel` and Import uses `NSOpenPanel`.
//
//  Mirrors the Flutter `import_export_menu.dart`. Drop into a list
//  workspace's overflow / toolbar. `onChanged` fires after a successful
//  import so the host can refresh the list it renders.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Import / Export menu for a single DocType, backed by `DataExporter` and
/// `DataImporter`.
public struct ImportExportMenu: View {

    private let docType: String
    private let exporter: DataExporter
    private let importer: DataImporter
    /// Called after a successful import so the host can reload its list.
    private let onChanged: (() -> Void)?

    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var showResult = false

    public init(
        docType: String,
        exporter: DataExporter,
        importer: DataImporter,
        onChanged: (() -> Void)? = nil
    ) {
        self.docType = docType
        self.exporter = exporter
        self.importer = importer
        self.onChanged = onChanged
    }

    public var body: some View {
        Menu {
            Button {
                export(format: .csv)
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            Button {
                export(format: .json)
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            Divider()
            Button {
                runImport()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("Import / Export", systemImage: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Import or export records")
        .alert(resultIsError ? "Operation failed" : "Done", isPresented: $showResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: - Export

    private func export(format: ImportExportFormat) {
        #if os(macOS)
        do {
            let data = try exporter.export(docType: docType, format: format)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(docType).\(format.rawValue)"
            if let type = Self.contentType(for: format) {
                panel.allowedContentTypes = [type]
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            present("Exported \(docType) to \(url.lastPathComponent).", isError: false)
        } catch {
            present("Export failed: \((error as NSError).localizedDescription)", isError: true)
        }
        #else
        present("Export is not available on this platform yet.", isError: true)
        #endif
    }

    // MARK: - Import

    private func runImport() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText, .json].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let format: ImportExportFormat =
                url.pathExtension.lowercased() == "json" ? .json : .csv
            let report = try importer.import(docType: docType, data: data, format: format)
            onChanged?()
            present(Self.summary(report), isError: report.failedCount > 0)
        } catch {
            present("Import failed: \((error as NSError).localizedDescription)", isError: true)
        }
        #else
        present("Import is not available on this platform yet.", isError: true)
        #endif
    }

    // MARK: - Helpers

    private func present(_ message: String, isError: Bool) {
        resultMessage = message
        resultIsError = isError
        showResult = true
    }

    private static func summary(_ report: ImportReport) -> String {
        """
        \(report.rowsRead) rows read
        Inserted: \(report.insertedCount)
        Updated: \(report.updatedCount)
        Skipped: \(report.skippedCount)
        Failed: \(report.failedCount)
        """
    }

    #if os(macOS)
    private static func contentType(for format: ImportExportFormat) -> UTType? {
        switch format {
        case .csv:  return .commaSeparatedText
        case .json: return .json
        }
    }
    #endif
}
