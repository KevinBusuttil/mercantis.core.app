//
//  PrintService.swift
//  mercantis core
//
//  Phase C / P3.2 (ADR-044) — Public entry point. Looks up a registered
//  `PrintFormat`, picks the renderer for the requested `PrintOutputKind`,
//  and produces bytes.
//

import Foundation

/// High-level print API for Hub and other host apps.
///
/// `PrintService` is intentionally a thin coordinator: it keeps a registry
/// of formats and letter heads (typically populated from
/// `AppManifest.printFormats` at install time), and dispatches to a
/// pluggable renderer keyed by `PrintOutputKind`.
public final class PrintService: @unchecked Sendable {

    private let lock = NSLock()
    private var formats: [String: PrintFormat] = [:]
    private var letterHeads: [String: LetterHead] = [:]
    private var renderers: [PrintOutputKind: PrintRenderer]

    public init(renderers: [PrintRenderer] = PrintService.defaultRenderers()) {
        var byKind: [PrintOutputKind: PrintRenderer] = [:]
        for renderer in renderers {
            byKind[renderer.outputKind] = renderer
        }
        self.renderers = byKind
    }

    /// Default renderer set: plain text + Core Graphics PDF.
    public static func defaultRenderers() -> [PrintRenderer] {
        [PlainTextPrintRenderer(), PDFPrintRenderer()]
    }

    // MARK: - Registration

    public func register(format: PrintFormat) {
        lock.lock(); defer { lock.unlock() }
        formats[format.id] = format
    }

    public func register(letterHead: LetterHead) {
        lock.lock(); defer { lock.unlock() }
        letterHeads[letterHead.id] = letterHead
    }

    public func unregister(formatId: String) {
        lock.lock(); defer { lock.unlock() }
        formats.removeValue(forKey: formatId)
    }

    public func unregister(letterHeadId: String) {
        lock.lock(); defer { lock.unlock() }
        letterHeads.removeValue(forKey: letterHeadId)
    }

    public func registeredFormatIds() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(formats.keys)
    }

    public func formats(forDocType docType: String) -> [PrintFormat] {
        lock.lock(); defer { lock.unlock() }
        return formats.values.filter { $0.docType == docType }
    }

    // MARK: - Render

    /// Render `document` with the format identified by `formatId` to bytes
    /// of `kind`. Throws if either no such format is registered or no
    /// renderer for the requested output kind is configured.
    public func render(
        formatId: String,
        document: Document,
        as kind: PrintOutputKind,
        now: Date = Date()
    ) throws -> PrintRenderResult {
        lock.lock()
        let format = formats[formatId]
        let letterHead: LetterHead? = format?.letterHeadId.flatMap { letterHeads[$0] }
        let renderer = renderers[kind]
        lock.unlock()

        guard let format else {
            throw PrintServiceError.unknownFormat(formatId)
        }
        guard let renderer else {
            throw PrintServiceError.noRendererForKind(kind)
        }
        guard format.docType == document.docType else {
            throw PrintServiceError.docTypeMismatch(
                formatId: formatId,
                expected: format.docType,
                actual: document.docType
            )
        }

        let context = PrintRenderContext(
            format: format,
            document: document,
            letterHead: letterHead,
            now: now
        )
        return try renderer.render(context)
    }

    public enum PrintServiceError: Error, Sendable, Equatable {
        case unknownFormat(String)
        case noRendererForKind(PrintOutputKind)
        case docTypeMismatch(formatId: String, expected: String, actual: String)
    }
}
