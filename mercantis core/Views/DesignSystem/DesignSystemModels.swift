import SwiftUI
import Observation

@Observable
final class LiquidGlassUIModel {
    var selectedScreen: DesignSystemScreen = .salesOrder
    var selectedOrderID: SalesOrderRecord.ID?
    var salesSearchText: String = ""
    var selectedFilters: Set<OrderFilterChip> = [.orderID]
    var scriptText: String = """
func validateOrder(_ order: SalesOrder) throws {
    guard order.items.isEmpty == false else {
        throw ValidationError(\"Order must include at least one line item\")
    }

    if order.totalAmount <= 0 {
        throw ValidationError(\"Total amount must be positive\")
    }
}
"""

    var orderRecords: [SalesOrderRecord] = SalesOrderRecord.mockRows
    var orderItems: [SalesOrderItem] = SalesOrderItem.mockRows

    init() {
        selectedOrderID = orderRecords.first?.id
    }

    var filteredOrders: [SalesOrderRecord] {
        if salesSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return orderRecords
        }

        let query = salesSearchText.lowercased()
        return orderRecords.filter {
            $0.id.lowercased().contains(query)
                || $0.customer.lowercased().contains(query)
                || $0.status.lowercased().contains(query)
        }
    }

    var selectedOrder: SalesOrderRecord? {
        guard let selectedOrderID else { return nil }
        return orderRecords.first { $0.id == selectedOrderID }
    }

    var subtotal: Double {
        orderItems.reduce(0) { $0 + $1.amount }
    }

    var tax: Double {
        subtotal * 0.15
    }

    var total: Double {
        subtotal + tax
    }
}

enum DesignSystemScreen: String, CaseIterable, Identifiable {
    case salesOrder
    case buildModule
    case doctypeBuilder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salesOrder: return "Sales Order"
        case .buildModule: return "Build Module"
        case .doctypeBuilder: return "Doctype Visual Builder"
        }
    }

    var subtitle: String {
        switch self {
        case .salesOrder: return "Manage customer orders and fulfillment workflows"
        case .buildModule: return "Create and deploy custom ERP components"
        case .doctypeBuilder: return "Design flexible forms with reusable schema blocks"
        }
    }

    var icon: String {
        switch self {
        case .salesOrder: return "dollarsign.circle"
        case .buildModule: return "hammer"
        case .doctypeBuilder: return "doc.text"
        }
    }

    var inspectorTitle: String {
        switch self {
        case .salesOrder: return "Order Details & History"
        case .buildModule: return "Component Details & Deployment"
        case .doctypeBuilder: return "Doctype 'Customer' Configuration"
        }
    }

    var linkedSectionTitle: String {
        switch self {
        case .salesOrder: return "Linked Docs"
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
    case salesOrder = "Sales order"
    case build = "Build"
    case doctypeBuilder = "Doctype Builder"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .salesOrder: return "dollarsign.circle"
        case .build: return "hammer"
        case .doctypeBuilder: return "doc.text"
        }
    }

    var screen: DesignSystemScreen {
        switch self {
        case .salesOrder: return .salesOrder
        case .build: return .buildModule
        case .doctypeBuilder: return .doctypeBuilder
        }
    }
}

enum OrderFilterChip: String, CaseIterable, Identifiable {
    case orderID = "Order ID"
    case customer = "Customer"
    case date = "Date"
    case amount = "Amount"

    var id: String { rawValue }
}

struct SalesOrderRecord: Identifiable, Hashable {
    let id: String
    let customer: String
    let postingDate: Date
    let amount: Double
    let status: String

    static let mockRows: [SalesOrderRecord] = (1...18).map { index in
        SalesOrderRecord(
            id: String(format: "SAL-ORD-2026-%04d", index),
            customer: ["Acme Trading", "Northwind Co.", "Blue Harbor", "Evergreen Retail", "Rivera Supplies"][index % 5],
            postingDate: Calendar.current.date(byAdding: .day, value: -index, to: .now) ?? .now,
            amount: Double(900 + (index * 135)),
            status: index % 4 == 0 ? "Draft" : "Submitted"
        )
    }
}

struct SalesOrderItem: Identifiable, Hashable {
    let id = UUID()
    let itemCode: String
    let itemName: String
    let qty: Double
    let uom: String
    let rate: Double

    var amount: Double { qty * rate }

    static let mockRows: [SalesOrderItem] = [
        SalesOrderItem(itemCode: "ITM-1001", itemName: "Ultra Laptop 14\"", qty: 2, uom: "Nos", rate: 1499),
        SalesOrderItem(itemCode: "ITM-1008", itemName: "Docking Station", qty: 2, uom: "Nos", rate: 189),
        SalesOrderItem(itemCode: "ITM-1042", itemName: "Ergonomic Keyboard", qty: 5, uom: "Nos", rate: 129)
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
