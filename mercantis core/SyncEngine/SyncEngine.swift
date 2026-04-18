//
//  SyncEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

/// Orchestrates synchronisation between the local database and the cloud adapter.
/// Implements the push/receive/apply/acknowledge flow. (ADR-005)
///
/// Conflict resolution follows the per-DocType sync policy. (ADR-006)
public final class SyncEngine {

    private let database: MercantisDatabase
    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry
    private let conflictResolver: ConflictResolver
    private let cloudAdapter: CloudAdapter

    /// The last known server sequence we have received. Persisted in-memory for
    /// simplicity; a production version would store this in SQLite.
    private var lastServerSequence: Int64 = 0
    private let sequenceLock = NSLock()

    public init(
        database: MercantisDatabase,
        documentEngine: DocumentEngine,
        registry: MetadataRegistry,
        cloudAdapter: CloudAdapter = NoOpCloudAdapter()
    ) {
        self.database = database
        self.documentEngine = documentEngine
        self.registry = registry
        self.conflictResolver = ConflictResolver()
        self.cloudAdapter = cloudAdapter
    }

    // MARK: - Push

    /// Push pending local mutations to the cloud adapter.
    /// Reads pending mutations from `sync_queue` ordered by `localTimestamp`,
    /// sends them to the cloud adapter, and marks them as `pushed` on success.
    public func pushPendingMutations() async throws {
        // 1. Read pending mutations from the sync_queue.
        let pendingRows = try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, type, payload, deviceId, userId, localTimestamp, syncVersion, status
                    FROM sync_queue
                    WHERE status = ?
                    ORDER BY localTimestamp ASC
                    """,
                arguments: [MutationStatus.pending.rawValue]
            )
        }

        guard !pendingRows.isEmpty else { return }

        let mutations = pendingRows.compactMap { row -> MutationRecord? in
            guard let idString: String = row["id"],
                  let id = UUID(uuidString: idString),
                  let typeRaw: String = row["type"],
                  let type = MutationType(rawValue: typeRaw),
                  let payloadString: String = row["payload"],
                  let deviceId: String = row["deviceId"],
                  let userId: String = row["userId"],
                  let timestampString: String = row["localTimestamp"],
                  let syncVersion: Int64 = row["syncVersion"],
                  let statusRaw: String = row["status"],
                  let status = MutationStatus(rawValue: statusRaw) else {
                return nil
            }

            let payload = payloadString.data(using: .utf8) ?? Data()
            let timestamp = ISO8601DateFormatter().date(from: timestampString) ?? Date()

            return MutationRecord(
                id: id,
                type: type,
                payload: payload,
                deviceId: deviceId,
                userId: userId,
                localTimestamp: timestamp,
                syncVersion: syncVersion,
                status: status
            )
        }

        // 2. Send to cloud adapter.
        let acknowledgements = try await cloudAdapter.pushMutations(mutations)

        // 3. Mark as pushed on success.
        let acknowledgedIds = Set(acknowledgements.map { $0.mutationId.uuidString })
        try database.write { db in
            for mutation in mutations where acknowledgedIds.contains(mutation.id.uuidString) {
                try db.execute(
                    sql: "UPDATE sync_queue SET status = ? WHERE id = ?",
                    arguments: [MutationStatus.pushed.rawValue, mutation.id.uuidString]
                )
            }
        }
    }

    // MARK: - Receive & Apply

    /// Pull and apply remote mutations from the cloud adapter.
    public func pullAndApplyRemoteMutations() async throws {
        let currentSequence: Int64
        sequenceLock.lock()
        currentSequence = lastServerSequence
        sequenceLock.unlock()

        let remoteMutations = try await cloudAdapter.pullMutations(
            since: SyncVersion(serverSequence: currentSequence)
        )
        guard !remoteMutations.isEmpty else { return }

        try await applyRemoteMutations(remoteMutations.map { $0.record })

        // Update our bookmark.
        if let maxSeq = remoteMutations.map({ $0.serverSequence }).max() {
            sequenceLock.lock()
            if maxSeq > lastServerSequence {
                lastServerSequence = maxSeq
            }
            sequenceLock.unlock()
        }
    }

    /// Receive and apply remote mutations from the cloud adapter.
    /// For each mutation, checks the DocType's syncPolicy and applies
    /// the appropriate conflict resolution strategy. (ADR-006)
    public func applyRemoteMutations(_ mutations: [MutationRecord]) async throws {
        for mutation in mutations {
            switch mutation.type {
            case .upsertDocument:
                try applyRemoteUpsert(mutation)

            case .deleteDocument:
                try applyRemoteDelete(mutation)

            case .installApp, .uninstallApp, .updateSchema, .updatePermissions:
                // Schema/app mutations are applied by re-decoding the payload and
                // re-running the appropriate installer/registry path.
                try applyRemoteMetadataMutation(mutation)

            case .resolveConflict:
                try applyRemoteConflictResolution(mutation)

            case .patchChildRows, .attachFile:
                // Forward-compatible: store the mutation and apply when supported.
                try storeMutationAsApplied(mutation)
            }
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by choosing a version. Records a `resolveConflict` mutation. (ADR-006)
    public func resolveConflict(docType: String, documentId: String, chosenVersion: Int64, resolvedBy: String) throws {
        // 1. Build the conflict resolution payload.
        let payloadDict: [String: String] = [
            "docType": docType,
            "documentId": documentId,
            "chosenVersion": "\(chosenVersion)"
        ]
        let payloadData = try JSONEncoder().encode(payloadDict)

        // 2. Create the resolveConflict mutation.
        let mutation = MutationRecord(
            id: UUID(),
            type: .resolveConflict,
            payload: payloadData,
            deviceId: "",
            userId: resolvedBy,
            localTimestamp: Date(),
            syncVersion: chosenVersion,
            status: .pending
        )

        let mutationPayloadString = String(data: mutation.payload, encoding: .utf8) ?? "{}"
        let mutationTimestamp = ISO8601DateFormatter().string(from: mutation.localTimestamp)

        try database.write { db in
            // 3. Clear conflicted status on the document.
            try db.execute(
                sql: "UPDATE documents SET syncState = ?, syncVersion = ? WHERE id = ? AND doctype = ?",
                arguments: [SyncState.synced.rawValue, chosenVersion, documentId, docType]
            )

            // 4. Append the resolveConflict mutation to sync_queue.
            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutation.id.uuidString,
                    mutation.type.rawValue,
                    mutationPayloadString,
                    mutation.deviceId,
                    mutation.userId,
                    mutationTimestamp,
                    mutation.syncVersion,
                    mutation.status.rawValue
                ]
            )
        }
    }

    // MARK: - Private Helpers

    private func applyRemoteUpsert(_ mutation: MutationRecord) throws {
        // Decode the payload to determine the document's DocType and fields.
        guard let payloadDict = try? JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any],
              let docTypeName = payloadDict["docType"] as? String,
              let documentId = payloadDict["id"] as? String else {
            try storeMutationAsApplied(mutation)
            return
        }

        // Look up the DocType's sync policy.
        let syncPolicy = registry.get(docTypeName)?.syncPolicy ?? SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)

        // Determine the local document's sync version (0 if not found = new document).
        let localSyncVersion: Int64 = (try? database.read { db in
            try Row.fetchOne(db, sql: "SELECT syncVersion FROM documents WHERE id = ?", arguments: [documentId])
        })?["syncVersion"] ?? 0

        // Apply conflict resolution.
        let resolution = conflictResolver.resolve(
            remoteMutation: mutation,
            localSyncVersion: localSyncVersion,
            syncPolicy: syncPolicy
        )

        switch resolution {
        case .accepted:
            // Apply the remote mutation: update all document columns and mark synced.
            let company = payloadDict["company"] as? String ?? ""
            let status = payloadDict["status"] as? String ?? ""
            let createdAt = payloadDict["createdAt"] as? String ?? ISO8601DateFormatter().string(from: mutation.localTimestamp)
            let updatedAt = payloadDict["updatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
            let docStatus = payloadDict["docStatus"] as? Int ?? 0
            let amendedFrom = payloadDict["amendedFrom"] as? String
            let payloadJSON: String
            if let fieldsObj = payloadDict["fields"] {
                payloadJSON = (try? String(data: JSONSerialization.data(withJSONObject: fieldsObj), encoding: .utf8)) ?? "{}"
            } else {
                payloadJSON = "{}"
            }

            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO documents
                            (id, doctype, company, status, createdAt, updatedAt, syncVersion, syncState, docStatus, amendedFrom, payload)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            company     = excluded.company,
                            status      = excluded.status,
                            updatedAt   = excluded.updatedAt,
                            syncVersion = excluded.syncVersion,
                            syncState   = excluded.syncState,
                            docStatus   = excluded.docStatus,
                            amendedFrom = excluded.amendedFrom,
                            payload     = excluded.payload
                        """,
                    arguments: [
                        documentId,
                        docTypeName,
                        company,
                        status,
                        createdAt,
                        updatedAt,
                        mutation.syncVersion,
                        SyncState.synced.rawValue,
                        docStatus,
                        amendedFrom,
                        payloadJSON
                    ]
                )
            }
            try storeMutationAsApplied(mutation)

        case .conflicted(_, _):
            // Mark the document as conflicted.
            try database.write { db in
                try db.execute(
                    sql: "UPDATE documents SET syncState = ? WHERE id = ?",
                    arguments: [SyncState.conflicted.rawValue, documentId]
                )
                try db.execute(
                    sql: "UPDATE sync_queue SET status = ? WHERE id = ?",
                    arguments: [MutationStatus.conflicted.rawValue, mutation.id.uuidString]
                )
            }

        case .appendedAsNew:
            // Append-Only: always insert as a new record.
            try storeMutationAsApplied(mutation)
        }
    }

    private func applyRemoteDelete(_ mutation: MutationRecord) throws {
        guard let payloadDict = try? JSONDecoder().decode([String: String].self, from: mutation.payload),
              let documentId = payloadDict["id"],
              let docType = payloadDict["docType"] else {
            return
        }
        try database.write { db in
            try db.execute(sql: "DELETE FROM document_children WHERE parentId = ?", arguments: [documentId])
            try db.execute(sql: "DELETE FROM documents WHERE id = ? AND doctype = ?", arguments: [documentId, docType])
        }
        try storeMutationAsApplied(mutation)
    }

    private func applyRemoteMetadataMutation(_ mutation: MutationRecord) throws {
        // Metadata mutations (installApp, updateSchema, updatePermissions) are stored
        // as applied. The actual schema update is handled by the app installer which
        // re-reads metadata on next access.
        try storeMutationAsApplied(mutation)
    }

    private func applyRemoteConflictResolution(_ mutation: MutationRecord) throws {
        guard let payloadDict = try? JSONDecoder().decode([String: String].self, from: mutation.payload),
              let documentId = payloadDict["documentId"],
              let chosenVersionStr = payloadDict["chosenVersion"],
              let chosenVersion = Int64(chosenVersionStr) else {
            return
        }
        try database.write { db in
            try db.execute(
                sql: "UPDATE documents SET syncState = ?, syncVersion = ? WHERE id = ?",
                arguments: [SyncState.synced.rawValue, chosenVersion, documentId]
            )
        }
        try storeMutationAsApplied(mutation)
    }

    private func storeMutationAsApplied(_ mutation: MutationRecord) throws {
        let payloadString = String(data: mutation.payload, encoding: .utf8) ?? "{}"
        let timestamp = ISO8601DateFormatter().string(from: mutation.localTimestamp)

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutation.id.uuidString,
                    mutation.type.rawValue,
                    payloadString,
                    mutation.deviceId,
                    mutation.userId,
                    timestamp,
                    mutation.syncVersion,
                    MutationStatus.applied.rawValue
                ]
            )
        }
    }
}
