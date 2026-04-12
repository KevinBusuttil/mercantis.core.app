//
//  SyncEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Orchestrates synchronisation between the local database and the cloud adapter.
/// Implements the push/receive/apply/acknowledge flow. (ADR-005)
///
/// Conflict resolution follows the per-DocType sync policy. (ADR-006)
public final class SyncEngine {

    private let database: MercantisDatabase
    private let documentEngine: DocumentEngine

    public init(database: MercantisDatabase, documentEngine: DocumentEngine) {
        self.database = database
        self.documentEngine = documentEngine
    }

    /// Push pending local mutations to the cloud adapter.
    public func pushPendingMutations() async throws {
        // TODO: Read pending mutations from sync_queue ordered by localTimestamp
        // TODO: Send to cloud adapter
        // TODO: Mark as pushed on success
    }

    /// Receive and apply remote mutations from the cloud adapter.
    public func applyRemoteMutations(_ mutations: [MutationRecord]) async throws {
        // TODO: For each mutation, check DocType's syncPolicy
        // TODO: LWW -> accept higher server sequence
        // TODO: VersionChecked -> compare syncVersions, reject + mark conflicted if diverged
        // TODO: AppendOnly -> always insert
        // TODO: Update document syncState accordingly
    }

    /// Resolve a conflict by choosing a version. Records a `resolveConflict` mutation. (ADR-006)
    public func resolveConflict(docType: String, documentId: String, chosenVersion: Int64, resolvedBy: String) throws {
        // TODO: Create resolveConflict mutation
        // TODO: Apply chosen version to document
        // TODO: Clear conflicted status
    }
}
