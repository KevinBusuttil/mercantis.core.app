//
//  SyncPolicy.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// How conflicts are resolved during sync for a given DocType. (ADR-006)
public enum ConflictResolution: String, Codable, Sendable {
    /// Descriptive, non-financial fields. Higher server sequence wins. (ADR-006 Policy 1)
    case lastWriteWins
    /// Financial/inventory documents. Concurrent edits require human resolution. (ADR-006 Policy 2)
    case versionChecked
    /// Immutable-once-created records (ledger entries, audit log). Always accepted. (ADR-006 Policy 3)
    case appendOnly
}

/// Sync policy assigned to a DocType in its metadata definition. (ADR-006)
public struct SyncPolicy: Codable, Sendable {
    public var conflictResolution: ConflictResolution
    public var immutableAfterSubmit: Bool

    public var requiresVersionCheck: Bool {
        conflictResolution == .versionChecked
    }
}
