//
//  FileSystemCloudAdapterTests.swift
//  mercantis coreTests
//
//  Phase D / §3.5 (ADR-047) — Two FileSystemCloudAdapter instances against
//  the same shared root simulate two devices syncing via a shared folder.
//  Verifies push fan-out, pull collection, peer-cursor advancement, and
//  state persistence across instance restarts.
//

import XCTest
@testable import mercantis_core

final class FileSystemCloudAdapterTests: XCTestCase {

    private var sharedRoot: URL!

    override func setUpWithError() throws {
        sharedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs-adapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sharedRoot, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sharedRoot)
        sharedRoot = nil
    }

    // MARK: - Helpers

    private func mutation(_ id: String = UUID().uuidString, deviceId: String) throws -> MutationRecord {
        let payload = try JSONEncoder().encode(["hello": "world"])
        return MutationRecord(
            id: UUID(uuidString: id) ?? UUID(),
            type: .upsertDocument,
            payload: payload,
            deviceId: deviceId,
            userId: "alice",
            localTimestamp: Date(),
            syncVersion: 0,
            status: .pending
        )
    }

    // MARK: - Push

    func testPushAssignsMonotonicLocalSequence() async throws {
        let adapter = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        let acks = try await adapter.pushMutations([
            try mutation(deviceId: "deviceA"),
            try mutation(deviceId: "deviceA"),
            try mutation(deviceId: "deviceA"),
        ])
        XCTAssertEqual(acks.map(\.serverSequence), [1, 2, 3])
        XCTAssertEqual(adapter.currentLocalPushSequence(), 3)
    }

    func testPushSequenceSurvivesReinitialisation() async throws {
        do {
            let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
            _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])
            _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])
            XCTAssertEqual(a.currentLocalPushSequence(), 2)
        }
        // Re-open against the same root.
        let reopened = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        XCTAssertEqual(reopened.currentLocalPushSequence(), 2)
        let acks = try await reopened.pushMutations([try mutation(deviceId: "deviceA")])
        XCTAssertEqual(acks.first?.serverSequence, 3)
    }

    // MARK: - Cross-device pull

    func testPeerPullsEverythingDeviceADropped() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        let b = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")

        _ = try await a.pushMutations([
            try mutation(deviceId: "deviceA"),
            try mutation(deviceId: "deviceA"),
        ])
        let received = try await b.pullMutations(since: SyncVersion(serverSequence: 0))
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.map(\.serverSequence), [1, 2],
                       "global receive sequence is monotonic")
    }

    func testIgnoreOwnMutationsOnPull() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])
        let received = try await a.pullMutations(since: SyncVersion(serverSequence: 0))
        XCTAssertTrue(received.isEmpty,
                      "an adapter must not pull its own pushed mutations")
    }

    func testPeerCursorAdvancesSoNothingIsReplayed() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        let b = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")

        _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])
        _ = try await b.pullMutations(since: SyncVersion(serverSequence: 0))
        // Second pull with no new pushes from A returns nothing.
        let again = try await b.pullMutations(since: SyncVersion(serverSequence: 1))
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(b.currentPeerCursor(for: "deviceA"), 1)
    }

    func testPullAfterAdapterRestartDoesNotReplay() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])

        do {
            let b = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")
            let r = try await b.pullMutations(since: SyncVersion(serverSequence: 0))
            XCTAssertEqual(r.count, 1)
        }

        // Re-open device B, ensure cursor + global seq survived.
        let bReopened = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")
        XCTAssertEqual(bReopened.currentPeerCursor(for: "deviceA"), 1)
        let r2 = try await bReopened.pullMutations(since: SyncVersion(serverSequence: 1))
        XCTAssertTrue(r2.isEmpty)
    }

    func testThreeDeviceFanoutAllPeersEventuallySee() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        let b = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")
        let c = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceC")

        _ = try await a.pushMutations([try mutation(deviceId: "deviceA")])
        _ = try await b.pushMutations([try mutation(deviceId: "deviceB")])

        // Device C pulls from both peers in one sweep.
        let received = try await c.pullMutations(since: SyncVersion(serverSequence: 0))
        let sourceDevices = Set(received.map(\.record.deviceId))
        XCTAssertEqual(sourceDevices, ["deviceA", "deviceB"])
        XCTAssertEqual(received.count, 2)
    }

    func testSyncVersionCutoffSuppressesAlreadyReturnedItems() async throws {
        let a = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceA")
        let b = try FileSystemCloudAdapter(rootURL: sharedRoot, localDeviceId: "deviceB")

        _ = try await a.pushMutations([
            try mutation(deviceId: "deviceA"),
            try mutation(deviceId: "deviceA"),
            try mutation(deviceId: "deviceA"),
        ])

        let first = try await b.pullMutations(since: SyncVersion(serverSequence: 0))
        XCTAssertEqual(first.map(\.serverSequence), [1, 2, 3])

        // After SyncEngine bookmarked at 2, pulling again should only emit
        // items whose synthetic global sequence is > 2 — but the peer
        // cursor has already advanced, so nothing new comes back.
        let resume = try await b.pullMutations(since: SyncVersion(serverSequence: 2))
        XCTAssertTrue(resume.isEmpty)
    }
}
