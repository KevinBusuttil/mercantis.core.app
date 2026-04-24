//
//  SchedulerPersistence.swift
//  mercantis core
//
//  P1.4 — Persists each scheduled task's last-run timestamp so the
//  launch-time due-check survives process restarts.
//

import Foundation
import GRDB

/// SQLite-backed `lastRun` store for `SchedulerService`. (P1.4, §4.13)
///
/// One row per task key in the `scheduler_state` table (created by
/// migration v6). Reads / writes are routed through `MercantisDatabase` so
/// they share the same `DatabasePool` as every other Core write — no
/// independent connection lifecycle to worry about.
public final class SchedulerPersistence: @unchecked Sendable {

    private let database: MercantisDatabase
    private let isoFormatter: ISO8601DateFormatter

    public init(database: MercantisDatabase) {
        self.database = database
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = f
    }

    /// Last time the task with `key` ran, or `nil` if it has never run on
    /// this device. Persistence read failures degrade to `nil` rather than
    /// throw — the scheduler treats that the same as "never run", which
    /// triggers a conservative immediate fire on next due-check.
    public func lastRun(forKey key: String) -> Date? {
        do {
            return try database.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT lastRunAt FROM scheduler_state WHERE taskKey = ?",
                    arguments: [key]
                )
                guard let raw: String = row?["lastRunAt"] else { return nil }
                return self.parse(raw)
            }
        } catch {
            return nil
        }
    }

    /// Snapshot of every persisted last-run timestamp. Used by the service
    /// at boot so it can decide which tasks fell behind while the app was
    /// closed without N round-trips to SQLite.
    public func loadAll() -> [String: Date] {
        do {
            return try database.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT taskKey, lastRunAt FROM scheduler_state")
                var out: [String: Date] = [:]
                for row in rows {
                    if let key: String = row["taskKey"],
                       let raw: String = row["lastRunAt"],
                       let parsed = self.parse(raw) {
                        out[key] = parsed
                    }
                }
                return out
            }
        } catch {
            return [:]
        }
    }

    /// Record that the task with `key` ran at `at`. Upserts the row, so a
    /// missing-task and an existing-task call both resolve in one statement.
    public func recordRun(key: String, at: Date) {
        let stamp = isoFormatter.string(from: at)
        do {
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO scheduler_state (taskKey, lastRunAt) VALUES (?, ?)
                        ON CONFLICT(taskKey) DO UPDATE SET lastRunAt = excluded.lastRunAt
                        """,
                    arguments: [key, stamp]
                )
            }
        } catch {
            // Persistence failure is non-fatal: the in-memory `lastRun` map
            // inside `SchedulerService` still advances, so this process keeps
            // a sane cadence. A fresh process restart could re-fire the task
            // — preferred over silently losing it.
        }
    }

    /// Remove the persisted last-run row for `key`. Used when a single task
    /// is deregistered. Failures are silent for the same reason as
    /// `recordRun(key:at:)`.
    public func clear(key: String) {
        do {
            try database.write { db in
                try db.execute(
                    sql: "DELETE FROM scheduler_state WHERE taskKey = ?",
                    arguments: [key]
                )
            }
        } catch {
            // See `recordRun(key:at:)`.
        }
    }

    /// Remove every persisted last-run row whose key starts with
    /// `appPrefix` — the scheduler composes keys as `appId::declarationId`,
    /// so this drops every task belonging to one app on uninstall.
    public func clear(appPrefix: String) {
        let likePattern = appPrefix + "::%"
        do {
            try database.write { db in
                try db.execute(
                    sql: "DELETE FROM scheduler_state WHERE taskKey LIKE ?",
                    arguments: [likePattern]
                )
            }
        } catch {
            // See `recordRun(key:at:)`.
        }
    }

    // MARK: - Parsing

    private func parse(_ raw: String) -> Date? {
        // The writer always emits fractional-seconds ISO-8601, but accept a
        // plain ISO-8601 string too for forward-compat with hand-written
        // rows in tests.
        if let parsed = isoFormatter.date(from: raw) {
            return parsed
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}
