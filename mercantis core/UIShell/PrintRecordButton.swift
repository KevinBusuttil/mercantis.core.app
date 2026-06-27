//
//  PrintRecordButton.swift
//  mercantis core
//
//  UI for the print engine (ADR-044). Renders a record to a real PDF via
//  `PrintService` and either prints it (`NSPrintOperation`) or shares it
//  (`NSSharingServicePicker`).
//
//  Mirrors the Flutter `print_record_button.dart`. The caller supplies a
//  `formatResolver` that returns the `PrintFormat` to use for a given
//  document (e.g. an auto-format built from the DocType's fields, or a
//  manifest-declared format). The button registers that format with the
//  service before rendering, matching the Flutter `registerFormat` step.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
import PDFKit
#endif

/// A menu button that renders the given record to PDF and prints or shares
/// it through the platform's native facilities.
public struct PrintRecordButton: View {

    /// The record to print. An empty `id` disables the control.
    private let document: Document
    private let printService: PrintService
    /// Resolves the candidate `PrintFormat`s for `document`, default first. The
    /// button registers each with the service before rendering. When more than
    /// one is returned the menu lets the operator pick; otherwise it prints the
    /// single (default) format directly.
    private let formatsResolver: (Document) -> [PrintFormat]
    /// Optional last-mile transform applied to the document just before
    /// rendering (only on print/share, not on every render) — e.g. resolving
    /// link-field ids to display names so the output shows "Kevin Busuttil"
    /// rather than a customer id. Identity when nil.
    private let documentTransform: ((Document) -> Document)?

    @State private var errorMessage: String?
    @State private var showError = false

    /// Single-format init (back-compat): renders `document` with exactly the
    /// resolved format.
    public init(
        document: Document,
        printService: PrintService,
        documentTransform: ((Document) -> Document)? = nil,
        formatResolver: @escaping (Document) -> PrintFormat
    ) {
        self.document = document
        self.printService = printService
        self.documentTransform = documentTransform
        self.formatsResolver = { [formatResolver($0)] }
    }

    /// Multi-format init: the operator chooses among several formats (default
    /// listed first). An empty result disables printing.
    public init(
        document: Document,
        printService: PrintService,
        documentTransform: ((Document) -> Document)? = nil,
        formatsResolver: @escaping (Document) -> [PrintFormat]
    ) {
        self.document = document
        self.printService = printService
        self.documentTransform = documentTransform
        self.formatsResolver = formatsResolver
    }

    public var body: some View {
        let formats = formatsResolver(document)
        return Menu {
            if formats.count <= 1 {
                Button { run(.print, formats.first) } label: {
                    Label("Print…", systemImage: "printer")
                }
                Button { run(.share, formats.first) } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
            } else {
                ForEach(formats) { format in
                    Section(format.isDefault ? "\(format.name) · Default" : format.name) {
                        Button { run(.print, format) } label: {
                            Label("Print…", systemImage: "printer")
                        }
                        Button { run(.share, format) } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        } label: {
            Label("Print", systemImage: "printer")
        }
        .disabled(document.id.isEmpty || formats.isEmpty)
        .accessibilityLabel("Print or share this record")
        .alert("Print failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private enum Action { case print, share }

    private func run(_ action: Action, _ format: PrintFormat?) {
        #if os(macOS)
        guard let format else {
            present("No print format is available for this record.")
            return
        }
        do {
            // Ensure the chosen format is known to the service before render.
            printService.register(format: format)
            let renderDocument = documentTransform?(document) ?? document
            let result = try printService.render(
                formatId: format.id,
                document: renderDocument,
                as: .pdf
            )
            switch action {
            case .print:
                try printPDF(result)
            case .share:
                try sharePDF(result)
            }
        } catch {
            present((error as NSError).localizedDescription)
        }
        #else
        present("Printing is not available on this platform yet.")
        #endif
    }

    #if os(macOS)
    /// Render the PDF into a `PDFView` and run a native `NSPrintOperation`
    /// over it so the user gets the standard print dialog.
    private func printPDF(_ result: PrintRenderResult) throws {
        guard let pdfDoc = PDFDocument(data: result.data) else {
            throw PrintUIError.invalidPDF
        }
        let pageSize = pdfDoc.page(at: 0)?.bounds(for: .mediaBox).size
            ?? NSSize(width: 612, height: 792)
        let pdfView = PDFView(frame: NSRect(origin: .zero, size: pageSize))
        pdfView.document = pdfDoc
        pdfView.autoScales = true

        let operation = NSPrintOperation(view: pdfView, printInfo: NSPrintInfo.shared)
        operation.showsPrintPanel = true
        operation.run()
    }

    /// Write the PDF to a temp file and offer the native share picker.
    private func sharePDF(_ result: PrintRenderResult) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(result.suggestedFileName)
        try result.data.write(to: url, options: .atomic)

        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(
                relativeTo: .zero,
                of: contentView,
                preferredEdge: .minY
            )
        } else {
            // Fall back to opening in the default viewer (Preview).
            NSWorkspace.shared.open(url)
        }
    }

    private enum PrintUIError: LocalizedError {
        case invalidPDF
        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "The renderer produced data that isn't a valid PDF."
            }
        }
    }
    #endif

    private func present(_ message: String) {
        errorMessage = message
        showError = true
    }
}
