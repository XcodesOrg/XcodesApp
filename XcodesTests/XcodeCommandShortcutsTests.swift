import SwiftUI
import XCTest
@testable import Xcodes

/// Guards the `CommandMenu` keyboard shortcuts against silent collisions.
///
/// SwiftUI keeps only the first `.keyboardShortcut` when two menu items bind
/// the same key + modifiers; the later item renders the correct glyph but can
/// never be triggered from the keyboard, with no compiler warning. These tests
/// turn that silent regression into a failing build by asserting the always-on
/// command shortcuts are pairwise distinct.
final class XcodeCommandShortcutsTests: XCTestCase {
    func testAlwaysOnCommandShortcutsArePairwiseDistinct() {
        // Mirrors the six always-on CommandMenu items in XcodeCommands.swift.
        // The conditional Install / Cancel-Install shortcuts (".", "i") are
        // mutually exclusive and intentionally excluded from this invariant.
        let shortcuts: [(name: String, shortcut: KeyboardShortcut)] = [
            ("makeActive (Make Active)", XcodeCommandShortcuts.makeActive),
            ("open (Open)", XcodeCommandShortcuts.open),
            ("reveal (Reveal in Finder)", XcodeCommandShortcuts.reveal),
            ("copyPath (Copy Path)", XcodeCommandShortcuts.copyPath),
            ("uninstall (Uninstall)", XcodeCommandShortcuts.uninstall),
            ("createSymbolicLink (Create Symbolic Link)", XcodeCommandShortcuts.createSymbolicLink),
        ]

        // Pairwise guard first so a failure names the two colliding items.
        for i in 0..<shortcuts.count {
            for j in (i + 1)..<shortcuts.count {
                XCTAssertNotEqual(
                    shortcuts[i].shortcut,
                    shortcuts[j].shortcut,
                    """
                    \(shortcuts[i].name) and \(shortcuts[j].name) bind the same keyboard shortcut. \
                    SwiftUI would silently keep only the first-declared one, making the second \
                    unreachable from the keyboard.
                    """
                )
            }
        }

        // Aggregate dedup check: a Set collapses equal key + modifier pairs.
        let all = shortcuts.map(\.shortcut)
        XCTAssertEqual(
            Set(all).count,
            all.count,
            "Always-on command shortcuts must be pairwise distinct: \(all.count) shortcuts but only \(Set(all).count) unique."
        )
    }
}
