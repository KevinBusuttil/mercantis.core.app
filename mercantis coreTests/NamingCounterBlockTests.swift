//
//  NamingCounterBlockTests.swift
//  mercantis coreTests
//
//  Phase B §3.7 (ADR-042) — Per-device counter range reservation. Two
//  devices saving offline must not pick the same counter value; a single
//  device must keep visually-sequential numbering for the legacy single-
//  device path.
//

import XCTest
import GRDB
@testable import mercantis_core

final class NamingCounterBlockTests: XCTestCase {

    private var url: URL!
    private var database: MercantisDatabase!

    override func setUpWithError() throws {
        url = TestSupport.tempDatabaseURL("counter-blocks")
        database = try TestSupport.makeDatabase(at: url)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: url)
        database = nil
    }

    // MARK: - Single-device sequential

    func testSingleDeviceIssuesSequentialValuesWithinABlock() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 50)
        var issued: [Int] = []
        for _ in 0..<5 {
            issued.append(try reserver.reserve(seriesKey: "X", deviceId: "A"))
        }
        XCTAssertEqual(issued, [1, 2, 3, 4, 5])
    }

    func testSingleDeviceClaimsFreshBlockOnExhaustion() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 3)
        var issued: [Int] = []
        for _ in 0..<7 {
            issued.append(try reserver.reserve(seriesKey: "X", deviceId: "A"))
        }
        // First block [1, 2, 3]; second block [4, 5, 6]; third block starts at 7.
        XCTAssertEqual(issued, [1, 2, 3, 4, 5, 6, 7])
    }

    // MARK: - Multi-device disjoint

    func testTwoDevicesGetDisjointBlocks() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 5)
        let first = try reserver.reserve(seriesKey: "X", deviceId: "A")
        let second = try reserver.reserve(seriesKey: "X", deviceId: "B")

        XCTAssertEqual(first, 1)
        // Device B's first reservation advances the global allocator beyond
        // device A's [1, 5] block, so it gets at least 6.
        XCTAssertGreaterThan(second, 5)
    }

    func testTwoDevicesDoNotCollideOnSequentialReservations() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 4)

        var deviceAValues: Set<Int> = []
        var deviceBValues: Set<Int> = []

        // Interleave to mimic two offline devices syncing later.
        for _ in 0..<10 {
            deviceAValues.insert(try reserver.reserve(seriesKey: "X", deviceId: "A"))
            deviceBValues.insert(try reserver.reserve(seriesKey: "X", deviceId: "B"))
        }

        XCTAssertEqual(deviceAValues.count, 10)
        XCTAssertEqual(deviceBValues.count, 10)
        XCTAssertTrue(deviceAValues.isDisjoint(with: deviceBValues),
                      "Offline two-device reservations must never overlap")
    }

    // MARK: - State inspection

    func testCurrentBlockReturnsNilBeforeFirstReservation() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 5)
        XCTAssertNil(try reserver.currentBlock(seriesKey: "X", deviceId: "A"))
    }

    func testCurrentBlockReflectsReservationProgress() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 5)
        _ = try reserver.reserve(seriesKey: "X", deviceId: "A")
        _ = try reserver.reserve(seriesKey: "X", deviceId: "A")
        let state = try XCTUnwrap(try reserver.currentBlock(seriesKey: "X", deviceId: "A"))
        XCTAssertEqual(state.blockStart, 1)
        XCTAssertEqual(state.blockEnd, 5)
        XCTAssertEqual(state.nextValue, 3)
        XCTAssertEqual(state.remaining, 3)
    }

    // MARK: - Series isolation

    func testSeparateSeriesKeysDoNotShareACounter() throws {
        let reserver = NamingCounterBlockReserver(database: database, blockSize: 5)
        let a = try reserver.reserve(seriesKey: "S1", deviceId: "A")
        let b = try reserver.reserve(seriesKey: "S2", deviceId: "A")
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 1, "Different series keys must not share a counter")
    }

    // MARK: - DocumentEngine integration regression

    func testDocumentEngineKeepsSequentialIdsForSingleDevice() throws {
        let harness = try TestSupport.makeHarness(deviceId: "device-1")
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        try harness.registry.register(
            TestSupport.makeDocType(
                id: "SalesInvoice",
                autoname: "naming_series:SINV-.YYYY.-.####"
            )
        )
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let prefix = "SINV-\(String(format: "%04d", currentYear))-"

        var ids: [String] = []
        for _ in 0..<3 {
            let saved = try harness.engine.save(
                TestSupport.makeDocument(id: "", docType: "SalesInvoice")
            )
            ids.append(saved.id)
        }

        XCTAssertEqual(ids, [
            "\(prefix)0001",
            "\(prefix)0002",
            "\(prefix)0003",
        ])
    }
}
