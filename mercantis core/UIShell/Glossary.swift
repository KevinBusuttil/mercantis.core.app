import SwiftUI

/// One plain-language definition of a domain term ("Fiscal Year", "Submit",
/// "Cost Center"). `summary` is the one-line gloss shown first; `detail` is an
/// optional longer explanation shown beneath it.
public struct GlossaryEntry: Identifiable, Hashable {
    public let term: String
    public let summary: String
    public let detail: String?

    public var id: String { term.lowercased() }

    public init(term: String, summary: String, detail: String? = nil) {
        self.term = term
        self.summary = summary
        self.detail = detail
    }
}

/// A small, case-insensitive registry of domain terms. The host (Hub) builds one
/// and injects it through the environment; UI shells look terms up to decorate
/// jargon labels and lifecycle controls with a "?" that explains them.
public struct Glossary: Equatable {
    private let byKey: [String: GlossaryEntry]

    public init(_ entries: [GlossaryEntry] = []) {
        var map: [String: GlossaryEntry] = [:]
        for entry in entries { map[Self.normalize(entry.term)] = entry }
        self.byKey = map
    }

    /// Look a term up, ignoring case, surrounding whitespace, and any trailing
    /// parenthetical qualifier — so "Debit To (Receivable)" still finds
    /// "Receivable" when only the concept is registered.
    public func lookup(_ term: String) -> GlossaryEntry? {
        let key = Self.normalize(term)
        if let hit = byKey[key] { return hit }
        // Try the label with any "(…)" qualifier stripped, then the qualifier
        // itself (e.g. resolve "Receivable" out of "Debit To (Receivable)").
        if let open = term.firstIndex(of: "(") {
            let head = Self.normalize(String(term[..<open]))
            if let hit = byKey[head] { return hit }
            if let close = term.firstIndex(of: ")"), term.index(after: open) < close {
                let inner = Self.normalize(String(term[term.index(after: open)..<close]))
                if let hit = byKey[inner] { return hit }
            }
        }
        // Strip a common leading qualifier so "Default Tax Code" / "Source
        // Warehouse" resolve to their concept ("Tax Code" / "Warehouse").
        for prefix in ["default ", "source ", "standard ", "required "] where key.hasPrefix(prefix) {
            if let hit = byKey[String(key.dropFirst(prefix.count))] { return hit }
        }
        return nil
    }

    public var all: [GlossaryEntry] {
        byKey.values.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }

    public var isEmpty: Bool { byKey.isEmpty }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Environment

private struct GlossaryKey: EnvironmentKey {
    static let defaultValue = Glossary()
}

public extension EnvironmentValues {
    /// The domain glossary, injected at app scope. Defaults to an empty glossary
    /// so views that look terms up simply render no help when none is wired.
    var glossary: Glossary {
        get { self[GlossaryKey.self] }
        set { self[GlossaryKey.self] = newValue }
    }
}

// MARK: - Inline "?" affordance

/// A small "?" button that explains a single term in a popover. Renders nothing
/// when the term isn't in the environment glossary, so it's safe to attach
/// next to any label without first checking.
public struct GlossaryInfoButton: View {
    @Environment(\.glossary) private var glossary
    @State private var isShowing = false

    let term: String
    public init(_ term: String) { self.term = term }

    public var body: some View {
        if let entry = glossary.lookup(term) {
            Button {
                isShowing = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.small)
                    .foregroundStyle(MercantisTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help(entry.summary)
            .accessibilityLabel(Text("What is \(entry.term)?"))
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                GlossaryEntryCard(entry: entry)
            }
        }
    }
}

/// Popover body for a single glossary term.
private struct GlossaryEntryCard: View {
    let entry: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.term)
                .font(.headline)
                .foregroundStyle(MercantisTheme.textPrimary)
            Text(entry.summary)
                .font(.callout)
                .foregroundStyle(MercantisTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

public extension View {
    /// Trailing "?" affordance for a term, laid out inline after the content.
    func glossaryHelp(_ term: String) -> some View {
        HStack(spacing: 4) {
            self
            GlossaryInfoButton(term)
        }
    }
}

// MARK: - Browser

/// A searchable list of every glossary term — a standalone "what do these words
/// mean?" reference the host can present from a Help menu or window.
public struct GlossaryBrowserView: View {
    @Environment(\.glossary) private var glossary
    @State private var query = ""

    public init() {}

    private var entries: [GlossaryEntry] {
        let all = glossary.all
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.term.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || ($0.detail?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search terms", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(MercantisTheme.surface)
            Divider()

            if glossary.isEmpty {
                ContentUnavailableView("No glossary terms",
                                       systemImage: "character.book.closed",
                                       description: Text("Domain terms haven't been registered for this app."))
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.term).font(.system(size: 14, weight: .semibold))
                        Text(entry.summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = entry.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .navigationTitle("Glossary")
    }
}
