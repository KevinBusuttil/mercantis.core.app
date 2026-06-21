//
//  DocumentTimelineView.swift
//  mercantis core
//
//  UI over the immutable audit log (AuditLog.swift §3.2). Renders a
//  document's history (save / submit / cancel / amend / attach / detach …)
//  as a vertical timeline with per-event field diffs decoded from each
//  audit row's `{ "before": {...}, "after": {...} }` payload.
//
//  Mirrors the Flutter `document_timeline_view.dart` +
//  `document_timeline_panel.dart`. Drop into the record chrome's Timeline
//  tab. The data source is `AuditLogWriter`, whose reader API
//  (`entries(forDocumentId:)`) returns rows oldest-first.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// Renders a document's audit-log history as a timeline. Newest event is
/// shown first.
public struct DocumentTimelineView: View {

    /// The saved document's id. Empty for an unsaved document.
    private let documentId: String
    /// The audit-log reader. `AuditLogWriter` exposes
    /// `entries(forDocumentId:)`, the structured audit source used here.
    private let auditLog: AuditLogWriter

    @State private var entries: [TimelineItem] = []
    @State private var errorMessage: String?

    public init(documentId: String, auditLog: AuditLogWriter) {
        self.documentId = documentId
        self.auditLog = auditLog
    }

    public var body: some View {
        Group {
            if documentId.isEmpty {
                ContentUnavailableView(
                    "Save the document to see activity",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("A timeline of changes appears once this record has been saved.")
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load activity",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock",
                    description: Text("Changes to this record will be recorded here.")
                )
            } else {
                timeline
            }
        }
        .onAppear(perform: reload)
    }

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Timeline")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                    .padding(.bottom, 14)

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                    TimelineRow(item: item, isLast: index == entries.count - 1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        guard !documentId.isEmpty else { return }
        do {
            // Reader returns oldest-first; reverse for newest-first display.
            let raw = try auditLog.entries(forDocumentId: documentId)
            entries = raw.reversed().map(TimelineItem.init(entry:))
            errorMessage = nil
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let item: TimelineItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(MercantisTheme.fillSoft(for: item.tone))
                        .frame(width: 28, height: 28)
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MercantisTheme.tint(for: item.tone))
                }
                if !isLast {
                    Rectangle()
                        .fill(MercantisTheme.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)

                if !item.diffs.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(item.diffs) { diff in
                            FieldDiffRow(diff: diff)
                        }
                    }
                    .padding(.top, 2)
                }

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 18)

            Spacer(minLength: 0)
        }
    }
}

private struct FieldDiffRow: View {
    let diff: FieldDiff

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(diff.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(MercantisTheme.textMuted)
            if let before = diff.before {
                Text(before)
                    .font(.caption.monospaced())
                    .foregroundStyle(MercantisTheme.danger)
                    .strikethrough()
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(MercantisTheme.textTertiary)
            Text(diff.after ?? "—")
                .font(.caption.monospaced())
                .foregroundStyle(MercantisTheme.success)
        }
    }
}

// MARK: - View models

private struct FieldDiff: Identifiable {
    let id = UUID()
    let label: String
    let before: String?
    let after: String?
}

private struct TimelineItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tone: MercantisSemanticTone
    let diffs: [FieldDiff]

    init(entry: AuditLogEntry) {
        self.id = entry.id
        let style = Self.style(forAction: entry.action)
        self.symbol = style.symbol
        self.tone = style.tone
        self.title = style.title

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: entry.timestamp)
        let who = entry.userId.isEmpty ? "system" : entry.userId
        self.subtitle = "\(who) · \(when)"

        self.diffs = Self.decodeDiffs(from: entry.payloadJSON)
    }

    private static func style(forAction action: String) -> (title: String, symbol: String, tone: MercantisSemanticTone) {
        switch action.lowercased() {
        case "save":       return ("Saved", "square.and.pencil", .info)
        case "submit":     return ("Submitted", "paperplane.fill", .success)
        case "cancel":     return ("Cancelled", "xmark.circle", .danger)
        case "amend":      return ("Amended", "arrow.triangle.branch", .warning)
        case "delete":     return ("Deleted", "trash", .danger)
        case "applyremote": return ("Synced from server", "arrow.triangle.2.circlepath", .muted)
        case "attach":     return ("Attached a file", "paperclip", .info)
        case "detach":     return ("Removed a file", "paperclip.badge.ellipsis", .muted)
        case "detachall":  return ("Removed all files", "paperclip.badge.ellipsis", .muted)
        default:           return (action.prefix(1).uppercased() + action.dropFirst(), "circle.fill", .muted)
        }
    }

    /// Decode the `{ "before": {fieldMap}, "after": {fieldMap} }` payload
    /// written by `AuditLogWriter.append(... before:after:)` into a list of
    /// human-readable field diffs. Non-diff payloads (e.g. attachment
    /// summaries) decode to an empty list and just show the title.
    private static func decodeDiffs(from json: String) -> [FieldDiff] {
        guard let data = json.data(using: .utf8) else { return [] }
        struct Wrapper: Decodable {
            let before: [String: FieldValue]?
            let after: [String: FieldValue]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let wrapper = try? decoder.decode(Wrapper.self, from: data) else { return [] }

        let before = wrapper.before ?? [:]
        let after = wrapper.after ?? [:]
        let keys = Set(before.keys).union(after.keys).sorted()

        return keys.compactMap { key in
            let b = before[key]
            let a = after[key]
            let bStr = b.map(Self.display)
            let aStr = a.map(Self.display)
            // Skip keys that didn't actually change.
            if bStr == aStr { return nil }
            return FieldDiff(label: Self.humanLabel(key), before: bStr, after: aStr)
        }
    }

    private static func display(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s.isEmpty ? "—" : s
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "—"
        case .date(let d), .dateTime(let d):
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return f.string(from: d)
        case .data(let d):   return "<\(d.count) bytes>"
        case .array(let xs): return xs.map(display).joined(separator: ", ")
        }
    }

    /// Humanise a snake_case / camelCase key into a label.
    private static func humanLabel(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        var spaced = ""
        for (i, ch) in key.enumerated() {
            if ch == "_" {
                spaced += " "
            } else if ch.isUppercase, i > 0 {
                spaced += " "
                spaced.append(ch)
            } else {
                spaced.append(ch)
            }
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
