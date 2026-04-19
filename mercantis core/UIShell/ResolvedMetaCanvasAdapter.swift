import Foundation

struct CanvasSectionViewModel: Identifiable, Hashable {
    let id: String
    let title: String
    let groups: [CanvasGroupViewModel]
}

struct CanvasGroupViewModel: Identifiable, Hashable {
    let id: String
    let title: String
    let fields: [CanvasFieldViewModel]
}

struct CanvasFieldViewModel: Identifiable, Hashable {
    let id: String
    let key: String
    let label: String
    let type: FieldType
    let isRequired: Bool
    let readOnlyExpression: String?
}

enum ResolvedMetaCanvasAdapter {
    static func project(_ meta: ResolvedMeta) -> [CanvasSectionViewModel] {
        var orderedSectionKeys: [String] = []
        var orderedGroupKeysBySection: [String: [String]] = [:]
        var fieldsBySectionGroup: [String: [String: [CanvasFieldViewModel]]] = [:]

        for field in meta.fields {
            let sectionKey = normalizedSection(for: field)
            let groupKey = normalizedGroup(for: field)

            if !orderedSectionKeys.contains(sectionKey) {
                orderedSectionKeys.append(sectionKey)
            }

            if orderedGroupKeysBySection[sectionKey] == nil {
                orderedGroupKeysBySection[sectionKey] = []
            }
            if orderedGroupKeysBySection[sectionKey]?.contains(groupKey) != true {
                orderedGroupKeysBySection[sectionKey]?.append(groupKey)
            }

            let projectedField = CanvasFieldViewModel(
                id: field.key,
                key: field.key,
                label: field.label,
                type: field.type,
                isRequired: field.isRequired,
                readOnlyExpression: field.readOnlyExpression
            )
            fieldsBySectionGroup[sectionKey, default: [:]][groupKey, default: []].append(projectedField)
        }

        return orderedSectionKeys.map { sectionKey in
            let groupKeys = orderedGroupKeysBySection[sectionKey] ?? []
            let groups = groupKeys.map { groupKey in
                CanvasGroupViewModel(
                    id: "\(sectionKey)::\(groupKey)",
                    title: groupKey,
                    fields: fieldsBySectionGroup[sectionKey]?[groupKey] ?? []
                )
            }
            return CanvasSectionViewModel(
                id: sectionKey,
                title: sectionKey,
                groups: groups
            )
        }
    }

    private static func normalizedSection(for field: ResolvedFieldDefinition) -> String {
        let trimmed = field.section?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Main" : trimmed
    }

    private static func normalizedGroup(for field: ResolvedFieldDefinition) -> String {
        columnGroupTitle(forColumn: field.column)
    }

    /// Returns the canvas group title derived from a field column hint.
    ///
    /// A nil/zero column maps to the primary group, while positive values map
    /// to `Column N`. Shared between adapter projection and inspector labels.
    static func columnGroupTitle(forColumn column: Int?) -> String {
        guard let column, column > 0 else {
            return "Primary"
        }
        return "Column \(column)"
    }
}
