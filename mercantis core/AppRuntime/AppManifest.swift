//
//  AppManifest.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A declarative app manifest that describes what an app adds to Mercantis Core. (ADR-004)
///
/// Apps are JSON/YAML manifests — never binaries. All behaviour is executed by Core's
/// sandboxed expression and rule engine. No downloaded executable code. (ADR-008)
public struct AppManifest: Codable, Identifiable, Sendable {
    public let id: String                             // reverse-DNS identifier, e.g. "app.mercantis.hub"
    public var name: String
    public var version: String                         // semver
    public var minimumCoreVersion: String
    public var description: String
    public var doctypes: [DocType]
    public var workflows: [WorkflowDefinition]
    public var permissions: [PermissionRule]
    public var reports: [ReportDefinition]
    public var automationRules: [AutomationRule]
    public var dashboards: [DashboardDefinition]
    public var localizations: [LocalizationBundle]
    public var iconAsset: String?

    public init(
        id: String,
        name: String,
        version: String,
        minimumCoreVersion: String,
        description: String,
        doctypes: [DocType],
        workflows: [WorkflowDefinition],
        permissions: [PermissionRule],
        reports: [ReportDefinition],
        automationRules: [AutomationRule],
        dashboards: [DashboardDefinition],
        localizations: [LocalizationBundle],
        iconAsset: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.minimumCoreVersion = minimumCoreVersion
        self.description = description
        self.doctypes = doctypes
        self.workflows = workflows
        self.permissions = permissions
        self.reports = reports
        self.automationRules = automationRules
        self.dashboards = dashboards
        self.localizations = localizations
        self.iconAsset = iconAsset
    }
}
