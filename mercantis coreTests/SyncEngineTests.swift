//
//  SyncEngineTests.swift
//  mercantis coreTests
//
//  Covers the push/receive/apply flow (ADR-005) with a stub CloudAdapter,
//  and verifies that sync-received writes now route through DocumentEngine
//  (P0.2 regression — no more raw SQL bypass of the ValidationPipeline).
//

import XCTest
import GRDB
@testable import mercantis_core

final class SyncEngineTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var adapter: StubCloudAdapter!
    private var sync: SyncEngine!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        adapter = StubCloudAdapter()
        sync = SyncEngine(
            database: harness.database,
            documentEngine: harness.engine,
            registry: harness.registry,
            cloudAdapter: adapter
        )
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
        adapter = nil
        sync = nil
    }

    // MARK: - Push

    func testPushForwardsPendingMutationsWithFullDocumentPayload() async throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(
            id: "push-1",
            fields: ["title": .string("Original")]
        ))

        try await sync.pushPendingMutations()

        XCTAssertEqual(adapter.pushed.count, 1)
        let pushed = try XCTUnwrap(adapter.pushed.first)
        XCTAssertEqual(pushed.type, .upsertDocument)

        // Payload must be a full Codable Document, not a 4-field UpsertPayload.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Document.self, from: pushed.payload)
        XCTAssertEqual(decoded.id, "push-1")
        XCTAssertEqual(decoded.fields["title"], .string("Original"))
    }

    // MARK: - Receive & Apply (P0.2 invariant)

    func testApplyRemoteMutationsPersistsRemoteDocumentThroughDocumentEngine() async throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let remoteDoc = TestSupport.makeDocument(
            id: "remote-1",
            fields: ["title": .string("From peer")],
            syncVersion: 3
        )
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(remoteDoc),
            deviceId: "peer-device",
            userId: "peer-user",
            localTimestamp: Date(),
            syncVersion: 3,
            status: .applied
        )

        try await sync.applyRemoteMutations([mutation])

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "remote-1"))
        XCTAssertEqual(fetched.fields["title"], .string("From peer"))
        XCTAssertEqual(fetched.syncState, .synced)

        // No *new* upsertDocument mutation should be queued — the received one is the record.
        let upsertQueueCount = try harness.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE type = 'upsertDocument'") ?? 0
        }
        XCTAssertEqual(upsertQueueCount, 1)
    }

    func testApplyRemoteMutationsRejectsInvalidRemoteDocument() async throws {
        let docType = TestSupport.makeDocType(fields: [
            TestSupport.textField("title", required: true)
        ])
        try harness.registry.register(docType)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let invalidRemote = TestSupport.makeDocument(id: "bad-1", fields: [:])
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(invalidRemote),
            deviceId: "peer",
            userId: "peer-user",
            localTimestamp: Date(),
            syncVersion: 1,
            status: .applied
        )

        do {
            try await sync.applyRemoteMutations([mutation])
            XCTFail("expected applyRemoteMutations to propagate validationFailed")
        } catch DocumentEngine.DocumentEngineError.validationFailed {
            // expected
        }

        XCTAssertNil(try harness.engine.fetch(docType: "Note", id: "bad-1"),
                     "rejected remote writes must not land in the documents table")
    }

    // MARK: - lastServerSequence persistence (P0.3)

    func testPullAdvancesAndPersistsLastServerSequence() async throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let remoteDoc = TestSupport.makeDocument(
            id: "remote-1",
            fields: ["title": .string("From peer")],
            syncVersion: 3
        )
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(remoteDoc),
            deviceId: "peer",
            userId: "peer-user",
            localTimestamp: Date(),
            syncVersion: 3,
            status: .applied
        )
        adapter.enqueueRemote([RemoteMutation(record: mutation, serverSequence: 42)])

        try await sync.pullAndApplyRemoteMutations()

        let persisted: String? = try harness.database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT value FROM sync_state WHERE key = ?",
                arguments: ["lastServerSequence"]
            )?["value"]
        }
        XCTAssertEqual(persisted, "42", "lastServerSequence must be written to sync_state after a successful pull")
    }

    func testLastServerSequenceSurvivesSyncEngineRestart() async throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let remoteDoc = TestSupport.makeDocument(
            id: "remote-1",
            fields: ["title": .string("From peer")],
            syncVersion: 3
        )
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(remoteDoc),
            deviceId: "peer",
            userId: "peer-user",
            localTimestamp: Date(),
            syncVersion: 3,
            status: .applied
        )
        adapter.enqueueRemote([RemoteMutation(record: mutation, serverSequence: 42)])

        try await sync.pullAndApplyRemoteMutations()

        // Simulate a process restart: new adapter, new SyncEngine pointing at the
        // same database. The bookmark must be loaded from `sync_state` so the
        // adapter is asked for mutations strictly after sequence 42.
        let restartedAdapter = StubCloudAdapter()
        let restartedSync = SyncEngine(
            database: harness.database,
            documentEngine: harness.engine,
            registry: harness.registry,
            cloudAdapter: restartedAdapter
        )
        try await restartedSync.pullAndApplyRemoteMutations()

        XCTAssertEqual(restartedAdapter.lastSincePulled, 42,
                       "restarted SyncEngine must load the persisted bookmark, not default to 0")
    }

    func testLastServerSequenceDefaultsToZeroOnFreshDatabase() async throws {
        // A brand-new database has no sync_state row: first pull must request from 0.
        try await sync.pullAndApplyRemoteMutations()
        XCTAssertEqual(adapter.lastSincePulled, 0)
    }

    // MARK: - Queue pruning (P0.4 / ADR-028)

    private func insertRawQueueRow(
        id: UUID = UUID(),
        type: MutationType = .upsertDocument,
        status: MutationStatus,
        localTimestamp: Date
    ) throws {
        let iso = ISO8601DateFormatter().string(from: localTimestamp)
        try harness.database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, '{}', 'dev', 'user', ?, 0, ?)
                    """,
                arguments: [id.uuidString, type.rawValue, iso, status.rawValue]
            )
        }
    }

    private func queueCount(status: MutationStatus) throws -> Int {
        try harness.database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?",
                arguments: [status.rawValue]
            ) ?? 0
        }
    }

    private func makeSync(
        config: SyncQueuePruneConfig = .default,
        now: Date = Date()
    ) -> SyncEngine {
        SyncEngine(
            database: harness.database,
            documentEngine: harness.engine,
            registry: harness.registry,
            cloudAdapter: adapter,
            pruneConfig: config,
            clock: { now }
        )
    }

    func testPruneRemovesPushedRowsOlderThanRetention() throws {
        let now = Date()
        let engine = makeSync(
            config: SyncQueuePruneConfig(
                pushedRetention: 30 * 86_400,
                appliedRetention: 30 * 86_400,
                pruneInterval: 86_400
            ),
            now: now
        )

        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-31 * 86_400))
        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-1 * 86_400))

        let deleted = try engine.pruneSyncQueue(force: true)

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try queueCount(status: .pushed), 1, "only the fresh .pushed row should remain")
    }

    func testPruneRemovesAppliedRowsOlderThanRetention() throws {
        let now = Date()
        let engine = makeSync(
            config: SyncQueuePruneConfig(
                pushedRetention: 30 * 86_400,
                appliedRetention: 30 * 86_400,
                pruneInterval: 86_400
            ),
            now: now
        )

        try insertRawQueueRow(status: .applied, localTimestamp: now.addingTimeInterval(-60 * 86_400))
        try insertRawQueueRow(status: .applied, localTimestamp: now.addingTimeInterval(-29 * 86_400))

        let deleted = try engine.pruneSyncQueue(force: true)

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try queueCount(status: .applied), 1)
    }

    func testPruneNeverDeletesPendingOrConflictedRows() throws {
        let now = Date()
        let engine = makeSync(now: now)

        // Ancient pending and conflicted rows that would be deleted if the
        // filter were age-only.
        let ancient = now.addingTimeInterval(-365 * 86_400)
        try insertRawQueueRow(status: .pending, localTimestamp: ancient)
        try insertRawQueueRow(status: .conflicted, localTimestamp: ancient)

        _ = try engine.pruneSyncQueue(force: true)

        XCTAssertEqual(try queueCount(status: .pending), 1,
                       "pending rows must survive prune regardless of age")
        XCTAssertEqual(try queueCount(status: .conflicted), 1,
                       "conflicted rows must survive prune regardless of age")
    }

    func testPruneThrottlesWhenCalledWithinInterval() throws {
        let now = Date()
        let engine = makeSync(
            config: SyncQueuePruneConfig(
                pushedRetention: 30 * 86_400,
                appliedRetention: 30 * 86_400,
                pruneInterval: 86_400
            ),
            now: now
        )

        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-40 * 86_400))
        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-41 * 86_400))

        let first = try engine.pruneSyncQueue(force: false)
        XCTAssertEqual(first, 2, "first non-forced prune should run")

        // Add another stale row; a second non-forced call within the interval
        // must be throttled and not touch the queue.
        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-42 * 86_400))

        let second = try engine.pruneSyncQueue(force: false)
        XCTAssertEqual(second, 0, "second non-forced prune within pruneInterval must no-op")
        XCTAssertEqual(try queueCount(status: .pushed), 1,
                       "the row added after the first prune must still be there")
    }

    func testForcePruneBypassesThrottle() throws {
        let now = Date()
        let engine = makeSync(now: now)

        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-60 * 86_400))
        _ = try engine.pruneSyncQueue(force: false)

        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-90 * 86_400))
        let forced = try engine.pruneSyncQueue(force: true)
        XCTAssertEqual(forced, 1, "force: true must bypass the pruneInterval throttle")
    }

    func testPruneWatermarkIsPersistedToSyncState() throws {
        let now = Date()
        let engine = makeSync(now: now)

        _ = try engine.pruneSyncQueue(force: true)

        let stored: String? = try harness.database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT value FROM sync_state WHERE key = ?",
                arguments: ["syncQueuePrunedAt"]
            )?["value"]
        }
        XCTAssertNotNil(stored, "prune must persist a watermark in sync_state")
    }

    func testPushPendingMutationsOpportunisticallyPrunesOldPushedRows() async throws {
        let docType = TestSupport.makeDocType()
        try harness.registry.register(docType)

        let now = Date()
        let engine = makeSync(now: now)

        // Ancient acknowledged row that predates the retention window.
        try insertRawQueueRow(status: .pushed, localTimestamp: now.addingTimeInterval(-60 * 86_400))

        // A fresh local save produces a pending mutation that will be pushed.
        try harness.engine.save(TestSupport.makeDocument(
            id: "prune-push-1",
            fields: ["title": .string("fresh")]
        ))

        try await engine.pushPendingMutations()

        XCTAssertEqual(try queueCount(status: .pushed), 1,
                       "the fresh push should remain; the 60-day-old .pushed row should be pruned")
    }

    func testConflictedRemoteMarksLocalDocumentConflictedWithoutOverwriting() async throws {
        let docType = TestSupport.makeDocType(syncPolicy: SyncPolicy(
            conflictResolution: .versionChecked,
            immutableAfterSubmit: true
        ))
        try harness.registry.register(docType)

        try harness.engine.save(TestSupport.makeDocument(
            id: "conf-1",
            fields: ["title": .string("Local version")]
        ))
        // Bump the local syncVersion to 5 to simulate a version mismatch.
        try harness.database.write { db in
            try db.execute(sql: "UPDATE documents SET syncVersion = 5 WHERE id = ?",
                           arguments: ["conf-1"])
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let remoteDoc = TestSupport.makeDocument(
            id: "conf-1",
            fields: ["title": .string("Remote version")],
            syncVersion: 2
        )
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(remoteDoc),
            deviceId: "peer",
            userId: "peer-user",
            localTimestamp: Date(),
            syncVersion: 2,
            status: .applied
        )

        try await sync.applyRemoteMutations([mutation])

        let fetched = try XCTUnwrap(harness.engine.fetch(docType: "Note", id: "conf-1"))
        XCTAssertEqual(fetched.fields["title"], .string("Local version"),
                       "conflicted remote must not overwrite local fields")
        XCTAssertEqual(fetched.syncState, .conflicted)
    }
}

// MARK: - Stub CloudAdapter

/// Records pushed mutations and serves pre-seeded remote mutations back on pull.
/// Deliberately synchronous-under-the-hood (actor-lite) since tests drive it serially.
final class StubCloudAdapter: CloudAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _pushed: [MutationRecord] = []
    private var _remote: [RemoteMutation] = []
    private var _lastSincePulled: Int64?

    var pushed: [MutationRecord] {
        lock.lock(); defer { lock.unlock() }
        return _pushed
    }

    /// The `serverSequence` argument from the most recent `pullMutations(since:)` call,
    /// or `nil` if the adapter hasn't been pulled from yet.
    var lastSincePulled: Int64? {
        lock.lock(); defer { lock.unlock() }
        return _lastSincePulled
    }

    func enqueueRemote(_ mutations: [RemoteMutation]) {
        lock.lock(); defer { lock.unlock() }
        _remote.append(contentsOf: mutations)
    }

    func pushMutations(_ mutations: [MutationRecord]) async throws -> [SyncAcknowledgement] {
        lock.lock(); defer { lock.unlock() }
        _pushed.append(contentsOf: mutations)
        return mutations.enumerated().map { offset, record in
            SyncAcknowledgement(mutationId: record.id, serverSequence: Int64(_pushed.count - mutations.count + offset + 1))
        }
    }

    func pullMutations(since version: SyncVersion) async throws -> [RemoteMutation] {
        lock.lock(); defer { lock.unlock() }
        _lastSincePulled = version.serverSequence
        return _remote.filter { $0.serverSequence > version.serverSequence }
    }
}
