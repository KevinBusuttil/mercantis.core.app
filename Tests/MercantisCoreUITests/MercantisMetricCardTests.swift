//
//  MercantisMetricCardTests.swift
//  MercantisCoreUITests
//
//  Pure-logic coverage for the KPI metric card's formatting/classification
//  helpers. These back the dashboard's "delta chip" (e.g. +12.5% ▲) so the
//  sign, rounding, and trend bucketing stay stable.
//

import XCTest
import MercantisCoreUI

final class MercantisMetricCardTests: XCTestCase {

    // MARK: - Delta percentage formatting

    func test_positive_fraction_gets_plus_sign() {
        XCTAssertEqual(MercantisMetricCard.formatDeltaPercent(0.125), "+12.5%")
    }

    func test_negative_fraction_keeps_minus_sign() {
        XCTAssertEqual(MercantisMetricCard.formatDeltaPercent(-0.032), "-3.2%")
    }

    func test_zero_has_no_sign() {
        XCTAssertEqual(MercantisMetricCard.formatDeltaPercent(0), "0.0%")
    }

    func test_decimals_are_configurable() {
        // Inputs chosen to avoid printf half-rounding ambiguity.
        XCTAssertEqual(MercantisMetricCard.formatDeltaPercent(0.12378, decimals: 2), "+12.38%")
        XCTAssertEqual(MercantisMetricCard.formatDeltaPercent(0.12, decimals: 0), "+12%")
    }

    func test_non_finite_returns_nil() {
        XCTAssertNil(MercantisMetricCard.formatDeltaPercent(.nan))
        XCTAssertNil(MercantisMetricCard.formatDeltaPercent(.infinity))
    }

    // MARK: - Trend classification

    func test_trend_buckets_by_sign() {
        if case .up = MercantisMetricCard.Trend(change: 10) {} else { XCTFail("expected up") }
        if case .down = MercantisMetricCard.Trend(change: -10) {} else { XCTFail("expected down") }
        if case .flat = MercantisMetricCard.Trend(change: 0) {} else { XCTFail("expected flat") }
    }

    func test_trend_epsilon_treats_tiny_change_as_flat() {
        if case .flat = MercantisMetricCard.Trend(change: 0.000001) {} else {
            XCTFail("sub-epsilon change should read as flat")
        }
    }
}
