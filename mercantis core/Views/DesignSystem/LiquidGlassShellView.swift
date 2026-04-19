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
                case .workspaceRecords:
                    WorkspaceRecordsScreen(model: model)
                case .buildModule:
                    BuildModuleScreen(model: model)
                case .doctypeBuilder:
                    DoctypeVisualBuilderScreen()
                }
            }
            .background(DesignSystemPalette.windowBackground)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
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

private struct WorkspaceRecordsScreen: View {
    @Bindable var model: LiquidGlassUIModel

    @State private var showMain = true
    @State private var showCurrency = true
    @State private var showItems = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SearchField(text: $model.searchText)

                FilterChipRow(selected: $model.selectedFilters)

                SectionCard {
                    Table(model.filteredRecords, selection: $model.selectedRecordID) {
                        TableColumn("Record") { record in
                            Text(record.id)
                        }
                        TableColumn("Title") { record in
                            Text(record.title)
                        }
                        TableColumn("Updated") { record in
                            Text(record.updatedAt, style: .date)
                        }
                        TableColumn("Effort") { record in
                            Text(record.amount, format: .currency(code: "USD"))
                        }
                        TableColumn("Status") { record in
                            StatusBadge(text: record.status)
                        }
                    }
                    .frame(minHeight: 280)
                }

                if let record = model.selectedRecord {
                    SectionCard {
                        DisclosureGroup("Main Information", isExpanded: $showMain) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Title", value: record.title)
                                LabeledContent("Updated At") {
                                    Text(record.updatedAt, style: .date)
                                }
                                LabeledContent("Review Date") {
                                    Text(
                                        Calendar.current.date(byAdding: .day, value: 2, to: record.updatedAt) ?? record.updatedAt,
                                        style: .date
                                    )
                                }
                                LabeledContent("Workspace", value: "Core Studio")
                            }
                            .padding(.top, 8)
                        }
                    }

                    SectionCard {
                        DisclosureGroup("Metrics", isExpanded: $showCurrency) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Currency", value: "USD")
                                LabeledContent("Profile", value: "Standard")
                            }
                            .padding(.top, 8)
                        }
                    }

                    SectionCard {
                        DisclosureGroup("Items", isExpanded: $showItems) {
                            VStack(alignment: .leading, spacing: 12) {
                                Table(model.recordItems) {
                                    TableColumn("Code", value: \.code)
                                    TableColumn("Name", value: \.name)
                                    TableColumn("Qty") { item in
                                        Text(item.quantity, format: .number)
                                    }
                                    TableColumn("Unit", value: \.unit)
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
                        Button("Review") {}
                            .buttonStyle(.bordered)
                        Button("Archive") {}
                            .buttonStyle(.bordered)
                        Button("Open Builder") {}
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                    }
                } else {
                    ContentUnavailableView("No matching records", systemImage: "magnifyingglass")
                }
            }
            .padding(24)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search records")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace Records")
                .font(.largeTitle.weight(.bold))
            Text("Review platform records, status updates, and linked metadata")
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
                    Text("Create custom platform components and deploy updates")
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
                    Button("Preview Module") {}
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
                                formGroup(title: "Basic Info", isExpanded: $basicExpanded, fields: ["Record ID", "Record Name"])
                                formGroup(title: "Ownership", isExpanded: $contactExpanded, fields: ["Owner", "Team"])
                                formGroup(title: "Metrics", isExpanded: $financialExpanded, fields: ["Threshold", "Status"])
                                formGroup(title: "Context", isExpanded: $addressExpanded, fields: ["Workspace", "Module", "DocType"])
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
