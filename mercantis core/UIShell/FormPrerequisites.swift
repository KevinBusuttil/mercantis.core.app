import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// A master-data record type that must exist before a document can reference
/// it — e.g. a Sales Invoice needs at least one Customer and one Item.
struct MissingPrerequisite: Identifiable, Equatable {
    let targetDocType: String
    let displayName: String
    var id: String { targetDocType }
}

/// Works out which master records a DocType depends on that don't exist yet, so
/// the form can tell a new user "add a Customer and an Item first" instead of
/// letting them fill a whole document and hit a wall of required-field errors on
/// Save. Looks at the DocType's required link fields plus the required link
/// columns of its child tables (the line-item `item`, etc.).
enum FormPrerequisites {

    static func missing(
        for docType: DocType,
        childDocType: (String) -> DocType?,
        isTargetEmpty: (String) -> Bool,
        displayName: (String) -> String?
    ) -> [MissingPrerequisite] {
        var result: [MissingPrerequisite] = []
        var seen = Set<String>()

        func consider(_ target: String?) {
            guard let target, !target.isEmpty, !seen.contains(target) else { return }
            seen.insert(target)
            guard isTargetEmpty(target) else { return }
            result.append(MissingPrerequisite(targetDocType: target, displayName: displayName(target) ?? target))
        }

        for field in docType.fields where field.required && (field.type == .link || field.type == .dynamicLink) {
            consider(field.linkedDocType)
        }
        // Required link columns inside child tables (e.g. a line's `item`): you
        // can't add a single row until that master has at least one record.
        for field in docType.fields where field.type == .table {
            guard let child = field.childDocType.flatMap(childDocType) else { continue }
            for column in child.fields where column.required && (column.type == .link || column.type == .dynamicLink) {
                consider(column.linkedDocType)
            }
        }
        return result
    }

    /// "Customer", "Customer and Item", "Customer, Item and Currency".
    static func phrase(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

/// Non-blocking banner shown above a create/edit form when the document depends
/// on master data that doesn't exist yet. Purely informational — it points the
/// user at what to set up first rather than blocking the form.
struct PrerequisiteBanner: View {
    let docTypeName: String
    let missing: [MissingPrerequisite]

    var body: some View {
        if !missing.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(MercantisTheme.brandPrimary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up your basics first")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
                    Text("Before you can save a \(docTypeName), add at least one \(FormPrerequisites.phrase(missing.map(\.displayName))). You can do that from the matching workspace in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MercantisTheme.brandPrimarySoft, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
