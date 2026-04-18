//
//  NavigationShell.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

final class UIShellRouter: ObservableObject {
    @Published var selectedSection: NavigationSection? = .home
    @Published var setupDestination: SetupDestination = .overview
    @Published var selectedModule: String?
    @Published var selectedItem: WorkspaceSelection?

    func showSetupOverview() {
        selectedSection = .setup
        setupDestination = .overview
        selectedItem = .setup
    }

    func openNewDocType() {
        selectedSection = .setup
        setupDestination = .newDocType
        selectedItem = .setup
    }

    func openVisualBuilder() {
        selectedSection = .setup
        setupDestination = .visualBuilder
        selectedItem = .setup
    }

    func openModule(_ module: String) {
        selectedSection = .home
        selectedModule = module
    }

    func openDocType(_ docTypeId: String, module: String?) {
        selectedSection = .home
        selectedModule = module
        selectedItem = .docType(docTypeId)
    }

    func openReport(_ reportId: String, module: String?) {
        selectedSection = .reports
        selectedModule = module
        selectedItem = .report(reportId)
    }

    func openDashboard(_ dashboardId: String, module: String?) {
        selectedSection = .dashboards
        selectedModule = module
        selectedItem = .dashboard(dashboardId)
    }
}

enum SetupDestination: Hashable {
    case overview
    case newDocType
    case visualBuilder
}

enum WorkspaceSelection: Hashable {
    case docType(String)
    case report(String)
    case dashboard(String)
    case setup
}

/// The top-level navigation shell for Mercantis Core.
public struct NavigationShell: View {

    @EnvironmentObject private var router: UIShellRouter
    @EnvironmentObject private var tooling: DocTypeToolingContext

    @State private var showCommandBar = false
    @State private var isSetupExpanded = false
    @State private var activeDocument: Document?
    @State private var recents: [RecentDestination] = []

    public init() {}

    public var body: some View {
        Group {
            if usesSplitShell {
                splitShell
            } else {
                iPhoneShell
            }
        }
        .onAppear {
            if router.selectedModule == nil {
                router.selectedModule = moduleNames.first
            }
        }
    }

