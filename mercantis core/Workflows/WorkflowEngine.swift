//
//  WorkflowEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Manages workflow state transitions for documents. (ADR-004)
public final class WorkflowEngine {

    public init() {}

    /// Get available transitions from the current state for the given user roles.
    public func availableTransitions(
        workflow: WorkflowDefinition,
        currentState: String,
        userRoles: Set<String>,
        document: Document,
        expressionEvaluator: ExpressionEvaluator
    ) throws -> [WorkflowTransition] {
        return workflow.transitions.filter { transition in
            guard transition.from == currentState else { return false }
            guard transition.allowedRoles.contains(where: { userRoles.contains($0) }) else { return false }
            // TODO: evaluate conditionExpression if present
            return true
        }
    }

    /// Execute a workflow transition on a document.
    public func transition(
        document: inout Document,
        workflow: WorkflowDefinition,
        action: String,
        userRoles: Set<String>,
        expressionEvaluator: ExpressionEvaluator
    ) throws {
        // TODO: Validate transition is allowed, update document status
    }
}
