//
//  WorkflowEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Manages workflow state transitions for documents. (ADR-004)
public final class WorkflowEngine {

    private let eventEmitter: EventEmitter

    public init(eventEmitter: EventEmitter = EventEmitter()) {
        self.eventEmitter = eventEmitter
    }

    // MARK: - Available Transitions

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

            // Evaluate the optional condition expression if present.
            if let condition = transition.conditionExpression, !condition.isEmpty {
                return (try? expressionEvaluator.evaluateBool(
                    expression: condition,
                    context: document.fields
                )) ?? false
            }
            return true
        }
    }

    // MARK: - Execute Transition

    /// Execute a workflow transition on a document.
    ///
    /// - Validates the transition is available for the current state and user roles.
    /// - Updates `document.status` to the transition's `to` state.
    /// - Fires a `WorkflowTransitionEvent` on the EventEmitter.
    /// - Returns a `WorkflowTransitionHistory` record for the caller to persist.
    @discardableResult
    public func transition(
        document: inout Document,
        workflow: WorkflowDefinition,
        action: String,
        userRoles: Set<String>,
        expressionEvaluator: ExpressionEvaluator,
        userId: String = ""
    ) throws -> WorkflowTransitionHistory {
        let available = try availableTransitions(
            workflow: workflow,
            currentState: document.status,
            userRoles: userRoles,
            document: document,
            expressionEvaluator: expressionEvaluator
        )

        guard let matched = available.first(where: { $0.action == action }) else {
            throw WorkflowError.transitionNotAllowed(
                action: action,
                currentState: document.status,
                workflowId: workflow.id
            )
        }

        let previousState = document.status
        document.status = matched.to
        document.updatedAt = Date()

        let history = WorkflowTransitionHistory(
            transitionId: UUID().uuidString,
            documentId: document.id,
            docType: document.docType,
            workflowId: workflow.id,
            from: previousState,
            to: matched.to,
            action: action,
            userId: userId,
            timestamp: Date()
        )

        eventEmitter.publish(WorkflowTransitionEvent(
            document: document,
            fromState: previousState,
            toState: matched.to,
            action: action,
            workflowId: workflow.id
        ))

        return history
    }

    // MARK: - Errors

    public enum WorkflowError: Error, Sendable {
        case transitionNotAllowed(action: String, currentState: String, workflowId: String)
    }
}
