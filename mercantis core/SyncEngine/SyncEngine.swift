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
/// Queue retention is governed by `SyncQueuePruneConfig` (ADR-028).
public final class SyncEngine {

    private let database: MercantisDatabase
    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry
    private let conflictResolver: ConflictResolver
    private let cloudAdapter: CloudAdapter
    private let pruneConfig: SyncQueuePruneConfig
    private let clock: () -> Date

    /// The last known server sequence we have received. Loaded from the
    /// `sync_state` table at init and rewritten there on every advance (P0.3).
    private var lastServerSequence: Int64 = 0
    private let sequenceLock = NSLock()

    /// Key used in the `sync_state` table to persist `lastServerSequence`.
    private static let lastServerSequenceKey = "lastServerSequence"

    /// Key used in the `sync_state` table to persist the last prune watermark.
    private static let lastPrunedAtKey = "syncQueuePrunedAt"

    public init(
        database: MercantisDatabase,
        documentEngine: DocumentEngine,
        registry: MetadataRegistry,
        cloudAdapter: CloudAdapter = NoOpCloudAdapter(),
        pruneConfig: SyncQueuePruneConfig = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.documentEngine = documentEngine
        self.registry = registry
        self.conflictResolver = ConflictResolver()
        self.cloudAdapter = cloudAdapter
        self.pruneConfig = pruneConfig
        self.clock = clock
        self.lastServerSequence = Self.loadPersistedLastServerSequence(from: database)
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

        // Opportunistic, throttled prune of acknowledged rows. (ADR-028 / P0.4)
        // Result intentionally discarded — pruning is best-effort.
        _ = try? pruneSyncQueue(force: false)
    }

    // MARK: - Receive & Apply

