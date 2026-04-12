//
//  Document.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A runtime document instance. Documents are generic containers
/// whose structure is defined by their DocType metadata. (ADR-003)
public struct Document: Identifiable, Sendable {
    public let id: String                       // UUID
    public let docType: String                  // references DocType.id
    public var company: String
    public var status: String
    public let createdAt: Date
    public var updatedAt: Date
    public var syncVersion: Int64
    public var syncState: SyncState

    /// Custom field values stored as a dictionary (persisted as JSON payload in SQLite). (ADR-002)
    public var fields: [String: FieldValue]

    /// Child table rows grouped by table name. (ADR-002)
    public var children: [String: [ChildRow]]
}

/// Sync state of a document on this device.
public enum SyncState: String, Codable, Sendable {
    case local        // created locally, not yet pushed
    case synced       // matches server version
    case modified     // locally modified since last sync
    case conflicted   // conflict detected, awaiting resolution
}

/// A single child row belonging to a parent document.
public struct ChildRow: Identifiable, Sendable {
    public let id: String
    public var rowIndex: Int
    public var fields: [String: FieldValue]
}
