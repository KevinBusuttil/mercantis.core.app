//
//  NotificationInbox.swift
//  mercantis core
//
//  Phase D / item 13 (ADR-048) — Reader API for the persisted
//  notification_log. Implements the in-app-inbox channel: list a user's
//  notifications, mark them read, count unread.
//

import Foundation
import GRDB

/// One row materialised from `notification_log`. Mirrors
/// `NotificationLogEntry` plus the persistence-specific `readAt` flag
/// that the in-app inbox uses for unread badges.
public struct NotificationInboxItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let appId: String
    public let docType: String
    public let documentId: String
    public let channel: String
    public let recipient: String?
    public let subject: String
    public let body: String
    public let emittedAt: Date
    public let readAt: Date?

    public var isRead: Bool { readAt != nil }
}

/// In-app notification inbox. The "channel" in question is the persisted
/// table itself: every notification a `SQLiteNotificationLog` write
/// produces becomes available here.
public final class NotificationInbox: @unchecked Sendable {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    // MARK: - Reads

    /// All notifications for `recipient`, newest first. Pass `nil` to
    /// retrieve the global feed (entries with no recipient set).
    public func entries(
        forRecipient recipient: String?,
        unreadOnly: Bool = false,
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [NotificationInboxItem] {
        try database.read { db in
            var sql = """
                SELECT id, appId, docType, documentId, channel, recipient,
                       subject, body, emittedAt, readAt
                FROM notification_log
                WHERE
                """
            var args: [any DatabaseValueConvertible] = []
            if let recipient {
                sql += " recipient = ?"
                args.append(recipient)
            } else {
                sql += " recipient IS NULL"
            }
            if unreadOnly {
                sql += " AND readAt IS NULL"
            }
            sql += " ORDER BY emittedAt DESC, id DESC LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(max(offset, 0))

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.compactMap(Self.itemFromRow)
        }
    }

    public func unreadCount(forRecipient recipient: String?) throws -> Int {
        try database.read { db in
            var sql = "SELECT COUNT(*) FROM notification_log WHERE readAt IS NULL AND"
            var args: [any DatabaseValueConvertible] = []
            if let recipient {
                sql += " recipient = ?"
                args.append(recipient)
            } else {
                sql += " recipient IS NULL"
            }
            return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)) ?? 0
        }
    }

    // MARK: - Writes (state transitions)

    public func markRead(id: UUID, at when: Date = Date()) throws {
        let ts = ISO8601DateFormatter().string(from: when)
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE notification_log
                    SET readAt = ?
                    WHERE id = ? AND readAt IS NULL
                    """,
                arguments: [ts, id.uuidString]
            )
        }
    }

    public func markAllRead(forRecipient recipient: String?, at when: Date = Date()) throws {
        let ts = ISO8601DateFormatter().string(from: when)
        try database.write { db in
            if let recipient {
                try db.execute(
                    sql: """
                        UPDATE notification_log
                        SET readAt = ?
                        WHERE recipient = ? AND readAt IS NULL
                        """,
                    arguments: [ts, recipient]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE notification_log
                        SET readAt = ?
                        WHERE recipient IS NULL AND readAt IS NULL
                        """,
                    arguments: [ts]
                )
            }
        }
    }

    /// Hard-delete an inbox item. Used for "swipe to delete" surfaces.
    /// The audit log remains the canonical record of what was sent.
    public func delete(id: UUID) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM notification_log WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Helpers

    private static func itemFromRow(_ row: Row) -> NotificationInboxItem? {
        let idString: String = row["id"] ?? ""
        guard let id = UUID(uuidString: idString) else { return nil }
        let appId: String = row["appId"] ?? ""
        let docType: String = row["docType"] ?? ""
        let documentId: String = row["documentId"] ?? ""
        let channel: String = row["channel"] ?? ""
        let recipient: String? = row["recipient"]
        let subject: String = row["subject"] ?? ""
        let body: String = row["body"] ?? ""
        let emittedAtStr: String = row["emittedAt"] ?? ""
        let readAtStr: String? = row["readAt"]
        let formatter = ISO8601DateFormatter()
        let emittedAt = formatter.date(from: emittedAtStr) ?? Date(timeIntervalSince1970: 0)
        let readAt = readAtStr.flatMap { formatter.date(from: $0) }
        return NotificationInboxItem(
            id: id, appId: appId, docType: docType, documentId: documentId,
            channel: channel, recipient: recipient,
            subject: subject, body: body,
            emittedAt: emittedAt, readAt: readAt
        )
    }
}
