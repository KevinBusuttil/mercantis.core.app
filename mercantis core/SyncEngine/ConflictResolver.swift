//
//  ConflictResolver.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Applies the per-DocType conflict resolution policy. (ADR-006)
///
/// Three policies:
/// - Last-Write-Wins (LWW): higher server sequence accepted, loser recorded in audit log
/// - Version-Checked Merge (VCM): concurrent edits rejected, human resolution required
/// - Append-Only (AO): always accepted as new record, no conflict concept
public struct ConflictResolver {

    public enum Resolution: Sendable {
        case accepted
        case conflicted(localVersion: Int64, remoteVersion: Int64)
        case appendedAsNew
    }

    public init() {}

    /// Determine the resolution for a remote mutation against a local document.
    public func resolve(
        remoteMutation: MutationRecord,
        localSyncVersion: Int64,
        syncPolicy: SyncPolicy
    ) -> Resolution {
        switch syncPolicy.conflictResolution {
        case .lastWriteWins:
            // Accept only if the remote version is at least as new as local.
            if remoteMutation.syncVersion >= localSyncVersion {
                return .accepted
            } else {
                return .conflicted(localVersion: localSyncVersion, remoteVersion: remoteMutation.syncVersion)
            }
        case .versionChecked:
            if remoteMutation.syncVersion == localSyncVersion {
                return .accepted
            } else {
                return .conflicted(localVersion: localSyncVersion, remoteVersion: remoteMutation.syncVersion)
            }
        case .appendOnly:
            return .appendedAsNew
        }
    }
}
