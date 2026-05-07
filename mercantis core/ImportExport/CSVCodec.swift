//
//  CSVCodec.swift
//  mercantis core
//
//  Phase C / P3.3 (ADR-046) — Minimal CSV reader / writer. RFC-4180-ish:
//  `,` separator, `"` quoting, `""` for embedded quotes, CRLF or LF line
//  endings on read, LF on write.
//
//  We deliberately avoid pulling in a third-party CSV library — the
//  surface we need (encode/decode `[String: String]` rows) is small
//  enough that a few hundred lines of focused parsing keep our
//  dependency graph clean.
//

import Foundation

public enum CSVCodec {

    // MARK: - Encode

    /// Render a header + rows array as RFC-4180 CSV bytes (LF line endings).
    /// `headers` defines column order; missing cells render empty.
    nonisolated public static func encode(headers: [String], rows: [[String: String]]) -> Data {
        var out = ""
        out += headers.map(escape).joined(separator: ",")
        out += "\n"
        for row in rows {
            out += headers.map { escape(row[$0] ?? "") }.joined(separator: ",")
            out += "\n"
        }
        return Data(out.utf8)
    }

    /// Escape one CSV cell. Quotes the value when it contains a separator,
    /// quote, CR, or LF.
    nonisolated public static func escape(_ raw: String) -> String {
        if raw.isEmpty { return "" }
        let needsQuote = raw.contains(",") || raw.contains("\"") || raw.contains("\n") || raw.contains("\r")
        if !needsQuote { return raw }
        let inner = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(inner)\""
    }

    // MARK: - Decode

    public struct DecodedTable: Sendable {
        public let headers: [String]
        public let rows: [[String: String]]
    }

    /// Parse `bytes` as RFC-4180 CSV. Throws `ImportExportError.malformedCSV`
    /// on quote / row mismatches (e.g. unterminated quoted cells).
    nonisolated public static func decode(_ bytes: Data) throws -> DecodedTable {
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw ImportExportError.malformedCSV(line: 0, reason: "input is not valid UTF-8")
        }
        let rawRows = try parseRows(text)
        guard let header = rawRows.first else {
            return DecodedTable(headers: [], rows: [])
        }
        let dataRows = rawRows.dropFirst().map { cells -> [String: String] in
            var row: [String: String] = [:]
            for (i, key) in header.enumerated() where i < cells.count {
                row[key] = cells[i]
            }
            return row
        }
        return DecodedTable(headers: header, rows: Array(dataRows))
    }

    nonisolated private static func parseRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var inQuotes = false
        var line = 1
        var iter = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return iter.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let peek = iter.next() {
                        if peek == "\"" {
                            currentCell.append("\"")
                        } else {
                            inQuotes = false
                            pending = peek
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    if ch == "\n" { line += 1 }
                    currentCell.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    if !currentCell.isEmpty {
                        throw ImportExportError.malformedCSV(line: line, reason: "quote inside unquoted cell")
                    }
                    inQuotes = true
                case ",":
                    currentRow.append(currentCell)
                    currentCell = ""
                case "\r":
                    // Swallow; the LF will close the row.
                    continue
                case "\n":
                    currentRow.append(currentCell)
                    rows.append(currentRow)
                    currentRow = []
                    currentCell = ""
                    line += 1
                default:
                    currentCell.append(ch)
                }
            }
        }
        if inQuotes {
            throw ImportExportError.malformedCSV(line: line, reason: "unterminated quoted cell")
        }
        if !currentCell.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }
        return rows
    }
}
