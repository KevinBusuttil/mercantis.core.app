//
//  MutationRecord.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// The type of mutation recorded in the sync queue. (ADR-005)
public enum MutationType: String, Codable, Sendable {
    case upsertDocument
    case deleteDocument
    case patchChildRows
    case attachFile
    case updateSchema
    case installApp
    case updatePermissions
    case resolveConflict       // ADR-006: conflict resolution decision
}

/// Status of a mutation in the sync queue.
public enum MutationStatus: String, Codable, Sendable {
    case pending
    case pushed
    case applied
    case conflicted
}

/// A single mutation record in the sync queue. (ADR-005)
/// Every persistent write produces exactly one MutationRecord.
public struct MutationRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: MutationType
    public let payload: Data              // JSON-encoded mutation payload
    public let deviceId: String
    public let userId: String
    public let localTimestamp: Date
    public let syncVersion: Int64         // monotonically increasing per document
    public var status: MutationStatus
}
