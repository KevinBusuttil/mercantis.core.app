//
//  SyncQueuePruneConfig.swift
//  mercantis core
//
//  Retention policy for acknowledged mutations in `sync_queue`. (ADR-028 / P0.4)
//

import Foundation

/// Retention policy applied by `SyncEngine.pruneSyncQueue(force:)`.
///
/// Only `.pushed` (local, server-acknowledged) and `.applied` (remote,
/// locally-applied) rows are ever deleted. `.pending` rows are still awaiting
/// push; `.conflicted` rows are awaiting user resolution — both are retained
/// indefinitely regardless of retention windows.
public struct SyncQueuePruneConfig: Sendable {

    /// Retention window for `.pushed` rows, measured from `localTimestamp`.
    /// Rows older than this are deleted.
    public var pushedRetention: TimeInterval

    /// Retention window for `.applied` rows, measured from `localTimestamp`.
    /// Rows older than this are deleted.
    public var appliedRetention: TimeInterval

    /// Minimum interval between throttled prune runs. Guards against running
    /// on every push/pull call; `pruneSyncQueue(force: true)` bypasses this.
    public var pruneInterval: TimeInterval

    public init(
        pushedRetention: TimeInterval,
        appliedRetention: TimeInterval,
        pruneInterval: TimeInterval
    ) {
        self.pushedRetention = pushedRetention
        self.appliedRetention = appliedRetention
        self.pruneInterval = pruneInterval
    }

    private static let day: TimeInterval = 24 * 60 * 60

    /// Default policy: 30-day retention for both `.pushed` and `.applied`
    /// rows, with a 24-hour throttle between opportunistic prunes.
    public static let `default` = SyncQueuePruneConfig(
        pushedRetention: 30 * day,
        appliedRetention: 30 * day,
        pruneInterval: day
    )
}
