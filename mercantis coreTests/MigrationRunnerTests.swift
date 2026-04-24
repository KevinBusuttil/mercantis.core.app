//
//  MigrationRunnerTests.swift
//  mercantis coreTests
//
//  Covers ADR-002: forward-only, versioned schema migrations.
//

import XCTest
import GRDB
@testable import mercantis_core

final class MigrationRunnerTests: XCTestCase {

    private var url: URL!
    private var pool: DatabasePool!

    override func setUpWithError() throws {
        url = TestSupport.tempDatabaseURL("migrations")
        pool = try DatabasePool(path: url.path)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: url)
        pool = nil
    }

    // MARK: - Helpers

    private func highestAppliedVersion() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_version") ?? 0
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        try pool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                arguments: [name]
            ) != nil
        }
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            return rows.contains { ($0["name"] as String?) == column }
        }
    }

    // MARK: - Tests

    func testBuiltInMigrationsApplyInOrder() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertEqual(try highestAppliedVersion(), 6)
    }

    func testV1CreatesExpectedTables() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        for table in ["doctypes", "fields", "documents", "document_children",
                      "sync_queue", "audit_log", "apps", "workflows"] {
            XCTAssertTrue(try tableExists(table), "\(table) should exist after v1")
        }
    }

    func testV2AddsDocStatusAndAmendedFromColumns() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertTrue(try columnExists("docStatus", in: "documents"))
        XCTAssertTrue(try columnExists("amendedFrom", in: "documents"))
    }

    func testV3CreatesDocumentVersionsTable() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertTrue(try tableExists("document_versions"))
    }

    func testV4CreatesSyncStateTable() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertTrue(try tableExists("sync_state"))
        XCTAssertTrue(try columnExists("key", in: "sync_state"))
        XCTAssertTrue(try columnExists("value", in: "sync_state"))
    }

    func testV5CreatesNamingCountersTable() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertTrue(try tableExists("naming_counters"))
        XCTAssertTrue(try columnExists("seriesKey", in: "naming_counters"))
        XCTAssertTrue(try columnExists("value", in: "naming_counters"))
    }

    func testV6CreatesSchedulerStateTable() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)

        XCTAssertTrue(try tableExists("scheduler_state"))
        XCTAssertTrue(try columnExists("taskKey", in: "scheduler_state"))
        XCTAssertTrue(try columnExists("lastRunAt", in: "scheduler_state"))
    }

    func testSecondMigrateIsIdempotent() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)
        let rowsAfterFirst = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_version") ?? 0
        }

        // Running migrate() again must not re-apply or duplicate rows.
        XCTAssertNoThrow(try runner.migrate(pool: pool))
        let rowsAfterSecond = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_version") ?? 0
        }
        XCTAssertEqual(rowsAfterFirst, rowsAfterSecond, "schema_version must not duplicate rows")
    }

    func testCustomMigrationRegisteredAtHigherVersionIsApplied() throws {
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        runner.register(version: 99, name: "test_marker", sql: """
            CREATE TABLE IF NOT EXISTS test_marker (
                id TEXT PRIMARY KEY NOT NULL
            );
        """)

        try runner.migrate(pool: pool)

        XCTAssertTrue(try tableExists("test_marker"))
        XCTAssertEqual(try highestAppliedVersion(), 99)
    }
}
