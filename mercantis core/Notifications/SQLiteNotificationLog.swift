//
//  SQLiteNotificationLog.swift
//  mercantis core
//
//  Phase D / item 13 (ADR-048) — Persistent NotificationLogWriter backed
//  by the v11 `notification_log` table. Replaces `InMemoryNotificationLog`
//  for production deployments where the in-app inbox needs entries to
//  survive a process restart.
//

import Foundation
import GRDB

/// `NotificationLogWriter` that persists each entry to the
/// `notification_log` table. Pair with `NotificationInbox` to read and
/// mark-as-read from the same table.
public final class SQLiteNotificationLog: NotificationLogWriter, @unchecked Sendable {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    public func write(_ entry: NotificationLogEntry) {
        let ts = ISO8601DateFormatter().string(from: entry.emittedAt)
        try? database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO notification_log
                        (id, appId, docType, documentId, channel, recipient,
                         subject, body, emittedAt, readAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(id) DO NOTHING
                    """,
                arguments: [
                    entry.id.uuidString,
                    entry.appId,
                    entry.docType,
                    entry.documentId,
                    entry.channel,
                    entry.recipient,
                    entry.subject,
                    entry.body,
                    ts
                ]
            )
        }
    }
}

/// Fanout writer that delivers each entry to every wrapped sink in order.
/// Lets a host app pair `SQLiteNotificationLog` (persistence) with extra
/// channels (a console logger, a future email adapter, etc.) without
/// touching the handler protocol.
public final class CompositeNotificationLog: NotificationLogWriter, @unchecked Sendable {

    private let sinks: [NotificationLogWriter]

    public init(sinks: [NotificationLogWriter]) {
        self.sinks = sinks
    }

    public func write(_ entry: NotificationLogEntry) {
        for sink in sinks {
            sink.write(entry)
        }
    }
}

/// Channel sink that routes entries to a `NotificationLogWriter` only when
/// the entry's `channel` matches one of the configured channel ids. Used
/// to plug per-channel adapters (email, push, webhook) into the broader
/// notification pipeline.
public final class ChannelFilteredNotificationLog: NotificationLogWriter, @unchecked Sendable {

    private let allowedChannels: Set<String>
    private let downstream: NotificationLogWriter

    public init(channels: Set<String>, downstream: NotificationLogWriter) {
        self.allowedChannels = channels
        self.downstream = downstream
    }

    public func write(_ entry: NotificationLogEntry) {
        guard allowedChannels.contains(entry.channel) else { return }
        downstream.write(entry)
    }
}
