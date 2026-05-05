//
//  NamingCounterBlockReserver.swift
//  mercantis core
//
//  Phase B §3.7 (ADR-042) — Per-device counter range reservation. Closes
//  the multi-device offline collision flagged in ADR-014's open follow-up:
//  two devices saving Sales Invoices offline would both pick `SINV-2026-0001`
//  if they shared a single counter row. Each device now reserves a
//  contiguous block of N counter values from the shared `naming_counters`
//  allocator and issues out of its own block until exhausted, then claims
//  a fresh block.
//
//  This is purely a *local* offline-correctness fix. The shared
//  `naming_counters` row still needs CRDT-style merge semantics on sync —
//  see `CloudAdapter` follow-up in ADR-014/ADR-018.
//

import Foundation
import GRDB

/// Reserves and issues sequential counter values per `(seriesKey, deviceId)`
/// pair. Issued values within a series are unique across devices because
/// each device draws from a disjoint block.
///
/// The default `blockSize` (50) keeps single-device behaviour visually
/// identical to the legacy single-row path: device A's first three saves
/// produce values `1, 2, 3`. Multi-device tests that want collision-free
/// numbering should construct the reserver per device.
public struct NamingCounterBlockReserver {

    public static let defaultBlockSize: Int = 50

    private let database: MercantisDatabase
    private let blockSize: Int

    public init(database: MercantisDatabase, blockSize: Int = NamingCounterBlockReserver.defaultBlockSize) {
        self.database = database
        self.blockSize = max(blockSize, 1)
    }

    /// Reserve and return the next counter value for `(seriesKey, deviceId)`.
    /// Atomic: the block reservation, the local block advance, and the
    /// returned value all commit in a single write transaction.
    public func reserve(seriesKey: String, deviceId: String) throws -> Int {
        try database.write { db in
            // Fast path: an existing block has spare capacity.
            if let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT blockStart, blockEnd, nextValue
                    FROM naming_counter_blocks
                    WHERE seriesKey = ? AND deviceId = ?
                    """,
                arguments: [seriesKey, deviceId]
            ),
            let nextValue: Int = row["nextValue"],
            let blockEnd: Int = row["blockEnd"],
            nextValue <= blockEnd {
                let issued = nextValue
                try db.execute(
                    sql: """
                        UPDATE naming_counter_blocks
                        SET nextValue = ?
                        WHERE seriesKey = ? AND deviceId = ?
                        """,
                    arguments: [issued + 1, seriesKey, deviceId]
                )
                return issued
            }

            // Slow path: claim a fresh block by advancing the shared allocator.
            try db.execute(
                sql: """
                    INSERT INTO naming_counters (seriesKey, value) VALUES (?, ?)
                    ON CONFLICT(seriesKey) DO UPDATE SET value = value + ?
                    """,
                arguments: [seriesKey, blockSize, blockSize]
            )
            let advancedRow = try Row.fetchOne(
                db,
                sql: "SELECT value FROM naming_counters WHERE seriesKey = ?",
                arguments: [seriesKey]
            )
            let advanced: Int = advancedRow?["value"] ?? blockSize
            let blockStart = advanced - blockSize + 1
            let blockEnd = advanced
            let issued = blockStart

            try db.execute(
                sql: """
                    INSERT INTO naming_counter_blocks
                        (seriesKey, deviceId, blockStart, blockEnd, nextValue)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(seriesKey, deviceId) DO UPDATE SET
                        blockStart = excluded.blockStart,
                        blockEnd   = excluded.blockEnd,
                        nextValue  = excluded.nextValue
                    """,
                arguments: [seriesKey, deviceId, blockStart, blockEnd, issued + 1]
            )
            return issued
        }
    }

    // MARK: - Inspection (test / diagnostics)

    public struct BlockState: Sendable, Equatable {
        public let blockStart: Int
        public let blockEnd: Int
        public let nextValue: Int
        /// Number of values still issuable from the current block.
        public var remaining: Int { max(blockEnd - nextValue + 1, 0) }
    }

    /// Return the device's current block state for `seriesKey`, or `nil`
    /// if the device has never reserved against this series.
    public func currentBlock(seriesKey: String, deviceId: String) throws -> BlockState? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT blockStart, blockEnd, nextValue
                    FROM naming_counter_blocks
                    WHERE seriesKey = ? AND deviceId = ?
                    """,
                arguments: [seriesKey, deviceId]
            ) else { return nil }
            let start: Int = row["blockStart"] ?? 0
            let end: Int = row["blockEnd"] ?? 0
            let next: Int = row["nextValue"] ?? 0
            return BlockState(blockStart: start, blockEnd: end, nextValue: next)
        }
    }
}
