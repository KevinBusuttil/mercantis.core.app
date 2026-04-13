//
//  PermissionRule.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// A permission rule assigned to a DocType. (ADR-003)
public struct PermissionRule: Codable, Sendable {
    public let role: String
    public let canRead: Bool
    public let canWrite: Bool
    public let canCreate: Bool
    public let canDelete: Bool
    public let canSubmit: Bool
    public let canAmend: Bool

    public init(role: String, canRead: Bool, canWrite: Bool, canCreate: Bool, canDelete: Bool, canSubmit: Bool, canAmend: Bool) {
        self.role = role
        self.canRead = canRead
        self.canWrite = canWrite
        self.canCreate = canCreate
        self.canDelete = canDelete
        self.canSubmit = canSubmit
        self.canAmend = canAmend
    }
}
