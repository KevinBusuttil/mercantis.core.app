//
//  AppInstaller.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

/// Installs, updates, and uninstalls app manifests. (ADR-004)
/// App state changes are distributed via the sync engine so all devices
/// in a workspace share the same app state.
public final class AppInstaller {

    private let database: MercantisDatabase
    private let schemaValidator: SchemaValidator
    private let registry: MetadataRegistry

    public init(database: MercantisDatabase, schemaValidator: SchemaValidator, registry: MetadataRegistry) {
        self.database = database
        self.schemaValidator = schemaValidator
        self.registry = registry
    }

    // MARK: - Install

    /// Install an app from its manifest. Validates all DocTypes before committing.
    /// Writes DocTypes, workflows, permissions, reports, and the manifest itself
    /// to their respective metadata tables, then appends an `installApp` mutation
    /// to the sync queue so the installation is distributed to all devices.
    public func install(_ manifest: AppManifest) throws {
        // 1. Validate every DocType in the manifest.
        for docType in manifest.doctypes {
            try schemaValidator.validate(docType)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Encode the full manifest payload.
        let manifestPayloadData = try encoder.encode(manifest)
        guard let manifestPayloadString = String(data: manifestPayloadData, encoding: .utf8) else {
            throw AppInstallerError.encodingFailed(appId: manifest.id)
        }

        let now = ISO8601DateFormatter().string(from: Date())

        try database.write { db in
            // 2. Persist the app record.
            try db.execute(
                sql: """
                    INSERT INTO apps (id, name, version, installedAt, payload)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name        = excluded.name,
                        version     = excluded.version,
                        installedAt = excluded.installedAt,
                        payload     = excluded.payload
                    """,
                arguments: [manifest.id, manifest.name, manifest.version, now, manifestPayloadString]
            )

            // 3. Register each DocType in the metadata tables.
            for docType in manifest.doctypes {
                let docPayloadData = try encoder.encode(docType)
                let docPayloadString = String(data: docPayloadData, encoding: .utf8) ?? "{}"

                try db.execute(
                    sql: """
                        INSERT INTO doctypes (id, name, module, appId, payload)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            name    = excluded.name,
                            module  = excluded.module,
                            appId   = excluded.appId,
                            payload = excluded.payload
                        """,
                    arguments: [docType.id, docType.name, docType.module, manifest.id, docPayloadString]
                )

                // Flatten field definitions into the fields table for efficient lookup.
                for field in docType.fields {
                    let fieldPayloadData = try encoder.encode(field)
                    let fieldPayloadString = String(data: fieldPayloadData, encoding: .utf8) ?? "{}"
                    try db.execute(
                        sql: """
                            INSERT INTO fields (docTypeId, fieldKey, fieldType, payload)
                            VALUES (?, ?, ?, ?)
                            ON CONFLICT(docTypeId, fieldKey) DO UPDATE SET
                                fieldType = excluded.fieldType,
                                payload   = excluded.payload
                            """,
                        arguments: [docType.id, field.key, field.type.rawValue, fieldPayloadString]
                    )
                }
            }

            // 4. Persist workflow definitions.
            for workflow in manifest.workflows {
                let wfPayloadData = try encoder.encode(workflow)
                let wfPayloadString = String(data: wfPayloadData, encoding: .utf8) ?? "{}"
                try db.execute(
                    sql: """
                        INSERT INTO workflows (id, name, docType, appId, payload)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            name    = excluded.name,
                            docType = excluded.docType,
                            appId   = excluded.appId,
                            payload = excluded.payload
                        """,
                    arguments: [workflow.id, workflow.name, workflow.docType, manifest.id, wfPayloadString]
                )
            }

            // 5. Append an installApp mutation to the sync queue.
            let mutationId = UUID()
            let mutationTimestamp = now
            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutationId.uuidString,
                    MutationType.installApp.rawValue,
                    manifestPayloadString,
                    "",   // deviceId filled by caller context
                    "",   // userId filled by caller context
                    mutationTimestamp,
                    0,
                    MutationStatus.pending.rawValue
                ]
            )
        }

        // 6. Update the in-memory registry cache.
        for docType in manifest.doctypes {
            try registry.register(docType)
        }
    }

    // MARK: - Uninstall

    /// Uninstall an app, removing its DocTypes and associated metadata.
    public func uninstall(appId: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try database.write { db in
            // 1. Remove workflows belonging to this app.
            try db.execute(sql: "DELETE FROM workflows WHERE appId = ?", arguments: [appId])

            // 2. Remove fields belonging to DocTypes of this app.
            try db.execute(
                sql: """
                    DELETE FROM fields WHERE docTypeId IN (
                        SELECT id FROM doctypes WHERE appId = ?
                    )
                    """,
                arguments: [appId]
            )

            // 3. Gather DocType IDs before deletion (for cache cleanup).
            let docTypeRows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM doctypes WHERE appId = ?",
                arguments: [appId]
            )
            let docTypeIds: [String] = docTypeRows.compactMap { $0["id"] }

            // 4. Remove DocTypes belonging to this app.
            try db.execute(sql: "DELETE FROM doctypes WHERE appId = ?", arguments: [appId])

            // 5. Remove the app record.
            try db.execute(sql: "DELETE FROM apps WHERE id = ?", arguments: [appId])

            // 6. Append an uninstall mutation to the sync queue.
            let payloadData = try JSONEncoder().encode(["appId": appId])
            let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
            let mutationId = UUID()
            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutationId.uuidString,
                    MutationType.uninstallApp.rawValue,
                    payloadString,
                    "",
                    "",
                    now,
                    0,
                    MutationStatus.pending.rawValue
                ]
            )

            // 7. Clear in-memory cache for removed DocTypes.
            for docTypeId in docTypeIds {
                try? registry.remove(docTypeId)
            }
        }
    }

    // MARK: - Errors

    public enum AppInstallerError: Error, Sendable {
        case encodingFailed(appId: String)
    }
}
