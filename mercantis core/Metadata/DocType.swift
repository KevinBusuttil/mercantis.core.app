//
//  DocType.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Describes a document type in the Mercantis metadata registry.
/// Every entity — built-in or user-defined — is described by a DocType. (ADR-003)
public struct DocType: Codable, Identifiable, Sendable {
    public let id: String                         // unique identifier, e.g. "SalesInvoice"
    public var name: String                        // display name
    public var module: String                      // owning module, e.g. "Sales"
    public var appId: String                       // owning app manifest id
    public var isChildTable: Bool                  // true if used only as a child table
    public var isSubmittable: Bool                 // true if this DocType uses the Submit/Cancel/Amend lifecycle (ADR-013)
    public var fields: [FieldDefinition]
    public var permissions: [PermissionRule]
    public var workflowId: String?
    public var syncPolicy: SyncPolicy
    public var indexes: [IndexDefinition]
    public var searchFields: [String]
    public var titleField: String
    public var isCustom: Bool

    public init(
        id: String,
        name: String,
        module: String,
        appId: String,
        isChildTable: Bool,
        isSubmittable: Bool = false,
        fields: [FieldDefinition],
        permissions: [PermissionRule],
        workflowId: String? = nil,
        syncPolicy: SyncPolicy,
        indexes: [IndexDefinition],
        searchFields: [String],
        titleField: String,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.module = module
        self.appId = appId
        self.isChildTable = isChildTable
        self.isSubmittable = isSubmittable
        self.fields = fields
        self.permissions = permissions
        self.workflowId = workflowId
        self.syncPolicy = syncPolicy
        self.indexes = indexes
        self.searchFields = searchFields
        self.titleField = titleField
        self.isCustom = isCustom
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case module
        case appId
        case isChildTable
        case isSubmittable
        case fields
        case permissions
        case workflowId
        case syncPolicy
        case indexes
        case searchFields
        case titleField
        case isCustom
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        module = try container.decode(String.self, forKey: .module)
        appId = try container.decode(String.self, forKey: .appId)
        isChildTable = try container.decode(Bool.self, forKey: .isChildTable)
        isSubmittable = try container.decode(Bool.self, forKey: .isSubmittable)
        fields = try container.decode([FieldDefinition].self, forKey: .fields)
        permissions = try container.decode([PermissionRule].self, forKey: .permissions)
        workflowId = try container.decodeIfPresent(String.self, forKey: .workflowId)
        syncPolicy = try container.decode(SyncPolicy.self, forKey: .syncPolicy)
        indexes = try container.decode([IndexDefinition].self, forKey: .indexes)
        searchFields = try container.decode([String].self, forKey: .searchFields)
        titleField = try container.decode(String.self, forKey: .titleField)
        // Older payloads don't include `isCustom`; treat them as system/non-custom by default.
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}
