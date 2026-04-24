//
//  AutomationSinks.swift
//  mercantis core
//
//  P1.2 — Side-effect sinks for `SendNotificationHandler` and `AssignHandler`.
//
//  Notifications and assignments are not yet persisted in Core. ADR-019 calls
//  for `NotificationLog` rows, but there is no `notification_log` /
//  `assignment_log` table today, and adding one before the consumers exist is
//  premature. For P1.2 the handlers write to an in-memory sink so the runtime
//  is observable in tests and at runtime, and a future migration can swap the
//  default for a persistent writer without changing the handler protocol.
//

import Foundation

// MARK: - Notification Log

/// One log entry produced by `SendNotificationHandler`.
public struct NotificationLogEntry: Sendable, Equatable {
    public let id: UUID
    public let appId: String
    public let docType: String
    public let documentId: String
    public let channel: String
    public let recipient: String?
    public let subject: String
    public let body: String
    public let emittedAt: Date

    public init(
        id: UUID = UUID(),
        appId: String,
        docType: String,
        documentId: String,
        channel: String,
        recipient: String?,
        subject: String,
        body: String,
        emittedAt: Date
    ) {
        self.id = id
        self.appId = appId
        self.docType = docType
        self.documentId = documentId
        self.channel = channel
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.emittedAt = emittedAt
    }
}

/// Sink for `SendNotificationHandler`. Implementations may log, persist,
/// or fan out to transports. The default (`InMemoryNotificationLog`) records
/// entries for inspection and is safe to use in tests.
public protocol NotificationLogWriter: AnyObject, Sendable {
    func write(_ entry: NotificationLogEntry)
}

/// Thread-safe in-memory notification sink. Records every entry in the
/// order `write(...)` was called.
public final class InMemoryNotificationLog: NotificationLogWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [NotificationLogEntry] = []

    public init() {}

    public var entries: [NotificationLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _entries.removeAll()
    }

    public func write(_ entry: NotificationLogEntry) {
        lock.lock()
        _entries.append(entry)
        lock.unlock()
    }
}

// MARK: - Assignment Log

/// One log entry produced by `AssignHandler`.
public struct AssignmentLogEntry: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case user(String)
        case role(String)
    }

    public let id: UUID
    public let appId: String
    public let docType: String
    public let documentId: String
    public let target: Target
    public let note: String?
    public let assignedBy: String
    public let assignedAt: Date

    public init(
        id: UUID = UUID(),
        appId: String,
        docType: String,
        documentId: String,
        target: Target,
        note: String?,
        assignedBy: String,
        assignedAt: Date
    ) {
        self.id = id
        self.appId = appId
        self.docType = docType
        self.documentId = documentId
        self.target = target
        self.note = note
        self.assignedBy = assignedBy
        self.assignedAt = assignedAt
    }
}

/// Sink for `AssignHandler`. Implementations may persist, notify, or ignore.
public protocol AssignmentLogWriter: AnyObject, Sendable {
    func write(_ entry: AssignmentLogEntry)
}

/// Thread-safe in-memory assignment sink. Default for tests and for runtime
/// use until a persistent assignment store is introduced.
public final class InMemoryAssignmentLog: AssignmentLogWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [AssignmentLogEntry] = []

    public init() {}

    public var entries: [AssignmentLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _entries.removeAll()
    }

    public func write(_ entry: AssignmentLogEntry) {
        lock.lock()
        _entries.append(entry)
        lock.unlock()
    }
}
