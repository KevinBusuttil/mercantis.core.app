//
//  NotificationInboxView.swift
//  mercantis core
//
//  Feature-parity port of the Flutter `NotificationInboxView`
//  (`mercantis_core_ui/lib/src/widgets/notification_inbox_view.dart`). Reader
//  UI over the in-app notification inbox (ADR-048): lists a recipient's
//  notifications with unread styling, tap-to-mark-read, "Mark all read", and
//  swipe-to-delete.
//
//  Backed by `NotificationInbox` (`Notifications/NotificationInbox.swift`).
//  That reader API is synchronous + throwing (GRDB), so this view loads entries
//  into `@State` and reloads after every mutation rather than observing a
//  publisher. The host supplies the inbox via `init`; wiring is described in
//  `CORE_VIEWS_WIRING.md`.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct NotificationInboxView: View {

    /// The inbox reader. Held as a plain reference (the type is a `final class`,
    /// not an `ObservableObject`); this view drives its own reload state.
    private let inbox: NotificationInbox
    /// Whose feed to show. `nil` = the global (unaddressed) feed, matching the
    /// inbox's `recipient: nil` semantics.
    private let recipient: String?

    @State private var items: [NotificationInboxItem] = []
    @State private var loadError: String?
    @State private var hasLoaded = false

    public init(inbox: NotificationInbox, recipient: String? = nil) {
        self.inbox = inbox
        self.recipient = recipient
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(MercantisTheme.background)
        .navigationTitle("Inbox")
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                reload()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Notifications")
                .font(.title3.weight(.semibold))
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .mercantisSemanticBadge(tone: .brand)
            }
            Spacer()
            Button("Mark all read", systemImage: "checkmark.circle") {
                markAllRead()
            }
            .buttonStyle(MercantisSecondaryButtonStyle())
            .disabled(unreadCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Couldn't load notifications", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") { reload() }
                    .buttonStyle(MercantisSecondaryButtonStyle())
            }
        } else if items.isEmpty {
            ContentUnavailableView(
                "No notifications",
                systemImage: "bell.slash",
                description: Text("You're all caught up.")
            )
        } else {
            List {
                ForEach(items) { item in
                    NotificationInboxRow(item: item) {
                        markRead(item)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - State

    private var unreadCount: Int {
        items.lazy.filter { !$0.isRead }.count
    }

    // MARK: - Actions

    private func reload() {
        do {
            items = try inbox.entries(forRecipient: recipient)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func markRead(_ item: NotificationInboxItem) {
        guard !item.isRead else { return }
        do {
            try inbox.markRead(id: item.id)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func markAllRead() {
        do {
            try inbox.markAllRead(forRecipient: recipient)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ item: NotificationInboxItem) {
        do {
            try inbox.delete(id: item.id)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// One inbox row. Unread rows show a filled dot + bold subject (mirroring the
/// Flutter `ListTile` styling) and a tap target that marks the row read.
private struct NotificationInboxRow: View {
    let item: NotificationInboxItem
    let onMarkRead: () -> Void

    var body: some View {
        Button(action: { if !item.isRead { onMarkRead() } }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isRead ? "bell" : "circle.fill")
                    .font(item.isRead ? .body : .system(size: 10))
                    .foregroundStyle(item.isRead ? Color.secondary : MercantisTheme.accent)
                    .frame(width: 18, alignment: .center)
                    .padding(.top, item.isRead ? 0 : 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(subjectText)
                        .font(.body)
                        .fontWeight(item.isRead ? .regular : .semibold)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Text(Self.formatted(item.emittedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isRead)
    }

    private var subjectText: String {
        item.subject.isEmpty ? "(no subject)" : item.subject
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func formatted(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
