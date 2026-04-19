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

            Section("Modules") {
                ForEach(SidebarModule.allCases) { module in
                    Button {
                        selectedScreen = module.screen
                    } label: {
                        Label(module.rawValue, systemImage: module.icon)
                    }
                    .buttonStyle(.plain)
                }

                Label("Accounts", systemImage: "creditcard")
                    .foregroundStyle(.secondary)
                Label("Customers", systemImage: "person.2")
                    .foregroundStyle(.secondary)
                Label("Profile", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Label("Shipping", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .listStyle(.sidebar)
        .navigationTitle("Mercantis ERP")
    }
}

#Preview("Light") {
    AppSidebar(selectedScreen: .constant(.salesOrder))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppSidebar(selectedScreen: .constant(.buildModule))
        .preferredColorScheme(.dark)
}
