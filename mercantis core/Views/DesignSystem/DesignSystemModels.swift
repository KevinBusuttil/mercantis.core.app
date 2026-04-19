import SwiftUI
import Observation

@Observable
final class LiquidGlassUIModel {
    var selectedScreen: DesignSystemScreen = .workspaceRecords
    var selectedRecordID: WorkspaceRecord.ID?
    var searchText: String = ""
    var selectedFilters: Set<RecordFilterChip> = [.recordID]
    var scriptText: String = """
func validateWorkspaceRecord(_ record: WorkspaceRecord) throws {
    guard record.items.isEmpty == false else {
        throw ValidationError(\"Record must include at least one item\")
    }

    if record.total <= 0 {
        throw ValidationError(\"Total must be positive\")
    }
}
"""

    var records: [WorkspaceRecord] = WorkspaceRecord.mockRows
    var recordItems: [WorkspaceItem] = WorkspaceItem.mockRows

    init() {
        selectedRecordID = records.first?.id
    }

    var filteredRecords: [WorkspaceRecord] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return records
        }

        let query = searchText.lowercased()
        return records.filter {
            $0.id.lowercased().contains(query)
                || $0.title.lowercased().contains(query)
                || $0.status.lowercased().contains(query)
        }
    }

    var selectedRecord: WorkspaceRecord? {
        guard let selectedRecordID else { return nil }
        return records.first { $0.id == selectedRecordID }
    }

    var subtotal: Double {
        recordItems.reduce(0) { $0 + $1.amount }
    }

    var tax: Double {
        subtotal * 0.15
    }

    var total: Double {
        subtotal + tax
    }
}

enum DesignSystemScreen: String, CaseIterable, Identifiable {
    case workspaceRecords
    case buildModule
    case doctypeBuilder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaceRecords: return "Workspace Records"
        case .buildModule: return "Build Module"
        case .doctypeBuilder: return "DocType Visual Builder"
        }
    }

    var subtitle: String {
        switch self {
        case .workspaceRecords: return "Review platform records, tasks, and statuses"
        case .buildModule: return "Create and deploy Core platform components"
        case .doctypeBuilder: return "Design reusable metadata schema blocks"
        }
    }

    var icon: String {
        switch self {
        case .workspaceRecords: return "list.bullet.rectangle.portrait"
        case .buildModule: return "hammer"
        case .doctypeBuilder: return "doc.text"
        }
    }

    var inspectorTitle: String {
        switch self {
        case .workspaceRecords: return "Record Details & Activity"
        case .buildModule: return "Component Details & Deployment"
        case .doctypeBuilder: return "DocType 'Workspace' Configuration"
        }
    }

    var linkedSectionTitle: String {
        switch self {
        case .workspaceRecords: return "Linked Resources"
        case .buildModule: return "Linked Code"
        case .doctypeBuilder: return "Linked Code"
        }
    }
}

enum SidebarCategory: String, CaseIterable, Identifiable {
    case starred = "Starred"
    case workspace = "Workspace"
    case inbox = "Inbox"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .starred: return "star"
        case .workspace: return "square.grid.2x2"
        case .inbox: return "tray"
        }
    }
}

enum SidebarModule: String, CaseIterable, Identifiable {
    case records = "Records"
    case build = "Build"
    case doctypeBuilder = "DocType Builder"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .records: return "list.bullet.rectangle.portrait"
        case .build: return "hammer"
        case .doctypeBuilder: return "doc.text"
        }
    }

    var screen: DesignSystemScreen {
        switch self {
        case .records: return .workspaceRecords
        case .build: return .buildModule
        case .doctypeBuilder: return .doctypeBuilder
        }
    }
}

enum RecordFilterChip: String, CaseIterable, Identifiable {
    case recordID = "Record ID"
    case owner = "Owner"
    case date = "Date"
    case amount = "Amount"

    var id: String { rawValue }
}

struct WorkspaceRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let updatedAt: Date
    let amount: Double
    let status: String

    static let mockRows: [WorkspaceRecord] = {
        let titles = ["Core Setup Review", "Permissions Audit", "Workflow Update", "Sync Health Check", "Dashboard Refresh"]
        return (1...18).map { index -> WorkspaceRecord in
            let id = String(format: "WRK-REC-2026-%04d", index)
            let title = titles[index % titles.count]
            let updatedAt = Calendar.current.date(byAdding: .day, value: -index, to: .now) ?? .now
            let amount = Double(900 + (index * 135))
            let status = index % 4 == 0 ? "Draft" : "Submitted"
            return WorkspaceRecord(
                id: id,
                title: title,
                updatedAt: updatedAt,
                amount: amount,
                status: status
            )
        }
    }()
}

struct WorkspaceItem: Identifiable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let quantity: Double
    let unit: String
    let rate: Double

    var amount: Double { quantity * rate }

    static let mockRows: [WorkspaceItem] = [
        WorkspaceItem(code: "CMP-1001", name: "DocType Schema Review", quantity: 2, unit: "hrs", rate: 149),
        WorkspaceItem(code: "CMP-1008", name: "Dashboard Wiring", quantity: 2, unit: "hrs", rate: 89),
        WorkspaceItem(code: "CMP-1042", name: "Workflow Validation", quantity: 5, unit: "hrs", rate: 129)
    ]
}

struct TimelineStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let date: String
    let isComplete: Bool
}

struct TimelineEvent: Identifiable, Hashable {
    let id = UUID()
    let author: String
    let text: String
    let date: String
}

struct LinkedResource: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
}
