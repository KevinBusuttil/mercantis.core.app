//
//  PlainTextPrintRenderer.swift
//  mercantis core
//
//  Phase C / P3.2 (ADR-044) — Plain-text renderer. Always available,
//  cross-platform, deterministic. Useful for scripting, CLI export,
//  and as the test oracle for higher-fidelity renderers.
//

import Foundation

public struct PlainTextPrintRenderer: PrintRenderer {

    public var outputKind: PrintOutputKind { .plainText }

    public init() {}

    public func render(_ context: PrintRenderContext) throws -> PrintRenderResult {
        var lines: [String] = []
        let document = context.document

        if let letterHead = context.letterHead {
            lines.append(PrintTemplate.substitute(letterHead.header, in: document))
            lines.append(String(repeating: "-", count: 60))
        }

        for section in context.format.sections {
            let block = try renderSection(section, document: document)
            if !block.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append(block)
            }
        }

        if let footer = context.letterHead?.footer {
            lines.append("")
            lines.append(String(repeating: "-", count: 60))
            lines.append(PrintTemplate.substitute(footer, in: document))
        }

        let body = lines.joined(separator: "\n") + "\n"
        let data = Data(body.utf8)
        let safeId = document.id.replacingOccurrences(of: "/", with: "-")
        return PrintRenderResult(
            data: data,
            mimeType: "text/plain; charset=utf-8",
            suggestedFileName: "\(context.format.id)-\(safeId).txt"
        )
    }

    // MARK: - Section dispatch

    private func renderSection(_ section: PrintSection, document: Document) throws -> String {
        switch section {
        case .heading(let text):
            let resolved = PrintTemplate.substitute(text, in: document)
            return resolved + "\n" + String(repeating: "=", count: max(resolved.count, 4))

        case .paragraph(let text):
            return PrintTemplate.substitute(text, in: document)

        case .fields(let keys, let labels):
            let labelWidth = keys
                .map { (labels[$0] ?? PrintTemplate.defaultLabel(forKey: $0)).count }
                .max() ?? 0
            var lines: [String] = []
            for key in keys {
                let label = labels[key] ?? PrintTemplate.defaultLabel(forKey: key)
                let value = PrintTemplate.lookup(key: key, in: document).map(PrintTemplate.format) ?? ""
                let padded = label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
                lines.append("\(padded)  \(value)")
            }
            return lines.joined(separator: "\n")

        case .table(let tableKey, let columns, let labels):
            return renderTable(tableKey: tableKey, columns: columns, labels: labels, document: document)

        case .keyValue(let label, let value):
            let l = PrintTemplate.substitute(label, in: document)
            let v = PrintTemplate.substitute(value, in: document)
            return "\(l): \(v)"
        }
    }

    private func renderTable(
        tableKey: String,
        columns explicitColumns: [String],
        labels: [String: String],
        document: Document
    ) -> String {
        let rows = document.children[tableKey] ?? []
        guard !rows.isEmpty else { return "" }

        // Resolve column list — explicit if given, else union of keys seen.
        let columns: [String]
        if !explicitColumns.isEmpty {
            columns = explicitColumns
        } else {
            var seen = Set<String>()
            var inOrder: [String] = []
            for row in rows {
                for k in row.fields.keys where !seen.contains(k) {
                    seen.insert(k)
                    inOrder.append(k)
                }
            }
            columns = inOrder
        }

        // Compute column widths.
        var widths: [String: Int] = [:]
        for col in columns {
            let header = labels[col] ?? PrintTemplate.defaultLabel(forKey: col)
            widths[col] = header.count
        }
        for row in rows {
            for col in columns {
                let v = row.fields[col].map(PrintTemplate.format) ?? ""
                widths[col] = max(widths[col] ?? 0, v.count)
            }
        }

        func padded(_ s: String, _ w: Int) -> String {
            s.padding(toLength: w, withPad: " ", startingAt: 0)
        }

        let header = columns.map { padded(labels[$0] ?? PrintTemplate.defaultLabel(forKey: $0), widths[$0] ?? 0) }
            .joined(separator: "  ")
        let separator = columns.map { String(repeating: "-", count: widths[$0] ?? 0) }
            .joined(separator: "  ")
        var body: [String] = [header, separator]
        for row in rows {
            let line = columns.map { col in
                let v = row.fields[col].map(PrintTemplate.format) ?? ""
                return padded(v, widths[col] ?? 0)
            }.joined(separator: "  ")
            body.append(line)
        }
        return body.joined(separator: "\n")
    }
}
