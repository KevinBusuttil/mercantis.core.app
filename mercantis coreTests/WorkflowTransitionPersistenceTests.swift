//
//  WorkflowTransitionPersistenceTests.swift
//  mercantis coreTests
//
//  Phase A §3.3 — `WorkflowEngine.transition(...)` writes its returned
//  history record into the new `workflow_transitions` table when configured
//  with a `WorkflowTransitionHistoryWriter`. The legacy "return-only"
//  behaviour is preserved when no writer is supplied.
//

import XCTest
import GRDB
@testable import mercantis_core

final class WorkflowTransitionPersistenceTests: XCTestCase {

    private var harness: TestSupport.Harness!

    override func setUpWithError() throws {
        harness = try TestSupport.makeHarness()
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: harness.url)
        harness = nil
    }

    private func makeWorkflow() -> WorkflowDefinition {
        WorkflowDefinition(
            id: "wf-approval",
            name: "Approval",
            docType: "Note",
            states: [
                WorkflowState(name: "Draft", isDefault: true, allowEdit: true),
                WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
                WorkflowState(name: "Approved", isDefault: false, allowEdit: false),
            ],
            transitions: [
                WorkflowTransition(
                    from: "Draft", to: "Submitted", action: "Submit",
                    allowedRoles: ["System Manager"]
                ),
                WorkflowTransition(
                    from: "Submitted", to: "Approved", action: "Approve",
                    allowedRoles: ["System Manager"]
                ),
            ]
        )
    }

    func testTransitionWithWriterPersistsToWorkflowTransitionsTable() throws {
        let writer = WorkflowTransitionHistoryWriter(database: harness.database)
        let engine = WorkflowEngine(historyWriter: writer)
        let evaluator = ExpressionEvaluator()

        var doc = TestSupport.makeDocument(id: "doc-1",
                                           fields: ["title": .string("X")])
        doc.status = "Draft"

        let history = try engine.transition(
            document: &doc,
            workflow: makeWorkflow(),
            action: "Submit",
            userRoles: ["System Manager"],
            expressionEvaluator: evaluator,
            userId: "alice"
        )

        XCTAssertEqual(doc.status, "Submitted")

        let stored = try writer.transitions(of: "doc-1")
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, history.id)
        XCTAssertEqual(stored.first?.from, "Draft")
        XCTAssertEqual(stored.first?.to, "Submitted")
        XCTAssertEqual(stored.first?.action, "Submit")
        XCTAssertEqual(stored.first?.userId, "alice")
    }

    func testTransitionWithoutWriterPreservesLegacyReturnOnlyBehaviour() throws {
        let engine = WorkflowEngine() // no writer
        let evaluator = ExpressionEvaluator()
        let writer = WorkflowTransitionHistoryWriter(database: harness.database)

        var doc = TestSupport.makeDocument(id: "doc-2",
                                           fields: ["title": .string("X")])
        doc.status = "Draft"

        _ = try engine.transition(
            document: &doc,
            workflow: makeWorkflow(),
            action: "Submit",
            userRoles: ["System Manager"],
            expressionEvaluator: evaluator,
            userId: "bob"
        )

        XCTAssertTrue(try writer.transitions(of: "doc-2").isEmpty,
                      "no writer => no row should be persisted")
    }

    func testMultipleTransitionsAccumulateInChronologicalOrder() throws {
        let writer = WorkflowTransitionHistoryWriter(database: harness.database)
        let engine = WorkflowEngine(historyWriter: writer)
        let evaluator = ExpressionEvaluator()

        var doc = TestSupport.makeDocument(id: "doc-3",
                                           fields: ["title": .string("X")])
        doc.status = "Draft"

        _ = try engine.transition(
            document: &doc, workflow: makeWorkflow(), action: "Submit",
            userRoles: ["System Manager"], expressionEvaluator: evaluator,
            userId: "alice"
        )
        // Sleep past the second boundary so timestamps order deterministically.
        Thread.sleep(forTimeInterval: 1.1)
        _ = try engine.transition(
            document: &doc, workflow: makeWorkflow(), action: "Approve",
            userRoles: ["System Manager"], expressionEvaluator: evaluator,
            userId: "alice"
        )

        let history = try writer.transitions(of: "doc-3")
        XCTAssertEqual(history.map(\.action), ["Submit", "Approve"])
        XCTAssertLessThanOrEqual(history[0].timestamp, history[1].timestamp)
    }

    func testReaderByWorkflowIdReturnsAllDocuments() throws {
        let writer = WorkflowTransitionHistoryWriter(database: harness.database)
        let engine = WorkflowEngine(historyWriter: writer)
        let evaluator = ExpressionEvaluator()

        for id in ["a", "b", "c"] {
            var doc = TestSupport.makeDocument(id: id, fields: ["title": .string(id)])
            doc.status = "Draft"
            _ = try engine.transition(
                document: &doc, workflow: makeWorkflow(), action: "Submit",
                userRoles: ["System Manager"], expressionEvaluator: evaluator,
                userId: "alice"
            )
        }

        let history = try writer.transitions(forWorkflow: "wf-approval")
        XCTAssertEqual(Set(history.map(\.documentId)), ["a", "b", "c"])
    }

    func testDocumentEngineExposesWorkflowTransitionReader() throws {
        // The engine's convenience reader threads through to the writer.
        let writer = WorkflowTransitionHistoryWriter(database: harness.database)
        let engine = WorkflowEngine(historyWriter: writer)
        let evaluator = ExpressionEvaluator()

        var doc = TestSupport.makeDocument(id: "doc-4",
                                           fields: ["title": .string("X")])
        doc.status = "Draft"
        _ = try engine.transition(
            document: &doc, workflow: makeWorkflow(), action: "Submit",
            userRoles: ["System Manager"], expressionEvaluator: evaluator,
            userId: "carol"
        )

        let viaEngine = try harness.engine.workflowTransitions(of: "doc-4")
        XCTAssertEqual(viaEngine.first?.userId, "carol")
    }
}
