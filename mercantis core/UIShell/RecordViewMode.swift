import Foundation
#if canImport(MercantisCore)
import MercantisCore
#endif

public enum RecordViewMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case list
    case browse
    case tree
    case detail

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .list: return "List"
        case .browse: return "Browse"
        case .tree: return "Tree"
        case .detail: return "Detail"
        }
    }
}

public struct RecordCollectionViewConfiguration: Hashable {
    public let supportedViewModes: [RecordViewMode]
    public let defaultViewMode: RecordViewMode

    public init(
        supportedViewModes: [RecordViewMode] = RecordViewMode.allCases,
        defaultViewMode: RecordViewMode = .list
    ) {
        let normalizedSupported = supportedViewModes.isEmpty ? [.list] : supportedViewModes
        self.supportedViewModes = normalizedSupported
        self.defaultViewMode = normalizedSupported.contains(defaultViewMode) ? defaultViewMode : normalizedSupported[0]
    }
}
