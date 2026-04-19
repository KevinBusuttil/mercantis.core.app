import SwiftUI

struct AppSidebar: View {
    @Binding var selectedScreen: DesignSystemScreen

    var body: some View {
        List(selection: $selectedScreen) {
            Section("Categories") {
                ForEach(SidebarCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Workspaces") {
                ForEach(SidebarModule.allCases) { module in
                    Button {
                        selectedScreen = module.screen
                    } label: {
                        Label(module.rawValue, systemImage: module.icon)
                    }
                    .buttonStyle(.plain)
                }

                Label("Dashboards", systemImage: "rectangle.3.group")
                    .foregroundStyle(.secondary)
                Label("Reports", systemImage: "chart.bar")
                    .foregroundStyle(.secondary)
                Label("Setup", systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .listStyle(.sidebar)
        .navigationTitle("Mercantis Design Lab")
    }
}

#Preview("Light") {
    AppSidebar(selectedScreen: .constant(.workspaceRecords))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppSidebar(selectedScreen: .constant(.buildModule))
        .preferredColorScheme(.dark)
}
