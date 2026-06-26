//
//  ExecutionContext.swift
//  mercantis core
//
//  Phase 0 / P0.1 — first-class execution identity.
//
//  Before this type, `DocumentEngine` baked a single `userId` / `deviceId` into
//  the instance at construction, so every audit row, document version, and
//  mutation recorded the same identity regardless of who actually performed the
//  operation. `ExecutionContext` carries the *live* operator (and their company,
//  roles, device, and session) into each call, so audit and permission checks
//  can attribute and authorise per operation.
//
//  Threading is intentionally additive: every `DocumentEngine` lifecycle method
//  takes `context:` as an optional defaulting to `nil`. When `nil`, the engine
//  synthesises a `.legacy(...)` context from its constructor identity, so all
//  existing call sites keep their current behaviour until they opt in.
//

import Foundation

/// Who is performing an operation, on behalf of which company, with which roles,
/// from which device and session. Propagated into `DocumentEngine` per call so
/// audit, versioning, mutation provenance, and permission checks reflect the
/// real operator rather than a single instance-wide identity.
public struct ExecutionContext: Sendable, Equatable {

    /// The authenticated operator performing the action. Recorded as the
    /// `userId` on audit rows, the `savedBy` on document versions, and the
    /// `userId` on mutation records.
    public let operatorId: String

    /// The company the operation is scoped to. Empty string means "unscoped"
    /// (single-company deployments). Used by company-scoped access checks.
    public let companyId: String

    /// The operator's roles, used by permission and workflow-guard checks.
    public let roles: Set<String>

    /// The physical device. Recorded as the `deviceId` on mutation records and
    /// used for offline-safe numbering. Stable per install, not per session.
    public let deviceId: String

    /// The current session (e.g. an unlock session). Optional; empty when not
    /// tracked. Useful for correlating an operator's actions within one sign-in.
    public let sessionId: String

    /// `true` for explicit system / import / migration work that is allowed to
    /// bypass interactive permission gating. Never set this implicitly — it must
    /// be a deliberate choice at the call site so the bypass is auditable.
    public let isSystemOperation: Bool

    /// `true` only for the synthesised pre-P0.1 fallback context (no caller
    /// supplied an identity). It distinguishes "no operator at all" — which stays
    /// permissive for backward compatibility — from "an explicit operator context
    /// that happens to carry no roles", which must NOT bypass permission checks
    /// (an authenticated operator with no granting role is denied). Callers
    /// cannot set this; only `.legacy(...)` produces it.
    public let isLegacyFallback: Bool

    public init(
        operatorId: String,
        companyId: String = "",
        roles: Set<String> = [],
        deviceId: String,
        sessionId: String = "",
        isSystemOperation: Bool = false
    ) {
        self.operatorId = operatorId
        self.companyId = companyId
        self.roles = roles
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.isSystemOperation = isSystemOperation
        self.isLegacyFallback = false
    }

    /// Private initialiser that can mark the context as the legacy fallback.
    private init(
        operatorId: String,
        companyId: String,
        roles: Set<String>,
        deviceId: String,
        sessionId: String,
        isSystemOperation: Bool,
        isLegacyFallback: Bool
    ) {
        self.operatorId = operatorId
        self.companyId = companyId
        self.roles = roles
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.isSystemOperation = isSystemOperation
        self.isLegacyFallback = isLegacyFallback
    }

    fileprivate static func makeLegacy(operatorId: String, deviceId: String) -> ExecutionContext {
        ExecutionContext(
            operatorId: operatorId,
            companyId: "",
            roles: [],
            deviceId: deviceId,
            sessionId: "",
            isSystemOperation: false,
            isLegacyFallback: true
        )
    }
}

public extension ExecutionContext {

    /// Backward-compatible context synthesised from a `DocumentEngine`'s
    /// constructor identity when a caller does not supply a per-operation
    /// context. Preserves pre-P0.1 behaviour: the instance `userId` becomes the
    /// operator and no roles are asserted (so role checks remain permissive for
    /// callers that have not yet adopted `ExecutionContext`).
    static func legacy(userId: String, deviceId: String) -> ExecutionContext {
        ExecutionContext.makeLegacy(operatorId: userId, deviceId: deviceId)
    }

    /// Explicit system / import context: audit-attributed to `operatorId`
    /// (default `"system"`) and flagged as a system operation so permission
    /// gating can deliberately exempt it.
    static func system(
        operatorId: String = "system",
        deviceId: String,
        companyId: String = ""
    ) -> ExecutionContext {
        ExecutionContext(
            operatorId: operatorId,
            companyId: companyId,
            deviceId: deviceId,
            isSystemOperation: true
        )
    }
}
