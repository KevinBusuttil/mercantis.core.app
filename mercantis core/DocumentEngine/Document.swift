//
//  Document.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A runtime document instance. Documents are generic containers
/// whose structure is defined by their DocType metadata. (ADR-003)
public struct Document: Identifiable, Codable, Sendable {
    public let id: String                       // UUID
    public let docType: String                  // references DocType.id
    public var company: String
    public var status: String
    public let createdAt: Date
    public var updatedAt: Date
    public var syncVersion: Int64
    public var syncState: SyncState

    /// Submit/Cancel/Amend lifecycle state. (ADR-013)
    /// 0 = Draft, 1 = Submitted, 2 = Cancelled.
    /// Only meaningful for DocTypes with `isSubmittable: true`.
    public var docStatus: Int

    /// The document this was amended from (if any). (ADR-013)
    public var amendedFrom: String?

    /// Parent document ID for tree-structured DocTypes. (W8)
    public var parentID: String?

    /// Custom field values stored as a dictionary (persisted as JSON payload in SQLite). (ADR-002)
    public var fields: [String: FieldValue]

    /// Child table rows grouped by table name. (ADR-002)
    public var children: [String: [ChildRow]]

    public init(
        id: String,
        docType: String,
        company: String,
        status: String,
        createdAt: Date,
        updatedAt: Date,
        syncVersion: Int64,
        syncState: SyncState,
        docStatus: Int = 0,
        amendedFrom: String? = nil,
        parentID: String? = nil,
        fields: [String: FieldValue],
        children: [String: [ChildRow]]
    ) {
        self.id = id
        self.docType = docType
        self.company = company
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncVersion = syncVersion
        self.syncState = syncState
        self.docStatus = docStatus
        self.amendedFrom = amendedFrom
        self.parentID = parentID
        self.fields = fields
        self.children = children
    }
}

/// Sync state of a document on this device.
public enum SyncState: String, Codable, Sendable {
    case local        // created locally, not yet pushed
    case synced       // matches server version
    case modified     // locally modified since last sync
    case conflicted   // conflict detected, awaiting resolution
}

/// A single child row belonging to a parent document.
public struct ChildRow: Identifiable, Codable, Sendable {
    public let id: String
    public var rowIndex: Int
    public var fields: [String: FieldValue]

    public init(id: String, rowIndex: Int, fields: [String: FieldValue]) {
        self.id = id
        self.rowIndex = rowIndex
        self.fields = fields
    }
}
