//
//  NavigationShell.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

@MainActor
final class UIShellRouter: ObservableObject {
    @Published var selectedSection: NavigationSection? = .home
    @Published var setupDestination: SetupDestination = .overview

    func showSetupOverview() {
        selectedSection = .setup
        setupDestination = .overview
    }

    func openNewDocType() {
        selectedSection = .setup
        setupDestination = .newDocType
    }

    func openVisualBuilder() {
        selectedSection = .setup
        setupDestination = .visualBuilder
    }
}

enum SetupDestination: Hashable {
    case overview
    case newDocType
    case visualBuilder
}

/// The top-level navigation shell for Mercantis Core.
///
/// On macOS and iPad it uses a `NavigationSplitView` with a sidebar.
/// On iPhone it uses a tab bar.
public struct NavigationShell: View {

    @EnvironmentObject private var router: UIShellRouter
    @State private var showCommandBar = false

    public init() {}

    public var body: some View {
        #if os(iOS)
        iPhoneLayout
        #else
        desktopLayout
        #endif
    }

    // MARK: - Desktop / iPad Layout

    private var desktopLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView(for: router.selectedSection)
        }
        .overlay(alignment: .top) {
            if showCommandBar {
                CommandBarView(isPresented: $showCommandBar)
                    .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mercantisOpenCommandBar)) { _ in
            showCommandBar = true
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        TabView(selection: $router.selectedSection) {
            detailView(for: .home)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(NavigationSection.home as NavigationSection?)

            detailView(for: .inbox)
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(NavigationSection.inbox as NavigationSection?)

            detailView(for: .search)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(NavigationSection.search as NavigationSection?)

            detailView(for: .modules)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag(NavigationSection.modules as NavigationSection?)

            detailView(for: .settings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(NavigationSection.settings as NavigationSection?)

            detailView(for: .setup)
                .tabItem { Label("Setup", systemImage: "wrench.and.screwdriver") }
                .tag(NavigationSection.setup as NavigationSection?)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationSection.allCases, selection: $router.selectedSection) { section in
            Label(section.title, systemImage: section.icon)
                .tag(section)
        }
        .navigationTitle("Mercantis")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showCommandBar.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailView(for section: NavigationSection?) -> some View {
        switch section {
        case .home:
            Text("Home")
                .navigationTitle("Home")
        case .inbox:
            Text("Inbox")
                .navigationTitle("Inbox")
        case .search:
            CommandBarView(isPresented: $showCommandBar)
        case .modules:
            Text("Modules")
                .navigationTitle("Modules")
        case .reports:
            Text("Reports")
                .navigationTitle("Reports")
        case .settings:
            Text("Settings")
                .navigationTitle("Settings")
        case .setup:
            setupDetailView
        case nil:
            Text("Select a section")
        }
    }

    @ViewBuilder
    private var setupDetailView: some View {
        switch router.setupDestination {
        case .overview:
            DocTypeListView()
                .navigationTitle("Setup")
        case .newDocType:
            DocTypeBuilderView {
                router.showSetupOverview()
            }
            .navigationTitle("New DocType")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to Setup") {
                        router.showSetupOverview()
                    }
                }
            }
        case .visualBuilder:
            FormBuilderView {
                router.showSetupOverview()
            }
            .navigationTitle("Visual Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to Setup") {
                        router.showSetupOverview()
                    }
                }
            }
        }
    }
}

// MARK: - Navigation Section

public enum NavigationSection: String, CaseIterable, Hashable, Identifiable {
    case home, inbox, search, modules, reports, settings, setup

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .inbox:    return "Inbox"
        case .search:   return "Search"
        case .modules:  return "Modules"
        case .reports:  return "Reports"
        case .settings: return "Settings"
        case .setup:    return "Setup"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house"
        case .inbox:    return "tray"
        case .search:   return "magnifyingglass"
        case .modules:  return "square.grid.2x2"
        case .reports:  return "chart.bar"
        case .settings: return "gear"
        case .setup:    return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mercantisOpenCommandBar = Notification.Name("mercantis.openCommandBar")
}
