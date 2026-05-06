//
//  DataExporter.swift
//  mercantis core
//
//  Phase C / P3.3 (ADR-046) — Bulk export. Walks every document of a
//  DocType (or a caller-supplied set), serialises to CSV or JSON.
//

import Foundation

public final class DataExporter: @unchecked Sendable {

    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry

    public init(documentEngine: DocumentEngine, registry: MetadataRegistry) {
        self.documentEngine = documentEngine
        self.registry = registry
    }

    // MARK: - Public API

    /// Export every document of `docType` in the requested format. Optional
    /// `predicates` narrow the export to a subset; when nil, every document
    /// of that DocType is included.
    public func export(
        docType: String,
        format: ImportExportFormat,
        predicates: [ListFilter]? = nil
    ) throws -> Data {
        guard registry.get(docType) != nil else {
            throw ImportExportError.docTypeNotRegistered(docType)
        }
        let documents = try documentEngine.list(
            docType: docType,
            predicates: predicates,
            sortBy: [ListSort(fieldKey: "id", direction: .ascending)],
            applyRowAccess: false
        )
        switch format {
        case .csv:  return try exportCSV(documents: documents, docType: docType)
        case .json: return try exportJSON(documents: documents)
        }
    }

    // MARK: - CSV

    private func exportCSV(documents: [Document], docType: String) throws -> Data {
        // Header order: id, status, docStatus, then each declared field key
        // (in DocType declaration order). Children are not exported in CSV
        // because they don't fit the flat-row format; callers needing those
        // should use JSON.
        let docTypeMeta = registry.get(docType)
        let fieldKeys = docTypeMeta?.fields.map(\.key) ?? []
        let headers = ["id", "status", "docStatus"] + fieldKeys

        let rows: [[String: String]] = documents.map { doc in
            var row: [String: String] = [
                "id": doc.id,
                "status": doc.status,
                "docStatus": String(doc.docStatus),
            ]
            for key in fieldKeys {
                if let value = doc.fields[key] {
                    row[key] = stringify(value)
                } else {
                    row[key] = ""
                }
            }
            return row
        }
        return CSVCodec.encode(headers: headers, rows: rows)
    }

    private func stringify(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return ""
        case .date(let d), .dateTime(let d):
            return ISO8601DateFormatter().string(from: d)
        case .data(let d):   return d.base64EncodedString()
        case .array(let xs):
            // Best-effort flatten for CSV; JSON path keeps full structure.
            return xs.map { stringify($0) }.joined(separator: ";")
        }
    }

    // MARK: - JSON

    /// JSON envelope: `{ "docType": "...", "documents": [Document...] }`.
    /// `Document` already encodes via `Codable` with the typed-envelope
    /// `FieldValue` form (ADR-032), so children round-trip correctly.
    private func exportJSON(documents: [Document]) throws -> Data {
        struct Envelope: Codable {
            let docType: String?
            let documents: [Document]
        }
        let envelope = Envelope(
            docType: documents.first?.docType,
            documents: documents
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}
