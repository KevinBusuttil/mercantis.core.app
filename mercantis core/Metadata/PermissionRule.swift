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
    /// Whether the role may cancel a submitted document (docStatus 1 → 2).
    /// Distinct from `canSubmit` so a deployment can let one role post and a
    /// different role reverse. Defaults to `false`; the memberwise default and
    /// the `canSubmit` fallback on decode keep older rules / call sites working.
    public let canCancel: Bool
    public let canAmend: Bool

    public init(role: String, canRead: Bool, canWrite: Bool, canCreate: Bool, canDelete: Bool, canSubmit: Bool, canAmend: Bool, canCancel: Bool = false) {
        self.role = role
        self.canRead = canRead
        self.canWrite = canWrite
        self.canCreate = canCreate
        self.canDelete = canDelete
        self.canSubmit = canSubmit
        self.canAmend = canAmend
        self.canCancel = canCancel
    }

    private enum CodingKeys: String, CodingKey {
        case role, canRead, canWrite, canCreate, canDelete, canSubmit, canAmend, canCancel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role      = try c.decode(String.self, forKey: .role)
        canRead   = try c.decode(Bool.self, forKey: .canRead)
        canWrite  = try c.decode(Bool.self, forKey: .canWrite)
        canCreate = try c.decode(Bool.self, forKey: .canCreate)
        canDelete = try c.decode(Bool.self, forKey: .canDelete)
        canSubmit = try c.decode(Bool.self, forKey: .canSubmit)
        canAmend  = try c.decode(Bool.self, forKey: .canAmend)
        // Older manifests predate `canCancel`; fall back to `canSubmit` so a
        // role that could post can still reverse, matching prior behaviour.
        canCancel = try c.decodeIfPresent(Bool.self, forKey: .canCancel) ?? canSubmit
    }
}
