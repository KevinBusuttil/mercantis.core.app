//
//  SidebarSelectionContrastTests.swift
//  MercantisCoreUITests
//
//  Guards the sidebar selected-row contrast contract (the "blue-on-blue"
//  regression where a selected row kept its accent/module-tinted foreground on
//  top of the strong accent selection background, leaving the label nearly
//  invisible).
//
//  The view layer derives every selected-row colour from
//  `MercantisTheme.sidebarRowEmphasis(isSelected:isEmphasized:)`, so exercising
//  that pure resolver proves the decision logic without needing to render.
//

import XCTest
import SwiftUI
import MercantisCoreUI

final class SidebarSelectionContrastTests: XCTestCase {

    // MARK: - Emphasis resolution

    func test_unselected_row_is_normal() {
        XCTAssertEqual(
            MercantisTheme.sidebarRowEmphasis(isSelected: false, isEmphasized: false),
            .normal
        )
        // Prominence is irrelevant when the row isn't selected.
        XCTAssertEqual(
            MercantisTheme.sidebarRowEmphasis(isSelected: false, isEmphasized: true),
            .normal
        )
    }

    func test_selected_on_strong_selection_is_emphasized() {
        XCTAssertEqual(
            MercantisTheme.sidebarRowEmphasis(isSelected: true, isEmphasized: true),
            .emphasizedSelection
        )
    }

    func test_selected_on_unfocused_selection_is_muted() {
        XCTAssertEqual(
            MercantisTheme.sidebarRowEmphasis(isSelected: true, isEmphasized: false),
            .mutedSelection
        )
    }

    // MARK: - Contrast contract

    func test_emphasized_selection_uses_high_contrast_white_foreground() {
        let emphasis = MercantisTheme.sidebarRowEmphasis(isSelected: true, isEmphasized: true)
        XCTAssertTrue(emphasis.usesHighContrastForeground)
        // High-contrast white, NOT the accent (which is the selection background
        // colour) — this is the core fix for the blue-on-blue bug.
        XCTAssertEqual(emphasis.foreground, MercantisTheme.selectionForegroundEmphasized)
        XCTAssertEqual(emphasis.foreground, Color.white)
    }

    func test_selected_foreground_is_not_the_selected_background_colour() {
        // Accessibility requirement: selected text must not share the selected
        // background's semantic colour. The strong selection background is the
        // accent, so the emphasized foreground must differ from it.
        let emphasized = MercantisTheme.sidebarRowEmphasis(isSelected: true, isEmphasized: true)
        XCTAssertNotEqual(emphasized.foreground, MercantisTheme.accent)
        XCTAssertNotEqual(emphasized.foreground, MercantisTheme.selectionForeground)
    }

    func test_muted_selection_keeps_primary_label_colour() {
        // On the light/grey unfocused selection white would wash out, so the
        // muted state keeps the primary label colour rather than going white.
        let muted = MercantisTheme.sidebarRowEmphasis(isSelected: true, isEmphasized: false)
        XCTAssertFalse(muted.usesHighContrastForeground)
        XCTAssertEqual(muted.foreground, MercantisTheme.textPrimary)
        XCTAssertNotEqual(muted.foreground, MercantisTheme.selectionForegroundEmphasized)
    }

    func test_normal_row_uses_primary_not_accent_foreground() {
        let normal = MercantisTheme.sidebarRowEmphasis(isSelected: false, isEmphasized: false)
        XCTAssertFalse(normal.usesHighContrastForeground)
        XCTAssertEqual(normal.foreground, MercantisTheme.textPrimary)
    }
}
