//
//  ExtensionPoints.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 24/04/2026.
//

import Foundation

/// Declarative extension points carried by an `AppManifest`. (ADR-015, ADR-026)
///
/// Apps declare lifecycle-event subscriptions and scheduled task registrations
/// here instead of shipping Python-style `hooks.py` code. `ExtensionPointResolver`
/// binds these declarations to the `EventEmitter` / `SchedulerService` at install
/// time.
public struct ExtensionPoints: Codable, Sendable, Equatable {
    public var documentEventSubscriptions: [DocumentEventSubscription]
    public var schedulerEvents: [SchedulerEventDeclaration]

    public init(
        documentEventSubscriptions: [DocumentEventSubscription] = [],
        schedulerEvents: [SchedulerEventDeclaration] = []
    ) {
        self.documentEventSubscriptions = documentEventSubscriptions
        self.schedulerEvents = schedulerEvents
    }

    public static let empty = ExtensionPoints()

    enum CodingKeys: String, CodingKey {
        case documentEventSubscriptions
        case schedulerEvents
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentEventSubscriptions = try container
            .decodeIfPresent([DocumentEventSubscription].self, forKey: .documentEventSubscriptions) ?? []
        schedulerEvents = try container
            .decodeIfPresent([SchedulerEventDeclaration].self, forKey: .schedulerEvents) ?? []
    }
}

// MARK: - Document Event Subscription

/// One declarative subscription to a document lifecycle event. (ADR-015)
///
/// `docTypeSelector` is either a specific DocType id or `"*"` for all DocTypes.
/// When the declared `trigger` fires for a matching document, each entry in
/// `actions` is dispatched via `ExtensionActionDispatcher`.
public struct DocumentEventSubscription: Codable, Sendable, Equatable {
    public var id: String
    public var docTypeSelector: String      // specific DocType id, or "*" for all
    public var trigger: DocumentEventTrigger
    public var actions: [ExtensionActionDeclaration]

    public init(
        id: String,
        docTypeSelector: String,
        trigger: DocumentEventTrigger,
        actions: [ExtensionActionDeclaration]
    ) {
        self.id = id
        self.docTypeSelector = docTypeSelector
        self.trigger = trigger
        self.actions = actions
    }

    /// True when this subscription applies to `docType`.
    public func matches(docType: String) -> Bool {
        docTypeSelector == "*" || docTypeSelector == docType
    }
}

/// Document lifecycle triggers understood by the resolver. (ADR-015)
///
/// The Frappe-style aliases `on_update`, `on_change`, and `on_save` all bind to
/// `DocumentSavedEvent`; Mercantis does not currently distinguish insert-vs-update
/// at the event layer. `after_insert` is intentionally rejected until the event
/// carries an "isNew" flag — see known follow-ups in `ExtensionPointResolver`.
public enum DocumentEventTrigger: String, Codable, Sendable, CaseIterable {
    case onSave      = "on_save"
    case onUpdate    = "on_update"
    case onChange    = "on_change"
    case onSubmit    = "on_submit"
    case onCancel    = "on_cancel"
    case onAmend     = "on_amend"
    case onTrash     = "on_trash"
    case onDelete    = "on_delete"
}

// MARK: - Scheduler Event Declaration

/// One declarative scheduled task registration. (ADR-015)
///
/// The resolver forwards this to `ExtensionSchedulerRegistrar`. Until the
/// `SchedulerService` (P1.4) ships, the default registrar records the
/// declaration without arming a timer.
public struct SchedulerEventDeclaration: Codable, Sendable, Equatable {
    public var id: String
    public var interval: ScheduleInterval
    public var actions: [ExtensionActionDeclaration]

    public init(
        id: String,
        interval: ScheduleInterval,
        actions: [ExtensionActionDeclaration]
    ) {
        self.id = id
        self.interval = interval
        self.actions = actions
    }
}

/// Scheduler cadences understood by the resolver. (ADR-015)
public enum ScheduleInterval: Codable, Sendable, Equatable {
    case all            // every tick
    case hourly
    case daily
    case weekly
    case monthly
    case cron(String)   // cron expression (see P1.4 for supported subset)

    private enum Kind: String, Codable {
        case all, hourly, daily, weekly, monthly, cron
    }

    private enum CodingKeys: String, CodingKey {
        case kind, expression
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:              try c.encode(Kind.all, forKey: .kind)
        case .hourly:           try c.encode(Kind.hourly, forKey: .kind)
        case .daily:            try c.encode(Kind.daily, forKey: .kind)
        case .weekly:           try c.encode(Kind.weekly, forKey: .kind)
        case .monthly:          try c.encode(Kind.monthly, forKey: .kind)
        case .cron(let expr):
            try c.encode(Kind.cron, forKey: .kind)
            try c.encode(expr, forKey: .expression)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .all:     self = .all
        case .hourly:  self = .hourly
        case .daily:   self = .daily
        case .weekly:  self = .weekly
        case .monthly: self = .monthly
        case .cron:
            let expr = try c.decode(String.self, forKey: .expression)
            self = .cron(expr)
        }
    }
}

// MARK: - Action Declaration

/// One built-in action to execute when a subscription fires. (ADR-015, ADR-025)
///
/// `actionType` is resolved by `ExtensionActionDispatcher` — typically against
/// the `AutomationActionRegistry` once P1.2 lands. `parameters` is the raw
/// map from the manifest; handlers interpret it per-action-type.
public struct ExtensionActionDeclaration: Codable, Sendable, Equatable {
    public var actionType: String
    public var parameters: [String: String]

    public init(actionType: String, parameters: [String: String] = [:]) {
        self.actionType = actionType
        self.parameters = parameters
    }
}
