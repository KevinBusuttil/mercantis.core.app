//
//  NavigationShell.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
import Combine
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

final class UIShellRouter: ObservableObject {
    @Published var selectedSection: NavigationSection? = .home
    @Published var selectedModule: String?
    @Published var selectedItem: WorkspaceSelection?
    /// Signals "the user has requested to create a new record of this DocType".
    /// Workspaces observe this and present the shared `CreateRecordSheet`.
    /// Set by Quick Create / Command Bar; cleared by the workspace that consumes it.
    @Published var pendingCreate: String?

    func openDocTypes() {
        selectedSection = .docTypes
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

    /// Request creation of a new record of `docTypeId`. The workspace responsible for that
    /// DocType is navigated to first so it renders before consuming the signal.
    func requestCreate(docTypeId: String, module: String?) {
        if docTypeId == BuiltInDocTypes.docType.id {
            openDocTypes()
        } else {
            openDocType(docTypeId, module: module)
        }
        pendingCreate = docTypeId
    }

    /// Called by a workspace after it has presented the create sheet for `docTypeId`.
    func consumePendingCreate(_ docTypeId: String) {
        if pendingCreate == docTypeId {
            pendingCreate = nil
        }
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
            Section {
                MercantisSidebarBrandHeader(
                    title: "Mercantis",
                    subtitle: "Workspace",
                    systemImage: "square.stack.3d.up"
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 6, trailing: 8))
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(topSplitSections) { workspace in
                    Button {
                        selectSection(workspace.section)
                    } label: {
                        MercantisSidebarRow(
                            title: workspace.title,
                            systemImage: workspace.icon,
                            tone: tone(for: workspace.section),
                            isSelected: router.selectedSection == workspace.section,
                            badge: workspaceBadge(for: workspace.section)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(bottomSplitSections) { workspace in
                    Button {
                        selectSection(workspace.section)
                    } label: {
                        MercantisSidebarRow(
                            title: workspace.title,
                            systemImage: workspace.icon,
                            tone: tone(for: workspace.section),
                            isSelected: router.selectedSection == workspace.section
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
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
                moduleManagementView
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

    @ViewBuilder
    private var moduleManagementView: some View {
        if tooling.docType(withId: BuiltInDocTypes.module.id) != nil {
            docTypeDetail(docTypeId: BuiltInDocTypes.module.id)
                .onAppear {
                    syncActiveDocumentToSelectedModule()
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
                        router.requestCreate(docTypeId: docType.id, module: docType.module)
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
            Text("Management").font(.headline)
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
            RecordCollectionHostView(
                preferenceKey: "docType.\(docType.id)",
                docType: docType,
                workspaceTitle: docType.id == BuiltInDocTypes.module.id ? "Modules" : nil,
                documents: documents,
                configuration: recordCollectionConfiguration(),
                onCreateDocument: {
                    let draft = tooling.createDraftDocument(for: docType)
                    addRecent(.docType(docType.id))
                    return draft
                },
                onSaveDocument: { document in
                    try tooling.saveDocument(document)
                    activeDocument = document
                    addRecent(.record(docTypeId: docType.id, documentId: document.id))
                },
                initialSelectedDocumentID: activeDocument?.id,
                onSelectionChange: { selected in
                    activeDocument = selected
                    if let selected {
                        addRecent(.record(docTypeId: docType.id, documentId: selected.id))
                    }
                },
                detailHeader: docType.id == BuiltInDocTypes.module.id
                    ? { document in AnyView(moduleSelectedRecordHeader(for: document)) }
                    : nil,
                externalCreateTrigger: createTriggerBinding(for: docType.id)
            )
        } else {
            Text("DocType not found")
                .foregroundStyle(.secondary)
        }
    }

    /// Returns a `Binding<Bool>` that is `true` when the router is requesting a new record
    /// of `docTypeId` and resets both the binding and the router's signal when consumed.
    private func createTriggerBinding(for docTypeId: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { router.pendingCreate == docTypeId },
            set: { newValue in
                if !newValue { router.consumePendingCreate(docTypeId) }
            }
        )
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
            Section("Management") {
                NavigationLink("DocTypes") {
                    DocTypeListView()
                }
                NavigationLink("Modules") {
                    moduleManagementView
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
            case .modules: moduleManagementView
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
                router.requestCreate(docTypeId: docType.id, module: docType.module)
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

    private func tone(for section: NavigationSection) -> MercantisModuleTone? {
        switch section {
        case .home, .reports, .dashboards:
            return .platform
        case .docTypes, .modules:
            return .setup
        case .recents:
            return .neutral
        case .settings, .inbox, .search, .more:
            return .system
        }
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
        if case .string(let moduleName)? = document.fields[BuiltInDocTypes.moduleNameFieldKey] {
            return moduleName
        }
        return nil
    }

    private func syncActiveDocumentToSelectedModule() {
        guard let selectedModule = router.selectedModule else { return }
        if activeModuleName(in: activeDocument) == selectedModule {
            return
        }
        activeDocument = tooling
            .listDocuments(docTypeId: BuiltInDocTypes.module.id)
            .first(where: { activeModuleName(in: $0) == selectedModule })
    }

    private func recordCollectionConfiguration() -> RecordCollectionViewConfiguration {
        RecordCollectionViewConfiguration(
            supportedViewModes: [.list, .browse, .detail],
            defaultViewMode: .list
        )
    }

    private func moduleSelectedRecordHeader(for document: Document) -> some View {
        let moduleName = stringValue(for: BuiltInDocTypes.moduleNameFieldKey, in: document) ?? document.id
        let appId = stringValue(for: "app_id", in: document)
        let isCustom = boolValue(for: "is_custom", in: document) ?? false
        let docTypeCount = tooling.navigableDocTypes.filter { $0.module == moduleName }.count

        var badges: [String] = [recordCustomizationBadge(isCustom: isCustom, nonCustomLabel: "System")]
        if let appId, !appId.isEmpty, appId != "custom.local" {
            badges.append(appId)
        }
        if docTypeCount > 0 {
            badges.append("\(docTypeCount) DocType\(docTypeCount == 1 ? "" : "s")")
        }

        return SelectedRecordHeader(
            title: moduleName,
            subtitle: isCustom ? "Custom Module" : "System Module",
            badges: badges
        )
    }

    private func stringValue(for field: String, in document: Document) -> String? {
        guard case .string(let value)? = document.fields[field] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolValue(for field: String, in document: Document) -> Bool? {
        guard case .bool(let value)? = document.fields[field] else { return nil }
        return value
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

    @MainActor
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

/// Stable identifiers for windows surfaced by `MercantisCoreUI`. Hoisted out of
/// the app entry point so library consumers (e.g. `mercantis.hub.app`) can
/// open these windows without depending on the standalone Xcode app target.
public enum MercantisShellWindow {
    public static let visualBuilderID = "visual-builder"
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
