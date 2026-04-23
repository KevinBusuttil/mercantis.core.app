//
//  ConflictResolverTests.swift
//  mercantis coreTests
//
//  Covers ADR-006: Last-Write-Wins, Version-Checked, and Append-Only policies.
//

import XCTest
@testable import mercantis_core

final class ConflictResolverTests: XCTestCase {

    private let resolver = ConflictResolver()

    // MARK: - Helpers

    private func mutation(at version: Int64) -> MutationRecord {
        MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: Data(),
            deviceId: "remote",
            userId: "remote-user",
            localTimestamp: Date(),
            syncVersion: version,
            status: .applied
        )
    }

    // MARK: - Last-Write-Wins

    func testLWWAcceptsRemoteWhenVersionIsNewer() {
        let policy = SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)
        let result = resolver.resolve(remoteMutation: mutation(at: 5), localSyncVersion: 3, syncPolicy: policy)
        guard case .accepted = result else { return XCTFail("expected .accepted, got \(result)") }
    }

    func testLWWAcceptsRemoteAtEqualVersion() {
        let policy = SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)
        let result = resolver.resolve(remoteMutation: mutation(at: 3), localSyncVersion: 3, syncPolicy: policy)
        guard case .accepted = result else { return XCTFail("expected .accepted, got \(result)") }
    }

    func testLWWConflictsWhenRemoteIsStale() {
        let policy = SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)
        let result = resolver.resolve(remoteMutation: mutation(at: 1), localSyncVersion: 3, syncPolicy: policy)
        guard case .conflicted(let local, let remote) = result else {
            return XCTFail("expected .conflicted, got \(result)")
        }
        XCTAssertEqual(local, 3)
        XCTAssertEqual(remote, 1)
    }

    // MARK: - Version-Checked Merge

    func testVCMAcceptsOnlyWhenVersionsMatch() {
        let policy = SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true)
        let result = resolver.resolve(remoteMutation: mutation(at: 7), localSyncVersion: 7, syncPolicy: policy)
        guard case .accepted = result else { return XCTFail("expected .accepted, got \(result)") }
    }

    func testVCMConflictsWhenVersionsDisagree() {
        let policy = SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true)
        let result = resolver.resolve(remoteMutation: mutation(at: 8), localSyncVersion: 7, syncPolicy: policy)
        guard case .conflicted = result else { return XCTFail("expected .conflicted, got \(result)") }
    }

    // MARK: - Append-Only

    func testAppendOnlyAlwaysAccepts() {
        let policy = SyncPolicy(conflictResolution: .appendOnly, immutableAfterSubmit: false)
        let result = resolver.resolve(remoteMutation: mutation(at: 0), localSyncVersion: 99, syncPolicy: policy)
        guard case .appendedAsNew = result else {
            return XCTFail("expected .appendedAsNew, got \(result)")
        }
    }
}
