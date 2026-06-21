//
//  DataImporter.swift
//  mercantis core
//
//  Phase C / P3.3 (ADR-046) — Bulk import. Reads CSV / JSON and routes
//  every row through `DocumentEngine.save(...)` so the validation
//  pipeline, naming, and audit log all run identically to interactive
//  saves.
//

import Foundation

public final class DataImporter: @unchecked Sendable {

    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry

    public init(documentEngine: DocumentEngine, registry: MetadataRegistry) {
        self.documentEngine = documentEngine
        self.registry = registry
    }

    // MARK: - Public API

    /// Import bytes into `docType`. Per-row failures are recorded in the
    /// returned `ImportReport` rather than aborting the whole batch.
    @discardableResult
    public func `import`(
        docType: String,
        data: Data,
        format: ImportExportFormat,
        conflictPolicy: ImportConflictPolicy = .overwrite
    ) throws -> ImportReport {
        guard registry.get(docType) != nil else {
            throw ImportExportError.docTypeNotRegistered(docType)
        }
        switch format {
        case .csv:  return try importCSV(docType: docType, data: data, conflictPolicy: conflictPolicy)
        case .json: return try importJSON(docType: docType, data: data, conflictPolicy: conflictPolicy)
        }
    }

    // MARK: - CSV path

    private func importCSV(
        docType: String,
        data: Data,
        conflictPolicy: ImportConflictPolicy
    ) throws -> ImportReport {
        let table = try CSVCodec.decode(data)
        let docTypeMeta = registry.get(docType)
        let fieldByKey: [String: FieldDefinition] = Dictionary(
            uniqueKeysWithValues: (docTypeMeta?.fields ?? []).map { ($0.key, $0) }
        )

        var outcomes: [ImportRowOutcome] = []
        for (index, row) in table.rows.enumerated() {
            do {
                let document = try makeDocument(
                    docType: docType,
                    row: row,
                    fieldByKey: fieldByKey
                )
                let outcome = try saveOrSkip(document, conflictPolicy: conflictPolicy)
                outcomes.append(outcome)
            } catch {
                outcomes.append(.failed(rowIndex: index, reason: "\(error)"))
            }
        }
        return ImportReport(docType: docType, rowsRead: table.rows.count, outcomes: outcomes)
    }

    private func makeDocument(
        docType: String,
        row: [String: String],
        fieldByKey: [String: FieldDefinition]
    ) throws -> Document {
        var fields: [String: FieldValue] = [:]
        for (key, raw) in row {
            if key == "id" || key == "status" || key == "docStatus" { continue }
            guard let definition = fieldByKey[key] else { continue }
            fields[key] = try coerce(raw, to: definition.type)
        }

        let id = row["id"] ?? ""
        let status = row["status"] ?? ""
        let docStatus = Int(row["docStatus"] ?? "") ?? 0
        let now = Date()
        return Document(
            id: id,
            docType: docType,
            company: "",
            status: status,
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            docStatus: docStatus,
            amendedFrom: nil,
            fields: fields,
            children: [:]
        )
    }

    private func coerce(_ raw: String, to type: FieldType) throws -> FieldValue {
        if raw.isEmpty { return .null }
        switch type {
        case .text, .longText, .richText, .email, .phone, .select, .multiselect,
             .link, .status, .barcode, .image, .attachment,
             .password, .code, .color, .signature, .geolocation,
             .autocomplete, .dynamicLink, .tableMultiSelect:
            return .string(raw)
        case .number, .rating, .duration:
            guard let v = Int(raw) else {
                throw ImportExportError.malformedCSV(line: 0, reason: "expected integer for \(type.rawValue), got '\(raw)'")
            }
            return .int(v)
        case .decimal, .currency, .percent:
            guard let v = Double(raw) else {
                throw ImportExportError.malformedCSV(line: 0, reason: "expected number for \(type.rawValue), got '\(raw)'")
            }
            return .double(v)
        case .boolean:
            switch raw.lowercased() {
            case "true", "yes", "1":  return .bool(true)
            case "false", "no", "0":  return .bool(false)
            default:
                throw ImportExportError.malformedCSV(line: 0, reason: "expected boolean, got '\(raw)'")
            }
        case .date:
            guard let d = ISO8601DateFormatter().date(from: raw) else {
                throw ImportExportError.malformedCSV(line: 0, reason: "expected ISO 8601 date, got '\(raw)'")
            }
            return .date(d)
        case .datetime, .time:
            guard let d = ISO8601DateFormatter().date(from: raw) else {
                throw ImportExportError.malformedCSV(line: 0, reason: "expected ISO 8601 dateTime, got '\(raw)'")
            }
            return .dateTime(d)
        case .table, .formula, .heading, .sectionBreak, .columnBreak:
            // CSV cannot losslessly carry child tables / formula results, and
            // layout separators carry no value. Skip the cell so the rest of
            // the row still imports.
            return .null
        }
    }

    // MARK: - JSON path

    private func importJSON(
        docType: String,
        data: Data,
        conflictPolicy: ImportConflictPolicy
    ) throws -> ImportReport {
        struct Envelope: Codable {
            let docType: String?
            let documents: [Document]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ImportExportError.malformedJSON(reason: "\(error)")
        }
        var outcomes: [ImportRowOutcome] = []
        for (index, doc) in envelope.documents.enumerated() {
            do {
                // Coerce docType so callers can re-target an export.
                let retargeted = withDocType(doc, docType: docType)
                let outcome = try saveOrSkip(retargeted, conflictPolicy: conflictPolicy)
                outcomes.append(outcome)
            } catch {
                outcomes.append(.failed(rowIndex: index, reason: "\(error)"))
            }
        }
        return ImportReport(
            docType: docType,
            rowsRead: envelope.documents.count,
            outcomes: outcomes
        )
    }

    private func withDocType(_ doc: Document, docType: String) -> Document {
        Document(
            id: doc.id,
            docType: docType,
            company: doc.company,
            status: doc.status,
            createdAt: doc.createdAt,
            updatedAt: doc.updatedAt,
            syncVersion: doc.syncVersion,
            syncState: doc.syncState,
            docStatus: doc.docStatus,
            amendedFrom: doc.amendedFrom,
            parentID: doc.parentID,
            fields: doc.fields,
            children: doc.children
        )
    }

    // MARK: - Save dispatch

    private func saveOrSkip(
        _ document: Document,
        conflictPolicy: ImportConflictPolicy
    ) throws -> ImportRowOutcome {
        let existing: Document? = (!document.id.isEmpty)
            ? try documentEngine.fetch(docType: document.docType, id: document.id)
            : nil

        if let existing {
            switch conflictPolicy {
            case .skipExisting:
                return .skipped(documentId: existing.id, reason: "id already exists")
            case .fail:
                return .failed(rowIndex: -1, reason: "id '\(existing.id)' already exists")
            case .overwrite:
                // Carry the existing updatedAt forward so the optimistic-
                // concurrency check passes on save.
                let merged = Document(
                    id: existing.id,
                    docType: existing.docType,
                    company: document.company,
                    status: document.status.isEmpty ? existing.status : document.status,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt,
                    syncVersion: existing.syncVersion,
                    syncState: existing.syncState,
                    docStatus: document.docStatus,
                    amendedFrom: existing.amendedFrom,
                    parentID: existing.parentID,
                    fields: document.fields,
                    children: document.children.isEmpty ? existing.children : document.children
                )
                let saved = try documentEngine.save(merged)
                return .updated(documentId: saved.id)
            }
        } else {
            let saved = try documentEngine.save(document)
            return .inserted(documentId: saved.id)
        }
    }
}
