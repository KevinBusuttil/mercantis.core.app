//
//  NavigationShell.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

final class UIShellRouter: ObservableObject {
    @Published var selectedSection: NavigationSection? = .home
    @Published var selectedModule: String?
    @Published var selectedItem: WorkspaceSelection?

    func openDocTypes() {
        selectedSection = .docTypes
        selectedItem = nil
    }

    func openModule(_ module: String) {
        selectedSection = .modules
        selectedModule = module
        selectedItem = nil
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

enum WorkspaceSelection: Hashable {
    case docType(String)
    case report(String)
    case dashboard(String)
}

/// The top-level navigation shell for Mercantis Core.
public struct NavigationShell: View {

    @EnvironmentObject private var router: UIShellRouter
    @EnvironmentObject private var tooling: DocTypeToolingContext

    @State private var showCommandBar = false
    @State private var activeDocument: Document?
    @State private var recents: [RecentDestination] = []
    @State private var sidebarSearchText = ""
    @State private var isInspectorPresented = true

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
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .inspector(isPresented: shellInspectorPresentation) {
            shellInspector
                .frame(minWidth: 250)
        }
        #endif
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

    #if os(macOS)
    private var shellInspectorPresentation: Binding<Bool> {
        $isInspectorPresented
    }
    #endif

    private var sidebar: some View {
        List {
            ForEach(topSplitSections) { workspace in
                Button {
                    selectSection(workspace.section)
                } label: {
                    HStack(spacing: 8) {
                        Label(workspace.title, systemImage: workspace.icon)
                            .fontWeight(router.selectedSection == workspace.section ? .semibold : .regular)
                        if let badge = workspaceBadge(for: workspace.section) {
                            Spacer()
                            Text(badge)
                                .mercantisSemanticBadge(tone: router.selectedSection == workspace.section ? .accent : .muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .mercantisSidebarSelection(isActive: router.selectedSection == workspace.section)
            }

            ForEach(bottomSplitSections) { workspace in
                Button {
                    selectSection(workspace.section)
                } label: {
                    Label(workspace.title, systemImage: workspace.icon)
                        .fontWeight(router.selectedSection == workspace.section ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .mercantisSidebarSelection(isActive: router.selectedSection == workspace.section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
        .searchable(text: $sidebarSearchText, placement: .sidebar, prompt: "Search workspace content")
        .navigationTitle("Mercantis")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showCommandBar.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button("Open Command Bar") { showCommandBar = true }
                .keyboardShortcut("g", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
            #endif
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
        default:
            switch router.selectedSection {
            case .home:
                homeDetail
            case .modules:
                moduleBrowser
            case .reports:
                reportBrowser
            case .dashboards:
                dashboardBrowser
            case .recents:
                recentsBrowser
            case .docTypes:
                DocTypeListView()
            case .settings:
                settingsContext
            case .inbox:
                inboxContext
            default:
                homeDetail
            }
        }
    }

    private var moduleBrowser: some View {
        if tooling.docType(withId: BuiltInDocTypes.module.id) != nil {
            docTypeDetail(docTypeId: BuiltInDocTypes.module.id)
                .onAppear {
                    guard let selectedModule = router.selectedModule else { return }
                    if activeModuleName(in: activeDocument) == selectedModule {
                        return
                    }
                    activeDocument = tooling
                        .listDocuments(docTypeId: BuiltInDocTypes.module.id)
                        .first(where: { activeModuleName(in: $0) == selectedModule })
                }
        } else {
            ContentUnavailableView("Module DocType unavailable", systemImage: "square.grid.2x2")
        }
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
        .navigationTitle("Home")
    }

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Create").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(tooling.navigableDocTypes.prefix(8), id: \.id) { docType in
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
            Text("Core Tooling").font(.headline)
            Button {
                selectSection(.docTypes)
            } label: {
                Label("DocTypes", systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            Button {
                selectSection(.modules)
            } label: {
                Label("Modules", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.plain)
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
            Section("Core Tooling") {
                NavigationLink("DocTypes") {
                    DocTypeListView()
                }
                NavigationLink("Modules") {
                    moduleBrowser
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
        .navigationTitle("Home")
    }

    private var phoneMore: some View {
        List {
            NavigationLink("Modules", value: MoreDestination.modules)
            NavigationLink("DocTypes", value: MoreDestination.docTypes)
            NavigationLink("Reports", value: MoreDestination.reports)
            NavigationLink("Dashboards", value: MoreDestination.dashboards)
            NavigationLink("Settings", value: MoreDestination.settings)
        }
        .navigationDestination(for: MoreDestination.self) { destination in
            switch destination {
            case .modules: moduleBrowser
            case .docTypes: DocTypeListView()
            case .reports: reportBrowser
            case .dashboards: dashboardBrowser
            case .settings: settingsContext
            }
        }
        .navigationTitle("More")
    }

    // MARK: - Command Bar

    private var commandBarActions: [CommandBarAction] {
        let docTypeActions = tooling.navigableDocTypes.map { docType in
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

        let createActions = tooling.navigableDocTypes.prefix(10).map { docType in
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

        let docTypeShellActions = [
            CommandBarAction(
                id: "open-doctypes",
                title: "Open DocTypes",
                subtitle: nil,
                icon: "doc.text",
                badge: "DocTypes",
                isQuickAction: true
            ) { router.openDocTypes() },
            CommandBarAction(
                id: "open-modules",
                title: "Open Modules",
                subtitle: nil,
                icon: "square.grid.2x2",
                badge: "Modules",
                isQuickAction: true
            ) { selectSection(.modules) }
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

        return createActions + docTypeActions + reportActions + dashboardActions + docTypeShellActions + recentActions
    }

    // MARK: - Helpers

    private var workspaceDefinitions: [WorkspaceDefinition] {
        WorkspaceDefinition.coreDefaults
    }

    private var topSplitSections: [WorkspaceDefinition] {
        workspaceDefinitions.filter { $0.placement == .primary }
    }

    private var bottomSplitSections: [WorkspaceDefinition] {
        workspaceDefinitions.filter { $0.placement == .secondary }
    }

    private func workspaceBadge(for section: NavigationSection) -> String? {
        switch section {
        case .recents:
            return recents.isEmpty ? nil : "\(recents.count)"
        case .docTypes:
            return tooling.navigableDocTypes.isEmpty ? nil : "\(tooling.navigableDocTypes.count)"
        case .reports:
            return tooling.reports.isEmpty ? nil : "\(tooling.reports.count)"
        case .dashboards:
            return tooling.dashboards.isEmpty ? nil : "\(tooling.dashboards.count)"
        default:
            return nil
        }
    }

    private func selectSection(_ section: NavigationSection) {
        router.selectedSection = section
        router.selectedItem = nil
    }

    private var sidebarBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color.clear
        #endif
    }

    private var moduleNames: [String] {
        tooling.moduleNames
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

    private func activeModuleName(in document: Document?) -> String? {
        guard let document else { return nil }
        if case .string(let moduleName)? = document.fields["module_name"] {
            return moduleName
        }
        return nil
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

    @ViewBuilder
    private var shellInspector: some View {
        List {
            Section("Context") {
                LabeledContent("Section", value: router.selectedSection?.title ?? NavigationSection.home.title)
                if let item = router.selectedItem {
                    LabeledContent("Selection", value: String(describing: item))
                } else {
                    LabeledContent("Selection", value: "None")
                }
            }

            Section("Workspace Summary") {
                LabeledContent("Modules", value: "\(moduleNames.count)")
                LabeledContent("DocTypes", value: "\(tooling.docTypes.count)")
                LabeledContent("Reports", value: "\(tooling.reports.count)")
                LabeledContent("Dashboards", value: "\(tooling.dashboards.count)")
                LabeledContent("Recent", value: "\(recents.count)")
            }
        }
        .navigationTitle("Inspector")
    }

}

public enum NavigationSection: String, CaseIterable, Hashable, Identifiable {
    case home, modules, docTypes, inbox, search, reports, dashboards, recents, settings, more

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .modules: return "Modules"
        case .docTypes: return "DocTypes"
        case .inbox: return "Inbox"
        case .search: return "Search"
        case .reports: return "Reports"
        case .dashboards: return "Dashboards"
        case .recents: return "Recents"
        case .settings: return "Settings"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .modules: return "square.grid.2x2"
        case .docTypes: return "doc.text"
        case .inbox: return "tray"
        case .search: return "magnifyingglass"
        case .reports: return "chart.bar"
        case .dashboards: return "rectangle.3.group"
        case .recents: return "clock"
        case .settings: return "gear"
        case .more: return "ellipsis.circle"
        }
    }
}

private enum MoreDestination: Hashable {
    case modules
    case docTypes
    case reports
    case dashboards
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

struct WorkspaceDefinition: Identifiable, Hashable {
    enum Placement: Hashable {
        case primary
        case secondary
    }

    let section: NavigationSection
    let title: String
    let icon: String
    let placement: Placement

    var id: NavigationSection { section }

    static let coreDefaults: [WorkspaceDefinition] = [
        WorkspaceDefinition(section: .home, title: "Home", icon: "house", placement: .primary),
        WorkspaceDefinition(section: .reports, title: "Reports", icon: "chart.bar", placement: .primary),
        WorkspaceDefinition(section: .dashboards, title: "Dashboards", icon: "rectangle.3.group", placement: .primary),
        WorkspaceDefinition(section: .recents, title: "Recents", icon: "clock", placement: .primary),
        WorkspaceDefinition(section: .docTypes, title: "DocTypes", icon: "doc.text", placement: .primary),
        WorkspaceDefinition(section: .modules, title: "Modules", icon: "square.grid.2x2", placement: .primary),
        WorkspaceDefinition(section: .settings, title: "Settings", icon: "gear", placement: .secondary)
    ]
}
