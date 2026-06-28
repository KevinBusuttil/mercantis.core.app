import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// A hierarchical (outline) presentation of a tree DocType's records — e.g. the
/// Chart of Accounts. Parent rows expand to reveal their children, derived from
/// the DocType's self-referential link field: the `.link` field whose
/// `linkedDocType` is the DocType itself (for `Account`, that's
/// `parent_account`). Selecting a row drives the same detail pane the other
/// view modes use.
public struct RecordTreeView: View {

    let docType: DocType
    let documents: [Document]
    let selectedDocumentID: String?
    let onSelect: (Document) -> Void

    public init(
        docType: DocType,
        documents: [Document],
        selectedDocumentID: String?,
        onSelect: @escaping (Document) -> Void
    ) {
        self.docType = docType
        self.documents = documents
        self.selectedDocumentID = selectedDocumentID
        self.onSelect = onSelect
    }

    private struct Node: Identifiable {
        let document: Document
        var children: [Node]?
        var id: String { document.id }
    }

    public var body: some View {
        let roots = buildTree()
        if roots.isEmpty {
            ContentUnavailableView("No records", systemImage: "list.bullet.indent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selectionBinding) {
                OutlineGroup(roots, children: \.children) { node in
                    row(node).tag(node.document.id)
                }
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { selectedDocumentID },
            set: { id in
                if let id, let doc = documents.first(where: { $0.id == id }) { onSelect(doc) }
            }
        )
    }

    private func row(_ node: Node) -> some View {
        let isParent = (node.children?.isEmpty == false)
        return HStack(spacing: 8) {
            Text(title(node.document))
                .font(.system(size: 13, weight: isParent ? .semibold : .regular))
            Spacer(minLength: 8)
            if let code = code(node.document) {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tree construction

    private func buildTree() -> [Node] {
        let parentKey = parentFieldKey
        let ids = Set(documents.map(\.id))
        var childrenByParent: [String: [Document]] = [:]
        var roots: [Document] = []
        for doc in documents {
            if let parentKey,
               let parent = stringValue(doc.fields[parentKey]),
               parent != doc.id,             // ignore a self-parent
               ids.contains(parent) {
                childrenByParent[parent, default: []].append(doc)
            } else {
                roots.append(doc)
            }
        }
        // `childrenByParent` is keyed by a present, in-set parent id, so the
        // recursion only ever descends into real children — a parent cycle
        // simply leaves both nodes out of `roots` rather than looping.
        func node(_ doc: Document) -> Node {
            let kids = (childrenByParent[doc.id] ?? []).sorted(by: order)
            return Node(document: doc, children: kids.isEmpty ? nil : kids.map(node))
        }
        return roots.sorted(by: order).map(node)
    }

    private var parentFieldKey: String? {
        docType.fields.first { $0.type == .link && $0.linkedDocType == docType.id }?.key
    }

    /// Sort by a numeric code field when the DocType has one (so a chart of
    /// accounts orders 1010, 1020, 2010…), otherwise by display title.
    private var sortFieldKey: String? {
        docType.fields.first { $0.key.contains("number") || $0.key.contains("code") }?.key
    }

    private func order(_ a: Document, _ b: Document) -> Bool {
        if let key = sortFieldKey {
            let av = stringValue(a.fields[key]) ?? ""
            let bv = stringValue(b.fields[key]) ?? ""
            if av != bv { return av < bv }
        }
        return title(a).localizedCaseInsensitiveCompare(title(b)) == .orderedAscending
    }

    private func title(_ document: Document) -> String {
        stringValue(document.fields[docType.titleField]) ?? document.id
    }

    private func code(_ document: Document) -> String? {
        guard let key = sortFieldKey, key != docType.titleField else { return nil }
        return stringValue(document.fields[key])
    }

    private func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
