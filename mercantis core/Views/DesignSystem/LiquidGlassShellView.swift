import SwiftUI
import Observation
#if os(macOS)
import AppKit
#endif

struct LiquidGlassShellView: View {
    @State private var model = LiquidGlassUIModel()
    @State private var isInspectorPresented = true

    var body: some View {
        @Bindable var bindableModel = model

        NavigationSplitView {
            AppSidebar(selectedScreen: $bindableModel.selectedScreen)
                .frame(minWidth: 220)
        } detail: {
            Group {
                switch model.selectedScreen {
                case .salesOrder:
                    SalesOrderScreen(model: model)
                case .buildModule:
                    BuildModuleScreen(model: model)
                case .doctypeBuilder:
                    DoctypeVisualBuilderScreen()
                }
            }
            .background(DesignSystemPalette.windowBackground)
            .toolbar(id: "main-toolbar") {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button {
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .keyboardShortcut("i", modifiers: .command)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button("Assignee View", systemImage: "person") {}
                        Button("List View", systemImage: "list.bullet") {}
                        Button("Column View", systemImage: "rectangle.split.3x1") {}
                        Button("Sidebar View", systemImage: "sidebar.right") {}
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    ForEach(["person", "list.bullet", "rectangle.split.3x1", "sidebar.right"], id: \.self) { icon in
                        Button {
                        } label: {
                            Image(systemName: icon)
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPane(
                title: model.selectedScreen.inspectorTitle,
                linkedTitle: model.selectedScreen.linkedSectionTitle
            )
            .frame(minWidth: 280)
        }
        .background(.regularMaterial)
    }

    private func toggleSidebar() {
        #if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        #endif
    }
}

private struct SalesOrderScreen: View {
    @Bindable var model: LiquidGlassUIModel

    @State private var showMain = true
    @State private var showCurrency = true
    @State private var showItems = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SearchField(text: $model.salesSearchText)

                FilterChipRow(selected: $model.selectedFilters)

                SectionCard {
                    Table(model.filteredOrders, selection: $model.selectedOrderID) {
                        TableColumn("Order") { order in
                            Text(order.id)
                        }
                        TableColumn("Customer") { order in
                            Text(order.customer)
                        }
                        TableColumn("Date") { order in
                            Text(order.postingDate, style: .date)
                        }
                        TableColumn("Amount") { order in
                            Text(order.amount, format: .currency(code: "USD"))
                        }
                        TableColumn("Status") { order in
                            StatusBadge(text: order.status)
                        }
                    }
                    .frame(minHeight: 280)
                }

                if let order = model.selectedOrder {
                    SectionCard {
                        DisclosureGroup("Main Information", isExpanded: $showMain) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Customer", value: order.customer)
                                LabeledContent("Posting Date") {
                                    Text(order.postingDate, style: .date)
                                }
                                LabeledContent("Delivery Date") {
                                    Text(order.postingDate.addingTimeInterval(172800), style: .date)
                                }
                                LabeledContent("Warehouse", value: "Central Warehouse")
                            }
                            .padding(.top, 8)
                        }
                    }

                    SectionCard {
                        DisclosureGroup("Currency & Price List", isExpanded: $showCurrency) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Currency", value: "USD")
                                LabeledContent("Price List", value: "Standard Selling")
                            }
                            .padding(.top, 8)
                        }
                    }

                    SectionCard {
                        DisclosureGroup("Items", isExpanded: $showItems) {
                            VStack(alignment: .leading, spacing: 12) {
                                Table(model.orderItems) {
                                    TableColumn("Item Code", value: \.itemCode)
                                    TableColumn("Item Name", value: \.itemName)
                                    TableColumn("Qty") { item in
                                        Text(item.qty, format: .number)
                                    }
                                    TableColumn("UOM", value: \.uom)
                                    TableColumn("Rate") { item in
                                        Text(item.rate, format: .currency(code: "USD"))
                                    }
                                    TableColumn("Amount") { item in
                                        Text(item.amount, format: .currency(code: "USD"))
                                    }
                                }
                                .frame(minHeight: 180)

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Subtotal: \(model.subtotal, format: .currency(code: "USD"))")
                                    Text("Tax: \(model.tax, format: .currency(code: "USD"))")
                                    Text("Total: \(model.total, format: .currency(code: "USD"))")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.top, 8)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Amend") {}
                            .buttonStyle(.bordered)
                        Button("Cancel") {}
                            .buttonStyle(.bordered)
                        Button("Create Delivery Note") {}
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                    }
                } else {
                    ContentUnavailableView("No matching orders", systemImage: "magnifyingglass")
                }
            }
            .padding(24)
        }
        .searchable(text: $model.salesSearchText, placement: .toolbar, prompt: "Search orders")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sales Order")
                .font(.largeTitle.weight(.bold))
            Text("Review customer transactions, pricing, and fulfillment details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BuildModuleScreen: View {
    @Bindable var model: LiquidGlassUIModel

    private let cards: [(icon: String, title: String, description: String)] = [
        ("doc.badge.plus", "Create Doctype", "Create structured metadata schemas for documents."),
        ("square.grid.2x2", "Create Workspace", "Bundle tools and records into a team workspace."),
        ("chart.bar.doc.horizontal", "Create Report", "Build analytics views and SQL reports."),
        ("curlybraces", "Create Script", "Add server or client scripts for custom logic.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Build Module")
                        .font(.largeTitle.weight(.bold))
                    Text("Create custom components and deploy updates")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(cards, id: \.title) { card in
                        ActionCard(icon: card.icon, title: card.title, description: card.description) {}
                    }
                }

                CodeEditorCard(text: $model.scriptText)

                HStack(spacing: 12) {
                    Button("Save Changes") {}
                        .buttonStyle(.bordered)
                    Button("Preview Component") {}
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                }
            }
            .padding(24)
        }
    }
}

private struct DoctypeVisualBuilderScreen: View {
    @State private var basicExpanded = true
    @State private var contactExpanded = true
    @State private var financialExpanded = true
    @State private var addressExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Doctype Visual Builder")
                        .font(.largeTitle.weight(.bold))
                    Text("Compose metadata-driven forms with visual schema groups")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    FieldPaletteList()
                        .frame(width: 250)

                    ZStack(alignment: .topTrailing) {
                        SectionCard {
                            VStack(alignment: .leading, spacing: 12) {
                                formGroup(title: "Basic Info", isExpanded: $basicExpanded, fields: ["Customer ID", "Customer Name"])
                                formGroup(title: "Contact Details", isExpanded: $contactExpanded, fields: ["Email", "Phone"])
                                formGroup(title: "Financial Info", isExpanded: $financialExpanded, fields: ["Credit Limit", "Payment Terms"])
                                formGroup(title: "Address", isExpanded: $addressExpanded, fields: ["Street", "City", "Country"])
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .background(
                                DottedGrid()
                                    .foregroundStyle(.quaternary)
                            )
                        }

                        FieldPropertyPopover()
                            .padding(20)
                    }
                }
            }
            .padding(24)
        }
    }

    private func formGroup(title: String, isExpanded: Binding<Bool>, fields: [String]) -> some View {
        DisclosureGroup(title, isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields, id: \.self) { field in
                    Text(field)
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 6)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        )
        .draggable(title)
    }
}

private struct DottedGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 14

        var y: CGFloat = 0
        while y <= rect.height {
            var x: CGFloat = 0
            while x <= rect.width {
                path.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                x += spacing
            }
            y += spacing
        }

        return path
    }
}

#Preview("Light") {
    LiquidGlassShellView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LiquidGlassShellView()
        .preferredColorScheme(.dark)
}
