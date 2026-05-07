//
//  PDFPrintRenderer.swift
//  mercantis core
//
//  Phase C / P3.2 (ADR-044) — PDF renderer backed by Core Graphics.
//  CoreGraphics is available on iOS, macOS, tvOS, and visionOS, so this
//  renderer ships in `MercantisCore` without a UIKit / AppKit dependency.
//  Linux builds compile a stub that throws `backendUnavailable`.
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif

public struct PDFPrintRenderer: PrintRenderer {

    public var outputKind: PrintOutputKind { .pdf }

    /// US Letter at 72 dpi. Adjustable per call by constructing a renderer
    /// with a different page rect.
    public let pageRect: CGRect
    public let margin: CGFloat

    public init(
        pageRect: CGRect = CGRect(x: 0, y: 0, width: 612, height: 792),
        margin: CGFloat = 36
    ) {
        self.pageRect = pageRect
        self.margin = margin
    }

    public func render(_ context: PrintRenderContext) throws -> PrintRenderResult {
        #if canImport(CoreGraphics)
        return try renderWithCoreGraphics(context)
        #else
        throw PrintRenderError.backendUnavailable(
            reason: "PDFPrintRenderer requires CoreGraphics, which is not available on this platform."
        )
        #endif
    }

    #if canImport(CoreGraphics)
    private func renderWithCoreGraphics(_ context: PrintRenderContext) throws -> PrintRenderResult {
        let document = context.document
        let lines = textLines(for: context)

        let cfData = CFDataCreateMutable(nil, 0)!
        let consumer = CGDataConsumer(data: cfData)!
        var mediaBox = pageRect
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PrintRenderError.backendUnavailable(reason: "CGPDFContext creation failed")
        }

        let lineHeight: CGFloat = 14
        let usableTop = pageRect.height - margin
        let usableBottom = margin
        var cursorY = usableTop

        pdfContext.beginPDFPage(nil)

        for line in lines {
            if cursorY - lineHeight < usableBottom {
                pdfContext.endPDFPage()
                pdfContext.beginPDFPage(nil)
                cursorY = usableTop
            }
            drawLine(line.text, atY: cursorY, isBold: line.isBold, in: pdfContext)
            cursorY -= lineHeight
        }

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        let data = Data(referencing: cfData as CFData as NSData)
        let safeId = document.id.replacingOccurrences(of: "/", with: "-")
        return PrintRenderResult(
            data: data,
            mimeType: "application/pdf",
            suggestedFileName: "\(context.format.id)-\(safeId).pdf"
        )
    }

    /// Convert the `PrintFormat` into a flat list of `(text, bold)` lines.
    /// We delegate the heavy lifting to `PlainTextPrintRenderer` for body
    /// generation and overlay bold formatting on heading + table-header
    /// lines so the PDF output preserves visual hierarchy.
    private func textLines(for context: PrintRenderContext) -> [(text: String, isBold: Bool)] {
        var output: [(String, Bool)] = []
        let document = context.document

        if let letterHead = context.letterHead {
            output.append((PrintTemplate.substitute(letterHead.header, in: document), true))
            output.append(("", false))
        }

        for section in context.format.sections {
            switch section {
            case .heading(let text):
                if !output.isEmpty { output.append(("", false)) }
                output.append((PrintTemplate.substitute(text, in: document), true))

            case .paragraph(let text):
                if !output.isEmpty { output.append(("", false)) }
                output.append((PrintTemplate.substitute(text, in: document), false))

            case .fields(let keys, let labels):
                if !output.isEmpty { output.append(("", false)) }
                let labelWidth = keys
                    .map { (labels[$0] ?? PrintTemplate.defaultLabel(forKey: $0)).count }
                    .max() ?? 0
                for key in keys {
                    let label = labels[key] ?? PrintTemplate.defaultLabel(forKey: key)
                    let value = PrintTemplate.lookup(key: key, in: document).map(PrintTemplate.format) ?? ""
                    let padded = label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
                    output.append(("\(padded)  \(value)", false))
                }

            case .table(let tableKey, let columns, let labels):
                if !output.isEmpty { output.append(("", false)) }
                let textRenderer = PlainTextPrintRenderer()
                let block: String = (try? {
                    let mini = PrintFormat(
                        id: "_table", name: "_", docType: document.docType,
                        sections: [.table(tableKey: tableKey, columns: columns, labels: labels)]
                    )
                    let result = try textRenderer.render(PrintRenderContext(
                        format: mini, document: document, letterHead: nil, now: context.now
                    ))
                    return String(data: result.data, encoding: .utf8) ?? ""
                }()) ?? ""
                let rows = block.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, line) in rows.enumerated() {
                    output.append((String(line), i == 0))
                }

            case .keyValue(let label, let value):
                if !output.isEmpty { output.append(("", false)) }
                output.append((
                    "\(PrintTemplate.substitute(label, in: document)): \(PrintTemplate.substitute(value, in: document))",
                    false
                ))
            }
        }

        if let footer = context.letterHead?.footer {
            output.append(("", false))
            output.append((PrintTemplate.substitute(footer, in: document), false))
        }
        return output
    }

    private func drawLine(
        _ text: String,
        atY y: CGFloat,
        isBold: Bool,
        in ctx: CGContext
    ) {
        // Use CoreText's own attribute keys so the renderer compiles
        // without an AppKit / UIKit dependency. The runtime semantics
        // are identical to NSAttributedString.Key.font / .foregroundColor;
        // only the key constants differ.
        let fontName = isBold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, 11, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ]
        let attributed = CFAttributedStringCreate(
            nil,
            text as CFString,
            attributes as CFDictionary
        )
        guard let attributed else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: margin, y: y - 11)
        CTLineDraw(line, ctx)
    }
    #endif
}
