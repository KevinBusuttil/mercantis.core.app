//
//  AppRuntimeTypes.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A workflow definition declared in an app manifest. (ADR-004)
public struct WorkflowDefinition: Codable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let states: [WorkflowState]
    public let transitions: [WorkflowTransition]
}

public struct WorkflowState: Codable, Sendable {
    public let name: String
    public let isDefault: Bool
    public let allowEdit: Bool
}

public struct WorkflowTransition: Codable, Sendable {
    public let from: String
    public let to: String
    public let action: String
    public let allowedRoles: [String]
    public let conditionExpression: String?
}

/// A report definition declared in an app manifest. (ADR-004)
public struct ReportDefinition: Codable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let columns: [String]
    public let filters: [ReportFilter]
}

public struct ReportFilter: Codable, Sendable {
    public let fieldKey: String
    public let label: String
    public let defaultValue: FieldValue?
}

/// An automation rule evaluated by Core's sandboxed expression engine. (ADR-004)
public struct AutomationRule: Codable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let triggerEvent: String         // e.g. "onSave", "onSubmit", "onSchedule"
    public let conditionExpression: String  // e.g. "document.status == \"Submitted\" && document.grandTotal > 10000"
    public let actions: [AutomationAction]
}

public struct AutomationAction: Codable, Sendable {
    public let type: String    // "sendNotification", "updateField", "createDocument", "triggerTransition"
    public let parameters: [String: String]
}

/// A dashboard definition declared in an app manifest. (ADR-004)
public struct DashboardDefinition: Codable, Sendable {
    public let id: String
    public let name: String
    public let widgets: [DashboardWidget]
}

public struct DashboardWidget: Codable, Sendable {
    public let type: String        // "chart", "count", "list", "shortcut"
    public let title: String
    public let reportId: String?
    public let docType: String?
    public let parameters: [String: String]
}

/// A localization bundle declared in an app manifest.
public struct LocalizationBundle: Codable, Sendable {
    public let locale: String      // e.g. "en", "mt", "it"
    public let strings: [String: String]
}