    /// Pull and apply remote mutations from the cloud adapter.
    public func pullAndApplyRemoteMutations() async throws {
        let currentSequence = readLastServerSequence()

        let remoteMutations = try await cloudAdapter.pullMutations(
            since: SyncVersion(serverSequence: currentSequence)
        )
        guard !remoteMutations.isEmpty else { return }

        try await applyRemoteMutations(remoteMutations.map { $0.record })

        // Update our bookmark.
        if let maxSeq = remoteMutations.map({ $0.serverSequence }).max() {
            updateLastServerSequence(toAtLeast: maxSeq)
        }

        // Opportunistic, throttled prune of acknowledged rows. (ADR-028 / P0.4)
        // Result intentionally discarded — pruning is best-effort.
        _ = try? pruneSyncQueue(force: false)
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

    // MARK: - Queue Pruning (ADR-028 / P0.4)

    /// Delete acknowledged rows from `sync_queue` according to `pruneConfig`.
    /// Only `.pushed` (local, server-acknowledged) and `.applied` (remote,
    /// locally-applied) rows are eligible. `.pending` and `.conflicted` rows
    /// are always retained.
    ///
    /// Callers do not need to invoke this directly — `pushPendingMutations()`
    /// and `pullAndApplyRemoteMutations()` call it (non-forcing) at the end of
    /// a successful run. The method no-ops when the last prune ran more
    /// recently than `pruneConfig.pruneInterval`, unless `force` is `true`.
    ///
    /// - Parameter force: Bypass the throttle and run regardless of the
    ///   persisted watermark.
    /// - Returns: Number of rows deleted.
    @discardableResult
    public func pruneSyncQueue(force: Bool = false) throws -> Int {
        let now = clock()

        if !force, let last = loadLastPrunedAt(),
           now.timeIntervalSince(last) < pruneConfig.pruneInterval {
            return 0
        }

        let pushedCutoff = now.addingTimeInterval(-pruneConfig.pushedRetention)
        let appliedCutoff = now.addingTimeInterval(-pruneConfig.appliedRetention)
        let iso = ISO8601DateFormatter()
        let pushedCutoffString = iso.string(from: pushedCutoff)
        let appliedCutoffString = iso.string(from: appliedCutoff)
        let watermarkString = iso.string(from: now)

        return try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sync_queue
                    WHERE status = ?
                      AND localTimestamp < ?
                    """,
                arguments: [MutationStatus.pushed.rawValue, pushedCutoffString]
            )
            let pushedDeleted = db.changesCount

            try db.execute(
                sql: """
                    DELETE FROM sync_queue
                    WHERE status = ?
                      AND localTimestamp < ?
                    """,
                arguments: [MutationStatus.applied.rawValue, appliedCutoffString]
            )
            let appliedDeleted = db.changesCount

            try db.execute(
                sql: """
                    INSERT INTO sync_state (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.lastPrunedAtKey, watermarkString]
            )

            return pushedDeleted + appliedDeleted
        }
    }

    private func loadLastPrunedAt() -> Date? {
        do {
            return try database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT value FROM sync_state WHERE key = ?",
                    arguments: [Self.lastPrunedAtKey]
                )
                guard let value: String = row?["value"] else { return nil }
                return ISO8601DateFormatter().date(from: value)
            }
        } catch {
            return nil
        }
    }

    // MARK: - Private Helpers

    private func readLastServerSequence() -> Int64 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        return lastServerSequence
    }

    private func updateLastServerSequence(toAtLeast value: Int64) {
        let shouldPersist: Bool = {
            sequenceLock.lock()
            defer { sequenceLock.unlock() }
            guard value > lastServerSequence else { return false }
            lastServerSequence = value
            return true
        }()

        guard shouldPersist else { return }

        do {
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO sync_state (key, value) VALUES (?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """,
                    arguments: [Self.lastServerSequenceKey, String(value)]
                )
            }
        } catch {
            // Persistence failure is non-fatal: the in-memory value is still
            // advanced so the current process won't re-pull already-applied
            // remote mutations. On next successful advance the bookmark will
            // be rewritten. Surfacing via EventEmitter is a future concern.
        }
    }

    private static func loadPersistedLastServerSequence(from database: MercantisDatabase) -> Int64 {
        do {
            return try database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT value FROM sync_state WHERE key = ?",
                    arguments: [lastServerSequenceKey]
                )
                guard let value: String = row?["value"], let parsed = Int64(value) else {
                    return 0
                }
                return parsed
            }
        } catch {
            return 0
        }
    }

    private func applyRemoteUpsert(_ mutation: MutationRecord) throws {
        // The mutation payload is a JSON-encoded Document.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let remoteDoc = try? decoder.decode(Document.self, from: mutation.payload) else {
            try storeMutationAsApplied(mutation)
            return
        }

        // Look up the DocType's sync policy.
        let syncPolicy = registry.get(remoteDoc.docType)?.syncPolicy
            ?? SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)

        // Determine the local document's sync version (0 if not found = new document).
        let localSyncVersion: Int64 = (try? database.read { db in
            try Row.fetchOne(db, sql: "SELECT syncVersion FROM documents WHERE id = ?", arguments: [remoteDoc.id])
        })?["syncVersion"] ?? 0

        let resolution = conflictResolver.resolve(
            remoteMutation: mutation,
            localSyncVersion: localSyncVersion,
            syncPolicy: syncPolicy
        )

        switch resolution {
        case .accepted:
            // Route through DocumentEngine so the ValidationPipeline (ADR-022),
            // submit-immutability guard (ADR-013), and DocumentVersion diff
            // recording (ADR-024) all fire for remote writes. (P0.2)
            try documentEngine.applyRemote(remoteDoc, from: mutation)
            try storeMutationAsApplied(mutation)

        case .conflicted:
            try database.write { db in
                try db.execute(
                    sql: "UPDATE documents SET syncState = ? WHERE id = ?",
                    arguments: [SyncState.conflicted.rawValue, remoteDoc.id]
                )
                try db.execute(
                    sql: "UPDATE sync_queue SET status = ? WHERE id = ?",
                    arguments: [MutationStatus.conflicted.rawValue, mutation.id.uuidString]
                )
            }

        case .appendedAsNew:
            // Append-Only: always insert as a new record.
            try documentEngine.applyRemote(remoteDoc, from: mutation)
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