    private var usesSplitShell: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        true
        #endif
    }

    // MARK: - Split Shell (macOS + iPad)

    private var splitShell: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailColumn
        }
        .overlay(alignment: .top) {
            if showCommandBar {
                CommandBarView(
                    isPresented: $showCommandBar,
                    actions: commandBarActions
                )
                .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mercantisOpenCommandBar)) { _ in
            showCommandBar = true
        }
    }

    private var sidebar: some View {
        List {
            ForEach(splitSections, id: \.self) { section in
                if section == .setup {
                    setupSidebarSection
                } else {
                    Button {
                        selectSection(section)
                    } label: {
                        Label(section.title, systemImage: section.icon)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(sidebarRowBackground(isActive: router.selectedSection == section))
                }
            }
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

    @ViewBuilder
    private var detailColumn: some View {
        switch router.selectedItem {
        case .docType(let id):
            docTypeDetail(docTypeId: id)
        case .report(let id):
            reportDetail(reportId: id)
        case .dashboard(let id):
            dashboardDetail(dashboardId: id)
        case .setup:
            setupDetailView
        case nil:
            switch router.selectedSection {
            case .home, .modules:
                homeDetail
            case .reports:
                reportBrowser
            case .dashboards:
                dashboardBrowser
            case .recents:
                recentsBrowser
            case .settings:
                settingsContext
            case .inbox:
                inboxContext
            case .setup:
                setupDetailView
            default:
                homeDetail
            }
        }
    }

    private var moduleBrowser: some View {
        List(selection: $router.selectedModule) {
            ForEach(moduleNames, id: \.self) { module in
                Section(module) {
                    Button {
                        router.openModule(module)
                    } label: {
                        Label(module, systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)

                    ForEach(docTypes(in: module), id: \.id) { docType in
                        Button {
                            router.openDocType(docType.id, module: module)
                            addRecent(.docType(docType.id))
                        } label: {
                            Label(docType.name, systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(reports(in: module), id: \.id) { report in
                        Button {
                            router.openReport(report.id, module: module)
                            addRecent(.report(report.id))
                        } label: {
                            Label(report.name, systemImage: "chart.bar.doc.horizontal")
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(dashboards(in: module), id: \.id) { dashboard in
                        Button {
                            router.openDashboard(dashboard.id, module: module)
                            addRecent(.dashboard(dashboard.id))
                        } label: {
                            Label(dashboard.name, systemImage: "rectangle.3.group")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Workspace")
    }

    private var reportBrowser: some View {
        List(tooling.reports, id: \.id) { report in
            Button {
                router.openReport(report.id, module: moduleForReport(report))
                addRecent(.report(report.id))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.name)
                    Text(report.docType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Reports")
    }

    private var dashboardBrowser: some View {
        List(tooling.dashboards, id: \.id) { dashboard in
            Button {
                router.openDashboard(dashboard.id, module: moduleForDashboard(dashboard))
                addRecent(.dashboard(dashboard.id))
            } label: {
                Text(dashboard.name)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Dashboards")
    }

    private var recentsBrowser: some View {
        List(recents, id: \.id) { recent in
            Button {
                openRecent(recent)
            } label: {
                Label(recent.title(using: tooling), systemImage: recent.icon)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Recents")
    }

    private var setupSidebarSection: some View {
        Group {
            Button {
                isSetupExpanded.toggle()
                if router.selectedSection != .setup {
                    router.showSetupOverview()
                }
            } label: {
                HStack {
                    Label(NavigationSection.setup.title, systemImage: NavigationSection.setup.icon)
                    Spacer()
                    Image(systemName: isSetupExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(sidebarRowBackground(isActive: router.selectedSection == .setup))

            if isSetupExpanded {
                setupSidebarSubItem(
                    title: "Setup Home",
                    icon: "house",
                    isActive: router.setupDestination == .overview,
                    action: router.showSetupOverview
                )
                setupSidebarSubItem(
                    title: "New DocType",
                    icon: "hammer",
                    isActive: router.setupDestination == .newDocType,
                    action: router.openNewDocType
                )
                setupSidebarSubItem(
                    title: "Visual Builder",
                    icon: "wand.and.stars",
                    isActive: router.setupDestination == .visualBuilder,
                    action: router.openVisualBuilder
                )
            }
        }
    }

    private var settingsContext: some View {
        List {
            Label("Metadata-Driven UI", systemImage: "checkmark.seal")
            Label("Sync Engine", systemImage: "arrow.triangle.2.circlepath")
            Label("Workspace Settings", systemImage: "gear")
        }
        .navigationTitle("Settings")
    }

    private var inboxContext: some View {
        List {
            Label("Workflow Approvals", systemImage: "tray")
            Label("Mentions", systemImage: "at")
            Label("System Alerts", systemImage: "bell")
        }
        .navigationTitle("Inbox")
    }

    private var homeDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                quickCreateSection
                shortcutsSection
                recentsSection
            }
            .padding()
        }
        .background(MercantisTheme.background)
        .navigationTitle("Desk")
    }

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Create").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(tooling.docTypes.prefix(8), id: \.id) { docType in
                    Button("New \(docType.name)") {
                        router.openDocType(docType.id, module: docType.module)
                        activeDocument = tooling.createDraftDocument(for: docType)
                        addRecent(.docType(docType.id))
                    }
                    .buttonStyle(MercantisSecondaryButtonStyle())
                }
            }
        }
        .mercantisCard()
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pinned Modules").font(.headline)
            ForEach(moduleNames.prefix(6), id: \.self) { module in
                Button {
                    router.openModule(module)
                } label: {
                    Label(module, systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
            }
        }
        .mercantisCard()
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.headline)
            if recents.isEmpty {
                Text("No recent activity yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recents.prefix(8), id: \.id) { recent in
                    Button {
                        openRecent(recent)
                    } label: {
                        Label(recent.title(using: tooling), systemImage: recent.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mercantisCard()
    }

    @ViewBuilder
    private func docTypeDetail(docTypeId: String) -> some View {
        if let docType = tooling.docType(withId: docTypeId) {
            let documents = tooling.listDocuments(docTypeId: docType.id)
            HStack(spacing: 0) {
                GenericListView(
                    docType: docType,
                    documents: documents,
                    onSelect: { document in
                        activeDocument = document
                        addRecent(.record(docTypeId: docType.id, documentId: document.id))
                    },
                    onCreate: {
                        activeDocument = tooling.createDraftDocument(for: docType)
                        addRecent(.docType(docType.id))
                    }
                )
                .frame(minWidth: 400, maxWidth: .infinity)

                Divider()

                if let activeDocument {
                    VStack(alignment: .leading, spacing: 10) {
                        GenericFormView(docType: docType, document: bindingForActiveDocument)
                        HStack {
                            Spacer()
                            Button("Save") {
                                try? tooling.saveDocument(activeDocument)
                            }
                            .buttonStyle(MercantisPrimaryButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .frame(minWidth: 380, maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Select a record to view details")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(docType.name)
        } else {
            Text("DocType not found")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reportDetail(reportId: String) -> some View {
        if let report = tooling.report(withId: reportId),
           let result = tooling.executeReport(report) {
            List {
                Section {
                    Text("\(result.rowCount) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { index, column in
                            HStack {
                                Text(column)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(row[index] ?? "—")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(report.name)
        } else {
            ContentUnavailableView("Report unavailable", systemImage: "chart.bar")
        }
    }

    @ViewBuilder
    private func dashboardDetail(dashboardId: String) -> some View {
        if let dashboard = tooling.dashboard(withId: dashboardId) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(dashboard.widgets.enumerated()), id: \.offset) { _, widget in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(widget.title)
                                .font(.headline)
                            if let docType = widget.docType {
                                Text("\(tooling.listDocuments(docTypeId: docType).count) records")
                                    .foregroundStyle(.secondary)
                                Button("Open \(docType)") {
                                    router.openDocType(docType, module: tooling.docType(withId: docType)?.module)
                                }
                                .buttonStyle(MercantisSecondaryButtonStyle())
                            } else if let reportId = widget.reportId {
                                Button("Open Report") {
                                    router.openReport(reportId, module: tooling.report(withId: reportId).flatMap(moduleForReport))
                                }
                                .buttonStyle(MercantisSecondaryButtonStyle())
                            } else {
                                Text(widget.type.capitalized)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .mercantisCard()
                    }
                }
                .padding()
            }
            .navigationTitle(dashboard.name)
        } else {
            ContentUnavailableView("Dashboard unavailable", systemImage: "rectangle.3.group")
        }
    }

    @ViewBuilder
    private var setupDetailView: some View {
        switch router.setupDestination {
        case .overview:
            DocTypeListView()
                .navigationTitle("Setup")
        case .newDocType:
            DocTypeBuilderView(onSave: handleSetupWorkspaceSaved)
                .navigationTitle("New DocType")
                .toolbar { setupBackToOverviewToolbar }
        case .visualBuilder:
            FormBuilderView(onSave: handleSetupWorkspaceSaved)
                .navigationTitle("Visual Builder")
                .toolbar { setupBackToOverviewToolbar }
        }
    }

    // MARK: - iPhone Shell

    private var iPhoneShell: some View {
        TabView(selection: $router.selectedSection) {
            NavigationStack {
                phoneHome
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(NavigationSection.home as NavigationSection?)

            NavigationStack {
                CommandBarView(
                    isPresented: .constant(true),
                    actions: commandBarActions,
                    showsCancel: false
                )
                .padding()
                .navigationTitle("Search")
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(NavigationSection.search as NavigationSection?)

            NavigationStack {
                inboxContext
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(NavigationSection.inbox as NavigationSection?)

            NavigationStack {
                recentsBrowser
            }
            .tabItem { Label("Recents", systemImage: "clock") }
            .tag(NavigationSection.recents as NavigationSection?)

            NavigationStack {
                phoneMore
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(NavigationSection.more as NavigationSection?)
        }
    }

    private var phoneHome: some View {
        List {
            Section("Modules") {
                ForEach(moduleNames, id: \.self) { module in
                    NavigationLink(module) {
                        phoneModuleDetail(module: module)
                    }
                }
            }
            Section("Reports") {
                ForEach(tooling.reports.prefix(8), id: \.id) { report in
                    NavigationLink(report.name) {
                        reportDetail(reportId: report.id)
                    }
                }
            }
            Section("Dashboards") {
                ForEach(tooling.dashboards.prefix(8), id: \.id) { dashboard in
                    NavigationLink(dashboard.name) {
                        dashboardDetail(dashboardId: dashboard.id)
                    }
                }
            }
        }
        .navigationTitle("Desk")
    }

    private func phoneModuleDetail(module: String) -> some View {
        List {
            Section("DocTypes") {
                ForEach(docTypes(in: module), id: \.id) { docType in
                    NavigationLink(docType.name) {
                        docTypeDetail(docTypeId: docType.id)
                    }
                }
            }
            Section("Reports") {
                ForEach(reports(in: module), id: \.id) { report in
                    NavigationLink(report.name) {
                        reportDetail(reportId: report.id)
                    }
                }
            }
            Section("Dashboards") {
                ForEach(dashboards(in: module), id: \.id) { dashboard in
                    NavigationLink(dashboard.name) {
                        dashboardDetail(dashboardId: dashboard.id)
                    }
                }
            }
        }
        .navigationTitle(module)
    }

    private var phoneMore: some View {
        List {
            NavigationLink("Modules", value: MoreDestination.modules)
            NavigationLink("Reports", value: MoreDestination.reports)
            NavigationLink("Dashboards", value: MoreDestination.dashboards)
            NavigationLink("Setup", value: MoreDestination.setup)
            NavigationLink("Settings", value: MoreDestination.settings)
        }
        .navigationDestination(for: MoreDestination.self) { destination in
            switch destination {
            case .modules: moduleBrowser
            case .reports: reportBrowser
            case .dashboards: dashboardBrowser
            case .setup: setupDetailView
            case .settings: settingsContext
            }
        }
        .navigationTitle("More")
    }

    // MARK: - Command Bar

    private var commandBarActions: [CommandBarAction] {
        let moduleActions = moduleNames.map { module in
            CommandBarAction(
                id: "module-\(module)",
                title: module,
                subtitle: "Module",
                icon: "square.grid.2x2",
                badge: "Module",
                keywords: [module],
                isQuickAction: true
            ) {
                router.openModule(module)
            }
        }

        let docTypeActions = tooling.docTypes.map { docType in
            CommandBarAction(
                id: "doctype-\(docType.id)",
                title: docType.name,
                subtitle: docType.module,
                icon: "doc.text",
                badge: "DocType",
                keywords: [docType.id, docType.module],
                isQuickAction: false
            ) {
                router.openDocType(docType.id, module: docType.module)
                addRecent(.docType(docType.id))
            }
        }

        let createActions = tooling.docTypes.prefix(10).map { docType in
            CommandBarAction(
                id: "create-\(docType.id)",
                title: "New \(docType.name)",
                subtitle: "Create document",
                icon: "plus.circle",
                badge: "Create",
                keywords: [docType.name, docType.id],
                isQuickAction: true
            ) {
                router.openDocType(docType.id, module: docType.module)
                activeDocument = tooling.createDraftDocument(for: docType)
            }
        }

        let reportActions = tooling.reports.map { report in
            CommandBarAction(
                id: "report-\(report.id)",
                title: report.name,
                subtitle: report.docType,
                icon: "chart.bar.doc.horizontal",
                badge: "Report",
                keywords: [report.docType],
                isQuickAction: false
            ) {
                router.openReport(report.id, module: moduleForReport(report))
                addRecent(.report(report.id))
            }
        }

        let dashboardActions = tooling.dashboards.map { dashboard in
            CommandBarAction(
                id: "dashboard-\(dashboard.id)",
                title: dashboard.name,
                subtitle: "Dashboard",
                icon: "rectangle.3.group",
                badge: "Dashboard",
                keywords: [dashboard.id],
                isQuickAction: false
            ) {
                router.openDashboard(dashboard.id, module: moduleForDashboard(dashboard))
                addRecent(.dashboard(dashboard.id))
            }
        }

        let setupActions = [
            CommandBarAction(
                id: "setup-overview",
                title: "Open Setup",
                subtitle: nil,
                icon: "wrench.and.screwdriver",
                badge: "Setup",
                isQuickAction: true
            ) { router.showSetupOverview() },
            CommandBarAction(
                id: "setup-doctype",
                title: "New DocType",
                subtitle: nil,
                icon: "hammer",
                badge: "Setup",
                isQuickAction: true
            ) { router.openNewDocType() }
        ]

        let recentActions = recents.map { recent in
            CommandBarAction(
                id: "recent-\(recent.id)",
                title: recent.title(using: tooling),
                subtitle: "Recent",
                icon: recent.icon,
                badge: "Recent",
                isQuickAction: false
            ) { openRecent(recent) }
        }

        return moduleActions + createActions + docTypeActions + reportActions + dashboardActions + setupActions + recentActions
    }

    // MARK: - Helpers

    private var splitSections: [NavigationSection] {
        [.home, .inbox, .reports, .dashboards, .recents, .setup, .settings]
    }

    private func selectSection(_ section: NavigationSection) {
        router.selectedSection = section
        if section == .setup {
            isSetupExpanded = true
            router.showSetupOverview()
        } else {
            isSetupExpanded = false
            router.selectedItem = nil
        }
    }

    private func setupSidebarSubItem(
        title: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Spacer()
                    .frame(width: setupSubItemIndentationWidth)
                Image(systemName: icon)
                    .frame(width: setupSubItemIconWidth)
                Text(title)
            }
            .padding(.leading, setupSubItemLeadingPadding)
        }
        .buttonStyle(.plain)
        .listRowBackground(sidebarRowBackground(isActive: isActive))
    }

    private func sidebarRowBackground(isActive: Bool) -> some View {
        Group {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
            } else {
                Color.clear
            }
        }
    }

    private var setupSubItemIndentationWidth: CGFloat { 18 }
    private var setupSubItemIconWidth: CGFloat { 16 }
    private var setupSubItemLeadingPadding: CGFloat { 14 }

    private var moduleNames: [String] {
        Array(Set(tooling.docTypes.map(\.module))).sorted()
    }

    private func docTypes(in module: String) -> [DocType] {
        tooling.docTypes.filter { $0.module == module && !$0.isChildTable }
    }

    private func reports(in module: String) -> [ReportDefinition] {
        tooling.reports.filter { moduleForReport($0) == module }
    }

    private func dashboards(in module: String) -> [DashboardDefinition] {
        tooling.dashboards.filter { moduleForDashboard($0) == module }
    }

    private func moduleForReport(_ report: ReportDefinition) -> String? {
        tooling.docType(withId: report.docType)?.module
    }

    private func moduleForDashboard(_ dashboard: DashboardDefinition) -> String? {
        dashboard.widgets.compactMap { widget in
            if let docType = widget.docType {
                return tooling.docType(withId: docType)?.module
            }
            if let reportId = widget.reportId,
               let report = tooling.report(withId: reportId) {
                return moduleForReport(report)
            }
            return nil
        }.first
    }

    private var bindingForActiveDocument: Binding<Document> {
        Binding<Document>(
            get: {
                activeDocument ?? Document(
                    id: UUID().uuidString,
                    docType: "",
                    company: "",
                    status: "",
                    createdAt: Date(),
                    updatedAt: Date(),
                    syncVersion: 0,
                    syncState: .local,
                    fields: [:],
                    children: [:]
                )
            },
            set: { newValue in
                activeDocument = newValue
            }
        )
    }

    private func addRecent(_ destination: RecentDestination) {
        recents.removeAll(where: { $0.id == destination.id })
        recents.insert(destination, at: 0)
        if recents.count > 20 {
            recents = Array(recents.prefix(20))
        }
    }

    private func openRecent(_ destination: RecentDestination) {
        switch destination {
        case .docType(let id):
            router.openDocType(id, module: tooling.docType(withId: id)?.module)
        case .report(let id):
            router.openReport(id, module: tooling.report(withId: id).flatMap(moduleForReport))
        case .dashboard(let id):
            router.openDashboard(id, module: tooling.dashboard(withId: id).flatMap(moduleForDashboard))
        case .record(let docTypeId, let documentId):
            router.openDocType(docTypeId, module: tooling.docType(withId: docTypeId)?.module)
            activeDocument = tooling.listDocuments(docTypeId: docTypeId).first(where: { $0.id == documentId })
        }
    }

    private func handleSetupWorkspaceSaved() {
        tooling.reload()
        router.showSetupOverview()
    }

    @ToolbarContentBuilder
    private var setupBackToOverviewToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Back to Setup") {
                router.showSetupOverview()
            }
        }
    }
}

public enum NavigationSection: String, CaseIterable, Hashable, Identifiable {
    case home, modules, inbox, search, reports, dashboards, recents, settings, setup, more

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Desk"
        case .modules: return "Modules"
        case .inbox: return "Inbox"
        case .search: return "Search"
        case .reports: return "Reports"
        case .dashboards: return "Dashboards"
        case .recents: return "Recents"
        case .settings: return "Settings"
        case .setup: return "Setup"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .modules: return "square.grid.2x2"
        case .inbox: return "tray"
        case .search: return "magnifyingglass"
        case .reports: return "chart.bar"
        case .dashboards: return "rectangle.3.group"
        case .recents: return "clock"
        case .settings: return "gear"
        case .setup: return "wrench.and.screwdriver"
        case .more: return "ellipsis.circle"
        }
    }
}

private enum MoreDestination: Hashable {
    case modules
    case reports
    case dashboards
    case setup
    case settings
}

private enum RecentDestination: Hashable, Identifiable {
    case docType(String)
    case report(String)
    case dashboard(String)
    case record(docTypeId: String, documentId: String)

    var id: String {
        switch self {
        case .docType(let id): return "doctype-\(id)"
        case .report(let id): return "report-\(id)"
        case .dashboard(let id): return "dashboard-\(id)"
        case .record(let docTypeId, let documentId): return "record-\(docTypeId)-\(documentId)"
        }
    }

    var icon: String {
        switch self {
        case .docType: return "doc.text"
        case .report: return "chart.bar.doc.horizontal"
        case .dashboard: return "rectangle.3.group"
        case .record: return "doc.text.magnifyingglass"
        }
    }

    func title(using tooling: DocTypeToolingContext) -> String {
        switch self {
        case .docType(let id):
            return tooling.docType(withId: id)?.name ?? id
        case .report(let id):
            return tooling.report(withId: id)?.name ?? id
        case .dashboard(let id):
            return tooling.dashboard(withId: id)?.name ?? id
        case .record(let docTypeId, let documentId):
            let name = tooling.docType(withId: docTypeId)?.name ?? docTypeId
            return "\(name): \(documentId)"
        }
    }
}

extension Notification.Name {
    static let mercantisOpenCommandBar = Notification.Name("mercantis.openCommandBar")
}
