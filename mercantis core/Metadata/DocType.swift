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
    public var fields: [FieldDefinition]
    public var permissions: [PermissionRule]
    public var workflowId: String?
    public var syncPolicy: SyncPolicy
    public var indexes: [IndexDefinition]
    public var searchFields: [String]
    public var titleField: String

    public init(
        id: String,
        name: String,
        module: String,
        appId: String,
        isChildTable: Bool,
        fields: [FieldDefinition],
        permissions: [PermissionRule],
        workflowId: String? = nil,
        syncPolicy: SyncPolicy,
        indexes: [IndexDefinition],
        searchFields: [String],
        titleField: String
    ) {
        self.id = id
        self.name = name
        self.module = module
        self.appId = appId
        self.isChildTable = isChildTable
        self.fields = fields
        self.permissions = permissions
        self.workflowId = workflowId
        self.syncPolicy = syncPolicy
        self.indexes = indexes
        self.searchFields = searchFields
        self.titleField = titleField
    }
}
