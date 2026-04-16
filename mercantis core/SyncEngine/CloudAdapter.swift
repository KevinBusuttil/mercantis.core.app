//
//  CloudAdapter.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 16/04/2026.
//

import Foundation

/// Acknowledgement returned by the cloud after accepting a pushed mutation.
public struct SyncAcknowledgement: Sendable {
    public let mutationId: UUID
    public let serverSequence: Int64

    public init(mutationId: UUID, serverSequence: Int64) {
        self.mutationId = mutationId
        self.serverSequence = serverSequence
    }
}

/// A remote mutation received from the cloud.
public struct RemoteMutation: Sendable {
    public let record: MutationRecord
    public let serverSequence: Int64

    public init(record: MutationRecord, serverSequence: Int64) {
        self.record = record
        self.serverSequence = serverSequence
    }
}

/// The version bookmark used when pulling remote mutations.
public struct SyncVersion: Sendable {
    public let serverSequence: Int64

    public init(serverSequence: Int64) {
        self.serverSequence = serverSequence
    }
}

/// Protocol boundary between Mercantis Core's SyncEngine and any cloud backend. (ADR-018)
///
/// Core never imports or references any specific cloud SDK. The host application provides a
/// concrete `CloudAdapter` implementation and injects it into the `SyncEngine` at
/// initialisation. Core ships with a `NoOpCloudAdapter` for fully offline use.
public protocol CloudAdapter: Sendable {
    /// Push local mutations to the cloud backend.
    func pushMutations(_ mutations: [MutationRecord]) async throws -> [SyncAcknowledgement]

    /// Pull remote mutations from the cloud since the given version bookmark.
    func pullMutations(since version: SyncVersion) async throws -> [RemoteMutation]
}

/// A no-op cloud adapter for fully offline use. (ADR-018)
///
/// All push operations succeed silently. Pull always returns an empty list.
public struct NoOpCloudAdapter: CloudAdapter {
    public init() {}

    public func pushMutations(_ mutations: [MutationRecord]) async throws -> [SyncAcknowledgement] {
        // Offline mode — acknowledge everything immediately with sequence 0.
        return mutations.map { SyncAcknowledgement(mutationId: $0.id, serverSequence: 0) }
    }

    public func pullMutations(since version: SyncVersion) async throws -> [RemoteMutation] {
        // Offline mode — no remote mutations.
        return []
    }
}
