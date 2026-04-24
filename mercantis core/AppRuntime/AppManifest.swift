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
    public var extensionPoints: ExtensionPoints        // ADR-015, P1.3
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
        extensionPoints: ExtensionPoints = .empty,
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
        self.extensionPoints = extensionPoints
        self.iconAsset = iconAsset
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, minimumCoreVersion, description
        case doctypes, workflows, permissions, reports
        case automationRules, dashboards, localizations
        case extensionPoints, iconAsset
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        minimumCoreVersion = try c.decode(String.self, forKey: .minimumCoreVersion)
        description = try c.decode(String.self, forKey: .description)
        doctypes = try c.decode([DocType].self, forKey: .doctypes)
        workflows = try c.decode([WorkflowDefinition].self, forKey: .workflows)
        permissions = try c.decode([PermissionRule].self, forKey: .permissions)
        reports = try c.decode([ReportDefinition].self, forKey: .reports)
        automationRules = try c.decode([AutomationRule].self, forKey: .automationRules)
        dashboards = try c.decode([DashboardDefinition].self, forKey: .dashboards)
        localizations = try c.decode([LocalizationBundle].self, forKey: .localizations)
        // Older manifests (pre-P1.3) don't carry `extensionPoints` — default to empty.
        extensionPoints = try c.decodeIfPresent(ExtensionPoints.self, forKey: .extensionPoints) ?? .empty
        iconAsset = try c.decodeIfPresent(String.self, forKey: .iconAsset)
    }
}
