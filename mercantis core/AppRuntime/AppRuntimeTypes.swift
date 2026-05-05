//
//  AppRuntimeTypes.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A workflow definition declared in an app manifest. (ADR-004)
public struct WorkflowDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let states: [WorkflowState]
    public let transitions: [WorkflowTransition]

    public init(id: String, name: String, docType: String, states: [WorkflowState], transitions: [WorkflowTransition]) {
        self.id = id
        self.name = name
        self.docType = docType
        self.states = states
        self.transitions = transitions
    }
}

public struct WorkflowState: Codable, Sendable {
    public let name: String
    public let isDefault: Bool
    public let allowEdit: Bool

    public init(name: String, isDefault: Bool, allowEdit: Bool) {
        self.name = name
        self.isDefault = isDefault
        self.allowEdit = allowEdit
    }
}

public struct WorkflowTransition: Codable, Sendable {
    public let from: String
    public let to: String
    public let action: String
    public let allowedRoles: [String]
    public let conditionExpression: String?

    public init(from: String, to: String, action: String, allowedRoles: [String], conditionExpression: String? = nil) {
        self.from = from
        self.to = to
        self.action = action
        self.allowedRoles = allowedRoles
        self.conditionExpression = conditionExpression
    }
}

/// A report definition declared in an app manifest. (ADR-004)
public struct ReportDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let columns: [String]
    public let filters: [ReportFilter]

    public init(id: String, name: String, docType: String, columns: [String], filters: [ReportFilter]) {
        self.id = id
        self.name = name
        self.docType = docType
        self.columns = columns
        self.filters = filters
    }
}

public struct ReportFilter: Codable, Sendable {
    public let fieldKey: String
    public let label: String
    public let defaultValue: FieldValue?

    public init(fieldKey: String, label: String, defaultValue: FieldValue? = nil) {
        self.fieldKey = fieldKey
        self.label = label
        self.defaultValue = defaultValue
    }
}

/// An automation rule evaluated by Core's sandboxed expression engine. (ADR-004)
public struct AutomationRule: Codable, Sendable {
    public let id: String
    public let name: String
    public let docType: String
    public let triggerEvent: String         // e.g. "onSave", "onSubmit", "onSchedule"
    public let conditionExpression: String  // e.g. "document.status == \"Submitted\" && document.grandTotal > 10000"
    public let actions: [AutomationAction]
    /// Required when `triggerEvent == "onSchedule"`. Ignored otherwise.
    /// (Phase B §3.8, ADR-041)
    public let schedule: ScheduleInterval?

    public init(
        id: String,
        name: String,
        docType: String,
        triggerEvent: String,
        conditionExpression: String,
        actions: [AutomationAction],
        schedule: ScheduleInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.docType = docType
        self.triggerEvent = triggerEvent
        self.conditionExpression = conditionExpression
        self.actions = actions
        self.schedule = schedule
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, docType, triggerEvent, conditionExpression, actions, schedule
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        docType = try c.decode(String.self, forKey: .docType)
        triggerEvent = try c.decode(String.self, forKey: .triggerEvent)
        conditionExpression = try c.decode(String.self, forKey: .conditionExpression)
        actions = try c.decode([AutomationAction].self, forKey: .actions)
        schedule = try c.decodeIfPresent(ScheduleInterval.self, forKey: .schedule)
    }
}

public struct AutomationAction: Codable, Sendable {
    public let type: String    // "sendNotification", "updateField", "createDocument", "triggerTransition"
    public let parameters: [String: String]

    public init(type: String, parameters: [String: String]) {
        self.type = type
        self.parameters = parameters
    }
}

/// A dashboard definition declared in an app manifest. (ADR-004)
public struct DashboardDefinition: Codable, Sendable {
    public let id: String
    public let name: String
    public let widgets: [DashboardWidget]

    public init(id: String, name: String, widgets: [DashboardWidget]) {
        self.id = id
        self.name = name
        self.widgets = widgets
    }
}

public struct DashboardWidget: Codable, Sendable {
    public let type: String        // "chart", "count", "list", "shortcut"
    public let title: String
    public let reportId: String?
    public let docType: String?
    public let parameters: [String: String]

    public init(type: String, title: String, reportId: String? = nil, docType: String? = nil, parameters: [String: String]) {
        self.type = type
        self.title = title
        self.reportId = reportId
        self.docType = docType
        self.parameters = parameters
    }
}

/// A localization bundle declared in an app manifest.
public struct LocalizationBundle: Codable, Sendable {
    public let locale: String      // e.g. "en", "mt", "it"
    public let strings: [String: String]

    public init(locale: String, strings: [String: String]) {
        self.locale = locale
        self.strings = strings
    }
}
