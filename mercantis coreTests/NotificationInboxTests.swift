//
//  NotificationInboxTests.swift
//  mercantis coreTests
//
//  Phase D / item 13 (ADR-048) — SQLiteNotificationLog persistence +
//  NotificationInbox reader API. Composite + channel-filtered sinks.
//

import XCTest
import GRDB
@testable import mercantis_core

final class NotificationInboxTests: XCTestCase {

    private var harness: TestSupport.Harness!
    private var sink: SQLiteNotificationLog!
    private var inbox: NotificationInbox!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
        sink = SQLiteNotificationLog(database: harness.database)
        inbox = NotificationInbox(database: harness.database)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        sink = nil
        inbox = nil
        harness = nil
    }

    private func entry(
        recipient: String? = "alice",
        channel: String = "default",
        subject: String = "Hello",
        body: String = "Body",
        emittedAt: Date = Date()
    ) -> NotificationLogEntry {
        NotificationLogEntry(
            appId: "app.test",
            docType: "Note",
            documentId: "n1",
            channel: channel,
            recipient: recipient,
            subject: subject,
            body: body,
            emittedAt: emittedAt
        )
    }

    // MARK: - Persistence

    func testSinkPersistsEntriesAcrossReaderQueries() throws {
        sink.write(entry(subject: "First"))
        sink.write(entry(subject: "Second"))

        let items = try inbox.entries(forRecipient: "alice")
        XCTAssertEqual(items.count, 2)
        // Ordered newest first; both saved within the same instant so
        // either order is acceptable — check membership instead.
        XCTAssertEqual(Set(items.map(\.subject)), ["First", "Second"])
    }

    func testInboxFiltersByRecipient() throws {
        sink.write(entry(recipient: "alice", subject: "For Alice"))
        sink.write(entry(recipient: "bob",   subject: "For Bob"))

        let alice = try inbox.entries(forRecipient: "alice")
        XCTAssertEqual(alice.map(\.subject), ["For Alice"])

        let bob = try inbox.entries(forRecipient: "bob")
        XCTAssertEqual(bob.map(\.subject), ["For Bob"])
    }

    func testInboxNullRecipientIsItsOwnFeed() throws {
        sink.write(entry(recipient: nil, subject: "Broadcast"))
        sink.write(entry(recipient: "alice", subject: "Alice only"))

        let global = try inbox.entries(forRecipient: nil)
        XCTAssertEqual(global.map(\.subject), ["Broadcast"])
    }

    // MARK: - Read state

    func testUnreadCountAndMarkRead() throws {
        sink.write(entry(subject: "1"))
        sink.write(entry(subject: "2"))
        sink.write(entry(subject: "3"))

        XCTAssertEqual(try inbox.unreadCount(forRecipient: "alice"), 3)

        let items = try inbox.entries(forRecipient: "alice")
        try inbox.markRead(id: items[0].id)
        XCTAssertEqual(try inbox.unreadCount(forRecipient: "alice"), 2)

        let unread = try inbox.entries(forRecipient: "alice", unreadOnly: true)
        XCTAssertEqual(unread.count, 2)
        XCTAssertFalse(unread.contains(where: { $0.id == items[0].id }))
    }

    func testMarkAllReadClearsUnreadCount() throws {
        sink.write(entry(subject: "a"))
        sink.write(entry(subject: "b"))

        try inbox.markAllRead(forRecipient: "alice")
        XCTAssertEqual(try inbox.unreadCount(forRecipient: "alice"), 0)
    }

    func testDeleteRemovesEntryFromInbox() throws {
        sink.write(entry(subject: "to-delete"))
        let items = try inbox.entries(forRecipient: "alice")
        XCTAssertEqual(items.count, 1)

        try inbox.delete(id: items[0].id)
        XCTAssertTrue(try inbox.entries(forRecipient: "alice").isEmpty)
    }

    // MARK: - Composite + channel filter

    func testCompositeFansOutToEverySink() throws {
        let memory = InMemoryNotificationLog()
        let composite = CompositeNotificationLog(sinks: [sink, memory])
        composite.write(entry(subject: "Both"))

        XCTAssertEqual(try inbox.entries(forRecipient: "alice").count, 1)
        XCTAssertEqual(memory.entries.count, 1)
    }

    func testChannelFilterDropsNonMatchingEntries() throws {
        let emailMemory = InMemoryNotificationLog()
        let emailOnly = ChannelFilteredNotificationLog(
            channels: ["email"], downstream: emailMemory
        )
        emailOnly.write(entry(channel: "email", subject: "✉️"))
        emailOnly.write(entry(channel: "push", subject: "📱"))

        XCTAssertEqual(emailMemory.entries.count, 1)
        XCTAssertEqual(emailMemory.entries.first?.subject, "✉️")
    }

    func testInsertIsIdempotentByPrimaryKey() throws {
        let dup = entry(subject: "Once")
        sink.write(dup)
        sink.write(dup)
        XCTAssertEqual(try inbox.entries(forRecipient: "alice").count, 1)
    }
}
